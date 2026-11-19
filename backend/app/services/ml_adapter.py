"""Adapter: ML decline prediction → BreakCoach recommendation (service layer)
Treats decline_probability as behavioral signal, not direct break-type mapping.
"""
import httpx
from ..models import Profile

def adapt_decline_to_recommendation(decline_result: dict, profile_id: int) -> dict:
    prob = decline_result.get("decline_probability", 0.0)
    # Behavioral signal: high probability → suggest break; medium/low → continue observing
    if prob >= 0.6:
        rec_type = "shortBreak"
        title = "Patterns suggest a break"
        reason = f"Work pattern decline probability is {prob:.0%}. A short break may help restore rhythm."
        suggested = "SHORT_BREAK"
    elif prob >= 0.4:
        rec_type = "shortBreak"
        title = "Consider a brief pause"
        reason = f"Work pattern showing early decline signal ({prob:.0%}). A quick break supports continuity."
        suggested = "SHORT_BREAK"
    else:
        # No recommendation at this signal level — UI should show waiting state, not fake rec
        rec_type = None
        title = None
        reason = None
        suggested = None
    return {
        "type": rec_type,
        "title": title,
        "reason": reason,
        "suggestedBreakType": suggested,
        "mlConfidence": prob,
        "trigger": "mlPrediction",
    }
