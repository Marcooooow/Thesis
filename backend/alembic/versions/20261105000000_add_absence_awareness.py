"""Add absence awareness tables and schemas (strictly non-fabricated backfill & approved notification types).

Revision ID: add_absence_awareness
Revises: 20261104_dnd_gov
Create Date: 2026-11-05 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'add_absence_awareness'
down_revision = '20261104_dnd_gov'
branch_labels = None
depends_on = None


def upgrade():
    # 1. Enable btree_gist extension safely with precise exception handling
    op.execute("""
        DO $$
        BEGIN
            BEGIN
                CREATE EXTENSION IF NOT EXISTS btree_gist;
            EXCEPTION WHEN insufficient_privilege THEN
                IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gist') THEN
                    RAISE EXCEPTION 'Extension btree_gist is required for schedule overlap exclusion constraints but could not be created due to insufficient privileges.';
                END IF;
            END;
        END $$;
    """)

    # 2. Reconcile user_settings for absence_grace_minutes
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'user_settings' AND column_name = 'absence_grace_minutes'
            ) THEN
                ALTER TABLE user_settings ADD COLUMN absence_grace_minutes INTEGER NOT NULL DEFAULT 120;
            END IF;
        END $$;
    """)
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'chk_absence_grace'
            ) THEN
                ALTER TABLE user_settings ADD CONSTRAINT chk_absence_grace CHECK (absence_grace_minutes IS NULL OR (absence_grace_minutes >= 30 AND absence_grace_minutes <= 480));
            END IF;
        END $$;
    """)

    # 3. Reconcile employee_schedules
    op.execute("""
        CREATE TABLE IF NOT EXISTS employee_schedules (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            effective_from DATE NOT NULL,
            effective_until DATE,
            work_days TEXT[] NOT NULL,
            shift_start TIME NOT NULL,
            shift_end TIME NOT NULL,
            timezone VARCHAR(100) NOT NULL DEFAULT 'Asia/Manila',
            created_by UUID NOT NULL REFERENCES users(id),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT chk_shift_order CHECK (shift_start != shift_end),
            CONSTRAINT chk_effective_range CHECK (effective_until IS NULL OR effective_from <= effective_until)
        );
    """)
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE;")
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS effective_from DATE;")
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS effective_until DATE;")
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS work_days TEXT[];")
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS shift_start TIME;")
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS shift_end TIME;")
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS timezone VARCHAR(100) DEFAULT 'Asia/Manila';")
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id);")
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();")
    op.execute("ALTER TABLE employee_schedules ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();")

    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_employee_schedules_profile_active') THEN
                CREATE INDEX ix_employee_schedules_profile_active ON employee_schedules (profile_id) WHERE effective_until IS NULL;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_employee_schedules_lookup') THEN
                CREATE INDEX ix_employee_schedules_lookup ON employee_schedules (profile_id, effective_from);
            END IF;
        END $$;
    """)

    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'ex_profile_schedule_overlap'
            ) THEN
                ALTER TABLE employee_schedules ADD CONSTRAINT ex_profile_schedule_overlap
                EXCLUDE USING GIST (
                    profile_id WITH =,
                    daterange(effective_from, COALESCE(effective_until, 'infinity'::date), '[)') WITH &&
                );
            END IF;
        END $$;
    """)

    # 4. Reconcile leave_types
    op.execute("""
        CREATE TABLE IF NOT EXISTS leave_types (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
            name VARCHAR(100) NOT NULL,
            requires_documentation BOOLEAN NOT NULL DEFAULT false,
            is_active BOOLEAN NOT NULL DEFAULT true,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT uq_leave_type_org_name UNIQUE (organization_id, name)
        );
    """)
    op.execute("ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE;")
    op.execute("ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS name VARCHAR(100);")
    op.execute("ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS requires_documentation BOOLEAN DEFAULT false;")
    op.execute("ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;")
    op.execute("ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS sort_order INTEGER DEFAULT 0;")
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_leave_types_org') THEN
                CREATE INDEX ix_leave_types_org ON leave_types (organization_id);
            END IF;
        END $$;
    """)

    # 5. Reconcile leave_requests
    op.execute("""
        CREATE TABLE IF NOT EXISTS leave_requests (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            leave_type_id UUID NOT NULL REFERENCES leave_types(id),
            start_date DATE NOT NULL,
            end_date DATE NOT NULL,
            reason TEXT,
            status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
            reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
            reviewed_at TIMESTAMPTZ,
            reviewer_note TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT chk_date_order CHECK (start_date <= end_date),
            CONSTRAINT chk_leave_status CHECK (status IN ('PENDING','APPROVED','REJECTED','CANCELLED'))
        );
    """)
    op.execute("ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE;")
    op.execute("ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS leave_type_id UUID REFERENCES leave_types(id);")
    op.execute("ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS start_date DATE;")
    op.execute("ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS end_date DATE;")
    op.execute("ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'PENDING';")
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_leave_requests_profile') THEN
                CREATE INDEX ix_leave_requests_profile ON leave_requests (profile_id);
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_leave_requests_dates') THEN
                CREATE INDEX ix_leave_requests_dates ON leave_requests (start_date, end_date);
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_leave_requests_status') THEN
                CREATE INDEX ix_leave_requests_status ON leave_requests (status) WHERE status = 'PENDING';
            END IF;
        END $$;
    """)

    # 6. Reconcile absence_records
    op.execute("""
        CREATE TABLE IF NOT EXISTS absence_records (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            absence_date DATE NOT NULL,
            schedule_id UUID NOT NULL REFERENCES employee_schedules(id),
            classification VARCHAR(30) NOT NULL DEFAULT 'UNREPORTED',
            leave_request_id UUID REFERENCES leave_requests(id) ON DELETE SET NULL,
            detection_run_at TIMESTAMPTZ NOT NULL,
            grace_period_minutes INTEGER NOT NULL,
            notification_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
            manager_acknowledged_at TIMESTAMPTZ,
            acknowledged_by UUID REFERENCES users(id) ON DELETE SET NULL,
            notes TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT chk_classification CHECK (classification IN ('UNREPORTED', 'LEAVE_APPROVED', 'EXCUSED', 'DISMISSED')),
            CONSTRAINT chk_absence_notification_status CHECK (notification_status IN ('PENDING', 'DISPATCHED', 'FAILED', 'NOT_REQUIRED')),
            CONSTRAINT uq_absence_profile_date UNIQUE (profile_id, absence_date)
        );
    """)
    op.execute("ALTER TABLE absence_records ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE;")
    op.execute("ALTER TABLE absence_records ADD COLUMN IF NOT EXISTS absence_date DATE;")
    op.execute("ALTER TABLE absence_records ADD COLUMN IF NOT EXISTS schedule_id UUID REFERENCES employee_schedules(id);")
    op.execute("ALTER TABLE absence_records ADD COLUMN IF NOT EXISTS classification VARCHAR(30) DEFAULT 'UNREPORTED';")
    op.execute("ALTER TABLE absence_records ADD COLUMN IF NOT EXISTS detection_run_at TIMESTAMPTZ;")
    op.execute("ALTER TABLE absence_records ADD COLUMN IF NOT EXISTS grace_period_minutes INTEGER;")
    op.execute("ALTER TABLE absence_records ADD COLUMN IF NOT EXISTS notification_status VARCHAR(30) DEFAULT 'PENDING';")
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_absence_records_profile_date') THEN
                CREATE INDEX ix_absence_records_profile_date ON absence_records (profile_id, absence_date);
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_absence_records_unacknowledged') THEN
                CREATE INDEX ix_absence_records_unacknowledged ON absence_records (profile_id) WHERE manager_acknowledged_at IS NULL;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_absence_records_notification_status') THEN
                CREATE INDEX ix_absence_records_notification_status ON absence_records (notification_status) WHERE notification_status IN ('PENDING', 'FAILED');
            END IF;
        END $$;
    """)

    # 7. Reconcile return_to_work_checkins (ensuring profile_id and work_session_id exist and backfilling if needed)
    op.execute("""
        CREATE TABLE IF NOT EXISTS return_to_work_checkins (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            work_session_id UUID NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
            absence_record_id UUID REFERENCES absence_records(id) ON DELETE SET NULL,
            absence_reason_category VARCHAR(50),
            overall_feeling SMALLINT,
            workload_concern SMALLINT,
            stress_concern SMALLINT,
            work_contributed_to_absence BOOLEAN,
            wants_manager_support BOOLEAN,
            additional_comments TEXT,
            is_manager_visible BOOLEAN NOT NULL DEFAULT false,
            submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT chk_feeling_range CHECK (overall_feeling IS NULL OR (overall_feeling >= 1 AND overall_feeling <= 5)),
            CONSTRAINT chk_workload_range CHECK (workload_concern IS NULL OR (workload_concern >= 1 AND workload_concern <= 5)),
            CONSTRAINT chk_stress_range CHECK (stress_concern IS NULL OR (stress_concern >= 1 AND stress_concern <= 5)),
            CONSTRAINT uq_rtw_session UNIQUE (work_session_id)
        );
    """)
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS work_session_id UUID REFERENCES work_sessions(id) ON DELETE CASCADE;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS absence_record_id UUID REFERENCES absence_records(id) ON DELETE SET NULL;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS absence_reason_category VARCHAR(50);")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS overall_feeling SMALLINT;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS workload_concern SMALLINT;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS stress_concern SMALLINT;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS work_contributed_to_absence BOOLEAN;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS wants_manager_support BOOLEAN;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS additional_comments TEXT;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS is_manager_visible BOOLEAN DEFAULT false;")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ DEFAULT now();")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();")
    op.execute("ALTER TABLE return_to_work_checkins ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();")

    # Backfill profile_id in return_to_work_checkins from work_sessions if NULL
    op.execute("""
        UPDATE return_to_work_checkins r
        SET profile_id = w.profile_id
        FROM work_sessions w
        WHERE r.work_session_id = w.id
          AND r.profile_id IS NULL;
    """)

    # Enforce NOT NULL on profile_id and work_session_id after backfill check
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM return_to_work_checkins WHERE profile_id IS NULL
            ) THEN
                ALTER TABLE return_to_work_checkins ALTER COLUMN profile_id SET NOT NULL;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM return_to_work_checkins WHERE work_session_id IS NULL
            ) THEN
                ALTER TABLE return_to_work_checkins ALTER COLUMN work_session_id SET NOT NULL;
            END IF;
        END $$;
    """)

    # Create indexes safely now that columns are confirmed present
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_rtw_profile') THEN
                CREATE INDEX ix_rtw_profile ON return_to_work_checkins (profile_id);
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_rtw_absence') THEN
                CREATE INDEX ix_rtw_absence ON return_to_work_checkins (absence_record_id);
            END IF;
        END $$;
    """)

    # 8. Widen notification type check constraint safely
    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_type;")
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'chk_notification_type'
            ) THEN
                ALTER TABLE notifications ADD CONSTRAINT chk_notification_type CHECK (
                    type IN ('TEAM_INVITATION', 'TEAM_INVITATION_ACCEPTED', 'TEAM_INVITATION_DECLINED', 'WORK_REMINDER', 'BREAK_COACH', 'SYSTEM_ALERT', 'TASK_NOTIFICATION', 'ABSENCE_ALERT', 'LEAVE_REQUEST', 'LEAVE_APPROVED', 'LEAVE_REJECTED', 'RTW_CHECKIN_PROMPT')
                );
            END IF;
        END $$;
    """)

    # 9. Backfill employee_schedules deterministically without duplicates
    op.execute("""
        INSERT INTO employee_schedules (profile_id, effective_from, work_days, shift_start, shift_end, timezone, created_by)
        SELECT
            p.id,
            p.hire_date,
            p.work_days,
            p.shift_start_time,
            p.shift_end_time,
            'Asia/Manila',
            p.user_id
        FROM profiles p
        WHERE p.shift_start_time IS NOT NULL
          AND p.shift_end_time IS NOT NULL
          AND p.work_days IS NOT NULL
          AND p.hire_date IS NOT NULL
        ON CONFLICT DO NOTHING;
    """)


def downgrade():
    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_type;")
    op.create_check_constraint(
        'chk_notification_type',
        'notifications',
        "type IN ('TEAM_INVITATION', 'TEAM_INVITATION_ACCEPTED', 'TEAM_INVITATION_DECLINED')"
    )
    op.drop_table('return_to_work_checkins')
    op.drop_table('absence_records')
    op.drop_table('leave_requests')
    op.drop_table('leave_types')
    op.drop_table('employee_schedules')
    op.execute("ALTER TABLE user_settings DROP CONSTRAINT IF EXISTS chk_absence_grace;")
    op.drop_column('user_settings', 'absence_grace_minutes')
