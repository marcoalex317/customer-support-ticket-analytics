# Data

The raw dataset is **not committed** to this repository. It is a synthetic
customer support ticket dataset of 100,000 rows covering January 2022 to
December 2025.

## Expected location

```
data/raw/support_tickets.csv
```

## Expected schema

The loader in `sql/01_load_and_verify.sql` reads these columns:

| Column | Type after casting | Notes |
|---|---|---|
| `ticket_id` | text | unique across all 100,000 rows |
| `created_at` | timestamp | stored as ISO 8601, not dd/mm/yyyy |
| `status` | text | resolved, closed_no_action, in_progress, on_hold, open |
| `priority` | text | urgent, high, medium, low |
| `sla_plan` | text | platinum, gold, standard |
| `issue_type` | text | 8 values |
| `product_area` | text | 7 values |
| `channel` | text | 5 values |
| `platform` | text | 5 values |
| `region` | text | 5 values |
| `customer_segment` | text | 5 values |
| `customer_id` | text | |
| `resolution_time_hours` | numeric | NULL for the three unresolved statuses |
| `csat_score` | integer | 0 means not rated, not a score of zero |
| `reopened` | integer | 0 or 1 |
| `has_attachment` | integer | 0 or 1 |
| `customer_sentiment` | text | |

## Loading note

Do not open the CSV in Excel before loading it. Under an Indonesian locale
Excel strips the decimal separator, which turns `23.5` hours into `235` hours
and silently inflates every duration by a factor of ten. Load the raw file into
the all-text staging table and cast from there.
