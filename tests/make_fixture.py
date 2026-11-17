"""
Small synthetic fixture with the SAME schema as
bigquery-public-data.thelook_ecommerce, used only to test the SQL locally
(DuckDB) and in CI. The real project runs on the real public dataset.
"""
import os
import random
from datetime import datetime, timedelta, timezone

import numpy as np
import pandas as pd

rng = np.random.default_rng(7)
random.seed(7)
NOW = datetime.now(timezone.utc).replace(tzinfo=None)
START = datetime(2022, 1, 1)
CATS = ["Jeans", "Tops & Tees", "Sweaters", "Outerwear & Coats", "Active", "Swim",
        "Accessories", "Shorts", "Socks", "Dresses"]
SOURCES_EV = ["Email", "Adwords", "Organic", "YouTube", "Facebook"]
SOURCES_US = ["Search", "Organic", "Facebook", "Email", "Display"]
STATUSES = ["Complete", "Shipped", "Processing", "Cancelled", "Returned"]


def ts(a, b):
    return a + timedelta(seconds=int(rng.integers(0, int((b - a).total_seconds()))))


def make_tables():
    """Return {table_name: DataFrame} with the thelook_ecommerce schema."""
    dcs = pd.DataFrame({"id": range(1, 11), "name": [f"DC {i}" for i in range(1, 11)],
                        "latitude": rng.uniform(25, 48, 10), "longitude": rng.uniform(-122, -71, 10)})
    n_p = 300
    cost = rng.uniform(3, 80, n_p).round(2)
    products = pd.DataFrame({
        "id": range(1, n_p + 1), "cost": cost,
        "category": rng.choice(CATS, n_p), "name": [f"Product {i}" for i in range(1, n_p + 1)],
        "brand": rng.choice(["Acme", "Bolt", "Cove", "Dune", "Echo"], n_p),
        "retail_price": (cost * rng.uniform(1.6, 2.6, n_p)).round(2),
        "department": rng.choice(["Men", "Women"], n_p),
        "sku": [f"SKU{i:05d}" for i in range(n_p)],
        "distribution_center_id": rng.integers(1, 11, n_p)})
    n_u = 3000
    users = pd.DataFrame({
        "id": range(1, n_u + 1),
        "first_name": "x", "last_name": "y", "email": "z",
        "age": rng.integers(12, 70, n_u), "gender": rng.choice(["M", "F"], n_u),
        "state": rng.choice(["California", "Texas", "New York", "Arizona"], n_u),
        "street_address": "a", "postal_code": "00000",
        "city": rng.choice(["LA", "Austin", "NYC", "Phoenix"], n_u),
        "country": rng.choice(["United States", "Brasil", "China", "Germany"], n_u),
        "latitude": 0.0, "longitude": 0.0,
        "traffic_source": rng.choice(SOURCES_US, n_u),
        "created_at": [ts(START, NOW) for _ in range(n_u)]})
    users.loc[users.sample(5, random_state=1).index, "created_at"] = NOW + timedelta(days=2)  # future rows

    orders, items, events = [], [], []
    oid = iid = eid = sid = 0
    for u in users.itertuples():
        if u.created_at > NOW:
            continue
        for _ in range(int(rng.poisson(1.2))):
            oid += 1
            created = ts(u.created_at, NOW)
            status = random.choices(STATUSES, [0.25, 0.3, 0.2, 0.15, 0.1])[0]
            shipped = created + timedelta(hours=float(rng.uniform(2, 72))) if status in ("Complete", "Shipped", "Returned") else None
            delivered = shipped + timedelta(hours=float(rng.uniform(24, 160))) if shipped and status != "Shipped" else None
            returned = delivered + timedelta(days=float(rng.uniform(1, 10))) if status == "Returned" and delivered else None
            n_items = int(rng.integers(1, 4))
            orders.append(dict(order_id=oid, user_id=u.id, status=status, gender=u.gender, created_at=created,
                               returned_at=returned, shipped_at=shipped, delivered_at=delivered, num_of_item=n_items))
            for _ in range(n_items):
                iid += 1
                p = products.iloc[int(rng.integers(0, n_p))]
                items.append(dict(id=iid, order_id=oid, user_id=u.id, product_id=int(p.id), inventory_item_id=iid,
                                  status=status, created_at=created, shipped_at=shipped, delivered_at=delivered,
                                  returned_at=returned, sale_price=round(float(p.retail_price * rng.uniform(0.85, 1.0)), 2)))
            # purchase session
            sid += 1
            src = random.choice(SOURCES_EV)
            path = ["home", "department", "product", "cart", "purchase"] + (["cancel"] if status == "Cancelled" else [])
            for seq, et in enumerate(path, 1):
                eid += 1
                events.append(dict(id=eid, user_id=u.id, sequence_number=seq, session_id=f"s{sid}",
                                   created_at=created - timedelta(minutes=len(path) - seq), ip_address="0", city=u.city,
                                   state=u.state, postal_code="0", browser=random.choice(["Chrome", "Safari", "Firefox"]),
                                   traffic_source=src, uri="/", event_type=et))
    for _ in range(9000):  # browse-only sessions, many anonymous
        sid += 1
        start = ts(START, NOW)
        depth = random.choice([1, 2, 3, 4])
        path = ["home", "department", "product", "cart"][:depth]
        uid = random.choice([None, None, int(rng.integers(1, n_u + 1))])
        src = random.choice(SOURCES_EV)
        for seq, et in enumerate(path, 1):
            eid += 1
            events.append(dict(id=eid, user_id=uid, sequence_number=seq, session_id=f"s{sid}",
                               created_at=start + timedelta(minutes=seq), ip_address="0", city="c", state="s",
                               postal_code="0", browser="Chrome", traffic_source=src, uri="/", event_type=et))
    # Like the real dataset, item rows don't always match their parent order exactly:
    # some item timestamps differ and some item statuses differ from the order status.
    oi = pd.DataFrame(items)
    idx = oi.sample(frac=0.08, random_state=3).index
    oi.loc[idx, "created_at"] = pd.to_datetime(oi.loc[idx, "created_at"]) + pd.Timedelta(days=3)
    idx2 = oi[oi.status == "Cancelled"].sample(frac=0.3, random_state=4).index
    oi.loc[idx2, "status"] = "Complete"
    items = oi
    tables = {"distribution_centers": dcs, "products": products, "users": users,
              "orders": pd.DataFrame(orders), "order_items": pd.DataFrame(items), "events": pd.DataFrame(events)}
    return tables


if __name__ == "__main__":
    for name, df in make_tables().items():
        print(f"  {name:22s} {len(df):>7,}")