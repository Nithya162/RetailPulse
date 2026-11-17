# Metric definitions

One definition per metric, used identically in SQL and DAX.

| Metric | Definition | Source |
|---|---|---|
| Gross Revenue | Sale price of all items not cancelled | `fct_order_items.gross_revenue` |
| Net Revenue | Gross revenue minus returned items | `fct_order_items.net_revenue` |
| Gross Profit | Net revenue − product cost of kept items | `fct_order_items.gross_profit` |
| Gross Margin % | Gross profit / net revenue (ratio of sums) | measure |
| Orders | Distinct non-cancelled orders | `fct_orders` |
| Avg Order Value (AOV) | Net revenue / orders | measure |
| New Customer | Customer whose first non-cancelled order falls in the period | `fct_orders.customer_order_number = 1` |
| Repeat Buyer | Customer with more than one non-cancelled order, lifetime | `dim_customer.is_repeat_buyer` |
| Cohort | Month of a customer's first non-cancelled order | `dim_customer.cohort_month` |
| Retention Rate (month N) | Share of a cohort that places an order N months after the cohort month | `agg_cohort_retention` |
| RFM Segment | Quintile scores for recency, frequency, monetary → rule-based segment | `customer_rfm` |
| Session Conversion Rate | Sessions with a purchase event / all sessions | `agg_funnel` |
| Cart Abandonment | Sessions with a cart event but no purchase / sessions with a cart event | `agg_funnel` |
| ABC Class | A = products making up the first 80% of revenue, B = next 15%, C = last 5% | `agg_product_performance` |
| Lift (category pair) | P(A and B) / (P(A) × P(B)); > 1 means bought together more than chance | `agg_category_affinity` |
| Return Rate | Returned items / non-cancelled items | measure |
| Days to Deliver | Order timestamp → delivered timestamp, in days | `fct_orders.days_to_deliver` |
| Churned (model label) | No non-cancelled order in the 90 days after the snapshot date | `retailpulse_ml.churn_training` |
