# SQL RecycleBin

🌐 **Live site:** [sqlrecyclebin.com](https://sqlrecyclebin.com) — pricing, licensing, and a live demo of the accident → recovery flow.

**A recycle bin for SQL Server.** Every `DELETE` and `UPDATE` on your protected tables is captured automatically. Query back what was lost. Undo it with one command.

```sql
EXEC rb.Enable @Table = 'dbo.Orders';       -- enable once

-- ... someone runs DELETE without a WHERE ...

EXEC rb.Deleted  @Table = 'dbo.Orders';     -- see the lost rows, as real columns
EXEC rb.UndoLast @Table = 'dbo.Orders';     -- put them back. Done.
```

No backups required. No log-reader tools. No downtime. Works on every edition from **SQL Server 2017+, including Express**.

## Why

Oracle has Flashback Query. SQL Server has... a $2,000 log-reader tool and a prayer that your backup chain is intact. When someone runs an accidental `DELETE`/`UPDATE` on a live database, the recovery options are a point-in-time restore (slow, loses newer transactions unless you merge manually) or commercial transaction-log forensics. SQL RecycleBin closes that gap: enable once per table, and destructive changes become instantly reversible.

## How it works

- `rb.Enable` generates a lightweight `AFTER UPDATE, DELETE` trigger for the table.
- Changed rows are captured **as JSON** into a compressed internal store (`rb.ChangeLog`) — JSON capture means `ALTER TABLE` never breaks your safety net.
- Retrieval procs (`rb.Deleted`, `rb.Updated`) project the JSON back into real typed columns via `OPENJSON`, using the table's *current* schema.
- `rb.UndoLast` / `rb.UndoTransaction` / `rb.Restore` re-insert deleted rows (handling `IDENTITY_INSERT`, skipping PK collisions) and revert updates to their before-values.
- Everything is persistent — it survives restarts and failovers, unlike an in-memory cache.

## Install

Run [`install.sql`](install.sql) in the target database. Then run [`demo.sql`](demo.sql) in a scratch database to see the full accident → recovery loop.

## API

| Command | What it does |
|---|---|
| `EXEC rb.Enable @Table` | Start capturing DELETE/UPDATE on a table (requires a primary key) |
| `EXEC rb.Disable @Table` | Stop capturing |
| `EXEC rb.Deleted @Table, @Top, @Since` | Show recently deleted rows as typed columns |
| `EXEC rb.Updated @Table, @Top, @Since` | Show recent updates with before/after values |
| `EXEC rb.UndoLast @Table` | Undo the most recent captured transaction on the table |
| `EXEC rb.UndoTransaction @Table, @TxId` | Undo a specific transaction |
| `EXEC rb.Restore @Table, @Since` | Roll the table's captured changes back to a point in time |
| `EXEC rb.BypassOn / rb.BypassOff` | Skip capture for this session (ETL, bulk maintenance) |
| `EXEC rb.Cleanup @KeepDays` | Purge history beyond retention (default 14 days, `rb.Config`) |
| `EXEC rb.Status` | Enabled tables, captured counts, store size |

## Honest limitations (v1)

- **`TRUNCATE TABLE`, `DROP TABLE`, and minimally-logged bulk operations do not fire triggers** — they are not captured. Keep backups; this is a safety net, not a replacement for them.
- Tables **must have a primary key**.
- Updating a primary key value itself breaks before/after pairing for that row (before-image is still captured).
- Trigger capture adds write overhead — measure on your workload; exclude ultra-hot tables or use `rb.BypassOn` around bulk jobs.
- Large `NVARCHAR(MAX)`/`VARBINARY(MAX)` columns inflate the history store; set retention accordingly.
- Restoring is subject to your foreign keys — restore parents before children.

## Roadmap (Pro)

- CDC-based capture engine — zero overhead on the write path, no triggers
- Web dashboard (Blazor): browse changes, diff viewer, one-click restore with preview
- App-level user identity (`SESSION_CONTEXT`) for who-did-what forensics behind connection pools
- Central multi-database monitoring, alerts on mass deletes, RBAC on restore
- TRUNCATE protection

## License

SQL RecycleBin is **source-available** under the [PolyForm Noncommercial License 1.0.0](LICENSE.md) — the **full version, free** for personal, educational, and noncommercial use.

**Commercial use requires a license.** For commercial licensing, priority support, and the Pro roadmap, contact **qaiser@92logics.com** — [92 Logics](https://www.92logics.com).

This is not an OSI-approved open source license; it is a fair-code model that keeps the project sustainable while giving everyone the complete product.

## Contributing

Contributions welcome — bug reports, edge cases, and PRs. All contributors sign a lightweight CLA (so the project retains the ability to offer commercial licenses). By opening a PR you agree to the CLA presented by the CLA bot.
