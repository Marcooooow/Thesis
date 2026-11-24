# IntelliBreak

Thesis project: sustainable work habits, productivity, wellness-oriented break management, and behavior-based recommendations.

Not intended to maximize productivity at the expense of user wellness. Not a medical or psychological diagnostic system.

---

## Overview

IntelliBreak is a web/desktop application for remote/work-from-home users. It helps manage work sessions and breaks, track tasks and patterns, provide wellness-oriented break recommendations, and analyze historical work behavior.

## Purpose / Problem

Remote workers often lose track of work-break balance. IntelliBreak aims to:
- Help users manage work sessions and breaks
- Track tasks and work patterns
- Provide wellness-oriented break recommendations
- Analyze historical work behavior
- Predict imminent work-pattern decline using machine learning (planned)
- Provide personalized recommendations without diagnosing medical or psychological conditions

## Key Features (implemented)

- Work session / shift start and end
- Break tracking (Break 1, Break 2, Lunch) with availability rules
- Task management (start, complete, history)
- Focus Rate calculation from session/task/break data
- Analytics / shift logs
- Team / organization management (manager/admin views)
- Recommendation pipeline with feedback loop (accept/dismiss/ignore)
- Browser tab title updates during active shift (`HH:MM:SS • Current Task`)
- Firebase Authentication + profile images
- Recommendation system uses cold-start baseline (heuristic scoring); trained ML recommender requires sufficient labeled feedback
- Forced password-change flow using restricted tokens for first-time employee login
- Team invitation workflow with Accept/Decline actions through notifications
- Notification actions disappear after the invitation is processed while the notification remains visible
- TabTitleTicker lifecycle handling prevents deactivated-widget ancestor errors
- Configurable notification alerts: browser notifications, subtle sounds, and browser-tab attention, with DND suppression

## Work-Life Balance (core module)

Work-life balance is a first-class feature, not a side widget:

- **Dashboard headline:** a balance score (0-100), trend and focus area sit at the top of the employee dashboard.
- **Work-Life Balance screen:** score ring, the five self-rated dimensions (disconnecting, personal time, balance, schedule, recovery), an 8-week trend, this week's work patterns (hours, overtime days, break adherence), habit recommendations and check-in history.
- **Weekly check-in:** five 1-5 statements; the score is computed server-side as `((sum - 5) / 20) * 100`. One submission per week.
- **Solo accounts are supported:** surveys are stored with `organization_id = NULL` and are excluded from organization roll-ups (migration `20261120000000`).
- Wording is self-reflection only; the system makes no medical or psychological assessment.

## Account types

- **Solo:** individual users. Team View, Employees, Team Attendance, Team Activity, Team Well-being, Attendance & Leave and Messages are hidden from the sidebar.
- **Organization:** managers and invited employees see the full team modules.

## System Architecture

- **Frontend:** Flutter (Dart) with Provider/ChangeNotifier state management; Flutter Web
- **Backend:** Python FastAPI with SQLAlchemy, Alembic, PostgreSQL, JWT auth
- **Database:** PostgreSQL via Docker (`docker-compose.yml`); 24 Alembic migrations present
- **ML / Recommendation:** Candidate-based recommendation pipeline (feature extraction → candidate generation → heuristic scoring → ranking); feedback stored in `recommendation_feedback`; `ml_models` table exists; currently cold-start baseline; no deployed predictive model yet
- **Auth:** Firebase Auth (frontend) + backend JWT (`python-jose`)
- **Storage:** Firebase Storage for profile images

## Technology Stack

| Layer | Technologies |
|---|---|
| Frontend | Flutter, Dart, Flutter Web, Provider, Firebase Auth/Storage |
| Backend | Python, FastAPI, SQLAlchemy 2.0, Alembic, PostgreSQL, Psycopg 3, JWT |
| ML / Data | pandas, NumPy, scikit-learn (available; trained model not deployed) |
| DevOps | Docker Compose, PostgreSQL 17, Python-dotenv |

## Repository Structure

```text
intellibreak/
├── backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── routers/          (auth, admin, analytics, team, work, profile, notification, employee, settings, recommendation)
│   │   ├── schemas/
│   │   ├── services/         (recommendation_service, analytics_utils)
│   │   ├── auth/security.py
│   │   ├── database.py
│   │   ├── models.py
│   │   └── sql/
│   ├── alembic/
│   │   ├── versions/          (24 migrations)
│   │   └── env.py
│   ├── tests/                 (test_password_security.py)
│   └── requirements.txt
├── lib/                      (Flutter source)
│   ├── core/
│   ├── features/
│   ├── providers/
│   ├── routes/
│   └── widgets/
├── test/                     (Flutter tests, regression tests)
├── web/                      (Flutter Web build artifacts; do NOT edit)
├── docker-compose.yml
├── firebase.json
├── storage.rules
├── pubspec.yaml
└── CLAUDE.md
```

