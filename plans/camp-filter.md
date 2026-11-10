# Camp filter for Chart and Numbers

## Goal

Add a shared camp filter to both the Chart and Numbers views: **All / Silent /
Non-silent**. The filter narrows the games shown in each view. Remove the
`Camp` column from the Numbers table (wide and compact) because the filter
already tells the reader which camp is in view.

## Context

- `lib/stats/logic/stats.dart` defines `Camp` and `GameStats`, and has
  `summarizeCamps`, `campLabel`, `metricLabel`.
- `lib/stats/ui/chart.dart` is a stateless `ComparisonChart` that renders a
  `_GameGroup` per game, with a `SILENT` / `NON-SILENT` label per game.
- `lib/stats/ui/numbers.dart` is a stateless `NumbersComparison` with a wide
  `DataTable` and a compact expandable list, plus a `_VerdictPanel` that
  compares the two camps.
- The table is grouped by camp and already has `Silent total` /
  `Non-silent total` / `... average` rows, so the `Camp` column is redundant.
- `lib/main.dart` owns the top-level destinations; the chart and numbers are
  separate destinations, so each view owns its own filter state.

## Design decisions

- **Filter type:** `Camp?` — `null` means "All", `Camp.silent` means "Silent",
  `Camp.nonSilent` means "Non-silent".
- **Shared widget:** add `CampFilter` in `lib/stats/ui/camp_filter.dart`, a
  `SegmentedButton<Camp?>` with `All`, `Silent`, `Non-silent` segments. It
  takes `selected` and `onChanged`.
- **Shared helper:** add `filterByCamp(List<GameStats>, Camp?)` to
  `lib/stats/logic/stats.dart`.
- **Chart:** make `ComparisonChart` stateful. It owns `_camp`, renders the
  `CampFilter` above the scrollable chart, and computes `maxValue` from the
  filtered games. The per-game `SILENT` / `NON-SILENT` labels stay.
- **Numbers:** make `NumbersComparison` stateful. It owns `_camp`, renders the
  `CampFilter` above the table, and passes the filtered games plus `_camp` to
  `_StatsTable`. The `_VerdictPanel` only appears when `_camp == null` (All);
  when a single camp is selected, the comparison verdict is meaningless.
- **Table:** remove the `Camp` column from both the wide `DataTable` and the
  compact list. In the wide table, the `Camp` `DataCell` and the spacer
  `DataCell` in footer rows are removed. In the compact list, remove the
  `Camp` header cell, the camp label cell, and the `_campColumnWidth` spacer.
  The `_campColumnWidth` constant becomes unused and is removed.
- **Camp grouping:** `_StatsTable` and `_CompactStatsList` loop over
  `Camp.values` when `camp == null`, and only over the selected camp when
  `camp != null`. This keeps the subtotal rows to the selected camp.

## Implementation steps

1. `lib/stats/logic/stats.dart`: add `filterByCamp`.
2. `lib/stats/ui/camp_filter.dart`: new `CampFilter` widget.
3. `lib/stats/ui/chart.dart`: make `ComparisonChart` stateful, add the filter
   bar, filter the games, and compute the max from the filtered games.
4. `lib/stats/ui/numbers.dart`: make `NumbersComparison` stateful, add the
   filter bar, pass the filtered games and `_camp` to `_StatsTable`, hide the
   verdict panel when filtered, and remove the `Camp` column from both table
   layouts.
5. Tests:
   - `test/camp_filter_test.dart`: filter renders all three options and
     reports the selected camp.
   - `test/chart_widget_test.dart`: chart shows the filter, selecting Silent
     hides non-silent games, selecting Non-silent hides silent games, and
     returning to All restores every game.
   - `test/numbers_widget_test.dart`: Numbers shows the filter, selecting a
     camp hides the other camp, the `Camp` column is gone from both layouts,
     and the verdict is hidden when filtered.
   - `test/home_tabs_test.dart`: update the narrow-table test name and add a
     `Camp` findsNothing assertion; the existing default-All assertions should
     keep passing.

## Verification

- `flutter test`
- `dart analyze`
