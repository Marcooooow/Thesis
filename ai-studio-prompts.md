# IntelliBreak AI Studio prototype: prompt pack

Use this for the web prototype shown in your screenshots (sidebar with Team Management / Work Monitoring, mock users Elena, Marcus, Sofia, Liam). The Flutter repo is handled separately by `intellibreak-flutter-changes.patch`.

How to use it:

1. Paste the **System Instruction** below into AI Studio once per session.
2. Paste **one prompt at a time**, in order. Start a fresh session for each prompt if the app is large.
3. After each prompt, run the app, check the **Acceptance** list, then commit before the next prompt.
4. If AI Studio adds anything not listed under Task, reply: "Revert everything not listed in Task."

---

## System Instruction (paste once)

```
You are a senior front-end engineer working on IntelliBreak, a workplace focus and work-life balance system (capstone thesis prototype).

Stack: use exactly what the existing project already uses. Read package.json and the existing files before changing anything. Do not change library versions.

Roles that exist in the prototype: Employee (organization), Solo user, Manager, Administrator. All data is mock data. There is no real backend.

BEHAVIOR
1. Do only what the prompt's Task section asks. Nothing more.
2. Before editing, read every file you will touch and scan it for obvious bugs. Report bugs you see but only fix the ones that block the task.
3. Write a short to-do list first. If a change would rename, move or delete existing files, stop and ask first.
4. Never remove or restyle features that are not mentioned in the Task.
5. After finishing, list the files you changed and append a short entry to docs/activity-log.md. Do not create other markdown files.
6. Code comments: one line, one sentence, plain text, no emojis.

CODE QUALITY
7. Simplest correct implementation. No new abstractions or design patterns unless the Task requires them.
8. No new external libraries. Use what is already installed and built-in browser APIs.
9. Use appropriate data structures (Map or Set where lookups matter, not arrays everywhere).
10. Keep components small. Reuse existing components and design tokens before creating new ones.

UX AND DESIGN (every screen you touch)
11. Provide loading, empty and error states.
12. WCAG AA contrast in both light and dark mode. Never use colour alone to convey meaning: pair colour with text or an icon.
13. Everything operable by keyboard with visible focus. Respect prefers-reduced-motion.
14. Layout works from 375px width up to desktop.
15. Tone: professional, calm, restrained. No gradients on text, no glow effects, no emoji in the UI.
16. Behavioural scores and recommendations are advisory, never medical or psychological diagnoses. Keep that wording on any screen that shows them.

SECURITY AND PRIVACY
17. Validate and trim all user input. Escape anything rendered from user input.
18. No real personal data, credentials, API keys or tokens anywhere. Mock users only.
19. Show safe error messages only, never raw error objects.

OUTPUT
20. Output only the files you changed or created, each starting with its full path in a one-line comment.
```

---

## Prompt 1: Custom task names (all roles, including solo)

```
TASK
Let users type their own task name wherever a task is chosen.

1. Dashboard shift card: the "Current Task" / "Pre-shift Task (optional)" dropdown gets a final option "+ Add custom task...". Choosing it reveals a text input (max 120 characters) with an "Add" button. On Add, the task is created for the current user with category "Other", priority "Medium", is selected immediately, and appears in the dropdown from then on.
2. Tasks page, "My Tasks" tab: solo users and employees can create their own tasks with title, category, priority and optional due date. Solo users have no "Assigned to Me" tab, so My Tasks is their only tasks tab.
3. Empty title or whitespace-only titles are rejected with an inline message. Duplicate titles (case-insensitive) for the same user are allowed but the second one gets " (2)".

ACCEPTANCE
- A solo user with no tasks can create a task from the dashboard dropdown and see it in My Tasks.
- The custom task shows as the current task on the running shift timer.
- Keyboard: Enter submits the custom task input, Escape cancels it.

DO NOT add task editing, deletion, drag-and-drop or recurring tasks.
```

## Prompt 2: Task priority colours, card borders, and "Other" with custom text

