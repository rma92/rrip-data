Awesome—since you already have `sqlite_zstd.dll` next to your DBs, here’s a clean set of steps you can run from the SQLite shell on Windows to compress your two tables (voters + addresses) and keep them queryable “as normal.”

> The gist: **load the extension → mark target columns for transparent compression → run the maintenance pass → VACUUM → done.** The tables keep their names; the extension creates a shadow storage table under the hood and a view so your SQL keeps working. ([GitHub][1])

---

# 1) Back up, open, and load the extension

```bat
copy voters.db voters.backup.db
sqlite3 voters.db
```

Inside the SQLite prompt:

```sql
-- Optional but recommended while compressing:
PRAGMA busy_timeout = 2000;          -- avoids "database is locked" during maintenance
-- Load the extension (adjust the path if needed)
.load ./sqlite_zstd.dll
```

You should see a one-line “initialized” message when it loads. You’ll need to load the DLL **each time** you open the database in a new process. ([GitHub][1])

---

# 2) Inspect columns and pick what to compress

You can only target columns with TEXT or BLOB affinity.

```sql
PRAGMA table_info(voters);
PRAGMA table_info(addresses);
```

Pick the *wide / repetitive* text columns (e.g., `full_name`, `first_name`, `last_name`, `street`, `city`, maybe a JSON column). The **primary key must not be NULL** for rows in a compressed table. ([GitHub][1])

---

# 3) Enable “transparent” compression on chosen columns

Call `zstd_enable_transparent` once **per column** you want to compress. You can start with a moderate compression level (e.g., 10–15); higher means more CPU but smaller files.

Examples (tweak table/column names to yours):

```sql
-- VOTERS
SELECT zstd_enable_transparent('{
  "table": "voters",
  "column": "full_name",
  "compression_level": 15
}');

SELECT zstd_enable_transparent('{
  "table": "voters",
  "column": "middle_name",
  "compression_level": 15
}');

-- ADDRESSES
SELECT zstd_enable_transparent('{
  "table": "addresses",
  "column": "street",
  "compression_level": 15
}');
SELECT zstd_enable_transparent('{
  "table": "addresses",
  "column": "city",
  "compression_level": 15
}');
```

What this does: the extension creates a hidden storage table (e.g., `_voters_zstd`) and turns `voters` into a **view** with triggers so your `SELECT/INSERT/UPDATE/DELETE` keep working as before. (You won’t see data shrink *yet*—that happens next.) ([GitHub][1])

> Tip: You can call `zstd_enable_transparent` for as many text/blob columns as you like—do the big ones first for the biggest win. ([GitHub][1])

---

# 4) Compress the existing rows

Run the incremental maintenance to train dictionaries and compress the data.

```sql
-- Fastest: run to completion in one go (DB will be busy while it runs)
SELECT zstd_incremental_maintenance(NULL, 1);
```

If you prefer time-sliced work (e.g., 60s bursts that leave breathing room for other writers), do:

```sql
SELECT zstd_incremental_maintenance(60, 0.5);
-- Re-run that statement as many times as you like until it returns 0 (nothing left to do).
```

You’ll see progress logs with before/after sizes per chunk. ([GitHub][1])

---

# 5) Reclaim space on disk

After compression, SQLite has free pages inside the file. Shrink the file with:

```sql
VACUUM;
```

This rebuilds the file to its new, smaller size. ([SQLite][2])

---

# 6) Verify and carry on

* Your table names stay the same; queries work as before.
* To see what got created:

  ```sql
  .schema voters
  .schema addresses
  SELECT name FROM sqlite_master WHERE name LIKE '%zstd%';
  ```
* **Every time you open the DB**, load the DLL first (`.load ./sqlite_zstd.dll`) so the views/triggers resolve. ([GitHub][1])

---

## Good-to-know caveats

* Only **TEXT/BLOB** columns can be compressed; don’t target INTEGER/REAL columns. ([GitHub][1])
* Some DDL on compressed tables is **partially supported**; if you need to restructure heavily, temporarily decompress (copy out/in) or compress after schema changes. ([GitHub][1])
* **ATTACH**-ing a database that already contains compressed tables is not supported by the extension. Open it directly instead. ([GitHub][1])
* For big runs, keeping `busy_timeout` > 2000ms helps avoid lock thrash during maintenance. ([GitHub][1])

---

## Undo / migrate back (if needed)

If you ever want the plain, uncompressed layout again:

```sql
CREATE TABLE voters_plain AS SELECT * FROM voters;
DROP VIEW voters;               -- this drops the view
DROP TABLE _voters_zstd;        -- remove compressed storage
ALTER TABLE voters_plain RENAME TO voters;

-- repeat for addresses
```

(Or simply export with `sqlite3`/`VACUUM INTO` from the view and import elsewhere.)

---

If you paste your exact column names for the two tables, I’ll mark up the exact `zstd_enable_transparent` calls for your schema (and suggest which columns are worth compressing first).

[1]: https://github.com/phiresky/sqlite-zstd "GitHub - phiresky/sqlite-zstd: Transparent dictionary-based row-level compression for SQLite"
[2]: https://www.sqlite.org/lang_vacuum.html?utm_source=chatgpt.com "VACUUM"

