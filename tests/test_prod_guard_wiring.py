"""The prod guard sits in front of the Postgres read in export_from_postgres.

The export defaults to 127.0.0.1:5434, which is a `fly proxy` tunnel to
production whenever one is open. This fakes a flyctl listener and asserts
nothing connects and the existing SQLite export is left alone.
"""
from __future__ import annotations

import importlib.util
import os

import pytest

pytest.importorskip("psycopg2")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")


def test_export_refuses_fly_tunnel(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_URL", "postgresql://localhost:5432/db")
    monkeypatch.delenv("ALLOW_PROD_DB", raising=False)
    monkeypatch.syspath_prepend(SCRIPTS)
    spec = importlib.util.spec_from_file_location(
        "export_from_postgres", os.path.join(SCRIPTS, "export_from_postgres.py"))
    exp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(exp)

    monkeypatch.setattr(exp, "OUT", tmp_path / "out.db")
    monkeypatch.setattr(exp.prod_guard, "_listener", lambda port: "flyctl")
    monkeypatch.setattr(exp.psycopg2, "connect", lambda *a, **kw: pytest.fail("connected"))
    with pytest.raises(exp.prod_guard.ProdDatabaseError):
        exp.export()