```
TASK
1. Priority styling. Priorities: Low, Medium, High, Urgent. Give each a colour token (Low: green, Medium: amber, High: orange, Urgent: red), defined for both light and dark mode with AA contrast. Apply to every task card: a 1.5px border in the priority colour, and a small pill showing a dot plus the word, for example "High priority". Priority must be readable without colour (the word is always shown).
2. Completed tasks keep their priority border but at reduced opacity, with the title struck through as today.
3. Category dropdown (create task dialog and the category filter): add "Other" as the last option. When "Other" is chosen in the create or edit dialog, show a text input "Custom category" (required, max 100 characters). The saved category is the typed text. Custom categories then appear in the filter dropdown for that user.

ACCEPTANCE
- All four priorities are visually distinct in light and dark mode and pass AA contrast.
- Choosing Other without typing a custom category blocks submit with an inline message.

DO NOT change task statuses, add new priorities, or alter the Log Time flow.
```

## Prompt 3: Notifications open what they refer to

```
TASK
Pressing a notification (in the bell dropdown and on the full notifications page) marks it read and navigates to the related screen.

Mapping by notification type:
- New Task Assigned, task due: Tasks page, "Assigned to Me" tab
- Weekly Break Compliance, report ready: Analytics page
- Break recommendation, lunch reminder, coach prompt: Dashboard, scrolled to the Break Coach panel
- Work-life balance check-in or score change: Work-Life Balance page
- Team invitation, team member change: Team View (hidden for solo users, fall back to Dashboard)
- Approval request (admin): Approvals page
- Wellbeing alert (manager): Team Well-being page

Close the dropdown after navigating. Types with no mapping just mark as read. Add an optional "target" field to the mock notification objects rather than parsing titles.

ACCEPTANCE
- Each existing mock notification opens the right page for its role.
- A solo user never lands on a team page.

DO NOT add real-time push or sound.
```

## Prompt 4: Demo sandbox (notifications, recommendations, work-life balance)

```
TASK
Add a "Demo sandbox" page, reachable from Settings (section "Demo & testing") for every role. Its purpose is to let panelists see how the system reacts. Everything is simulated and nothing persists.

Layout: a banner "Sandbox: simulated data only", scenario chips, controls on the left, live output on the right (stacked on mobile).

Scenario chips (each fills the controls): Healthy rhythm, Long focus block, Skipped lunch, Overtime week, Burnout risk.

Controls: continuous focus minutes (0-180), breaks taken today (0-8), lunch taken (toggle), hours worked this week (0-70), days with after-hours work (0-7), and the five weekly check-in answers (1-5): Disconnecting, Personal time, Balance, Schedule, Recovery.

Live output, recomputed on every change:
1. Notifications: the notifications the system would raise (lunch reminder if no lunch; short-break if focus >= 90 and no breaks; stretch if focus >= 60; overtime pattern if weekly hours > 45; evening boundary if after-hours days >= 3; work-life balance check-in if score < 50; otherwise "On a healthy rhythm").
2. Break Coach recommendation: highest priority candidate in this order: LUNCH, SHORT_BREAK, WALK, STRETCH, HYDRATE. Show title, why, action, expected outcome, and Accept / Snooze 5 min / Dismiss buttons that show "Feedback recorded (sandbox only)".
3. Work-life balance: score = ((sum of five answers - 5) / 20) * 100, a ring gauge, a trend label (>=70 improving, <50 declining, else stable), and the five answers as bars.

ACCEPTANCE
- Picking "Burnout risk" produces a low score, several notifications, and a LUNCH recommendation.
- Nothing is written to storage or the notification bell.

DO NOT call any API or add charts beyond the ring and bars.
```

## Prompt 5: Richer organization analytics (Administrator)

