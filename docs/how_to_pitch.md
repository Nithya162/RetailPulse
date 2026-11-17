# Using RetailPulse in applications

Fill every `[X]` from `analysis/insights.sql` after your real BigQuery run.
**Never put a number on your resume that you didn't get from your own query.**

## Resume entry (pick 2–3 bullets per application)

**RetailPulse: End-to-End E-commerce Analytics Platform** | BigQuery, SQL, Power BI, DAX, BigQuery ML, Python | [GitHub link]

- Built a layered BigQuery warehouse (staging → star schema → analytics marts) over [X]K orders and [X]M clickstream events from Google's public thelook_ecommerce dataset, using partitioning/clustering and window functions.
- Designed a 6-page Power BI report on a star-schema semantic model with [X] DAX measures (YoY, rolling 3-month, cohort retention, funnel conversion) for executive, marketing, product and operations audiences.
- Built cohort retention, RFM segmentation and session-funnel models in SQL. Found [traffic source] converts [X]× better than [traffic source] and that [X]% of products drive 80% of revenue.
- Trained BigQuery ML models: a 90-day ARIMA_PLUS revenue forecast and a churn classifier (ROC AUC [X]) that flags [X] high-risk customers representing $[X] in historical revenue.
- Added 14 automated SQL data tests (uniqueness, referential integrity, revenue reconciliation) and a CI pipeline that runs the full SQL locally in DuckDB on every commit.

## Which bullets to lead with, by role

| Role you apply to | Lead with | Talk about |
|---|---|---|
| Data Analyst / BI Analyst | Power BI report + insights bullet | Star schema, DAX time intelligence, the story behind 2–3 findings |
| Business / Product Analyst | Funnel + cohort bullet | Conversion drop-offs, retention curve, what you'd recommend |
| Marketing Analyst | Funnel by traffic source + RFM | Channel performance, win-back targeting with churn scores |
| Analytics Engineer | Warehouse layers + tests + CI | Grain of each table, reconciliation tests, why marts are pre-aggregated |
| Data Engineer | Warehouse + partitioning + runner | Cost control (bytes scanned), partition/cluster choice, idempotent rebuilds |
| Data Scientist / ML (entry) | BigQuery ML bullet | Leakage-safe churn label (snapshot cutoff), class weights, evaluation |
| Data Governance / Quality | Pair with **BuildTrust** | Use BuildTrust as the main project, RetailPulse as the BI proof |

## 60-second interview walkthrough
1. **Problem:** "An online retailer wants one trusted view of revenue, customers and funnel performance."
2. **Data:** "Google's public e-commerce dataset in BigQuery: orders, items, products, users and [X]M web events."
3. **Build:** "Three layers in BigQuery. Staging cleans and types, marts are a star schema, analytics tables hold cohorts, RFM and funnel. 14 SQL tests run every build, including a check that revenue reconciles to the cent between order and item grain."
4. **Report:** "Power BI on that star schema, with Import mode, a marked date table, and measures for YoY and rolling periods."
5. **Insight:** "[Your best finding] → [what you'd recommend]."
6. **Extra:** "BigQuery ML forecast and churn scoring, so the report says who to target, not just what happened."

## Questions you should be ready for
- *What's the grain of fct_orders vs fct_order_items, and why keep both?*
- *Why is Gross Margin % a ratio of sums, not an average of percentages?*
- *Import vs DirectQuery: which did you use and why?*
- *How did you avoid leakage in the churn label?* (Features stop at the cutoff date; the label only looks after it.)
- *How would you make this incremental?* (MERGE on order_item_id for the last N days of partitions, or dbt incremental models.)
- *What would you do differently in production?* (Scheduled queries/Composer, dbt, alerting on test failures, row-level security in Power BI.)
