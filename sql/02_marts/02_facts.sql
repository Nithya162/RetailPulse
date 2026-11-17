-- =====================================================================
-- MARTS: facts
-- Revenue definitions (see docs/metric_definitions.md):
--   gross_revenue = sale_price of all non-cancelled items
--   net_revenue   = gross_revenue minus returned items
--   gross_profit  = net_revenue - product cost of kept items
-- {{PARTITION_ORDER_DATE}} -> "PARTITION BY order_date" when billing is on,
--                              empty in the sandbox (60-day partition expiry)
-- =====================================================================

CREATE OR REPLACE TABLE retailpulse_mart.fct_order_items
{{PARTITION_ORDER_DATE}}
CLUSTER BY product_id, user_id
AS
SELECT
  oi.order_item_id,
  oi.order_id,
  oi.user_id,
  oi.product_id,
  oi.order_date,
  oi.status,
  oi.sale_price,
  p.cost                                                     AS unit_cost,
  oi.status = 'Cancelled'                                    AS is_cancelled,
  oi.status = 'Returned'                                     AS is_returned,
  IF(oi.status != 'Cancelled', oi.sale_price, 0)             AS gross_revenue,
  IF(oi.status NOT IN ('Cancelled', 'Returned'), oi.sale_price, 0) AS net_revenue,
  IF(oi.status NOT IN ('Cancelled', 'Returned'), oi.sale_price - p.cost, 0) AS gross_profit,
  SAFE_DIVIDE(p.retail_price - oi.sale_price, p.retail_price) AS discount_pct
FROM retailpulse_stg.order_items oi
LEFT JOIN retailpulse_stg.products p USING (product_id);

-- Order grain: totals + fulfillment SLA metrics
CREATE OR REPLACE TABLE retailpulse_mart.fct_orders
{{PARTITION_ORDER_DATE}}
CLUSTER BY user_id
AS
WITH items AS (
  SELECT
    order_id,
    COUNT(*)            AS item_lines,
    SUM(gross_revenue)  AS gross_revenue,
    SUM(net_revenue)    AS net_revenue,
    SUM(gross_profit)   AS gross_profit
  FROM retailpulse_mart.fct_order_items
  GROUP BY order_id
)
SELECT
  o.order_id,
  o.user_id,
  o.order_date,
  o.status,
  o.items_in_order,
  i.item_lines,
  i.gross_revenue,
  i.net_revenue,
  i.gross_profit,
  -- sequence of non-cancelled orders per customer: 1 = new customer, >1 = returning
  IF(o.status = 'Cancelled', NULL,
     ROW_NUMBER() OVER (PARTITION BY o.user_id, o.status = 'Cancelled' ORDER BY o.order_ts, o.order_id)
  ) AS customer_order_number,
  TIMESTAMP_DIFF(o.shipped_ts,   o.order_ts,   HOUR) / 24.0 AS days_to_ship,
  TIMESTAMP_DIFF(o.delivered_ts, o.shipped_ts, HOUR) / 24.0 AS days_in_transit,
  TIMESTAMP_DIFF(o.delivered_ts, o.order_ts,   HOUR) / 24.0 AS days_to_deliver,
  u.acquisition_channel
FROM retailpulse_stg.orders o
LEFT JOIN items i USING (order_id)
LEFT JOIN retailpulse_stg.users u USING (user_id);

-- Session grain: web funnel built from the clickstream
CREATE OR REPLACE TABLE retailpulse_mart.fct_sessions AS
SELECT
  session_id,
  ANY_VALUE(user_id)                                   AS user_id,
  MIN(event_ts)                                        AS session_start_ts,
  DATE(MIN(event_ts))                                  AS session_date,
  -- traffic source of the first event in the session
  ANY_VALUE(traffic_source HAVING MIN sequence_number) AS traffic_source,
  ANY_VALUE(browser        HAVING MIN sequence_number) AS browser,
  COUNT(*)                                             AS events,
  TIMESTAMP_DIFF(MAX(event_ts), MIN(event_ts), SECOND) AS session_seconds,
  LOGICAL_OR(event_type = 'home')                      AS reached_home,
  LOGICAL_OR(event_type IN ('department', 'product'))  AS reached_browse,
  LOGICAL_OR(event_type = 'product')                   AS reached_product,
  LOGICAL_OR(event_type = 'cart')                      AS reached_cart,
  LOGICAL_OR(event_type = 'purchase')                  AS reached_purchase,
  LOGICAL_OR(event_type = 'cancel')                    AS had_cancel,
  ANY_VALUE(user_id) IS NULL                           AS is_anonymous
FROM retailpulse_stg.events
GROUP BY session_id;
