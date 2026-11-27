import 'package:flutter/material.dart';

enum LegalDoc { terms, privacy }

/// Opens the Terms of Use or the Data Privacy Notice in a scrollable dialog.
Future<void> showLegalDialog(BuildContext context, LegalDoc doc) {
  final isPrivacy = doc == LegalDoc.privacy;
  final sections = isPrivacy ? _privacySections : _termsSections;
  final theme = Theme.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(isPrivacy ? 'Data Privacy Notice' : 'Terms of Use', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                shrinkWrap: true,
                children: [
                  Text(
                    'Draft for a capstone research system. Last updated November 2026.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  for (final s in sections) ...[
                    Text(s.$1, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(s.$2, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

const List<(String, String)> _privacySections = [
  (
    'Who we are',
    'IntelliBreak is a capstone research system of Dr. Yanga\'s Colleges, Inc. (DYCI). The research team acts as the personal information controller for the data described here.',
  ),
  (
    'What we collect',
    'Account details (name, email, role, account type); profile information you provide (including age, gender, education, marital status, experience, job role, industry, and work schedule); work sessions, shifts, breaks and tasks you record; attendance or leave information when you use those features; post-session and weekly work-life-balance check-ins; messages you send; and recommendation feedback (accepted, dismissed, helpful, or not helpful). During registration, the system records the Terms of Use and Data Privacy Notice versions you accepted and the acceptance timestamps.',
  ),
  (
    'What we do not collect',
    'IntelliBreak does not record your screen, keystrokes, webcam, microphone or location.',
  ),
  (
    'Why we collect it',
    'To run the features you use (shift and break tracking, the Break Coach, your work-life balance check-in and habit suggestions), to improve recommendations using your recorded patterns and feedback, and to evaluate the system for the thesis. Recommendations use a rule-based baseline when a trained model is unavailable. Scores and recommendations are advisory reflections, not medical or psychological diagnoses.',
  ),
  (
    'Who can see your data',
    'Solo accounts: only you. Organization accounts: you, and your organization\'s managers and administrators, limited to what their role allows. Research outputs are intended to be de-identified before they are shared or published.',
  ),
  (
    'Your rights under the Data Privacy Act of 2012 (RA 10173)',
    'You may ask to access your data, correct it, object to its processing, withdraw your consent, and have your account and its related records deleted. You can delete your account in the app; deleting it removes your profile and its related work sessions, breaks, tasks and recommendations. New registrations record the notice versions accepted and their timestamps.',
  ),
  (
    'How long we keep it',
    'While your account is active, and for no longer than needed for the research and evaluation described above. De-identified research data may be kept for the duration of the study.',
  ),
  (
    'Security',
    'Passwords are stored as hashes, access is controlled by role, and two-factor authentication is available for your account.',
  ),
  (
    'Contact',
    'Questions or requests about your data can be sent to the IntelliBreak research team through your thesis adviser or the contact email provided on the system\'s About page.',
  ),
];

const List<(String, String)> _termsSections = [
  (
    'Purpose',
    'IntelliBreak helps remote and hybrid workers pace their work, take breaks and keep a sustainable work-life balance. It is a research prototype.',
  ),
  (
    'Not medical advice',
    'Recommendations, scores and risk indicators are advisory reflections of your own recorded patterns. They are not a medical or psychological assessment. If you are struggling, please contact a qualified professional.',
  ),
  (
    'Your account',
    'You are responsible for the accuracy of the information you enter and for keeping your password and authenticator app secure. Use a strong password of at least 12 characters.',
  ),
  (
    'Acceptable use',
    'Do not attempt to access other users\' data, interfere with the system, or enter information you do not have the right to share.',
  ),
  (
    'Organization accounts',
    'If you join an organization, its managers and administrators can see the information their role allows, as described in the Data Privacy Notice.',
  ),
  (
    'Prototype notice',
    'The system is provided as-is for research and evaluation. Features may change, and data entered during testing may be reset.',
  ),
  (
    'Changes',
    'These terms may be updated. Continued use after an update means you accept the revised terms.',
  ),
];
