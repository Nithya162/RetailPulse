-- =====================================================================
-- BIGQUERY ML (runs in BigQuery only; skipped by the local DuckDB test)
--  1. 90-day revenue forecast  (ARIMA_PLUS time series)
--  2. Customer churn propensity (logistic regression)
-- =====================================================================

-- ---------- 1. Revenue forecast ----------
CREATE OR REPLACE MODEL retailpulse_ml.revenue_forecast
OPTIONS (
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'date',
  time_series_data_col = 'net_revenue',
  horizon = 90,
  holiday_region = 'US'
) AS
SELECT date, net_revenue
FROM retailpulse_mart.agg_daily_kpis
WHERE date < CURRENT_DATE();

-- Actuals + forecast in one table so Power BI can draw a single line chart
CREATE OR REPLACE TABLE retailpulse_mart.agg_revenue_forecast AS
SELECT date, net_revenue AS actual_net_revenue,
       CAST(NULL AS FLOAT64) AS forecast_net_revenue,
       CAST(NULL AS FLOAT64) AS forecast_lower_90,
       CAST(NULL AS FLOAT64) AS forecast_upper_90
FROM retailpulse_mart.agg_daily_kpis
WHERE date < CURRENT_DATE()
UNION ALL
SELECT DATE(forecast_timestamp), NULL,
       forecast_value, prediction_interval_lower_bound, prediction_interval_upper_bound
FROM ML.FORECAST(MODEL retailpulse_ml.revenue_forecast,
                 STRUCT(90 AS horizon, 0.9 AS confidence_level));

-- ---------- 2. Churn propensity ----------
-- Training snapshot: features as of (today - 90d); label = no order in the next 90 days
CREATE OR REPLACE TABLE retailpulse_ml.churn_training AS
WITH params AS (SELECT DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AS cutoff),
hist AS (
  SELECT
    o.user_id,
    DATE_DIFF(p.cutoff, MAX(o.order_date), DAY)                    AS recency_days,
    COUNT(DISTINCT o.order_id)                                     AS frequency,
    SUM(o.net_revenue)                                             AS monetary,
    AVG(o.net_revenue)                                             AS avg_order_value,
    DATE_DIFF(p.cutoff, MIN(o.order_date), DAY)                    AS tenure_days,
    SAFE_DIVIDE(COUNTIF(o.status = 'Returned'), COUNT(*))          AS return_rate
  FROM retailpulse_mart.fct_orders o, params p
  WHERE o.order_date <= p.cutoff AND o.status != 'Cancelled'
  GROUP BY o.user_id, p.cutoff
),
future AS (
  SELECT DISTINCT o.user_id
  FROM retailpulse_mart.fct_orders o, params p
  WHERE o.order_date > p.cutoff AND o.status != 'Cancelled'
)
SELECT
  h.*,
  c.age, c.gender, c.country, c.acquisition_channel,
  f.user_id IS NULL AS churned
FROM hist h
JOIN retailpulse_mart.dim_customer c USING (user_id)
LEFT JOIN future f USING (user_id);

CREATE OR REPLACE MODEL retailpulse_ml.churn_model
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['churned'],
  auto_class_weights = TRUE,
  data_split_method = 'AUTO_SPLIT',
  enable_global_explain = TRUE
) AS
SELECT * EXCEPT (user_id) FROM retailpulse_ml.churn_training;

-- Score every buyer using features as of today
CREATE OR REPLACE TABLE retailpulse_mart.customer_churn_scores AS
WITH today AS (
  SELECT
    o.user_id,
    DATE_DIFF(CURRENT_DATE(), MAX(o.order_date), DAY)      AS recency_days,
    COUNT(DISTINCT o.order_id)                             AS frequency,
    SUM(o.net_revenue)                                     AS monetary,
    AVG(o.net_revenue)                                     AS avg_order_value,
    DATE_DIFF(CURRENT_DATE(), MIN(o.order_date), DAY)      AS tenure_days,
    SAFE_DIVIDE(COUNTIF(o.status = 'Returned'), COUNT(*))  AS return_rate
  FROM retailpulse_mart.fct_orders o
  WHERE o.status != 'Cancelled'
  GROUP BY o.user_id
)
SELECT
  user_id,
  (SELECT prob FROM UNNEST(predicted_churned_probs) WHERE label) AS churn_probability,
  CASE
    WHEN (SELECT prob FROM UNNEST(predicted_churned_probs) WHERE label) >= 0.7 THEN 'High'
    WHEN (SELECT prob FROM UNNEST(predicted_churned_probs) WHERE label) >= 0.4 THEN 'Medium'
    ELSE 'Low'
  END AS churn_risk_band
FROM ML.PREDICT(
  MODEL retailpulse_ml.churn_model,
  (SELECT t.*, c.age, c.gender, c.country, c.acquisition_channel
   FROM today t JOIN retailpulse_mart.dim_customer c USING (user_id)));

-- Model quality + feature importance, for the README / interview
CREATE OR REPLACE TABLE retailpulse_ml.churn_model_evaluation AS
SELECT * FROM ML.EVALUATE(MODEL retailpulse_ml.churn_model);

CREATE OR REPLACE TABLE retailpulse_ml.churn_feature_importance AS
SELECT * FROM ML.GLOBAL_EXPLAIN(MODEL retailpulse_ml.churn_model);
