"""
Run every BigQuery SQL file locally in DuckDB against a schema-identical
fixture, then assert all data tests pass. No GCP account needed.

    pip install duckdb sqlglot pandas numpy
    python tests/test_local.py

BigQuery ML (sql/04_ml) only runs in BigQuery and is skipped here.
"""
import glob
import os
import re
import sys

import duckdb
import sqlglot

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from make_fixture import make_tables  # noqa: E402

LOCAL_VARS = {"{{SRC}}": "thelook", "{{PARTITION_ORDER_DATE}}": ""}


def render_local(sql: str) -> str:
    for k, v in LOCAL_VARS.items():
        sql = sql.replace(k, v)
    # DuckDB has no CLUSTER BY on CTAS (it is a BigQuery storage option)
    return re.sub(r"^\s*CLUSTER BY .*$", "", sql, flags=re.MULTILINE)


def build(verbose=True):
    con = duckdb.connect()
    con.execute("SET TimeZone = 'UTC'")
    for s in ["thelook", "retailpulse_stg", "retailpulse_mart", "retailpulse_qa", "retailpulse_ml"]:
        con.execute(f"CREATE SCHEMA {s}")
    for name, df in make_tables().items():
        con.register("tmp_df", df)
        con.execute(f"CREATE TABLE thelook.{name} AS SELECT * FROM tmp_df")
        con.unregister("tmp_df")
    files = sorted(glob.glob(os.path.join(ROOT, "sql", "*", "*.sql")))
    for path in files:
        if "04_ml" in path:
            if verbose:
                print(f"  skip {os.path.relpath(path, ROOT)} (BigQuery ML only)")
            continue
        for stmt in sqlglot.transpile(render_local(open(path).read()), read="bigquery", write="duckdb"):
            con.execute(stmt)
        if verbose:
            print(f"  ok   {os.path.relpath(path, ROOT)}")
    return con


def main():
    con = build()
    print("\nData tests")
    failed = 0
    for name, sev, failures, status in con.execute(
            "SELECT test_name, severity, failures, status FROM retailpulse_qa.test_results").fetchall():
        print(f"  {status:4s}  {name}  (failures={failures})")
        failed += status == "FAIL"
    print("\nRow counts")
    for t in ["fct_order_items", "fct_orders", "fct_sessions", "dim_customer", "agg_daily_kpis",
              "agg_cohort_retention", "customer_rfm", "agg_funnel", "agg_product_performance",
              "agg_category_affinity", "agg_fulfillment"]:
        print(f"  {t:26s} {con.execute(f'SELECT COUNT(*) FROM retailpulse_mart.{t}').fetchone()[0]:>7,}")
    print("\nRFM segments:", con.execute(
        "SELECT rfm_segment, COUNT(*) FROM retailpulse_mart.customer_rfm GROUP BY 1 ORDER BY 2 DESC").fetchall())
    print("\nALL TESTS PASSED" if not failed else f"\n{failed} TEST(S) FAILED")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
