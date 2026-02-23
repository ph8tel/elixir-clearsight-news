# Copilot instructions for clearsight_news

## Architecture at a glance

Phoenix 1.8 + LiveView app. Core flow: search topic → fetch NewsAPI articles → upsert to Postgres → run Groq LLM analysis → stream results to UI → compare framing across outlets.

**LiveViews** are the surface and orchestration layer (`lib/clearsight_news_web/live/`):
- `SearchLive` — homepage, shows headlines with live sentiment badges.
- `ResultsLive` — fetches, persists, and trickle-analyses up to 15 articles.
- `CompareLive` — runs rhetoric + cross-article comparison in parallel.

**Service boundaries:**
- `ClearsightNews.NewsApi` — behaviour contract (callbacks: `search/2`, `top_headlines/1`).
- `ClearsightNews.NewsApiService` — `Req`-backed implementation; swappable via `:news_api_impl` config key.
- `ClearsightNews.Analysis` — Groq calls; all functions return `{:ok, struct}` or `{:error, reason}`. **Sentiment uses direct `Req`; rhetoric/comparison use Instructor.** (See LLM strategy below.)
- `ClearsightNews.ArticleAnalyzer` — shared pipeline: upsert articles → return cached scores → dispatch supervised tasks for new ones.

**Persistence:**
- `articles` — deduplicated by URL (`conflict_target: :url`).
- `model_responses` — every LLM call logged; `status` transitions `pending → complete | error`; stores `latency_ms`, `computed_score`, `computed_result`.

## Critical code paths

Start here when changing behaviour:
- `lib/clearsight_news/article_analyzer.ex` — upsert + cache-check pipeline; `allow_sandbox/1` must be called before spawning task processes in tests.
- `lib/clearsight_news/analysis.ex` — `compute_sentiment_score/1` and `classify/1` drive UI column thresholds (`@threshold 0.1`); text truncated to `@max_chars 4000` before LLM calls.
- `lib/clearsight_news/analysis/` — Instructor embedded schemas (`SentimentResult`, `RhetoricResult`, `ComparisonResult`). Each uses `use Ecto.Schema` + `use Instructor`; keep these as `@primary_key false` embedded schemas.
- `lib/clearsight_news_web/article_helpers.ex` — display helpers (`format_score/1`, `dominant_emotion/1`, `loaded_language_high?/1`) and `@analysis_interval 300`. Auto-imported in all LiveViews/HTML modules via `html_helpers` in `clearsight_news_web.ex`; no explicit import needed.

## LLM call strategy

`analyse_sentiment/1` bypasses Instructor and makes a **direct `Req.post/2`** to `https://api.groq.com/openai/v1/chat/completions`, then parses the JSON `content` field and manually constructs `%SentimentResult{}` via `cast_sentiment_result/1`. This is necessary because `instructor 0.1.0`'s Groq adapter only supports `@supported_modes [:tools]`, and `llama-3.1-8b-instant` inconsistently wraps its response as `<function=Schema>Schema="..."` text instead of a proper tool-call object — Groq rejects this with HTTP 400. Plain chat completion (no tool-calling) returns clean JSON in the `content` field reliably.

`analyse_rhetoric/1` and `analyse_comparison/2` continue to use Instructor + `llama-3.3-70b-versatile`, which handles tool-calling correctly. Do not switch these to direct calls.

The `@sentiment_system_prompt` module attribute in `analysis.ex` is the single place to edit the sentiment prompt. All three Req retry attempts use it.

Test stubbing is unchanged: `instructor_http_options: [plug: {Req.Test, :groq_api}]` in `test.exs` intercepts both the direct `Req` call and any Instructor calls via the same stub name.

## Trickle analysis pattern

Cards render immediately (cached = score shown; new = pulsing "Analyzing…" badge). New articles are analysed sequentially with 300 ms spacing (`@analysis_interval`) to stay within Groq rate limits. Each supervised `Task` sends `{:analysis_result, article}` back to the LiveView PID. Do not batch or parallelize Groq sentiment calls.

## Project-specific conventions

- **HTTP client:** always use `Req`; never `:httpoison`, `:tesla`, or `:httpc`.
- **NewsAPI access:** always go through the `NewsApi` behaviour — never call `NewsApiService` directly from LiveViews.
- **LLM model names:** read at runtime via `System.get_env/2`; never hardcode. Defaults: `GROQ_SENTIMENT_MODEL=llama-3.1-8b-instant`, `GROQ_RHETORIC_MODEL=llama-3.3-70b-versatile`, `GROQ_COMPARISON_MODEL=llama-3.3-70b-versatile`. Do not change the sentiment default to a 70b model without also verifying Instructor tool-calling still isn't needed.
- **Templates:** wrap all LiveView content with `<Layouts.app flash={@flash} ...>` (aliased automatically). Use `<.icon name="hero-*">`, `<.input>`, `<.form for={@form}>` from `core_components.ex`. Never call `<.flash_group>` outside `layouts.ex`.
- **Elixir patterns:** use `Enum.at/2` for list access (not `list[i]`); bind `if/case/cond` results to a variable; never nest multiple modules in one file; use struct field access (`struct.field`), not map access syntax on structs.

## Developer workflows

```bash
mix setup                  # deps + DB create/migrate/seed + assets
mix phx.server             # start dev server at localhost:4000
docker-compose up -d db    # start local Postgres only

mix test                   # run all tests (auto-creates/migrates test DB)
mix test test/path/foo.exs # single file
mix test --failed          # re-run only previously failed tests
mix precommit              # compile (warnings-as-errors) + deps.unlock --unused + format + test
```

`mix precommit` runs under the `:test` env (set in `mix.exs` `cli/0`). Always run it before committing.

## Test and integration notes

- **NewsAPI mocked** with Mox: `ClearsightNews.MockNewsApi` defined in `test/support/mocks.ex`; wired via `config :clearsight_news, :news_api_impl, ClearsightNews.MockNewsApi` in `config/test.exs`.
- **Groq HTTP mocked** with `Req.Test`: test config sets `instructor_http_options: [plug: {Req.Test, :groq_api}]`. Use `Req.Test.stub(:groq_api, ...)` in tests — no live API calls.
- **Sandbox for tasks:** call `ArticleAnalyzer.allow_sandbox(task_pid)` before a spawned task accesses the repo; otherwise tests will see connection ownership errors.
- Use `LazyHTML` (test-only dep) for targeted HTML assertions; never assert against raw HTML strings.
- Prefer `has_element?(view, "#dom-id")` over text-content assertions.

## Environment and deployment

Required env vars: `GROQ_API_KEY`, `NEWS_API_KEY`, `DATABASE_URL` (production), `SECRET_KEY_BASE`.  
Deploy: `fly deploy` — set secrets with `fly secrets set KEY=value`.
