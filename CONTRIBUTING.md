# Contributing to SQL RecycleBin

Bug reports, edge cases, and PRs are welcome.

## Before you open a PR

This project is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md) rather than an OSI-approved open source license, so that 92 Logics can continue to offer a commercial license and fund development. To keep that option open, **all contributors must sign a lightweight Contributor License Agreement (CLA)**.

- The CLA is handled automatically by [cla-assistant](https://cla-assistant.io) when you open a pull request — you'll be prompted to sign electronically, once, the first time you contribute.
- By opening a PR you agree to the CLA presented by the CLA bot. PRs won't be merged until the CLA check passes.

## Reporting bugs / edge cases

Please include:
- SQL Server version and edition (`SELECT @@VERSION;`)
- The table schema involved (identity columns, computed columns, `rowversion`, LOBs, FKs, collation)
- Repro steps against `install.sql` + `demo.sql` where possible

## Development notes

- Keep `install.sql` fully idempotent (`CREATE OR ALTER`, `IF` existence checks) — it must be safe to re-run.
- Follow the existing `rb.*` schema and naming conventions.
- Known v1 limitations (`TRUNCATE`/`DROP`/bulk-load not captured, PK-value updates, FK order on restore) are tracked in the README — please don't silently work around them without discussion.
