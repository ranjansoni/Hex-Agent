# Fix: InvoiceReminderLog table missing on server

When `npx prisma migrate deploy` says "No pending migrations" but the `InvoiceReminderLog` table does not exist, Prisma has already recorded that migration as applied (or the migration never ran). Use this runbook on the **Hex Billing server** (`billing-test.hex.inc`, in `~/billing-test.hex.inc/web` or your Hex Billing app directory).

## 1. Confirm the table is missing

```bash
# From Hex Billing app directory
cd ~/billing-test.hex.inc/web   # or your path

# Connect to MySQL (use your .env DATABASE_URL or RDS credentials)
mysql -h bennett-websites.cpwtalwthzlk.us-east-1.rds.amazonaws.com -u YOUR_USER -p hex_billing -e "SHOW TABLES LIKE 'InvoiceReminderLog';"
# Expected: empty result = table does not exist
```

## 2. Check whether Prisma thinks the migration was applied

```sql
SELECT migration_name, finished_at, rolled_back_at
FROM _prisma_migrations
WHERE migration_name LIKE '%invoice_reminder%';
```

- If you see `20260212000000_add_invoice_reminder_log` with a `finished_at` and no `rolled_back_at`: Prisma marked it applied; the table was never created or was dropped. Go to step 3.
- If you see no row: this migration is not recorded. After creating the table (step 3), run step 4 to mark it applied.

## 3. Create the table by running the migration SQL

The migration file is in your Hex Billing repo. **Run its contents** against the DB.

```bash
# On the server, print the migration SQL
cat prisma/migrations/20260212000000_add_invoice_reminder_log/migration.sql
```

Copy that SQL, then run it against `hex_billing` (same way you connect in step 1), for example:

```bash
mysql -h bennett-websites.cpwtalwthzlk.us-east-1.rds.amazonaws.com -u YOUR_USER -p hex_billing < prisma/migrations/20260212000000_add_invoice_reminder_log/migration.sql
# Or paste the SQL into your MySQL client.
```

Or from a MySQL client:

```sql
-- Paste the contents of migration.sql here and execute.
```

## 4. If the migration was NOT in _prisma_migrations (step 2 was empty)

So Prisma didn’t record it. After creating the table in step 3, tell Prisma the migration is already applied so it won’t try to run it again:

```bash
npx prisma migrate resolve --applied "20260212000000_add_invoice_reminder_log"
```

## 5. Verify

```bash
# Table exists
mysql ... -e "SHOW CREATE TABLE InvoiceReminderLog\G"

# Prisma still reports no pending migrations
npx prisma migrate deploy
```

After this, the `InvoiceReminderLog` table exists and Prisma’s migration history matches the database.
