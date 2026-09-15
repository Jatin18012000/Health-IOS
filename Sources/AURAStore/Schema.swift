import Foundation
import GRDB
import AURACore

/// The database schema, as migrations.
///
/// Mirrors `tools/reference_pipeline.py`'s `build_schema` exactly. The two are
/// one schema in two languages, and `tools/conformance.py` is what proves they
/// have not drifted: it asserts 81 hand-computed expectations against a fixture
/// that both must reproduce.
///
/// Migrations rather than a bare `CREATE TABLE` because the store outlives any
/// one version of the app, and a health database with four years in it is not
/// something to rebuild casually.
public enum Schema {

    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-core") { db in
            // ── Lookup tables ──────────────────────────────────────────────
            //
            // The `device` attribute in an Apple export is a ~180-byte
            // descriptor repeated on every single sample. Interning it,
            // alongside source and metric names, was measured at the difference
            // between a 340 MB database and a 34 MB one on identical data.
            try db.execute(sql: """
                CREATE TABLE metrics (
                    id         INTEGER PRIMARY KEY,
                    identifier TEXT NOT NULL UNIQUE,
                    domain     TEXT NOT NULL,
                    unit       TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE sources (
                    id       INTEGER PRIMARY KEY,
                    name     TEXT NOT NULL UNIQUE,
                    priority INTEGER NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE devices (
                    id         INTEGER PRIMARY KEY,
                    descriptor TEXT NOT NULL UNIQUE
                )
                """)

            // ── Samples ────────────────────────────────────────────────────
            //
            // Timestamps are unix seconds, not ISO strings: 8 bytes instead of
            // 25, and range scans compare integers. Formatting is a view
            // concern and happens at the view.
            try db.execute(sql: """
                CREATE TABLE samples (
                    id        INTEGER PRIMARY KEY,
                    metric_id INTEGER NOT NULL REFERENCES metrics(id),
                    source_id INTEGER NOT NULL REFERENCES sources(id),
                    device_id INTEGER          REFERENCES devices(id),
                    value     REAL,
                    category  TEXT,
                    start_at  INTEGER NOT NULL,
                    end_at    INTEGER NOT NULL
                )
                """)

            // This index does double duty: it serves every drill-down read, and
            // it is what the import's duplicate probe narrows through.
            //
            // There is deliberately NO unique index over the identity columns.
            // Measured on the reference export, one cost 21.9 MB -- as much as
            // the samples table itself -- to enforce something this index
            // already makes cheap. See `insert` in SQLiteHealthStore.
            try db.execute(sql:
                "CREATE INDEX idx_samples_metric_start ON samples (metric_id, start_at)")

            // ── Rollups ────────────────────────────────────────────────────
            try db.execute(sql: """
                CREATE TABLE daily_metrics (
                    day          TEXT NOT NULL,
                    identifier   TEXT NOT NULL,
                    domain       TEXT NOT NULL,
                    unit         TEXT NOT NULL,
                    value        REAL,
                    value_min    REAL,
                    value_max    REAL,
                    sample_count INTEGER NOT NULL,
                    source_count INTEGER NOT NULL,
                    method       TEXT NOT NULL,
                    PRIMARY KEY (day, identifier)
                )
                """)
            try db.execute(sql:
                "CREATE INDEX idx_daily_identifier ON daily_metrics (identifier, day)")

            try db.execute(sql: """
                CREATE TABLE sleep_nights (
                    night_of      TEXT PRIMARY KEY,
                    in_bed_start  INTEGER,
                    in_bed_end    INTEGER,
                    in_bed_min    REAL,
                    asleep_min    REAL,
                    core_min      REAL,
                    deep_min      REAL,
                    rem_min       REAL,
                    awake_min     REAL,
                    efficiency    REAL,
                    staged        INTEGER NOT NULL,
                    sources       TEXT
                )
                """)

            // Surfaced, never swallowed. An import that silently drops 3% of a
            // person's data is worse than one that fails loudly.
            try db.execute(sql: """
                CREATE TABLE ingest_issues (
                    id     INTEGER PRIMARY KEY,
                    kind   TEXT NOT NULL,
                    detail TEXT NOT NULL,
                    count  INTEGER NOT NULL,
                    seen_at INTEGER NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE meta (
                    key   TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
                """)
        }

        return migrator
    }

    /// Seed the metric registry from `MetricCatalog`.
    ///
    /// Run on every open, not just on first creation: adding a metric to the
    /// catalog is a one-line change and must not also require a migration.
    static func seedMetrics(_ db: Database) throws {
        for metric in MetricCatalog.all {
            try db.execute(sql: """
                INSERT INTO metrics (identifier, domain, unit) VALUES (?, ?, ?)
                ON CONFLICT(identifier) DO UPDATE SET domain = excluded.domain,
                                                      unit = excluded.unit
                """, arguments: [metric.id, metric.domain.rawValue, metric.unit.rawValue])
        }
    }
}
