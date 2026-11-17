-- =====================================================================
-- STAGING: 1:1 with source tables. Rename, cast, derive dates, and drop
-- records timestamped in the future (the public dataset is regenerated
-- daily and can contain rows a few hours ahead).
-- {{SRC}} = bigquery-public-data.thelook_ecommerce
-- =====================================================================

CREATE OR REPLACE TABLE retailpulse_stg.users AS
SELECT
  id                          AS user_id,
  age,
  gender,
  city,
  state,
  country,
  traffic_source              AS acquisition_channel,
  created_at                  AS signup_ts,
  DATE(created_at)            AS signup_date
FROM `{{SRC}}.users`
WHERE created_at <= CURRENT_TIMESTAMP();

CREATE OR REPLACE TABLE retailpulse_stg.products AS
SELECT
  id                          AS product_id,
  name                        AS product_name,
  brand,
  category,
  department,
  cost,
  retail_price,
  distribution_center_id
FROM `{{SRC}}.products`;

CREATE OR REPLACE TABLE retailpulse_stg.orders AS
SELECT
  order_id,
  user_id,
  status,
  num_of_item                 AS items_in_order,
  created_at                  AS order_ts,
  DATE(created_at)            AS order_date,
  shipped_at                  AS shipped_ts,
  delivered_at                AS delivered_ts,
  returned_at                 AS returned_ts
FROM `{{SRC}}.orders`
WHERE created_at <= CURRENT_TIMESTAMP();

CREATE OR REPLACE TABLE retailpulse_stg.order_items AS
SELECT
  id                          AS order_item_id,
  order_id,
  user_id,
  product_id,
  status,
  sale_price,
  created_at                  AS order_ts,
  DATE(created_at)            AS order_date
FROM `{{SRC}}.order_items`
WHERE created_at <= CURRENT_TIMESTAMP();

CREATE OR REPLACE TABLE retailpulse_stg.events AS
SELECT
  id                          AS event_id,
  user_id,                    -- NULL for anonymous visitors
  session_id,
  sequence_number,
  event_type,
  traffic_source,
  browser,
  created_at                  AS event_ts,
  DATE(created_at)            AS event_date
FROM `{{SRC}}.events`
WHERE created_at <= CURRENT_TIMESTAMP();

CREATE OR REPLACE TABLE retailpulse_stg.distribution_centers AS
SELECT id AS distribution_center_id, name AS distribution_center_name, latitude, longitude
FROM `{{SRC}}.distribution_centers`;
