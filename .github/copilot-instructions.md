# Copilot instructions for clearsight_news

## Architecture at a glance
- This is a Phoenix 1.8 + LiveView app. Core flow: search topic → fetch news articles → run LLM analysis → persist results → render compare UI.
- LiveViews are the app surface and orchestration layer:
  - `SearchLive` routes query input to results.
  - `ResultsLive` fetches + persists articles and sentiment scores.
  - `CompareLive` runs per-article rhetoric + cross-article comparison.
- Service boundaries:
  - `ClearsightNews.NewsApi` is a behaviour contract.
  - `ClearsightNews.NewsApiService` is the Req-backed implementation.
  - `ClearsightNews.Analysis` wraps Instructor/Groq calls with typed response models.
- Persistence model:
  - `articles` stores normalized source data (unique by URL).
  - `model_responses` stores pending/completed/error LLM runs, latency, scores, and structured output.

## Critical code paths and patterns
- Start with these files when changing behavior:
  - `lib/clearsight_news_web/live/results_live.ex`
  - `lib/clearsight_news_web/live/compare_live.ex`
  - `lib/clearsight_news/analysis.ex`
  - `lib/clearsight_news/news_api_service.ex`
- Async work is done with `assign_async/3` and a supervised task pool (`ClearsightNews.TaskSupervisor`), not ad-hoc spawned processes.
- Sentiment scoring/classification is centralized in `ClearsightNews.Analysis.compute_sentiment_score/1` and `classify/1`; UI columns depend on these exact thresholds.
- Articles are upserted via `Repo.insert_all(... conflict_target: :url ...)` before model analysis; preserve this dedupe-first flow.
- Model runs are logged as `ModelResponse` rows with `status` transitions (`pending` → `complete`/`error`).

## Project-specific conventions
- Prefer `Req` for HTTP clients (already configured/dependency present).
- Keep external-news access behind the `NewsApi` behaviour so tests can swap implementations.
- Analysis schemas are Ecto embedded schemas + `Instructor.Validator`; maintain strict field validation for model outputs.
- In templates, use Phoenix function components (`<.link>`, `<.form>`, `<.input>`, `<.icon>`) and HEEx idioms already used in `core_components.ex`.

## Developer workflows
- Initial setup: `mix setup`
- Run app: `mix phx.server`
- Run tests: `mix test` (or targeted files)
- Final gate before merge: `mix precommit` (compile warnings as errors, format, tests)
- Local DB service (if needed): `docker-compose up -d db`

## Test and integration notes
- Tests use Mox for NewsAPI isolation:
  - mock defined in `test/support/mocks.ex`
  - test env wires `:news_api_impl` to `ClearsightNews.MockNewsApi` in `config/test.exs`
- Keep tests deterministic by asserting behaviour/module contracts, not live third-party API responses.

## Environment and deployment
- Required runtime env vars include `GROQ_API_KEY`, `NEWS_API_KEY`, and `DATABASE_URL` in production.
- Model selection is env-driven (`GROQ_SENTIMENT_MODEL`, `GROQ_RHETORIC_MODEL`, `GROQ_COMPARISON_MODEL`), so avoid hardcoding model names outside defaults.
