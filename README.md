# ClearSight News

ClearSight News is a Phoenix LiveView app for comparing how news outlets frame the same topic.

## Live demo

https://clearsight-news.fly.dev/

## How it works

### Search page (`/`)

- Shows a search bar and a 3×3 grid of latest headlines loaded on mount.
- Headlines appear immediately; each card shows a pulsing **Analyzing…** badge while sentiment runs in the background.
- Once analysis completes the badge is replaced with a sentiment score, dominant emotion emoji, and a loaded-language pill if applicable.

### Results page (`/results?q=…`)

- Fetches up to 15 recent English-language articles from NewsAPI for the query.
- Articles are upserted into Postgres (deduplicated by URL). Already-analysed articles load instantly from cache; new ones show a pulsing **Analyzing…** badge.
- Analysis runs sequentially per-article in supervised Tasks, spaced 300 ms apart to stay within Groq rate limits. Each card updates in place as its result arrives.
- Completed articles are sorted into **Positive / Neutral / Negative** columns by polarity score.
- Select any two articles as Primary and Reference, then click **Compare Selected**.

### Compare page (`/compare?primary=…&reference=…`)

- Runs rhetorical analysis on both articles and a cross-article comparison in parallel.
- Shows tone, rhetorical devices, and bias indicators for each article side-by-side.
- Shows a structured comparison of framing differences, tone, source selection, and bias assessment.

### Persistence

Every LLM call is recorded as a `model_responses` row with `status`, `latency_ms`, `computed_score`, and the full structured output for traceability and caching.

## Architecture

```
SearchLive / ResultsLive
  └─ ArticleAnalyzer.upsert_articles/1   # fast DB upsert, returns cached scores
  └─ ArticleAnalyzer.run_sentiment/1     # Groq call, persists ModelResponse
       └─ Analysis.analyse_sentiment/1   # direct Req call + manual cast (no Instructor)

CompareLive
  └─ Analysis.analyse_rhetoric/1         # Instructor + Groq tool-calling
  └─ Analysis.analyse_comparison/2       # Instructor + Groq tool-calling
```

- `NewsApi` behaviour + `NewsApiService` (Req-backed) keeps the HTTP client swappable for tests (Mox).
- Trickle analysis: `Process.send_after` chains per-article tasks so the UI updates as each result arrives rather than waiting for a batch.
- **Sentiment** uses a direct `Req` call (bypassing Instructor's tool-calling protocol) with `llama-3.1-8b-instant`. `instructor 0.1.0`'s Groq adapter only supports `:tools` mode, which the 8b model handles inconsistently, producing `<function=Schema>` text that Groq rejects with HTTP 400. The direct call receives plain JSON in the `content` field, which the 8b model returns reliably.
- **Rhetoric and comparison** use Instructor + `llama-3.3-70b-versatile`, which handles tool-calling correctly.
- Model names are read at runtime from env vars (`GROQ_SENTIMENT_MODEL`, `GROQ_RHETORIC_MODEL`, `GROQ_COMPARISON_MODEL`).

## Stack

- Elixir / Phoenix 1.8 / LiveView
- Ecto + PostgreSQL
- Req (NewsAPI + direct Groq sentiment client)
- Instructor + Groq (`llama-3.3-70b-versatile` for rhetoric/comparison)
- Tailwind CSS + daisyUI

## Local development

### 1. Start Postgres

```bash
docker-compose up -d db
```

### 2. Set environment variables

```bash
export GROQ_API_KEY=...
export NEWS_API_KEY=...
```

### 3. Setup and run

```bash
mix setup
mix phx.server
```

Open http://localhost:4000.

## Tests

```bash
mix test              # run all tests
mix precommit         # compile (warnings-as-errors) + format check + tests
```

Tests use Mox to stub `NewsApi` and `Req.Test` to stub Groq HTTP calls — no live API calls are made.

## Deployment (Fly.io)

```bash
fly deploy
```

Required secrets (set with `fly secrets set KEY=value`):

| Secret | Notes |
|---|---|
| `DATABASE_URL` | Postgres connection string |
| `SECRET_KEY_BASE` | Generate with `mix phx.gen.secret` |
| `GROQ_API_KEY` | Groq API key |
| `NEWS_API_KEY` | NewsAPI.org key |

Optional model overrides:

| Secret | Default |
|---|---|
| `GROQ_SENTIMENT_MODEL` | `llama-3.1-8b-instant` |
| `GROQ_RHETORIC_MODEL` | `llama-3.3-70b-versatile` |
| `GROQ_COMPARISON_MODEL` | `llama-3.3-70b-versatile` |
