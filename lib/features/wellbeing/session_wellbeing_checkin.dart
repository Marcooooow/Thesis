/// Session Wellbeing Check-in Modal
/// Compact centered modal with dark semi-transparent backdrop.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intellibreak/core/config/api_config.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/core/error_handling.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class SessionWellbeingCheckin extends StatefulWidget {
  final String workSessionId;
  const SessionWellbeingCheckin({Key? key, required this.workSessionId}) : super(key: key);
  @override
  State<SessionWellbeingCheckin> createState() => _SessionWellbeingCheckinState();
}

class _SessionWellbeingCheckinState extends State<SessionWellbeingCheckin> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _error;
  int? _overallWellbeing;
  int? _mentalFatigue;
  int? _workloadManageability;
  int? _perceivedFocus;
  int? _breakRecovery;
  List<String> _stressFactors = [];
  String? _notes;

  static const List<String> _stressFactorOptions = [
    'Heavy workload',
    'Difficult task',
    'Too many interruptions',
    'Lack of focus',
    'Long periods without a break',
    'Breaks were helpful',
    'Technical problems',
    'Personal distractions',
    'I felt tired',
    'Nothing significant',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHighContrast = themeController.isHighContrast;

    return Dialog(
      backgroundColor: const Color(0xFF1A1D23),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 680),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Session Wellbeing Check-in',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 21,
                                color: Colors.white,
                              ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close',
                        padding: const EdgeInsets.all(8),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 4),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'How was your work session?',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Take a moment to check in with yourself. Your answers help IntelliBreak understand your work patterns and improve future break recommendations.',
                              style: TextStyle(
                                fontSize: 14.5,
                                color: Colors.white70,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 22),
                            ..._buildQuestions(context, isDark, isHighContrast),
                            const SizedBox(height: 22),
                            Text(
                              'What affected your work session?',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 8,
                              children: _stressFactorOptions.map((option) {
                                final selected = _stressFactors.contains(option);
                                return FilterChip(
                                  label: Text(
                                    option,
                                    style: TextStyle(
                                      color: selected ? Colors.white : Colors.white70,
                                      fontSize: 13,
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                  selected: selected,
                                  onSelected: (s) => setState(() {
                                    if (s) {
                                      _stressFactors.add(option);
                                    } else {
                                      _stressFactors.remove(option);
                                    }
                                  }),
                                  selectedColor: Theme.of(context).colorScheme.primary,
                                  checkmarkColor: Colors.white,
                                  backgroundColor: Colors.white.withOpacity(0.06),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: selected
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.white.withOpacity(0.18),
                                      width: 1.2,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              'Anything else you\'d like to note?',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              maxLines: 3,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Optional notes',
                                hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: const Color(0xFF23252D),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              onSaved: (value) => _notes = value,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        label: const Text(
                          'Skip for now',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _submitCheckin,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Submit Check-in'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildQuestions(BuildContext context, bool isDark, bool isHighContrast) {
    return [
      _buildScaleQuestion(context, 'How do you feel after this work session?', _overallWellbeing, (v) => setState(() => _overallWellbeing = v), ['Very stressed','Stressed','Okay','Good','Very good']),
      const SizedBox(height: 22),
      _buildScaleQuestion(context, 'How mentally tired do you feel?', _mentalFatigue, (v) => setState(() => _mentalFatigue = v), ['Not tired at all','Slightly tired','Moderately tired','Very tired','Extremely tired']),
      const SizedBox(height: 22),
      _buildScaleQuestion(context, 'How manageable did your workload feel?', _workloadManageability, (v) => setState(() => _workloadManageability = v), ['Very difficult','Difficult','Manageable','Easy','Very easy']),
      const SizedBox(height: 22),
      _buildScaleQuestion(context, 'How focused did you feel during this session?', _perceivedFocus, (v) => setState(() => _perceivedFocus = v), ['Very unfocused','Somewhat unfocused','Neutral','Focused','Very focused']),
      const SizedBox(height: 22),
      _buildScaleQuestion(context, 'Did your breaks help you recover?', _breakRecovery, (v) => setState(() => _breakRecovery = v), ['Not at all','A little','Somewhat','Quite a lot','Very much']),
    ];
  }

  Widget _buildScaleQuestion(BuildContext context, String question, int? value, Function(int) onChanged, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(question, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 8,
          children: options.asMap().entries.map((entry) {
            final index = entry.key;
            final label = entry.value;
            final selected = value == index + 1;
            return GestureDetector(
              onTap: () => onChanged(index + 1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFF23252D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? Theme.of(context).colorScheme.primary : Colors.white.withOpacity(0.22),
                    width: 1.1,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (value == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Please select an option', style: TextStyle(color: Colors.redAccent.withOpacity(0.85), fontSize: 12.5)),
          ),
        const SizedBox(height: 6),
      ],
    );
  }

  Future<void> _submitCheckin() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    if (_overallWellbeing == null ||
        _mentalFatigue == null ||
        _workloadManageability == null ||
        _perceivedFocus == null ||
        _breakRecovery == null) {
      showError(context, 'Please answer all required questions', isDialog: false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) throw Exception('Not authenticated');
      final Map<String, dynamic> data = {
        'work_session_id': widget.workSessionId,
        'overall_wellbeing': _overallWellbeing,
        'mental_fatigue': _mentalFatigue,
        'workload_manageability': _workloadManageability,
        'perceived_focus': _perceivedFocus,
        'break_recovery': _breakRecovery,
        if (_stressFactors.isNotEmpty) 'stress_factors': _stressFactors,
        if (_notes != null && _notes!.isNotEmpty) 'notes': _notes,
      };
      final url = Uri.parse('${ApiConfig.baseUrl}/session-wellbeing');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session check-in submitted successfully'), duration: Duration(seconds: 2)),
          );
        }
      } else {
        throw Exception('Failed to submit check-in: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        showError(context, 'Failed to submit check-in: $e', isDialog: false);
      }
    }
  }
}