# tools

## `reference_pipeline.py`

The executable specification for ingestion. Not the shipping implementation —
that's Swift, in `Sources/AURAIngest` and `Sources/AURAStore` — but the thing
those must agree with.

Its purpose is to make the data model falsifiable before any Swift is compiled.
Running it against a real export proved out several things that would otherwise
have been discovered late and expensively:

- the multi-source double-counting problem, and that it affects 471 day/metric
  combinations with up to 1.9x inflation
- that `count/min` means beats per minute for one metric and breaths per minute
  for another, so unit aliasing must be per-metric
- that a naive schema produced a database **larger than the source XML**
  (337 MB), and that interning device descriptors and storing integer
  timestamps brings it to 34 MB

```bash
python3 tools/reference_pipeline.py <apple_health_export dir> --out aura.sqlite
```

No dependencies beyond the Python standard library.

When `AURAStore` lands (M1), the acceptance test is a row-for-row diff between
this script's output and the Swift store's output on the same export.
