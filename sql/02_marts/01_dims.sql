-- =====================================================================
-- MARTS: dimensions
-- =====================================================================

CREATE OR REPLACE TABLE retailpulse_mart.dim_date AS
SELECT
  d                                   AS date,
  EXTRACT(YEAR FROM d)                AS year,
  EXTRACT(QUARTER FROM d)             AS quarter,
  EXTRACT(MONTH FROM d)               AS month_num,
  FORMAT_DATE('%b', d)                AS month_name,
  DATE_TRUNC(d, MONTH)                AS month_start,
  DATE_TRUNC(d, WEEK(MONDAY))         AS week_start,
  FORMAT_DATE('%a', d)                AS day_name,
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7) AS is_weekend
FROM UNNEST(GENERATE_DATE_ARRAY('2019-01-01', DATE_ADD(CURRENT_DATE(), INTERVAL 1 YEAR))) AS d;

CREATE OR REPLACE TABLE retailpulse_mart.dim_product AS
SELECT
  p.product_id,
  p.product_name,
  p.brand,
  p.category,
  p.department,
  p.cost,
  p.retail_price,
  SAFE_DIVIDE(p.retail_price - p.cost, p.retail_price) AS list_margin_pct,
  dc.distribution_center_name
FROM retailpulse_stg.products p
LEFT JOIN retailpulse_stg.distribution_centers dc USING (distribution_center_id);

-- Customer dimension with lifetime metrics and acquisition cohort
CREATE OR REPLACE TABLE retailpulse_mart.dim_customer AS
-- Order dates/counts come from the ORDER grain (same source as fct_orders), so
-- cohorts here always line up with order-level activity. Item-level status and
-- timestamps can differ slightly from their parent order in the source data.
WITH order_stats AS (
  SELECT
    user_id,
    MIN(order_date)                                   AS first_order_date,
    MAX(order_date)                                   AS last_order_date,
    COUNT(DISTINCT order_id)                          AS lifetime_orders
  FROM retailpulse_stg.orders
  WHERE status != 'Cancelled'          -- a cancelled order does not make someone a customer
  GROUP BY user_id
),
revenue AS (
  SELECT user_id, SUM(IF(status NOT IN ('Cancelled', 'Returned'), sale_price, 0)) AS lifetime_net_revenue
  FROM retailpulse_stg.order_items
  GROUP BY user_id
),
order_stats_rev AS (
  SELECT o.*, COALESCE(r.lifetime_net_revenue, 0) AS lifetime_net_revenue
  FROM order_stats o LEFT JOIN revenue r USING (user_id)
)
SELECT
  u.user_id,
  u.age,
  CASE
    WHEN u.age < 25 THEN '18-24'
    WHEN u.age < 35 THEN '25-34'
    WHEN u.age < 45 THEN '35-44'
    WHEN u.age < 55 THEN '45-54'
    ELSE '55+'
  END                                                 AS age_band,
  u.gender,
  u.city,
  u.state,
  u.country,
  u.acquisition_channel,
  u.signup_date,
  o.first_order_date,
  DATE_TRUNC(o.first_order_date, MONTH)               AS cohort_month,
  o.last_order_date,
  COALESCE(o.lifetime_orders, 0)                      AS lifetime_orders,
  COALESCE(o.lifetime_net_revenue, 0)                 AS lifetime_net_revenue,
  o.user_id IS NOT NULL                               AS is_buyer,
  COALESCE(o.lifetime_orders, 0) > 1                  AS is_repeat_buyer,
  DATE_DIFF(o.first_order_date, u.signup_date, DAY)   AS days_signup_to_first_order
FROM retailpulse_stg.users u
LEFT JOIN order_stats_rev o USING (user_id);