> Note: `build/`, `.dart_tool/`, `.venv/`, `backend/venv/` are generated and excluded by `.gitignore`.

## Prerequisites

- Flutter SDK (^3.13.0 per `pubspec.yaml`)
- Python 3 (^3.13.0 per backend requirements)
- Docker + Docker Compose
- PostgreSQL local client (optional; DB runs in container)
- Firebase project (for Auth/Storage; configure via `firebase.json` / `lib/firebase_options.dart`)

## Installation and Setup

### 1. Clone

```bash
git clone <repo-url>
cd intellibreak
```

### 2. Configure environment (must be done before running backend)

Create `backend/.env` with required variables (do NOT commit `.env`; `.gitignore` excludes `.env` and `.env.*`). Required variables (verify with `docker-compose.yml` / backend config):

- `POSTGRES_PASSWORD`
- JWT secret / algorithm settings (see `backend/app/auth/security.py`)
- Firebase configuration (if not using `firebase_options.dart` defaults)

> There is no `.env.example` file in the repo; create your own based on `docker-compose.yml` and backend needs.

### 3. Start database (Docker)

```bash
docker compose up db -d
```

This creates `postgres:17` container named `intellibreak-db` on port `5432`. Database name `intellibreak`, user `intellibreak_user`. Credentials come from `backend/.env`.

> **Important:** The PostgreSQL database, data volume (`intellibreak_restored`), and credentials are NOT committed to GitHub. Each teammate creates their own local database.

### 4. Run migrations

From `backend/` with the DB running:

```bash
python -m alembic upgrade head
```

There are 24 Alembic migrations in `backend/alembic/versions/`. The `docker-compose.yml` backend command also runs `python -m alembic upgrade head` on startup.

### 5. Backend dependencies

```bash
cd backend
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

Requirements include: `fastapi==0.104.1`, `uvicorn`, `SQLAlchemy==2.0.46`, `psycopg[binary]==3.3.5`, `python-dotenv`, `python-jose`, `passlib[bcrypt]`, `pyotp`, `scikit-learn==1.9.0`, `pandas==3.0.5`, `numpy==2.5.3`, `alembic==1.13.1`.

### 6. Start backend

```bash
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Or via Docker:

```bash
docker compose up backend -d
```

Health endpoint: `http://localhost:8000/health`

### 7. Flutter frontend setup

```bash
flutter pub get
```

No seed/demo-data script exists in the repository (verified). Teammates receive database schema through migrations; additional demo data must be created manually or provided separately.

### 8. Start Flutter Web

```bash
flutter run -d chrome
```

Or build:

```bash
flutter build web --release
```

The app uses `lib/main.dart` with `MultiProvider` (WorkSessionProvider, ShiftTimerProvider, ThemeController, etc.).

## Database Setup (detailed for teammates)

**New teammate workflow:**

1. Clone repo.
2. Create `backend/.env` with DB password and JWT settings.
3. `docker compose up db -d` (PostgreSQL 17).
4. `cd backend && python -m alembic upgrade head`.
5. Start backend; start Flutter.

**No seed script exists.** If a teammate needs initial data, they must insert manually or ask the project owner. The schema is fully defined by Alembic.

**Migration workflow:**

```bash
# Create new migration (developer)
alembic revision --autogenerate -m "description"

# Apply
alembic upgrade head

# Check history
alembic history
```

**Important tables/models (from `backend/app/models.py`):** `users`, `profiles`, `work_sessions`, `breaks`, `tasks`, `teams`, `team_memberships`, `team_invitations`, `organization_memberships`, `organizations`, `recommendation_feedback`, `ml_models`, `notifications`, `user_settings`.

## Backend API Overview

Base: `http://localhost:8000`

Key routers (prefixes from code):
- `/auth` — register, login, 2FA/TOTP, forgot/reset password, admin user list
- `/work` — work sessions, breaks, tasks
- `/analytics` — analytics endpoints
- `/team` — team management
- `/profile` — user profile
- `/notification` — notifications
- `/employee` — employee views
- `/settings` — user settings
- `/recommend` — recommendation generate (`POST /generate`) and feedback (`POST /feedback`)
- `/ml` — ML-related router (not a deployed predictive model)
- `/admin` — admin endpoints

Authentication: JWT Bearer token from `/auth/login`; restricted endpoints use `get_current_active_user`, `get_current_admin_user`, `get_current_restricted_user`.

