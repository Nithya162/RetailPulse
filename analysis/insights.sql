-- =====================================================================
-- Headline insight queries. Run in the BigQuery console after the
-- pipeline, then paste the real numbers into docs/findings.md and your
-- resume bullets. (Every number on your resume should come from here.)
-- =====================================================================

-- 1. Business size: last 12 months
SELECT
  SUM(net_revenue)                          AS net_revenue_12m,
  SUM(gross_profit) / SUM(net_revenue)      AS gross_margin_pct,
  SUM(orders)                               AS orders_12m,
  SUM(net_revenue) / SUM(orders)            AS avg_order_value
FROM retailpulse_mart.agg_daily_kpis
WHERE date > DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH);

-- 2. Growth: this year vs last year, same period to date
SELECT
  SUM(IF(EXTRACT(YEAR FROM date) = EXTRACT(YEAR FROM CURRENT_DATE()), net_revenue, 0)) AS ytd,
  SUM(IF(EXTRACT(YEAR FROM date) = EXTRACT(YEAR FROM CURRENT_DATE()) - 1
         AND EXTRACT(DAYOFYEAR FROM date) <= EXTRACT(DAYOFYEAR FROM CURRENT_DATE()), net_revenue, 0)) AS ly_ytd
FROM retailpulse_mart.agg_daily_kpis;

-- 3. Repeat purchase rate and revenue share from repeat buyers
SELECT
  COUNTIF(is_repeat_buyer) / COUNTIF(is_buyer)                                   AS repeat_buyer_rate,
  SUM(IF(is_repeat_buyer, lifetime_net_revenue, 0)) / SUM(lifetime_net_revenue)  AS repeat_revenue_share
FROM retailpulse_mart.dim_customer;

-- 4. Month-1 and month-3 retention, average across cohorts
SELECT months_since_first_order, AVG(retention_rate) AS avg_retention
FROM retailpulse_mart.agg_cohort_retention
WHERE months_since_first_order IN (1, 3, 6)
GROUP BY 1 ORDER BY 1;

-- 5. Best and worst converting traffic sources (last 12 months)
SELECT traffic_source,
       SUM(purchase_sessions) / SUM(sessions)                                AS conversion_rate,
       SUM(cart_sessions - purchase_sessions) / NULLIF(SUM(cart_sessions), 0) AS cart_abandonment
FROM retailpulse_mart.agg_funnel
WHERE month_start > DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
GROUP BY 1 ORDER BY 2 DESC;

-- 6. Pareto: what % of products drive 80% of revenue
SELECT COUNTIF(abc_class = 'A') / COUNT(*) AS share_of_products_in_A
FROM retailpulse_mart.agg_product_performance;

-- 7. Categories with the highest return rate
SELECT category, SUM(units_sold) AS units, AVG(return_rate) AS avg_return_rate
FROM retailpulse_mart.agg_product_performance
GROUP BY 1 ORDER BY 3 DESC LIMIT 5;

-- 8. Strongest category pairing (cross-sell)
SELECT * FROM retailpulse_mart.agg_category_affinity ORDER BY lift DESC LIMIT 5;

-- 9. RFM: revenue concentration in Champions
SELECT rfm_segment, COUNT(*) AS customers, SUM(monetary) AS revenue,
       SUM(monetary) / SUM(SUM(monetary)) OVER () AS revenue_share
FROM retailpulse_mart.customer_rfm GROUP BY 1 ORDER BY revenue DESC;

-- 10. (after --with-ml) churn model quality and revenue at risk
SELECT * FROM retailpulse_ml.churn_model_evaluation;
SELECT s.churn_risk_band, COUNT(*) AS customers, SUM(r.monetary) AS historical_revenue
FROM retailpulse_mart.customer_churn_scores s
JOIN retailpulse_mart.customer_rfm r USING (user_id)
GROUP BY 1;
