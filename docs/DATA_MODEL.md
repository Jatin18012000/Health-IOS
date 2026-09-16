# Data model

The schema is defined twice — in `tools/reference_pipeline.py` (executable
specification, proven against a real 664,515-record export) and in
`AURAStore` (the shipping Swift implementation). They must produce equivalent
output; the reference pipeline exists so that can be checked by diffing.

## Tables

### Lookups: `metrics`, `sources`, `devices`

The `device` attribute in an Apple export is a ~180-byte descriptor string
repeated on every single sample. Interning it, alongside source and metric
names, is the difference between a **340 MB** database and a **34 MB** one on
identical data — measured, not estimated. Timestamps are stored as unix seconds
(8 bytes) rather than ISO strings (25 bytes); formatting is a view concern.

### `samples`

Every normalized reading. 664,515 rows on the reference export. Kept for
drill-down and for re-aggregation when an aggregation rule changes — never read
to build a dashboard card.

### `daily_metrics`

One row per (day, metric): 14,597 rows. **This is what the dashboard reads.**
Carries `value`, optional `min`/`max`, `sample_count`, and `source_count`.

`source_count > 1` means the value went through deduplication and is not a naive
sum. Keeping that visible in the row is deliberate: it is the difference between
a figure you can trust and one you can't, and it should be inspectable rather
than buried in the import log.

### `sleep_nights`

One row per night: 819 rows. Built by unioning overlapping `SleepAnalysis`
intervals and attributing a session to the night it *ends* (anything ending
before 18:00 rolls back a day).

`staged` distinguishes the two eras in the data — 53 nights with real Core/Deep/
REM staging versus 766 with in-bed intervals only. These are not comparable
quantities. Anything that charts them on one axis without saying which is which
is showing a hardware upgrade and calling it a trend.

### `ingest_issues`

Unmapped types, unit mismatches, unparseable records — counted and surfaced, not
swallowed. An import that silently drops 3% of your data is worse than one that
fails.

## Aggregation rules

Each metric declares how its samples collapse to a day (`Aggregation`):

| Rule | Used for | Note |
|---|---|---|
| `sum` | steps, distance, energy, exercise minutes | **requires dedup first** |
| `mean` | HRV, resting HR, walking speed | |
| `minMax` | heart rate | mean kept, plus the day's range |
| `last` | body mass, height, VO2 Max | most recent wins |
| `count` | stand hours, exposure events | qualifying samples |
| `interval` | sleep | intervals unioned, not numbers added |

Adding a metric is one line in `MetricCatalog`. Nothing else needs to know.

## Idempotent import

Every Apple Health export contains **all** history, so the second import is
~99% records already stored. That is the normal case, not an error. Re-importing
must be a cheap no-op and must never create a duplicate row, a double-counted
day, or a corrupted rollup. Rollups are rebuilt only for the affected day range.

Two levels, because there are two kinds of duplicate:

**Within one file** — the reference export contains 118 byte-identical records.
These are filtered on identity before rollup, so the stored sample count and the
rollups always describe the same set.

**Across imports** — enforced by an existence probe at insert time, not by a
unique index. That choice was measured rather than assumed: a `UNIQUE` index
over the identity columns cost **21.9 MB on the reference dataset — as much as
the samples table itself (21.7 MB)**, to enforce something the existing
`(metric_id, start_at)` index can already check. The probe narrows through that
index to a handful of rows before comparing the rest, so idempotency costs an
indexed lookup per candidate row during import and **nothing at all in stored
bytes**.

One subtlety the Swift port must preserve: the comparison uses `IS`, not `=`,
on `value` and `category`. Both are nullable, and `=` never matches `NULL` —
with `=`, every category sample (all sleep, all stand hours) would re-insert on
every import.

`tools/conformance.py` asserts this by importing the fixture twice and checking
that every table is unchanged.

## Measured performance

On the reference dataset (1,450 days, 664,515 samples, 34 MB):

| Query | Time |
|---|---|
| 4-year monthly step trend | 6.3 ms |
| Full-history yearly summary | 7.2 ms |
| Last 30 days, resting HR + HRV | 0.3 ms |
| Sleep averages over staged nights | 0.4 ms |
| One day of raw heart rate (706 samples) | 0.4 ms |

There is no performance problem to solve here, which is worth stating plainly so
that effort goes to the character and the AI instead.
