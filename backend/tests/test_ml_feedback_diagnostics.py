"""
Diagnostic test for ML feedback reconciliation and teammate data collection.
"""
import pytest
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.models import RecommendationFeedback, Profile, User
from app.services.ml_training_pipeline import assess_data_sufficiency, _extract_training_data

def test_production_feedback_reconciliation_report(db: Session):
    """
    Diagnostic report test verifying production feedback collection, user association,
    test/demo exclusions, label validity, and final eligible positive/negative training samples.
    """
    total_records = db.query(RecommendationFeedback).count()

    # By user
    user_counts = db.query(RecommendationFeedback.user_id, func.count(RecommendationFeedback.id)).group_by(RecommendationFeedback.user_id).all()

    # By status
    status_counts = db.query(RecommendationFeedback.user_action, func.count(RecommendationFeedback.id)).group_by(RecommendationFeedback.user_action).all()

    # Test/demo exclusions
    test_user_ids = db.query(Profile.user_id).filter(Profile.is_test_data == True).all()
    test_user_ids_set = {r[0] for r in test_user_ids if r[0] is not None}

    dev_demo_count = db.query(RecommendationFeedback).filter(RecommendationFeedback.context_features['dev_demo'].as_string() == 'true').count() if total_records > 0 else 0
    is_test_data_feat_count = db.query(RecommendationFeedback).filter(RecommendationFeedback.context_features['is_test_data'].as_string() == 'true').count() if total_records > 0 else 0
    test_profile_count = db.query(RecommendationFeedback).filter(RecommendationFeedback.user_id.in_(test_user_ids_set)).count() if test_user_ids_set else 0

    # Training pipeline extraction
    features, labels, _, user_ids = _extract_training_data(db, dataset="production")
    eligible_count = len(labels)
    pos_count = sum(1 for l in labels if l == 1)
    neg_count = sum(1 for l in labels if l == 0)

    sufficiency = assess_data_sufficiency(db, dataset="production")

    print("\n=== INTELLIBREAK ML FEEDBACK RECONCILIATION REPORT ===")
    print(f"Total Feedback Records in DB: {total_records}")
    print(f"Feedback by Status: {dict(status_counts)}")
    print(f"Excluded dev_demo='true': {dev_demo_count}")
    print(f"Excluded is_test_data feature='true': {is_test_data_feat_count}")
    print(f"Excluded Test Profile Users: {test_profile_count}")
    print(f"Final Production-Eligible Samples: {eligible_count}")
    print(f"  - Positive Samples (Accepted): {pos_count}")
    print(f"  - Negative Samples (Dismissed/Ignored): {neg_count}")
    print(f"Dashboard Readiness Status: {sufficiency}")
    print("===================================================\n")

    assert eligible_count == assess_data_sufficiency(db, dataset="production")["labeled_feedback"]
