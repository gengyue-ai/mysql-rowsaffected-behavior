---
name: mysql-rowsaffected-behavior
description: MySQL RowsAffected returns changed rows, not matched rows. Use when an UPDATE-then-INSERT upsert hits Error 1062.
---

## When to use

- Go `database/sql`: `Result.RowsAffected()` used to decide whether an `UPDATE` "worked"
- Upsert code shaped as `UPDATE ...; if affected == 0 { INSERT ... }`
- Any logic that treats `RowsAffected() == 0` as "the row does not exist"

## Symptom

```go
res, _ := db.Exec("UPDATE sites SET site_domain=? WHERE account_id=?", domain, accountID)
if n, _ := res.RowsAffected(); n == 0 {
    db.Exec("INSERT INTO sites (account_id, site_domain) VALUES (?,?)", accountID, domain)
    // Error 1062: Duplicate entry ... for key 'uk_account_id'
}
```

## Root cause

`RowsAffected()` returns rows **actually changed**. Writing the same value again changes
nothing, so MySQL reports `0` even though the row matched.

MySQL C API docs, `mysql_affected_rows()`: "For UPDATE statements, the affected-rows value
by default is the number of rows actually changed. If CLIENT_FOUND_ROWS flag is specified,
the affected-rows value is the number of rows matched by the WHERE clause."

## Fixes

1. `SELECT COUNT(*)` first, then `UPDATE` — when you must distinguish "missing" from "unchanged".
2. `INSERT ... ON DUPLICATE KEY UPDATE` — pure upsert; requires the unique key.
3. Add `updated_at = NOW()` to `SET` — if "touched" semantics are acceptable.
4. DSN `clientFoundRows=true` — whole-service semantics change; audit every `RowsAffected()` before using.

## Checklist

- [ ] Is `affected == 0` being read as "row missing"?
- [ ] Does the target table have a unique index (what the 1062 is really telling you)?
- [ ] Is "value did not change" a normal case in this flow (double submit, idempotent replay)?
- [ ] If switching to `clientFoundRows`, have all other call sites been reviewed?
