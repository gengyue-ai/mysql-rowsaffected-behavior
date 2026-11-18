# MySQL `RowsAffected()` is not "matched rows"

A one-page field note: `UPDATE` returns **rows actually changed**, not rows matched by `WHERE`. Any code shaped like `if affected == 0 { INSERT }` is a duplicate-key bomb.

## The trap

```go
res, _ := db.Exec("UPDATE sites SET site_domain = ? WHERE account_id = ?", domain, accountID)
affected, _ := res.RowsAffected()
if affected == 0 {
    // "row doesn't exist" — wrong
    _, err := db.Exec("INSERT INTO sites (account_id, site_domain) VALUES (?, ?)", accountID, domain)
    // Error 1062 (23000): Duplicate entry '42' for key 'uk_account_id'
}
```

The row exists. The value simply did not change, so MySQL reports `affected = 0`.

## Why it behaves that way

From the MySQL C API docs for [`mysql_affected_rows()`](https://dev.mysql.com/doc/c-api/8.0/en/mysql-affected-rows.html):

> For UPDATE statements, the affected-rows value by default is the number of rows **actually changed**. If `CLIENT_FOUND_ROWS` flag is specified, the affected-rows value is the number of rows **matched** by the WHERE clause.

Go's `go-sql-driver/mysql` exposes that flag as `clientFoundRows=true` in the DSN.

## Four fixes, and when each is right

| # | Fix | Use when | Cost |
|--:|:--|:--|:--|
| 1 | `SELECT COUNT(*)` first, then `UPDATE` | You must know existence vs. no-change | One extra round trip |
| 2 | `INSERT … ON DUPLICATE KEY UPDATE` | Pure upsert, no other logic | Needs a unique key |
| 3 | Add `updated_at = NOW()` to the `SET` | You want "touched" semantics anyway | Writes on every call |
| 4 | `clientFoundRows=true` in the DSN | Whole-service semantics should be "matched" | Global; changes other queries too |

Do **not** pick #4 casually: it silently changes every `RowsAffected()` in the service.

## Verify it yourself

```bash
mysql -u root -p < examples/repro.sql
```

Run on MySQL 8.4.13 (Ubuntu 26.04 under WSL), 2026-11-18 — actual output:

```
+---------------+
| affected_rows |
+---------------+
|             0 |   <- same value written again
+---------------+
+--------------+
| matched_rows |
+--------------+
|            1 |   <- the row is definitely there
+--------------+
+---------------+
| affected_rows |
+---------------+
|             1 |   <- a real change
+---------------+
ERROR 1062 (23000) at line 36: Duplicate entry '42' for key 'sites.uk_account_id'
```

MySQL 8.4 prints the key name table-qualified (`sites.uk_account_id`); older versions print it bare.

## What is verified, and what is not

- **Verified**: the wording of the behaviour, quoted from MySQL's own C API documentation (link above).
- **Verified in production**: this exact `if affected == 0 { INSERT }` pattern raised `Error 1062` on a live service; the fix was #1 plus a unique-key audit.
- **Re-run here**: yes. MySQL 8.4.13 on Ubuntu 26.04 (WSL), 2026-11-18, four statements, output pasted above verbatim. The database is created and dropped by the script itself.

## Use it as an agent skill

`SKILL.md` in this repo drops into a Hermes Agent skills directory as-is (`skills/<category>/mysql-rowsaffected-behavior/SKILL.md`). It is the same note, in the format an agent reads.

## License

MIT — see [LICENSE](LICENSE).
