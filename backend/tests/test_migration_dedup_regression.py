"""
Regression tests for recommendation_feedback deduplication migration logic.
Covering:
- No duplicate feedback
- Multiple duplicate feedback records
- Different recommendation IDs
- Different user IDs
- Correct retained feedback record (ordered by timestamp ASC, created_at ASC, id ASC)
"""

import pytest
from sqlalchemy.orm import Session
from sqlalchemy import text
import uuid
from datetime import datetime, timezone, timedelta

def test_recommendation_feedback_dedup_regression(test_db: Session):
    """
    Test the migration deduplication logic against various scenarios:
    - No duplicates
    - Multiple duplicates for same (recommendation_id, user_id)
    - Different recommendation IDs
    - Different user IDs
    - Correct retained feedback record (earliest timestamp/created_at/id)
    """
    user1_id = str(uuid.uuid4())
    user2_id = str(uuid.uuid4())
    
    test_db.execute(text("""
        INSERT INTO users (id, email, password_hash, full_name, role, approval_status, is_active)
        VALUES (:id1, 'u1_reg@example.com', 'hash', 'U1', 'EMPLOYEE', 'APPROVED', 1),
               (:id2, 'u2_reg@example.com', 'hash', 'U2', 'EMPLOYEE', 'APPROVED', 1)
    """), {"id1": user1_id, "id2": user2_id})
    test_db.commit()

    rec_id_1 = str(uuid.uuid4())
    rec_id_2 = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    test_db.execute(text("DROP TABLE IF EXISTS recommendation_feedback"))
    test_db.execute(text("""
        CREATE TABLE recommendation_feedback (
            id VARCHAR(36) PRIMARY KEY,
            user_id VARCHAR(36) NOT NULL,
            recommendation_id VARCHAR(36) NOT NULL,
            model_version VARCHAR(255) NOT NULL,
            recommendation_type VARCHAR(50) NOT NULL,
            recommendation_score FLOAT NOT NULL,
            context_features JSON NOT NULL,
            timestamp DATETIME NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            user_action VARCHAR(20)
        )
    """))
    test_db.commit()

    fb_unique_id = uuid.uuid4().hex
    fb_oldest_id = uuid.uuid4().hex
    fb_middle_id = uuid.uuid4().hex
    fb_newest_id = uuid.uuid4().hex
    fb_user2_id = uuid.uuid4().hex

    t_old = (now - timedelta(hours=3)).isoformat()
    t_mid = (now - timedelta(hours=2)).isoformat()
    t_new = (now - timedelta(hours=1)).isoformat()

    # Scenario 1: Unique record
    test_db.execute(text("""
        INSERT INTO recommendation_feedback (id, user_id, recommendation_id, model_version, recommendation_type, recommendation_score, context_features, timestamp, user_action)
        VALUES (:id, :user_id, :rec_id, 'v1', 'SHORT_BREAK', 0.8, '{}', :ts, NULL)
    """), {"id": fb_unique_id, "user_id": user1_id, "rec_id": rec_id_1, "ts": t_old})

    # Scenario 2: Multiple duplicates for user1 & rec_id_2
    test_db.execute(text("""
        INSERT INTO recommendation_feedback (id, user_id, recommendation_id, model_version, recommendation_type, recommendation_score, context_features, timestamp, user_action)
        VALUES 
        (:id_old, :user_id, :rec_id, 'v1', 'WALK', 0.9, '{}', :t_old, 'accepted'),
        (:id_mid, :user_id, :rec_id, 'v1', 'WALK', 0.9, '{}', :t_mid, 'dismissed'),
        (:id_new, :user_id, :rec_id, 'v1', 'WALK', 0.9, '{}', :t_new, 'ignored')
    """), {
        "id_old": fb_oldest_id,
        "id_mid": fb_middle_id,
        "id_new": fb_newest_id,
        "user_id": user1_id,
        "rec_id": rec_id_2,
        "t_old": t_old,
        "t_mid": t_mid,
        "t_new": t_new
    })

    # Scenario 3: Same recommendation_id but different user
    test_db.execute(text("""
        INSERT INTO recommendation_feedback (id, user_id, recommendation_id, model_version, recommendation_type, recommendation_score, context_features, timestamp, user_action)
        VALUES (:id, :user_id, :rec_id, 'v1', 'WALK', 0.9, '{}', :ts, NULL)
    """), {"id": fb_user2_id, "user_id": user2_id, "rec_id": rec_id_2, "ts": t_old})
    test_db.commit()

    # Run migration upgrade logic
    dedup_sql = """
        WITH ranked_feedback AS (
            SELECT id,
                   ROW_NUMBER() OVER (
                       PARTITION BY recommendation_id, user_id
                       ORDER BY timestamp ASC, created_at ASC, id ASC
                   ) as rn
            FROM recommendation_feedback
        )
        DELETE FROM recommendation_feedback
        WHERE id IN (
            SELECT id FROM ranked_feedback WHERE rn > 1
        )
    """
    test_db.execute(text(dedup_sql))
    test_db.commit()

    test_db.execute(text("""
        CREATE UNIQUE INDEX uq_feedback_rec_user ON recommendation_feedback (recommendation_id, user_id)
    """))
    test_db.commit()

    res = test_db.execute(text("SELECT id FROM recommendation_feedback")).fetchall()
    remaining_ids = {row[0] for row in res}

    assert fb_unique_id in remaining_ids
    assert fb_oldest_id in remaining_ids
    assert fb_middle_id not in remaining_ids
    assert fb_newest_id not in remaining_ids
    assert fb_user2_id in remaining_ids
    assert len(remaining_ids) == 3
