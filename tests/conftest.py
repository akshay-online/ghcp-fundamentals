"""Shared pytest fixtures for Snowflake procedure tests.

Tests run against a zero-copy clone of SNOWFLAKE_SOURCE_DATABASE (default DEMO_DB),
created once per session and dropped at the end, so the source data is never touched.
"""
import os
import uuid

import pytest
import snowflake.connector
from snowflake.connector import DictCursor

REQUIRED_ENV = ["SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_ROLE", "SNOWFLAKE_WAREHOUSE"]


class SnowflakeSession:
    """Thin wrapper so tests read as arrange / act / assert."""

    def __init__(self, conn):
        self._conn = conn

    def execute(self, sql, params=None):
        with self._conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.rowcount

    def query(self, sql, params=None):
        with self._conn.cursor(DictCursor) as cur:
            cur.execute(sql, params)
            return cur.fetchall()

    def scalar(self, sql, params=None):
        with self._conn.cursor() as cur:
            cur.execute(sql, params)
            row = cur.fetchone()
            return row[0] if row else None

    def call(self, proc_name, *args):
        placeholders = ", ".join(["%s"] * len(args))
        return self.scalar(f"CALL {proc_name}({placeholders})", args)

    def truncate(self, *tables):
        for table in tables:
            self.execute("TRUNCATE TABLE IF EXISTS IDENTIFIER(%s)", (table,))

    def insert_rows(self, table, rows):
        if not rows:
            return
        columns = list(rows[0].keys())
        placeholders = ", ".join(["%s"] * len(columns))
        sql = f"INSERT INTO IDENTIFIER(%s) ({', '.join(columns)}) SELECT {placeholders}"
        for row in rows:
            self.execute(sql, (table, *[row[c] for c in columns]))

    def latest_audit(self, proc_name):
        rows = self.query(
            "SELECT * FROM ETL.LOAD_AUDIT WHERE PROC_NAME = %s ORDER BY AUDIT_ID DESC LIMIT 1",
            (proc_name,),
        )
        return rows[0] if rows else None


@pytest.fixture(scope="session")
def sf_conn():
    missing = [name for name in REQUIRED_ENV if not os.getenv(name)]
    if missing:
        pytest.skip(f"Snowflake environment variables not set: {', '.join(missing)}")

    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        role=os.environ["SNOWFLAKE_ROLE"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        authenticator=os.getenv("SNOWFLAKE_AUTHENTICATOR", "externalbrowser"),
        session_parameters={"QUERY_TAG": "pytest"},
    )

    source_db = os.getenv("SNOWFLAKE_SOURCE_DATABASE", "DEMO_DB")
    test_db = f"{source_db}_PYTEST_{uuid.uuid4().hex[:8]}".upper()

    with conn.cursor() as cur:
        cur.execute("CREATE DATABASE IDENTIFIER(%s) CLONE IDENTIFIER(%s)", (test_db, source_db))
        cur.execute("USE DATABASE IDENTIFIER(%s)", (test_db,))
    try:
        yield conn
    finally:
        with conn.cursor() as cur:
            cur.execute("DROP DATABASE IF EXISTS IDENTIFIER(%s)", (test_db,))
        conn.close()


@pytest.fixture
def sf(sf_conn):
    return SnowflakeSession(sf_conn)
