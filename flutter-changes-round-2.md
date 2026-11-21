# Flutter repo: changes from changes.docx (round 2)

Apply to a clean checkout of github.com/Marcooooow/Thesis (HEAD e0eb8b6):

    git apply intellibreak-flutter-changes.patch
    flutter pub get && flutter analyze    # not compiled in the sandbox, run this first

## Done in this patch
| Note in changes.docx | What changed |
|---|---|
| Colour distinction for task priorities and card borders | `tasks/widgets/task_priority.dart`; priority pill (dot + word) and priority-coloured border on assigned and team-assignment cards |
| "Other" opens a custom text field | Already existed in the task dialogs; added to the dashboard quick-create dialog (`shift_controller.dart`) |
| Sandbox to simulate notifications, recommendations, work-life balance | `sandbox/screens/demo_sandbox_screen.dart`, opened from Settings > Notifications > "Demo & testing". Local simulation only, nothing saved |
| Pressing a notification opens what it is about | `notifications/notification_navigator.dart`; registered by the employee and manager shells; used by the bell dropdown and the notification center. Solo users never get routed to team pages |
| Improve palette and card-to-background contrast | Page background, card surface and borders separated further in light and dark; remapped across 38 files |
| Change password and more on account security | Settings > Security: "Change password" and "Two-factor authentication" were dead (`onTap: null` and an unreachable screen); both now open their screens |
| More date filters, pick a number of days | Employee analytics: 14/30/90 days + Custom (1-365). Manager analytics: 14/90 days + "Custom days..." |
| Data privacy agreement on account creation | New `legal_dialog.dart` (Terms of Use + Data Privacy Notice, RA 10173 wording). The old Terms link was a TODO that only toggled the checkbox. Checkbox now covers both documents |
| Data collection survey / ML data notice | Data Collection step now also discloses weekly work-life balance check-ins |
| Subtle ticking clock on the left side | `auth/widgets/auth_brand_panel.dart`: split login layout on wide windows, stepping second hand, slow gears, reduced-motion aware |

## Already in the Flutter app (no change needed)
Custom tasks for solo users (task entry bar), password strength meter and 12-character rule (frontend and backend), professional-background fields in registration (job role, industry, department), team members tab, 9-section organization analytics (work-life balance, team comparison, recommendation effectiveness, ML dataset export), ML training pipeline and adapter.

## Please verify before the defense
- Run `flutter analyze` and click through: login (wide and narrow), Settings, a notification press, task cards, both analytics pages, registration.
- The Privacy Notice says research outputs are "intended to be de-identified". The ML export code does not visibly strip identifiers, so confirm or implement that before you present this claim.
- The notice has no contact email; add one on the About page.
- Admin notifications (approvals etc.) are not routed yet; only the employee and manager shells register the handler.
