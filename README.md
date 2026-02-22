# ClearSight News

ClearSight News is a Phoenix LiveView app for comparing how news outlets frame the same topic.

## Live demo

- App: https://clearsight-news.fly.dev/


## Current app behavior

1. Enter a topic on the search page.
2. The app fetches recent English-language articles from NewsAPI.
3. Articles are deduplicated/upserted by URL in Postgres.
4. Each article is analyzed with Groq via Instructor for sentiment signals.
5. Results are grouped into Positive / Neutral / Negative columns.
6. You can pick a primary and reference article, then run side-by-side rhetoric + cross-article comparison.

Model responses are persisted with status/latency/structured output for traceability.

## Stack

- Elixir / Phoenix 1.8 / LiveView
- Ecto + PostgreSQL
- Req (NewsAPI client)
- Instructor + Groq (structured LLM analysis)
- Tailwind + daisyUI

## Local development

### 1) Start Postgres

Use Docker:

`docker-compose up -d db`

### 2) Set required environment variables

- `GROQ_API_KEY`
- `NEWS_API_KEY`

### 3) Setup and run

- `mix setup`
- `mix phx.server`

Then open http://localhost:4000.

## Tests

- Run all tests: `mix test`
- Final local gate: `mix precommit`

Tests use Mox to mock the NewsAPI behavior in test env.

## Deployment notes

- Hosted on Fly.io (`fly.toml`)
- Production runtime expects at least:
	- `DATABASE_URL`
	- `SECRET_KEY_BASE`
	- `GROQ_API_KEY`
	- `NEWS_API_KEY`
