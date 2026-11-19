#!/usr/bin/env python3
"""Run OrderFlow FOCUS 1.2 FinOps SQL analytics via SQLite stdlib."""

from __future__ import annotations

import csv
import sqlite3
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
CSV_PATH = BASE_DIR / "02-orderflow-focus12-sample.csv"
SQL_PATH = BASE_DIR / "03-focus12-unit-economics.sql"

NUMERIC_FLOAT_COLS = {
    "ConsumedQuantity",
    "ListCost",
    "EffectiveCost",
    "BilledCost",
}
NUMERIC_INT_COLS = {"x_OrderCount"}

CREATE_TABLE_SQL = """
CREATE TABLE focus_1_2 (
  BillingPeriodStart TEXT NOT NULL,
  InvoiceId TEXT NOT NULL,
  SubAccountId TEXT NOT NULL,
  SubAccountName TEXT NOT NULL,
  RegionId TEXT NOT NULL,
  ServiceName TEXT NOT NULL,
  ChargeCategory TEXT NOT NULL,
  PricingCategory TEXT NOT NULL,
  ResourceId TEXT NOT NULL,
  ConsumedQuantity REAL NOT NULL,
  ConsumedUnit TEXT NOT NULL,
  ListCost REAL NOT NULL,
  EffectiveCost REAL NOT NULL,
  BilledCost REAL NOT NULL,
  CapacityReservationStatus TEXT,
  x_Environment TEXT NOT NULL,
  x_Workload TEXT NOT NULL,
  x_OrderCount INTEGER NOT NULL
);
"""


def load_focus_csv(conn: sqlite3.Connection, csv_path: Path) -> int:
    """Create focus_1_2 table in memory and load FOCUS 1.2 CSV rows."""
    conn.execute(CREATE_TABLE_SQL)
    with csv_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        columns = reader.fieldnames or []
        placeholders = ", ".join(["?"] * len(columns))
        insert_sql = (
            f"INSERT INTO focus_1_2 ({', '.join(columns)}) "
            f"VALUES ({placeholders})"
        )
        rows = []
        for raw in reader:
            row = []
            for col in columns:
                val = raw[col].strip()
                if col in NUMERIC_FLOAT_COLS:
                    row.append(float(val))
                elif col in NUMERIC_INT_COLS:
                    row.append(int(val))
                else:
                    row.append(val)
            rows.append(tuple(row))
    conn.executemany(insert_sql, rows)
    conn.commit()
    return len(rows)


def parse_sql_queries(sql_path: Path) -> list[tuple[str, str]]:
    """Split SQL file into (title, statement) tuples."""
    content = sql_path.read_text(encoding="utf-8")
    parsed: list[tuple[str, str]] = []
    for chunk in content.split(";"):
        lines = [ln for ln in chunk.strip().splitlines() if ln.strip()]
        sql_lines = [
            ln for ln in lines if not ln.lstrip().startswith("--")
        ]
        if not sql_lines:
            continue
        comments = [
            ln.lstrip("- ").strip()
            for ln in lines
            if ln.lstrip().startswith("--")
        ]
        title = comments[-1] if comments else "FinOps Query"
        parsed.append((title, "\n".join(sql_lines)))
    return parsed


def format_cell(value: object, col_name: str) -> str:
    """Format scalar values cleanly for ASCII table display."""
    if value is None:
        return ""
    if isinstance(value, float):
        if col_name in {
            "cost_per_1k_orders_usd",
            "effective_rate_per_hr",
        }:
            return f"{value:,.4f}"
        if col_name.endswith("_usd"):
            return f"{value:,.2f}"
        if value.is_integer():
            return f"{int(value):,}"
        return f"{value:,.2f}"
    if isinstance(value, int):
        return f"{value:,}"
    return str(value)


def print_ascii_table(headers: list[str], rows: list[tuple]) -> None:
    """Render query output as a crisp, zero-dependency ASCII table."""
    str_rows = [
        [format_cell(cell, headers[idx]) for idx, cell in enumerate(row)]
        for row in rows
    ]
    numeric_cols = [
        all(
            isinstance(r[idx], (int, float))
            for r in rows
            if r[idx] is not None
        )
        for idx in range(len(headers))
    ]
    widths = [
        max([len(headers[i])] + [len(r[i]) for r in str_rows])
        for i in range(len(headers))
    ]
    border = "+-" + "-+-".join("-" * w for w in widths) + "-+"
    header_cells = [
        headers[i].ljust(widths[i]) for i in range(len(headers))
    ]
    print(border)
    print("| " + " | ".join(header_cells) + " |")
    print(border)
    for row in str_rows:
        cells = []
        for i, cell in enumerate(row):
            justified = (
                cell.rjust(widths[i])
                if numeric_cols[i]
                else cell.ljust(widths[i])
            )
            cells.append(justified)
        print("| " + " | ".join(cells) + " |")
    print(border)


def main() -> None:
    """Load FOCUS 1.2 sample CSV into SQLite and run all queries."""
    conn = sqlite3.connect(":memory:")
    try:
        row_count = load_focus_csv(conn, CSV_PATH)
        print(f"Loaded {row_count} FOCUS 1.2 rows from {CSV_PATH.name}")
        queries = parse_sql_queries(SQL_PATH)
        for idx, (title, sql) in enumerate(queries, start=1):
            print(f"\n=== Query {idx}: {title} ===")
            cursor = conn.execute(sql)
            headers = [desc[0] for desc in cursor.description]
            rows = cursor.fetchall()
            print_ascii_table(headers, rows)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
