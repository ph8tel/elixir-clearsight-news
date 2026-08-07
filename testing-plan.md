## Plan: Raise Core Logic Coverage to 80%+

Target is to improve meaningful coverage (core logic and failure paths), not just raw line count. This plan is sequenced into 3 PRs per your preference: unit/service first, then LiveView orchestration.

**Phase 0: Baseline + Guardrails**
1. Run `mix test --cover` and capture baseline overall plus per-module results.
2. Track coverage deltas per PR in a short table.
3. Define completion criteria:
4. Core modules at 80%+ coverage.
5. All critical error/fallback branches have direct assertions.

**PR 1: Core Logic (Highest ROI)**
1. Add test/clearsight_news/article_analyzer_test.exs:
2. `upsert_articles/1` cache hit/miss + URL dedupe behavior.
3. `run_sentiment/1` success/error persistence behavior.
4. `deep_struct_to_map/1` recursion edge cases.
5. `allow_sandbox/1` no-op vs active sandbox path.
6. Expand news_api_service_test.exs:
7. `top_headlines/1` success/error/http error paths.
8. malformed/removed article filtering and date parsing branches.
9. missing API key behavior.
10. Add schema tests:
11. test/clearsight_news/article_test.exs
12. test/clearsight_news/model_response_test.exs
13. Add helper tests in test/clearsight_news_web/article_helpers_test.exs:
14. score/date formatting thresholds.
15. emotion/loaded-language edge behavior.
16. scheduling semantics for queued analysis messages.

**PR 2: Analysis Edge Cases**
1. Expand analysis_test.exs:
2. malformed/partial sentiment payload parsing.
3. retry loop behavior (fail-then-success and fail-all-attempts).
4. truncation boundary behavior around 4000 chars.
5. compatibility test for both sentiment parse sources:
6. `message.content` JSON.
7. tool-call arguments fallback.

**PR 3: LiveView Orchestration Coverage**
1. Expand results_live_test.exs:
2. fetch failure rendering and recovery.
3. analysis-result updates reflected in active/mobile and desktop views.
4. compare button visibility rules and navigation.
5. Add test/clearsight_news_web/live/search_live_test.exs:
6. headlines loading/success/failure flow.
7. flash behavior and message handling.
8. Add test/clearsight_news_web/live/compare_live_test.exs:
9. valid/invalid mount behavior.
10. async loading, success, and failure states for rhetoric/comparison.

**Verification Per PR**
1. Run `mix test`.
2. Run `mix test --cover`.
3. Run `mix precommit`.
4. Record module-by-module coverage changes in PR notes.
5. Enforce “no net decrease” in coverage for core modules.

**Scope Boundaries**
1. Included: business logic, service boundaries, schema validations, LiveView event/message orchestration.
2. Excluded: low-value framework boilerplate and CSS-only tests.

I also saved this plan to session memory at /memories/session/plan.md so we can execute it step-by-step without losing context.