```
TASK
Extend the Organization Analytics page. Keep the two existing charts and add the sections below. All numbers come from the existing mock dataset (extend the mock data if needed, keep it deterministic).

1. KPI row: active employees, average daily hours, break compliance, recommendation acceptance rate, average work-life balance score, overtime incidence.
2. Work-life balance: average score trend over 8 weeks (line), score distribution (Excellent, Good, Fair, Poor, Critical) as a bar, and check-in completion rate.
3. Department table: department, headcount, break compliance, average WLB score, overtime days. Sortable by clicking headers.
4. Recommendation effectiveness: accepted / snoozed / dismissed split per recommendation type.
5. Filters: date range (7, 14, 30, 90 days, custom number of days 1-365) and department.
6. Privacy: any group with fewer than 5 people shows "Not enough data to protect privacy" instead of numbers.
7. Export: "Download CSV" for the department table.

ACCEPTANCE
- Changing the date range or department updates every section.
- A department with fewer than 5 mock employees shows the privacy message.

DO NOT add real PDF generation or new chart libraries; draw simple SVG or use the charting already in the project.
```

## Prompt 6: View team members (Administrator and Manager)

```
TASK
1. Teams & Organization (admin): clicking a team card opens a detail panel or page with the roster: name, role, department, status, and a "Lead" badge. Add search by name. Admins can remove a member (confirmation dialog) and add an existing organization user to the team.
2. Team View (manager): same roster for the manager's own team, read-only except for the manager's existing actions.
3. Member counts on the cards update after add or remove.
4. Do not show individual wellbeing or check-in details in the roster.

ACCEPTANCE
- Opening "Core Product Engineering" lists its 5 members, with Marcus Chen as Lead.
- Removing a member updates the count to 4 and the member disappears.

DO NOT add messaging, invitations by email, or role editing.
```

## Prompt 7: Colour palette and card contrast (light and dark)

```
TASK
Revise the design tokens so cards stand out from the page background in both themes, and fix the overall palette. Change tokens only, not component structure.

Light: page background a cool grey (about #ECEFF3), cards white with a 1px border (about #D3D9E1), primary text #111827, secondary text #5B6472.
Dark: page background about #0E1217, cards about #182029 with a 1px border (about #2D3643), primary text #E8EBEF, secondary text #9AA3AF.
Accent: one deep teal (#0F766E) in light mode; lighten it to about #2DB5A6 for text, rings and selected states in dark mode so it meets AA. Buttons use the accent with white or near-black text, whichever passes AA.

Also: remove drop shadows from cards (borders only), keep the selected sidebar item as a tinted background with accent text, and make the "Light/Dark" toggle visible in the header.

ACCEPTANCE
- In both themes the card edge is clearly visible against the background without zooming.
- Run a contrast check on body text, secondary text, buttons and the accent on cards: all at least 4.5:1.

DO NOT change layout, spacing, fonts or component behaviour.
```

## Prompt 8: Account security (change password and more)

```
TASK
Settings > Security becomes a working panel:
1. Change password: current password, new password, confirm. Show the strength meter and requirements from Prompt 10 (shared component). Reject when current password is wrong (mock check), new equals current, or confirm does not match.
2. Two-factor authentication: enable or disable with a mock authenticator setup (QR placeholder, 6-digit code input; accept any 6 digits in the mock). Show status clearly.
3. Active sessions: list of mock sessions (device, last active) with "Sign out" and "Sign out of all other sessions".
4. Success and failure use inline messages, not alerts.

ACCEPTANCE
- Changing the password updates the mock credential so the next mock login uses it.
- Security panel shows a text status for 2FA ("On" / "Off"), not just a colour.

DO NOT add email flows or real TOTP libraries.
```

## Prompt 9: Date filters with a custom number of days

```
TASK
On every analytics page that has the 7D / 14D / 30D control (including Work-Life Balance Analytics), extend it to: 7D, 14D, 30D, 90D and "Custom". Custom opens a small popover with a number input (whole number 1-365) and quick chips (3, 5, 10, 21, 45, 60). Apply updates all KPIs and charts on the page. The active custom value is shown on the control, for example "21D".

ACCEPTANCE
- Entering 0, 400, blank or a decimal shows an inline error and does not apply.
- Charts rescale for 1 day (single point) and 365 days (aggregate to weekly points above 90 days).

DO NOT add a calendar range picker.
```

