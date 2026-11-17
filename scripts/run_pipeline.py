"""
Build RetailPulse in your BigQuery project from the public thelook_ecommerce data.

    pip install google-cloud-bigquery
    gcloud auth application-default login
    python scripts/run_pipeline.py --project YOUR_PROJECT_ID              # free sandbox OK
    python scripts/run_pipeline.py --project YOUR_PROJECT_ID --with-ml    # + BigQuery ML
    python scripts/run_pipeline.py --project YOUR_PROJECT_ID --partition  # billing on only

Cost: the source is ~a few GB; one full run scans far less than the 1 TB/month
free query tier. Use --dry-run to print the bytes each file would scan first.
"""
import argparse
import glob
import os
import sys
import time

from google.cloud import bigquery

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = "bigquery-public-data.thelook_ecommerce"
DATASETS = {
    "retailpulse_stg": "Staging: typed, renamed copies of thelook_ecommerce source tables",
    "retailpulse_mart": "Star schema + analytics tables consumed by Power BI",
    "retailpulse_ml": "BigQuery ML models and training data",
    "retailpulse_qa": "Automated data test results",
}


def render(sql, partition):
    return (sql.replace("{{SRC}}", SRC)
               .replace("{{PARTITION_ORDER_DATE}}", "PARTITION BY order_date" if partition else ""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--location", default="US", help="must be US: the public dataset lives in the US multi-region")
    ap.add_argument("--with-ml", action="store_true", help="also train BigQuery ML models (sql/04_ml)")
    ap.add_argument("--partition", action="store_true",
                    help="partition fact tables by day. Do NOT use in the sandbox: sandbox partitions expire after 60 days")
    ap.add_argument("--dry-run", action="store_true", help="estimate bytes scanned without running")
    a = ap.parse_args()

    client = bigquery.Client(project=a.project, location=a.location)
    for ds, desc in DATASETS.items():
        d = bigquery.Dataset(f"{a.project}.{ds}")
        d.location, d.description, d.labels = a.location, desc, {"project": "retailpulse"}
        client.create_dataset(d, exists_ok=True)

    total_bytes = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "sql", "*", "*.sql"))):
        rel = os.path.relpath(path, ROOT)
        if "04_ml" in path and not a.with_ml:
            print(f"skip  {rel}  (add --with-ml)")
            continue
        sql = render(open(path).read(), a.partition)
        cfg = bigquery.QueryJobConfig(dry_run=a.dry_run, use_query_cache=False)
        t0 = time.time()
        if a.dry_run:
            try:
                b = client.query(sql, job_config=cfg).total_bytes_processed or 0
            except Exception:  # later files read tables that don't exist until the first real run
                print(f"plan  {rel:45s}     n/a  (reads tables created by earlier steps)")
                continue
        else:
            job = client.query(sql, job_config=cfg)
            job.result()
            # multi-statement scripts report bytes on their child jobs
            b = job.total_bytes_processed or sum(
                (c.total_bytes_processed or 0) for c in client.list_jobs(parent_job=job.job_id))
        total_bytes += b
        print(f"{'plan' if a.dry_run else 'ran '}  {rel:45s} {b / 1e9:7.2f} GB  {time.time() - t0:5.1f}s")

    print(f"\nTotal scanned: {total_bytes / 1e9:.2f} GB")
    if a.dry_run:
        return

    print("\nData tests")
    failed = 0
    for r in client.query("SELECT test_name, failures, status FROM retailpulse_qa.test_results ORDER BY test_name").result():
        print(f"  {r.status:4s}  {r.test_name}  (failures={r.failures})")
        failed += r.status == "FAIL"
    if failed:
        sys.exit(f"\n{failed} data test(s) failed")
    print("\nAll data tests passed. Connect Power BI to the retailpulse_mart dataset.")


if __name__ == "__main__":
    main()
