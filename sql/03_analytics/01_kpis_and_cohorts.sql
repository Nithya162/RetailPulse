-- =====================================================================
-- ANALYTICS: daily KPIs, cohort retention, RFM segmentation
-- =====================================================================

-- Daily KPI table with 7-day / 28-day rolling averages and YoY comparison
CREATE OR REPLACE TABLE retailpulse_mart.agg_daily_kpis AS
WITH daily AS (
  SELECT
    order_date                                        AS date,
    COUNT(DISTINCT order_id)                          AS orders,
    COUNT(DISTINCT user_id)                           AS customers,
    COUNTIF(customer_order_number = 1)                AS new_customer_orders,
    SUM(gross_revenue)                                AS gross_revenue,
    SUM(net_revenue)                                  AS net_revenue,
    SUM(gross_profit)                                 AS gross_profit
  FROM retailpulse_mart.fct_orders
  WHERE status != 'Cancelled'
  GROUP BY order_date
),
sessions AS (
  SELECT session_date AS date, COUNT(*) AS sessions, COUNTIF(reached_purchase) AS purchase_sessions
  FROM retailpulse_mart.fct_sessions
  GROUP BY session_date
)
SELECT
  d.date,
  COALESCE(k.orders, 0)                 AS orders,
  COALESCE(k.customers, 0)              AS customers,
  COALESCE(k.new_customer_orders, 0)    AS new_customer_orders,
  COALESCE(k.gross_revenue, 0)          AS gross_revenue,
  COALESCE(k.net_revenue, 0)            AS net_revenue,
  COALESCE(k.gross_profit, 0)           AS gross_profit,
  SAFE_DIVIDE(k.net_revenue, k.orders)  AS avg_order_value,
  COALESCE(s.sessions, 0)               AS sessions,
  SAFE_DIVIDE(s.purchase_sessions, s.sessions) AS session_conversion_rate,
  AVG(COALESCE(k.net_revenue, 0)) OVER (ORDER BY d.date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)  AS net_revenue_7d_avg,
  AVG(COALESCE(k.net_revenue, 0)) OVER (ORDER BY d.date ROWS BETWEEN 27 PRECEDING AND CURRENT ROW) AS net_revenue_28d_avg,
  LAG(COALESCE(k.net_revenue, 0), 364) OVER (ORDER BY d.date) AS net_revenue_same_weekday_ly
FROM retailpulse_mart.dim_date d
LEFT JOIN daily    k ON d.date = k.date
LEFT JOIN sessions s ON d.date = s.date
WHERE d.date BETWEEN (SELECT MIN(order_date) FROM retailpulse_mart.fct_orders) AND CURRENT_DATE();

-- Monthly cohort retention: % of each first-purchase cohort that orders again in month N
CREATE OR REPLACE TABLE retailpulse_mart.agg_cohort_retention AS
WITH orders_by_month AS (
  SELECT DISTINCT
    user_id,
    DATE_TRUNC(order_date, MONTH) AS activity_month
  FROM retailpulse_mart.fct_orders
  WHERE status != 'Cancelled'
),
-- cohort = month of each customer's first non-cancelled order, taken from the
-- same activity we measure, so month 0 retention is always exactly 100%
activity AS (
  SELECT
    user_id,
    activity_month,
    MIN(activity_month) OVER (PARTITION BY user_id) AS cohort_month
  FROM orders_by_month
),
cohort_size AS (
  SELECT cohort_month, COUNT(DISTINCT user_id) AS cohort_customers
  FROM activity
  GROUP BY cohort_month
)
SELECT
  a.cohort_month,
  DATE_DIFF(a.activity_month, a.cohort_month, MONTH) AS months_since_first_order,
  cs.cohort_customers,
  COUNT(DISTINCT a.user_id)                           AS active_customers,
  SAFE_DIVIDE(COUNT(DISTINCT a.user_id), cs.cohort_customers) AS retention_rate
FROM activity a
JOIN cohort_size cs USING (cohort_month)
GROUP BY a.cohort_month, months_since_first_order, cs.cohort_customers;

-- RFM segmentation (Recency, Frequency, Monetary) with quintile scores
CREATE OR REPLACE TABLE retailpulse_mart.customer_rfm AS
WITH base AS (
  SELECT
    user_id,
    DATE_DIFF(CURRENT_DATE(), MAX(order_date), DAY) AS recency_days,
    COUNT(DISTINCT order_id)                        AS frequency,
    SUM(net_revenue)                                AS monetary
  FROM retailpulse_mart.fct_orders
  WHERE status NOT IN ('Cancelled')
  GROUP BY user_id
),
scored AS (
  SELECT
    *,
    6 - NTILE(5) OVER (ORDER BY recency_days)       AS r_score,   -- recent = 5
    NTILE(5) OVER (ORDER BY frequency, monetary)    AS f_score,
    NTILE(5) OVER (ORDER BY monetary)               AS m_score
  FROM base
)
SELECT
  *,
  CONCAT(CAST(r_score AS STRING), CAST(f_score AS STRING), CAST(m_score AS STRING)) AS rfm_code,
  CASE
    WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
    WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal'
    WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
    WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk'
    WHEN r_score <= 2 AND m_score >= 4                  THEN "Can't Lose Them"
    WHEN r_score <= 2                                   THEN 'Hibernating'
    ELSE 'Needs Attention'
  END AS rfm_segment
FROM scored;