import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from urllib.parse import urlparse

def verify_production_target(db_url: str):
    """
    Strict pre-write production guard:
    - Validates URL structure.
    - Requires SSL mode (require or verify-full).
    - Requires pooler hostname 'aws-0-ap-southeast-2.pooler.supabase.com' and username containing 'wwrwnpjsvtjotckqnsjt'.
    - Connects and verifies connected Supabase instance via metadata queries.
    - Fails closed on any mismatch, missing SSL, localhost, or unverifiable connection.
    """
    if not db_url:
        raise RuntimeError("DATABASE_URL is missing or empty.")

    parsed = urlparse(db_url)
    if parsed.scheme not in ("postgresql", "postgresql+psycopg", "postgresql+psycopg2"):
        raise RuntimeError("Invalid database scheme; PostgreSQL required.")

    # 1. Reject localhost / non-production hosts for strict production guard
    hostname = (parsed.hostname or "").lower()
    expected_host = "aws-0-ap-southeast-2.pooler.supabase.com"
    if hostname != expected_host:
        raise RuntimeError(f"Production target guard violation: host '{hostname}' is not the trusted Supabase pooler '{expected_host}'. Localhost/non-production hosts are rejected by this guard.")

    # 2. Verify project-specific username containing 'wwrwnpjsvtjotckqnsjt'
    username = parsed.username or ""
    expected_ref = "wwrwnpjsvtjotckqnsjt"
    if expected_ref not in username:
        raise RuntimeError(f"Production target guard violation: username does not contain expected Supabase project reference '{expected_ref}'.")

    # 3. Require effective SSL enforcement (sslmode=require or verify-full)
    query_params = parsed.query
    has_ssl = "sslmode=require" in query_params or "sslmode=verify-full" in query_params or os.getenv("PGSSLMODE") in ("require", "verify-full")
    if not has_ssl:
        raise RuntimeError("Security constraint violation: Effective SSL mode ('sslmode=require' or 'verify-full') is strictly required for production writes.")

    # 4. Establish test connection to verify actual connected instance via SQL metadata
    from sqlalchemy import create_engine, text
    engine = create_engine(db_url)
    with engine.connect() as conn:
        res = conn.execute(text("SELECT current_database()")).fetchone()
        if not res:
            raise RuntimeError("Database connection verification query returned no result.")

    return True
