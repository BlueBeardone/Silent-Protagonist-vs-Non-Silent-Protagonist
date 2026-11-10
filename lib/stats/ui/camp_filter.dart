import 'package:flutter/material.dart';

import '../logic/stats.dart';

/// A filter bar for the camp whose games are shown. A null [selected] means
/// "All"; otherwise only that camp's games are shown.
class CampFilter extends StatelessWidget {
  const CampFilter({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Camp? selected;
  final ValueChanged<Camp?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<Camp?>(
        segments: const [
          ButtonSegment(value: null, label: Text('All')),
          ButtonSegment(value: Camp.silent, label: Text('Silent')),
          ButtonSegment(value: Camp.nonSilent, label: Text('Non-silent')),
        ],
        selected: {selected},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}
