import 'package:flutter/material.dart';

/// Work Schedule section for Create Employee form
/// Reuses existing Profile schedule fields via backend /employees endpoint
class WorkScheduleSection extends StatefulWidget {
  final Function(String start, String end, List<String> days)? onChanged;
  final String? initialStart;
  final String? initialEnd;
  final List<String>? initialDays;

  const WorkScheduleSection({
    super.key,
    this.onChanged,
    this.initialStart,
    this.initialEnd,
    this.initialDays,
  });

  @override
  State<WorkScheduleSection> createState() => _WorkScheduleSectionState();
}

class _WorkScheduleSectionState extends State<WorkScheduleSection> {
  String startTime = '08:00';
  String endTime = '17:00';
  final Set<String> selectedDays = {'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'};

  final List<String> days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialStart != null) startTime = widget.initialStart!;
    if (widget.initialEnd != null) endTime = widget.initialEnd!;
    if (widget.initialDays != null) selectedDays.addAll(widget.initialDays!);
  }

  void _notify() {
    widget.onChanged?.call(startTime, endTime, selectedDays.toList());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Work Schedule',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: startTime,
                decoration: const InputDecoration(
                  labelText: 'Shift Start Time',
                  border: OutlineInputBorder(),
                  hintText: '08:00',
                ),
                onChanged: (v) {
                  startTime = v;
                  _notify();
                },
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: endTime,
                decoration: const InputDecoration(
                  labelText: 'Shift End Time',
                  border: OutlineInputBorder(),
                  hintText: '17:00',
                ),
                onChanged: (v) {
                  endTime = v;
                  _notify();
                },
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Working Days',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: days.map((day) {
            final selected = selectedDays.contains(day);
            return FilterChip(
              label: Text(day),
              selected: selected,
              onSelected: (sel) {
                setState(() {
                  if (sel) {
                    selectedDays.add(day);
                  } else {
                    selectedDays.remove(day);
                  }
                });
                _notify();
              },
              showCheckmark: true,
             checkmarkColor: isDark ? Colors.white : Colors.black,
              selectedColor: Theme.of(context).colorScheme.primary,
            );
          }).toList(),
        ),
        if (selectedDays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Select at least one working day.',
                style: TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }
}
