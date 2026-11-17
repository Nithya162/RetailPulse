# Power BI build guide

Power BI Desktop is free but **Windows only**. On a Mac: use a Windows VM
(Parallels/UTM) or your university's virtual desktop lab.

## 1. Connect
1. **Get data → Google BigQuery** → sign in → expand your project → `retailpulse_mart`.
2. Select: `dim_date`, `dim_product`, `dim_customer`, `fct_order_items`, `fct_orders`,
   `agg_cohort_retention`, `customer_rfm`, `agg_funnel`, `agg_product_performance`,
   `agg_category_affinity`, `agg_fulfillment`, plus `agg_revenue_forecast` and
   `customer_churn_scores` if you ran `--with-ml`.
3. Choose **Import** (fast, and you can explain Import vs DirectQuery in interviews:
   Import caches data in the model for speed; DirectQuery queries BigQuery live,
   which is fresher but slower and costs a query per visual).
4. In Power Query, set `fct_order_items[order_date]`, `fct_orders[order_date]` and
   `dim_date[date]` to type **Date**. Rename query steps so they read cleanly.

## 2. Star schema (Model view)
| Many side | One side |
|---|---|
| `fct_order_items[product_id]` | `dim_product[product_id]` |
| `fct_order_items[user_id]` | `dim_customer[user_id]` |
| `fct_order_items[order_date]` | `dim_date[date]` |
| `fct_orders[user_id]` | `dim_customer[user_id]` |
| `fct_orders[order_date]` | `dim_date[date]` |
| `customer_rfm[user_id]` | `dim_customer[user_id]` (1:1) |
| `customer_churn_scores[user_id]` | `dim_customer[user_id]` (1:1) |
| `agg_revenue_forecast[date]` | `dim_date[date]` |
| `agg_product_performance[product_id]` | `dim_product[product_id]` (1:1) |

`agg_funnel`, `agg_cohort_retention`, `agg_fulfillment` and `agg_category_affinity`
are pre-aggregated and stay unrelated (disconnected tables). Then:
- **Mark `dim_date` as date table** (Table tools → Mark as date table)
- Hide every key column and every raw numeric column that has a measure
- Add the measures from `measures.dax` into a `_Measures` table, organized into display folders (Revenue, Customers, Funnel, Ops, Forecast)
- **View → Themes → Browse** → `retailpulse_theme.json`

## 3. Pages (16:9, consistent header + slicer bar)

**1 · Executive Overview**
- KPI cards: Net Revenue (with `Revenue Trend Arrow` as subtitle), Orders, AOV, Gross Margin %, Repeat Customer %
- Line: Net Revenue and Net Revenue LY by month
- Bar: Net Revenue by `dim_product[category]` (top 10)
- Map or filled map: Net Revenue by `dim_customer[country]`
- Slicers: year, department, country

**2 · Customers & Retention**
- Matrix heatmap: `agg_cohort_retention` rows = cohort_month, columns = months_since_first_order (0–12), values = retention_rate, conditional formatting background color scale
- Donut or bar: customers and revenue by `customer_rfm[rfm_segment]`
- Column: New vs Returning customers by month
- Bar: Avg Customer Lifetime Revenue by acquisition_channel

**3 · Marketing Funnel**
- Funnel visual: Sessions → browse → product → cart → purchase (from `agg_funnel` sums)
- Clustered bar: Conversion Rate and Cart Abandonment % by traffic_source
- Line: Conversion Rate by month, legend = traffic_source

**4 · Products**
- Pareto chart: column = product net revenue (sorted desc), line = cumulative_revenue_share
- Table: top products with units, revenue, gross profit, return rate, ABC class (data bars)
- Scatter: avg_discount_pct (x) vs return_rate (y), size = net_revenue, legend = category
- Table: top category pairs by lift (`agg_category_affinity`) as the "cross-sell opportunities" panel

**5 · Operations**
- KPI cards: Return Rate, Cancel Rate, Avg Days to Deliver
- Line: avg_days_to_ship and p90_days_to_deliver by month (`agg_fulfillment`)
- Column: return_rate by month

**6 · Forecast & Churn** (if you ran `--with-ml`)
- Line: Actual Revenue (daily) + Forecast Revenue with an error band (Forecast Lower/Upper 90)
- Card: High Churn Risk Customers; table of high-risk customers with lifetime revenue → "who to target with a win-back campaign"

## 4. Polish that interviewers notice
- Tooltip page: hover a category → mini trend + margin
- Drill-through: right-click a product → product detail page
- Bookmarks + buttons to switch between "Revenue" and "Profit" views
- A small "How to read this dashboard / metric definitions" info button
- Performance Analyzer: screenshot showing visuals render in < 1 s
- Export each page to `docs/screenshots/` and the whole report to PDF for the README
