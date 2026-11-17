-- =====================================================================
-- ANALYTICS: marketing funnel, product performance (Pareto/ABC),
-- market basket, fulfillment & returns
-- =====================================================================

-- Funnel by traffic source and month (session-based)
CREATE OR REPLACE TABLE retailpulse_mart.agg_funnel AS
SELECT
  DATE_TRUNC(session_date, MONTH)        AS month_start,
  traffic_source,
  COUNT(*)                               AS sessions,
  COUNTIF(reached_browse)                AS browse_sessions,
  COUNTIF(reached_product)               AS product_sessions,
  COUNTIF(reached_cart)                  AS cart_sessions,
  COUNTIF(reached_purchase)              AS purchase_sessions,
  SAFE_DIVIDE(COUNTIF(reached_cart), COUNTIF(reached_product))     AS product_to_cart_rate,
  SAFE_DIVIDE(COUNTIF(reached_purchase), COUNTIF(reached_cart))    AS cart_to_purchase_rate,
  SAFE_DIVIDE(COUNTIF(reached_purchase), COUNT(*))                 AS session_conversion_rate,
  SAFE_DIVIDE(COUNTIF(reached_cart AND NOT reached_purchase), COUNTIF(reached_cart)) AS cart_abandonment_rate
FROM retailpulse_mart.fct_sessions
GROUP BY month_start, traffic_source;

-- Product performance with Pareto (ABC) classification and return rate
CREATE OR REPLACE TABLE retailpulse_mart.agg_product_performance AS
WITH p AS (
  SELECT
    f.product_id,
    d.product_name,
    d.brand,
    d.category,
    d.department,
    COUNTIF(NOT f.is_cancelled)                         AS units_sold,
    SUM(f.net_revenue)                                  AS net_revenue,
    SUM(f.gross_profit)                                 AS gross_profit,
    SAFE_DIVIDE(COUNTIF(f.is_returned), COUNTIF(NOT f.is_cancelled)) AS return_rate,
    AVG(f.discount_pct)                                 AS avg_discount_pct
  FROM retailpulse_mart.fct_order_items f
  JOIN retailpulse_mart.dim_product d USING (product_id)
  GROUP BY 1, 2, 3, 4, 5
),
ranked AS (
  SELECT
    *,
    SUM(net_revenue) OVER (ORDER BY net_revenue DESC, product_id
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      / SUM(net_revenue) OVER ()                        AS cumulative_revenue_share,
    RANK() OVER (PARTITION BY category ORDER BY net_revenue DESC) AS rank_in_category
  FROM p
)
SELECT
  *,
  CASE
    WHEN cumulative_revenue_share <= 0.80 THEN 'A'
    WHEN cumulative_revenue_share <= 0.95 THEN 'B'
    ELSE 'C'
  END AS abc_class
FROM ranked;

-- Market basket: category pairs bought in the same order (lift > 1 = affinity)
CREATE OR REPLACE TABLE retailpulse_mart.agg_category_affinity AS
WITH order_cats AS (
  SELECT DISTINCT f.order_id, d.category
  FROM retailpulse_mart.fct_order_items f
  JOIN retailpulse_mart.dim_product d USING (product_id)
  WHERE NOT f.is_cancelled
),
totals AS (SELECT COUNT(DISTINCT order_id) AS n_orders FROM order_cats),
cat_freq AS (SELECT category, COUNT(*) AS orders_with_cat FROM order_cats GROUP BY category),
pairs AS (
  SELECT a.category AS category_a, b.category AS category_b, COUNT(*) AS orders_with_both
  FROM order_cats a
  JOIN order_cats b ON a.order_id = b.order_id AND a.category < b.category
  GROUP BY 1, 2
)
SELECT
  p.category_a,
  p.category_b,
  p.orders_with_both,
  SAFE_DIVIDE(p.orders_with_both, t.n_orders)                            AS support,
  SAFE_DIVIDE(p.orders_with_both, fa.orders_with_cat)                    AS confidence_a_to_b,
  SAFE_DIVIDE(p.orders_with_both * t.n_orders, fa.orders_with_cat * fb.orders_with_cat) AS lift
FROM pairs p
CROSS JOIN totals t
JOIN cat_freq fa ON p.category_a = fa.category
JOIN cat_freq fb ON p.category_b = fb.category
WHERE p.orders_with_both >= 5;

-- Fulfillment & returns by month
CREATE OR REPLACE TABLE retailpulse_mart.agg_fulfillment AS
SELECT
  DATE_TRUNC(order_date, MONTH)                         AS month_start,
  COUNT(*)                                              AS orders,
  COUNTIF(status = 'Cancelled')                         AS cancelled_orders,
  COUNTIF(status = 'Returned')                          AS returned_orders,
  SAFE_DIVIDE(COUNTIF(status = 'Cancelled'), COUNT(*))  AS cancel_rate,
  SAFE_DIVIDE(COUNTIF(status = 'Returned'), COUNTIF(status != 'Cancelled')) AS return_rate,
  AVG(days_to_ship)                                     AS avg_days_to_ship,
  APPROX_QUANTILES(days_to_deliver, 100)[OFFSET(90)]    AS p90_days_to_deliver,
  SAFE_DIVIDE(COUNTIF(days_to_deliver <= 5), COUNTIF(days_to_deliver IS NOT NULL)) AS on_time_rate_5d
FROM retailpulse_mart.fct_orders
GROUP BY month_start;
