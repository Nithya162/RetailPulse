-- =====================================================================
-- DATA TESTS: every row is one assertion. failures = 0 means PASS.
-- The runner fails loudly if any 'error' test fails (like dbt tests, in plain SQL).
-- =====================================================================
CREATE OR REPLACE TABLE retailpulse_qa.test_results AS
WITH tests AS (
  SELECT 'unique: fct_orders.order_id' AS test_name, 'error' AS severity,
         (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM retailpulse_mart.fct_orders) AS failures
  UNION ALL
  SELECT 'unique: fct_order_items.order_item_id', 'error',
         (SELECT COUNT(*) - COUNT(DISTINCT order_item_id) FROM retailpulse_mart.fct_order_items)
  UNION ALL
  SELECT 'unique: dim_customer.user_id', 'error',
         (SELECT COUNT(*) - COUNT(DISTINCT user_id) FROM retailpulse_mart.dim_customer)
  UNION ALL
  SELECT 'unique: fct_sessions.session_id', 'error',
         (SELECT COUNT(*) - COUNT(DISTINCT session_id) FROM retailpulse_mart.fct_sessions)
  UNION ALL
  SELECT 'not_null: fct_order_items.sale_price', 'error',
         (SELECT COUNTIF(sale_price IS NULL) FROM retailpulse_mart.fct_order_items)
  UNION ALL
  SELECT 'relationship: order_items -> dim_product', 'error',
         (SELECT COUNT(*) FROM retailpulse_mart.fct_order_items f
          LEFT JOIN retailpulse_mart.dim_product p USING (product_id) WHERE p.product_id IS NULL)
  UNION ALL
  SELECT 'relationship: orders -> dim_customer', 'error',
         (SELECT COUNT(*) FROM retailpulse_mart.fct_orders o
          LEFT JOIN retailpulse_mart.dim_customer c USING (user_id) WHERE c.user_id IS NULL)
  UNION ALL
  SELECT 'accepted_values: order status', 'error',
         (SELECT COUNTIF(status NOT IN ('Shipped', 'Complete', 'Processing', 'Cancelled', 'Returned'))
          FROM retailpulse_mart.fct_orders)
  UNION ALL
  SELECT 'range: sale_price > 0', 'error',
         (SELECT COUNTIF(sale_price <= 0) FROM retailpulse_mart.fct_order_items)
  UNION ALL
  SELECT 'freshness: no future order dates', 'error',
         (SELECT COUNTIF(order_date > CURRENT_DATE()) FROM retailpulse_mart.fct_orders)
  UNION ALL
  -- revenue must reconcile between item grain and order grain (to the cent)
  SELECT 'reconciliation: order vs item net revenue', 'error',
         (SELECT IF(ABS((SELECT SUM(net_revenue) FROM retailpulse_mart.fct_orders)
                      - (SELECT SUM(net_revenue) FROM retailpulse_mart.fct_order_items)) < 0.01, 0, 1))
  UNION ALL
  SELECT 'reconciliation: daily KPIs vs orders (non-cancelled)', 'error',
         (SELECT IF(ABS((SELECT SUM(net_revenue) FROM retailpulse_mart.agg_daily_kpis)
                      - (SELECT SUM(net_revenue) FROM retailpulse_mart.fct_orders
                         WHERE status != 'Cancelled' AND order_date <= CURRENT_DATE())) < 0.01, 0, 1))
  UNION ALL
  SELECT 'logic: funnel steps never increase', 'warn',
         (SELECT COUNTIF(cart_sessions > product_sessions OR purchase_sessions > cart_sessions)
          FROM retailpulse_mart.agg_funnel)
  UNION ALL
  SELECT 'logic: retention month 0 = 100%', 'error',
         (SELECT COUNTIF(ABS(retention_rate - 1) > 1e-9)
          FROM retailpulse_mart.agg_cohort_retention WHERE months_since_first_order = 0)
)
SELECT
  CURRENT_TIMESTAMP()               AS run_ts,
  test_name,
  severity,
  failures,
  CASE WHEN failures = 0 THEN 'PASS' WHEN severity = 'warn' THEN 'WARN' ELSE 'FAIL' END AS status
FROM tests;
