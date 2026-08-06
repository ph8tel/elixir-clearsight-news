## Plan: Mobile Sentiment Tabs Theme

Implement a mobile-first tabbed layout on the Results page so sentiment content is shown in one column under a top tab bar, while preserving the existing 3-column desktop behavior. Reuse existing sentiment grouping and article card logic to minimize risk, and add LiveView tests for tab switching plus responsive rendering assumptions.

**Steps**
1. Confirm and lock UI behavior contracts in Results page state model: mobile-only tab UX, desktop unchanged, tab order Positive -> Neutral -> Negative, and default active tab handling during load/error/content states.
2. Phase 1 - LiveView state updates in /home/ph8l/elixir-clearsight-news/lib/clearsight_news_web/live/results_live.ex:
   1. Add assign for selected sentiment tab in mount (for example :positive) and ensure it survives incremental sentiment updates from analysis messages.
   2. Add a new handle_event for tab switching (e.g., "switch_tab") with validated tab values to avoid invalid atom creation and malformed params.
   3. Keep existing sentiment column derivation (Analysis.classify + grouped assigns) as the single source of truth; do not duplicate classification logic.
3. Phase 2 - Results page render refactor in /home/ph8l/elixir-clearsight-news/lib/clearsight_news_web/live/results_live.ex:
   1. Replace hardcoded grid usage with responsive branching: mobile shows tab nav + single active sentiment column; md+ keeps current three-column view.
   2. Reuse existing column/article_card components for both mobile and desktop views to prevent behavior drift in selection buttons, badges, and links.
   3. Add mobile tab button UI with count badges from col_positive/col_neutral/col_negative and clear active/inactive states using existing theme tokens.
   4. Ensure loading and error states render appropriately for both breakpoints (mobile skeleton for active tab, desktop 3-column skeleton remains).
4. Phase 3 - Mobile theme styling adjustments:
   1. Add focused CSS utilities in /home/ph8l/elixir-clearsight-news/assets/css/app.css for a sticky, horizontally scrollable tab rail if needed on narrow screens.
   2. Keep styling aligned with daisyUI semantic colors (error/ghost/success) and existing border/radius conventions.
   3. Ensure touch targets, spacing, and typography meet mobile readability expectations without changing desktop typography scale.
5. Phase 4 - Optional app-level consistency pass (non-breaking):
   1. Audit Search and Compare views for obvious mobile overflow and apply lightweight breakpoint fixes only where required for consistency.
   2. Explicitly avoid introducing sentiment tabs outside Results per current scope decision.
6. Phase 5 - Test coverage updates:
   1. Update or add LiveView tests for Results in /home/ph8l/elixir-clearsight-news/test/clearsight_news_web/live/results_live_test.exs (or create if missing) to assert tab controls exist on mobile render path and switching tab updates visible sentiment column content.
   2. Preserve existing behavior tests for selecting Primary/Reference and compare navigation.
   3. Add selector-based assertions using stable DOM IDs/data attributes for tab buttons and active panel containers.
7. Phase 6 - Verification and regression checks:
   1. Run targeted tests for Results LiveView.
   2. Run full project checks via mix precommit after implementation.
   3. Manually validate on a mobile viewport: tab switching, article selection actions, pending analysis updates, and no layout breakage when counts are zero.

**Relevant files**
- /home/ph8l/elixir-clearsight-news/lib/clearsight_news_web/live/results_live.ex - Primary implementation target; currently owns sentiment grouping, article selection events, and 3-column rendering.
- /home/ph8l/elixir-clearsight-news/lib/clearsight_news_web/article_helpers.ex - Reuse existing helpers for score/emoji/loaded-language display and analysis scheduling behavior.
- /home/ph8l/elixir-clearsight-news/assets/css/app.css - Add minimal mobile tab-rail/theme utilities if Tailwind/daisyUI utility classes are insufficient.
- /home/ph8l/elixir-clearsight-news/test/clearsight_news_web/live/results_live_test.exs - Add/adjust test coverage for mobile tab behavior and regressions.
- /home/ph8l/elixir-clearsight-news/lib/clearsight_news_web/live/search_live.ex - Reference existing responsive grid pattern for consistency (no tab implementation planned here).
- /home/ph8l/elixir-clearsight-news/lib/clearsight_news_web/live/compare_live.ex - Optional consistency audit target for mobile breakpoint improvements only.

**Verification**
1. Run mix test test/clearsight_news_web/live/results_live_test.exs and confirm tab-switch interactions and article controls still pass.
2. Run mix precommit and ensure compile, format, and tests all pass under project alias.
3. Manual viewport verification at ~375px width on Results page:
   1. Tabs appear in selected order and show counts.
   2. Only one sentiment list is visible at a time.
   3. Primary/Reference selection buttons still work within active tab.
   4. Pending analyses move cards between tabs correctly as scores arrive.
4. Manual desktop verification at >= md breakpoint:
   1. Existing 3-column layout remains unchanged.
   2. Compare button and card actions remain intact.

**Decisions**
- Included scope: mobile tabbed sentiment layout on Results page.
- Excluded scope: converting Search or Compare to sentiment tabs.
- Responsive policy: desktop/tablet keeps existing columns; mobile uses tabs.
- Chosen tab order from alignment: Positive -> Neutral -> Negative.

**Further Considerations**
1. Default active tab recommendation: keep Positive as initial tab for continuity with chosen order; optionally auto-focus the first non-empty tab if Positive is empty.
2. Accessibility recommendation: include aria-selected, role=tablist/tab/panel, and keyboard support for robust mobile/desktop hybrid behavior.
3. Performance recommendation: continue reusing pre-grouped assigns instead of filtering lists in template to keep render cheap during incremental analysis updates.

**Implementation Status (Completed)**
1. Phase 1 complete: Results state model now tracks active mobile tab and validates tab-switch events.
2. Phase 2 complete: Results uses mobile tabbed single-column rendering while preserving desktop three-column layout.
3. Phase 3 complete: mobile tab rail styling and top-area spacing polish applied.
4. Phase 4 complete: Search and Compare received lightweight responsive overflow and stacking fixes.
5. Phase 5 complete: expanded Results LiveView tests cover tab switching content and compare-flow interactions.
6. Phase 6 complete:
   1. Targeted Results tests pass.
   2. Full suite passes.
   3. mix precommit passes (compile/format/tests gate).
   4. Manual mobile verification reported as successful.
