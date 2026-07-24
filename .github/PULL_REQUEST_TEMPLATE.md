## What does this change?

## Testing

- [ ] Ran `install.sql` (idempotent — re-run without error)
- [ ] Ran `demo.sql` end-to-end (accident → `rb.Deleted`/`rb.Updated` → `rb.UndoLast` recovery)
- [ ] Tested against SQL Server version(s): 2017 / 2019 / 2022 / Express (circle or list which)

## Checklist

- [ ] Consistent with existing `rb.*` naming and code style
- [ ] `install.sql` changes remain idempotent (`CREATE OR ALTER`, `IF` checks)
- [ ] Edge cases considered (identity, computed columns, `rowversion`, LOBs, FKs, collation)
- [ ] I have signed the CLA (via the cla-assistant bot on this PR)
