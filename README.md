# Customer Support Ticket Analytics

I took a dataset of 100,000 customer support tickets from January 2022 to
December 2025 and tried to answer one question: why does this support team
have a backlog it never manages to clear?

I loaded the raw CSV into PostgreSQL, cleaned and analysed it with SQL, built a
star schema in Power BI and turned the results into a three-page dashboard.

My first guess was that the team was simply slow. It isn't. Tickets that
actually get resolved are closed in a median of 23.5 hours. The real problem is
that half of all tickets are never resolved, and the queue has grown by roughly
830 tickets a month for four years straight.

![Overview page of the dashboard](images/01-overview.png)

## What I found

- **Only half of the tickets get resolved.** 50,131 were resolved (50.1%),
  9,982 were closed without any action (10.0%) and 39,887 are still open
  (39.9%).
- **The backlog grows every month.** Around 2,080 tickets come in each month
  and only about 1,250 get closed. The open backlog went from 883 in January
  2022 to 39,931 by December 2025.
- **Most of the open queue is old.** 29,725 of the 39,887 unresolved tickets
  (74.5%) have been waiting for more than a year.
- **Priority is the only thing that affects speed.** Median hours to resolve:
  urgent 3.9, high 12.4, medium 25.7, low 40.4. Low priority tickets take about
  10 times longer than urgent ones. Issue type, channel, product area and
  customer segment make almost no difference.
- **A better SLA plan changes nothing.** Platinum, Gold and Standard customers
  all get a median of around 23.5 hours, with the same mix of priorities.
- **The "slow" tickets are actually abandoned ones.** No resolved ticket took
  longer than 72 hours. All 6,103 tickets above the 106.9-hour outlier fence
  were closed without action, with a median of 131.2 hours.

So if this team is judged on average resolution time, they look fine while the
queue keeps doubling. The numbers I think should be tracked instead are median
time per priority, abandonment rate, backlog age and backlog growth.

## Tools

PostgreSQL 17 with psql and pgAdmin 4 for loading and querying, SQL for all the
cleaning and analysis, Power BI Desktop for the data model, DAX measures and
dashboard, and Word for the written report.

## What's in this repo

```
customer-support-ticket-analytics/
├── README.md
├── .gitignore
├── data/
│   └── README.md                     # where the raw dataset comes from and its columns
├── sql/
│   ├── 01_load_and_verify.sql        # loads the raw CSV and runs data quality checks
│   ├── 02_build_star_schema.sql      # builds the dimensions and the fact table
│   └── 03_analysis_queries.sql       # one query for each business question
├── powerbi/
│   ├── ticket_analytics_powerbi.pbix # the dashboard
│   ├── measures_dax.txt              # every DAX measure, with formatting notes
│   └── midnight_gold_theme.json      # the report theme
├── outputs/                          # CSV results of the analysis queries
├── images/                           # dashboard screenshots
└── docs/
    ├── 01_project_charter.docx       # scope, goals and success metrics
    ├── 02_project_plan.docx          # phases, deliverables and timeline
    ├── 03_findings_report.docx       # full findings and recommendations
    └── 03_findings_report.pdf
```

## Data problems I had to fix

A few things went wrong before I could trust any of the numbers, so I wrote
them down.

- **The dates looked different in Excel.** `created_at` is stored as ISO 8601,
  but Excel shows it as dd/mm/yyyy. I first wrote a `TO_TIMESTAMP` format
  based on what Excel showed me and it failed on every row. Casting directly
  with `::TIMESTAMP` fixed it.
- **Excel removed the decimal points.** Opening the CSV with an Indonesian
  locale turned 23.5 hours into 235. After that I stopped touching the file in
  Excel and loaded the raw CSV into a text-only staging table instead.
- **I loaded the data twice by accident.** Running the load again without
  clearing the staging table gave me 200,000 rows. Now I truncate first and
  check the row count after every load.
- **Blank resolution times are not missing data.** 39,887 rows have no
  resolution time because those tickets were never closed. I left them as NULL
  and kept them out of every duration calculation instead of filling in zeros.
- **A CSAT score of 0 means "not rated".** About 30% of rows have
  `csat_score = 0`, spread evenly across every status. I treated those as
  unrated with `NULLIF(csat_score, 0)`.

The fix that mattered most was separating resolved tickets from tickets closed
without action. Averaging both groups together is what makes the team look
slow. Looked at separately, resolved tickets have a median of 23.5 hours and
abandoned ones 131.2 hours.

## How the model is built

It's a star schema with one fact table and six dimensions.

- `fact_ticket` has one row per ticket, plus columns I derived for close date,
  duration, ticket age, age group, duration group and an outlier flag.
- `dim_date` covers 2022-01-01 to 2026-01-31. It has a second, inactive
  relationship to the close date, which the "tickets closed" measure turns on
  with `USERELATIONSHIP`. That way created and closed tickets can share the
  same date axis.
- `dim_priority`, `dim_status` and `dim_sla` each have a sort column, so
  priorities go from urgent to low and statuses appear in a sensible order
  instead of alphabetically.
- `dim_issue` and `dim_product` round out the model.

Ticket age is the number of whole days between 30 December 2025, the last date
in the data, and the day the ticket was created. I always read age from the
`kelompok_umur` column rather than recalculating it, because using timestamps
instead of whole days moves some tickets into a different age group.

## The dashboard

There are three pages, and each one answers one question.

**Overview - what state is the queue in?**
Five KPIs (total tickets, resolution rate, median hours to resolve, closed
without action, still unresolved), how the backlog has grown over time, tickets
by status, and tickets created vs closed each month. This is the page shown at
the top.

**Resolution Drivers - what decides how fast a ticket gets closed?**
Median hours by priority, median hours by SLA plan split by priority, and a
100% stacked chart comparing resolved and abandoned tickets in 20-hour bands.
That last chart is the clearest one in the project: past 80 hours, nothing was
ever actually resolved.

![Resolution Drivers page](images/02-resolution-drivers.png)

**Backlog Health - how bad is the backlog, and is it getting worse?**
The backlog split by age, the age mix within each status, and CSAT over time. I
fixed the CSAT axis at 1 to 5 so small month-to-month movement doesn't look
like a trend.

![Backlog Health page](images/03-backlog-health.png)

## What I would recommend

1. Stop reporting average resolution time. Report median time per priority,
   abandonment rate, backlog age and backlog growth instead.
2. Always report resolved and closed-without-action tickets separately. Mixing
   them hides both problems.
3. Add a rule for tickets waiting on the customer: send reminders at 24 and 48
   hours, close the ticket automatically on day seven, and leave these tickets
   out of resolution time.
4. Run a one-off cleanup of the 29,725 tickets that are more than a year old,
   with clear closing rules so the backlog doesn't build up again.
5. Fix how priority is assigned. Right now it has nothing to do with the issue
   type or the SLA plan the customer pays for, even though it's the only thing
   that changes how fast a ticket gets handled.

## Limitations

- The dataset is synthetic. Ticket volume is almost perfectly even across
  region, platform, channel, product area and customer segment, and priority is
  the only column with a real pattern. This project shows the method, not the
  behaviour of a real company.
- There's no timestamp for the first reply, so I couldn't measure first
  response time.
- There are no SLA targets per plan, so I couldn't count SLA breaches. I could
  only compare the plans against each other.
- There's no agent or cost data, so productivity and cost were out of scope.
- About 30% of tickets have no CSAT rating, so the averages only include rated
  tickets.

## About me

Marco Alexander, Information Systems student at BINUS University
[linkedin.com/in/marcolex](https://linkedin.com/in/marcolex)
