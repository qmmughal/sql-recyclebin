/* =============================================================================
   SQL RecycleBin — demo & smoke test
   Run in a scratch database AFTER install.sql. Safe: uses its own demo table.
   ============================================================================= */

SET NOCOUNT ON;

/* 1. Demo table */
DROP TABLE IF EXISTS dbo.rbDemo_Orders;
CREATE TABLE dbo.rbDemo_Orders
(
    OrderId    INT IDENTITY(1,1) PRIMARY KEY,
    Customer   NVARCHAR(100) NOT NULL,
    Amount     DECIMAL(12,2) NOT NULL,
    Status     NVARCHAR(20)  NOT NULL DEFAULT N'New',
    CreatedAt  DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);

INSERT dbo.rbDemo_Orders (Customer, Amount, Status)
VALUES (N'Moore Belgium', 12500.00, N'Paid'),
       (N'BlueberryCMS',   3400.50, N'New'),
       (N'Namfus',         990.00,  N'Paid'),
       (N'Merit Wealth',   7600.25, N'Shipped');

/* 2. Enable capture */
EXEC rb.Enable @Table = N'dbo.rbDemo_Orders';

/* 3. THE ACCIDENT: delete without a proper WHERE, then a bad mass update */
DELETE dbo.rbDemo_Orders WHERE Status = N'Paid';        -- oops, 2 rows gone
UPDATE dbo.rbDemo_Orders SET Amount = 0;                -- oops, zeroed the rest

SELECT [After the accident] = 1, * FROM dbo.rbDemo_Orders;

/* 4. What just got destroyed? */
EXEC rb.Deleted @Table = N'dbo.rbDemo_Orders';          -- deleted rows, as real columns
EXEC rb.Updated @Table = N'dbo.rbDemo_Orders';          -- before/after JSON per row

/* 5. Undo, newest first: first the bad UPDATE, then the bad DELETE */
EXEC rb.UndoLast @Table = N'dbo.rbDemo_Orders';         -- reverts the zeroed amounts
EXEC rb.UndoLast @Table = N'dbo.rbDemo_Orders';         -- re-inserts the deleted rows

SELECT [After recovery] = 1, * FROM dbo.rbDemo_Orders;

/* Alternative to the two UndoLast calls above:
   EXEC rb.Restore @Table = N'dbo.rbDemo_Orders', @Since = '2026-01-01';  */

/* 6. Housekeeping views */
EXEC rb.Status;

/* 7. Tidy up the demo */
-- EXEC rb.Disable @Table = N'dbo.rbDemo_Orders';
-- DROP TABLE dbo.rbDemo_Orders;