## Prompt 10: Account creation: privacy agreement, password strength, professional background, ML data survey

```
TASK
Rebuild the Create Account flow as a stepper with a progress bar. Steps:
1. Account: name, email, password with live strength meter and requirements checklist, confirm password.
2. Account type: Solo or Organization (Organization shows an organization code field).
3. Personal and work basics: job role, industry, department, years of experience, work arrangement (Remote / Hybrid / Office / Other), schedule type (Flexible / Variable / Other). Do not offer a "Fixed" schedule. Every dropdown has a final "Other" option that reveals a required text input.
4. Professional background questionnaire (for ML data collection): typical weekly work hours, typical focus block length, typical breaks per day, lunch habit, after-hours work frequency, work-from-home years, caregiving or other daily responsibilities (multi-select, optional), self-rated stress level (1-5). All optional except weekly hours; add a "Prefer not to say" option where sensitive.
5. Machine learning data survey (shown after Terms and Privacy are accepted): explain in plain language which data trains the prediction system and let the user choose: "Use my data to personalise my recommendations" (default on) and "Include my de-identified data in the research dataset" (default off).
6. Terms and privacy: two required checkboxes, "I agree to the Terms of Use" and "I agree to the Data Privacy Notice", each with a link that opens the full text in a dialog. The Privacy Notice must follow the Philippine Data Privacy Act of 2012 (RA 10173): what is collected, why, who can see it, retention, and the rights to access, correct, object, withdraw consent and delete. State that the system does not record screen, keystrokes, webcam, microphone or location.

Password rules (shared component, also used when changing password): at least 12 characters, upper and lower case, a number, a symbol, not containing the email name, not in a short list of common passwords. Meter levels: Too weak, Weak, Fair, Strong, with text labels. Block submit until at least "Fair" and all rules pass.

Order of steps for Solo: 1, 3, 4, 5, 6 (skip step 2 organization code). Back button keeps entered data. Validate each step inline before Next.

ACCEPTANCE
- "Password1234" is rejected with specific reasons; a 14-character mixed password is accepted.
- The two ML choices are stored on the mock user object and shown in Settings > Privacy where they can be changed later.
- Can create an account using only the keyboard.

DO NOT send emails or add real authentication.
```

## Prompt 11: Add the machine learning layer (client-side, explainable)

```
CONTEXT
The prototype has an "ML Model Dashboard" for the administrator but the recommendations are rule-based. Add a real, small, in-browser model so the dashboard shows genuinely computed results. Use plain TypeScript or JavaScript with no ML library.

TASK
1. Dataset: build a deterministic seeded mock dataset of about 400 rows (fixed seed) with features: continuous focus minutes, breaks taken, lunch taken (0/1), weekly hours, after-hours days, average WLB score, years of experience, self-rated stress, time of day. Label: whether a break recommendation was accepted (1) or not (0). Generate labels from a hidden rule plus noise so the model has something real to learn.
2. Model: logistic regression trained by gradient descent with feature standardisation and L2 regularisation. 80/20 train/test split with the fixed seed. Expose train(), predict(features) and explain(features) (per-feature contribution = weight * standardised value).
3. Hybrid use: the Break Coach computes the rule-based recommendation as today, then the model returns an acceptance probability. If probability < 0.35, show the recommendation with a softer wording and lower priority; never suppress a safety rule (lunch or 2+ hours without a break).
4. ML Model Dashboard: show real computed accuracy, precision, recall and F1 on the test set; the confusion matrix; the feature weights as a sorted bar list; a "Retrain" button that re-runs training; and a comparison table: rule-based baseline vs model vs hybrid on the same test set.
5. Feedback loop: Accept / Snooze / Dismiss in the app append a row to the in-memory dataset; "Retrain" includes them.
6. Show a short "Why this recommendation" panel using explain(): top 3 factors in plain language.

ACCEPTANCE
- Metrics change when the seed or hyperparameters change, and are never hard-coded.
- The dashboard clearly says the model is trained on mock data for demonstration.
- Retraining finishes in under 2 seconds.

DO NOT add a backend, download model files, or claim clinical accuracy.
```

