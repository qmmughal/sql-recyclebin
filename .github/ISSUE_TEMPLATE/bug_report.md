---
name: Bug report
about: Something in rb.Enable / rb.Deleted / rb.UndoLast / rb.Restore isn't behaving
title: "[BUG] "
labels: bug
assignees: ''
---

**SQL Server version/edition**
Output of `SELECT @@VERSION;`

**Table schema involved**
DDL for the affected table (identity? computed columns? `rowversion`? LOB columns? FKs? collation?)

**What you ran**
The `rb.*` calls, in order (e.g. `rb.Enable`, then the DML, then `rb.UndoLast`).

**Expected behavior**


**Actual behavior**


**Anything else**
e.g. is this one of the known v1 limits (TRUNCATE/DROP/bulk-load, PK-value updates, FK order on restore)?