Health: `/health` (DB status included)

## Authentication / Security

- Backend: JWT (`python-jose`) with access token expiration.
- Rate limiting: in-memory (`_login_failures`) per IP for login attempts (15 min window, max 5).
- Passwords hashed with bcrypt (`passlib[bcrypt]`).
- 2FA/TOTP supported (`pyotp`).
- Password change token versioning (`password_change_token_version`).
- `.env` must never be committed; `.gitignore` excludes `.env`, `.env.*`, backups, `backend/reset_admin_password.py`, `ADMIN_PASSWORD_RESET_REPORT.txt`.
- Secrets (JWT key, DB password, Firebase credentials) must remain local.
- Restricted first-login token flow:
  * Manager-created employee accounts receive a restricted JWT with `type: restricted` and `must_change_password=true`.
  * AuthGate detects the restricted flag and routes to the Change Password screen without calling `/auth/me`.
  * Change Password screen sends the restricted JWT via `Authorization: Bearer <token>` header.
  * Backend validates the restricted token (version, type, must_change flag) and allows password update.
  * After successful password change, the employee logs in normally to obtain a standard access token.
  * While the restricted token is active, `/auth/me` is not called to avoid 401 responses.

## Team Invitation Workflow

- Managers can send invitations to employees via the Team management interface.
- Employees receive invitations as notifications with Accept and Decline buttons.
- Upon accepting or declining an invitation:
  * The action buttons (Accept/Decline) disappear from the notification.
  * The notification remains visible in the list as a record of the invitation.
  * The employee's team membership is updated accordingly (accepted) or the invitation is recorded as declined.
- The notification's `isActioned` flag is used to control the visibility of the action buttons.

## Recommendation / AI / ML System

**Implemented:** Candidate-based recommendation pipeline (`backend/app/services/recommendation_service.py`).

- Feature extraction from existing data: session length, time since last break, recent task completion rate, focus rate, user preferences.
- Candidates: `SHORT_BREAK`, `WALK`, `HYDRATE`, `STRETCH`, `LUNCH`.
- Scoring: heuristic ranking score (not calibrated probability).
- Feedback loop: `POST /recommend/feedback` updates `user_action` (`accepted`/`dismissed`/`ignored`) and records break start/end if provided.
- Storage: `recommendation_feedback` (with `user_action = NULL` initially); `ml_models` table exists.
- Cold-start: explicitly detected (`cold_start = true` when <2 tasks or no active session); uses `SHORT_BREAK` baseline (`model_version="cold-start-baseline"`).
- `/recommend/health` reports `cold-start-baseline`; notes that trained ML recommender requires sufficient labeled feedback.

**Not implemented:** Trained ML recommender for work-pattern decline prediction.

**Thesis scope preserved:** Predictions/recommendations remain behavior-based. Must NOT diagnose medical fatigue, stress, depression, mental illness, or universal productivity scores.

## Testing

Backend tests (verified commands):

```bash
cd backend
python -m pytest tests/test_password_security.py
```

Flutter tests:

```bash
flutter test test/tab_title_ticker_regression_test.dart
```

Test structure: `backend/tests/`, `test/` (Flutter). No full integration test suite verified.

## Docker Setup

```bash
docker compose up db -d      # DB only
docker compose up -d         # DB + backend
```

Services defined in `docker-compose.yml`: `db` (postgres:17, port 5432, volume `intellibreak_restored`), `backend` (build `./backend`, port 8000, env_file `./backend/.env`, depends_on db healthcheck).

Backend startup command (from compose): `sh -c "python -m alembic upgrade head && python -m uvicorn app.main:app --host 0.0.0.0 --port 8000"`

## Development Workflow for Teammates

1. Clone; configure `backend/.env`; start DB.
2. Run migrations (`alembic upgrade head`).
3. Start backend (`uvicorn` or Docker).
4. `flutter pub get`; `flutter run -d chrome`.
5. Make changes; test with existing suite; do NOT commit `.env` or build artifacts.

## Trial / Thesis Status

- Project: IntelliBreak (thesis)
- Author (from git): GaliaArjhond
- Status: Implementation active; recommendation pipeline in cold-start baseline; predictive ML model is planned, not deployed
- Scope: Behavior-based work-pattern management and recommendations only; not medical/psychological diagnosis

## Contributors

- GaliaArjhond (`galiaarjhond0@gmail.com`) — primary contributor (from git history)

No `LICENSE` file present; no additional authors listed.

---

*Last updated: 2026-09-26. Based on repository state at time of creation. Some steps (seed data, exact `.env` variables) may require confirmation from project owner.*