## Prompt 12: Login page: ticking clock and a better layout

```
TASK
Redesign the sign-in screen (desktop is a split layout; mobile is a single column).

Left panel:
- Brand mark and wordmark.
- Eyebrow "WORK-LIFE BALANCE AND FOCUS RECOVERY", headline "Sustainable focus. Structured breaks. Balanced weeks.", one short paragraph.
- A subtle animated analogue clock on the right of the headline: a stepping second hand that settles with a tiny overshoot each second (CSS or SVG, no library), minute and hour hands showing real time, and two small slowly rotating gears partly visible behind the dial at low opacity. Disable all motion under prefers-reduced-motion and mark the clock aria-hidden.
- Four feature tiles: Work-life balance, Break Coach, Session check-ins, Privacy by design (no screen or keystroke monitoring).
- Footer line: scores are advisory, not diagnoses.

Right panel:
- Sign-in card: email, password with show/hide, Remember session, Forgot password link, Sign In.
- Keep "Instant workspace preview" role buttons but label the section "Demo accounts" and visually separate it so it is clearly a demo aid, with an "Are you a panelist? Try a demo role" caption.
- "Create an account" link.
- Inline validation and a clear error state for wrong credentials.

ACCEPTANCE
- At 1280px: split layout, clock animating. At 375px: single column, clock hidden or static.
- Light and dark mode both pass AA.
- Tab order is logical and every control has a visible focus ring.

DO NOT change authentication logic or the mock users.
```

## Prompt 13: Work-life balance as a core feature (matches the Flutter app)

```
TASK
Make work-life balance a first-class feature for every role.
1. Add a "Work-Life Balance" item to the sidebar directly below Dashboard (for Solo users it replaces the old "Work-Life Balance" analytics entry; keep that analytics view as a tab named "Trends" inside the new page).
2. Dashboard: a headline card at the top with a score ring (0-100), band label (Excellent 80+, Good 70+, Fair 50+, Poor 30+, Critical below), trend chip, the weakest of the five areas as "Focus area", and a "Complete this week's check-in" button.
3. Weekly check-in dialog: five statements rated 1-5 (Disconnecting, Personal time, Balance, Schedule, Recovery). Score = ((sum - 5) / 20) * 100. One submission per week.
4. Work-Life Balance page: score ring, the five areas as bars, 8-week trend line, this-week work patterns (hours, overtime days, break adherence), "Habits to try this week" (2-4 suggestions with action and reason), and check-in history.
5. Solo users never see team modules (Team View, Messages, Team Attendance).

ACCEPTANCE
- Submitting the check-in updates the dashboard card and the page immediately.
- Wording says advisory reflection, not diagnosis.

DO NOT add medical language, diagnoses, or comparisons between named employees.
```

## Prompt 14: Final polish and accessibility pass

```
TASK
Review the whole app and fix only these categories, listing each fix:
1. Missing loading, empty or error states on any screen.
2. Contrast failures below 4.5:1 for text and 3:1 for UI components in either theme.
3. Controls not reachable or visible by keyboard.
4. Layout breaks at 375px width.
5. Any place colour alone carries meaning.
6. Inconsistent spacing, radius or font sizes compared with the design tokens.

Report anything bigger as a short list for me to decide on. Do not restructure files or add features.
```

---

## Suggested order and checkpoints

1. Prompts 7 and 12 (look and feel) so later screens inherit the tokens.
2. Prompts 1, 2, 3 (tasks and notifications).
3. Prompts 13, 9, 5, 6 (work-life balance, analytics, teams).
4. Prompts 10, 8 (account creation and security).
5. Prompts 4 and 11 (sandbox and ML), then Prompt 14.

Commit after each prompt: `feat: <short description> via AI Studio`. Do not push until you have clicked through every role (Employee, Solo, Manager, Administrator).
