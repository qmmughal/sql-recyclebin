# SqlRecycleBin (PowerShell module)

PowerShell cmdlets for [SQL RecycleBin](https://github.com/qmmughal/sql-recyclebin) — a trigger-based recycle bin for SQL Server. Install it, capture `DELETE`/`UPDATE` on a table, and undo accidents with one command, from the pipeline instead of SSMS.

```powershell
Install-Module SqlRecycleBin

Install-SqlRecycleBin -ServerInstance 'localhost' -Database 'Sales'
Enable-SqlRecycleBinCapture -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders'

# ...someone runs a bad DELETE...

Get-SqlRecycleBinDeletedRow -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders'
Restore-SqlRecycleBinLast   -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders'
```

## Requirements

- PowerShell 5.1+ (Windows PowerShell or PowerShell 7+)
- The [`SqlServer`](https://www.powershellgallery.com/packages/SqlServer) module (for `Invoke-Sqlcmd`) — installed automatically as a dependency when you `Install-Module SqlRecycleBin`
- SQL Server 2017+, any edition including Express

## Cmdlets

| Cmdlet | Wraps | What it does |
|---|---|---|
| `Install-SqlRecycleBin` | `install.sql` | Installs the `rb` schema on a database. Idempotent — safe to re-run. |
| `Uninstall-SqlRecycleBin` | `uninstall.sql` | Removes SQL RecycleBin. **Permanently deletes captured history.** Requires confirmation or `-Force`. |
| `Enable-SqlRecycleBinCapture` | `rb.Enable` | Starts capturing DELETE/UPDATE on a table (requires a primary key). |
| `Disable-SqlRecycleBinCapture` | `rb.Disable` | Stops capturing on a table. |
| `Get-SqlRecycleBinDeletedRow` | `rb.Deleted` | Returns recently deleted rows as typed objects. |
| `Get-SqlRecycleBinUpdatedRow` | `rb.Updated` | Returns recent updates with before/after JSON. |
| `Restore-SqlRecycleBinLast` | `rb.UndoLast` | Undoes the most recent captured transaction on a table. |
| `Restore-SqlRecycleBinTransaction` | `rb.UndoTransaction` | Undoes a specific transaction by `TxId`. |
| `Restore-SqlRecycleBinPointInTime` | `rb.Restore` | Undoes every captured change since a given time. |
| `Invoke-SqlRecycleBinBypass` | `rb.BypassOn`/`rb.BypassOff` | Runs a query or script with capture bypassed, in a single session (see note below). |
| `Clear-SqlRecycleBinHistory` | `rb.Cleanup` | Purges history beyond a retention window. Permanent. |
| `Get-SqlRecycleBinStatus` | `rb.Status` | Enabled tables, capture counts, and change-log store size. |
| `Invoke-SqlRecycleBinDemo` | `demo.sql` | Runs the accident → recovery smoke test against a scratch database. |

## Why `Invoke-SqlRecycleBinBypass` exists as its own cmdlet

`rb.BypassOn`/`rb.BypassOff` toggle a `SESSION_CONTEXT` flag scoped to a single connection. `Invoke-Sqlcmd` opens a new connection per call, so calling a hypothetical `Enable-Bypass` cmdlet and then a separate cmdlet for your bulk job would **not** share a session — the bypass would silently do nothing. `Invoke-SqlRecycleBinBypass` wraps `BypassOn`, your query (or `-InputFile` script), and `BypassOff` into one batch on one connection, so it actually works.

## Known limitations

Same as the underlying product — see the [main README](https://github.com/qmmughal/sql-recyclebin#honest-limitations-v1). In addition, specific to this module:

- Every cmdlet builds its `EXEC rb.*` call by escaping string parameters (doubling embedded quotes) rather than using true ADO.NET parameter binding, because `Invoke-Sqlcmd` doesn't expose parameter binding for arbitrary values. This is basic literal-escaping, not a substitute for running with least-privilege SQL permissions.
- `Get-SqlRecycleBinStatus` issues `rb.Status`'s two underlying queries separately rather than calling the procedure directly — `Invoke-Sqlcmd`'s handling of a single call returning two differently-shaped result sets is inconsistent across versions, so this sidesteps it.

## License

Same as SQL RecycleBin itself: [PolyForm Noncommercial 1.0.0](LICENSE.md) — free for personal, educational, and noncommercial use. Commercial use requires a license from 92 Logics: **qaiser@92logics.com**.
