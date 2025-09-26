# Steps to import NY voter data using vsv extension in sqlean
Absolutely—Sqlean’s **vsv** module is perfect for “read-only import” of huge CSV-ish files while selecting just the columns you need.

Below are end-to-end steps that use **vsv parameters** (as in the page you linked) to read your 9 GB NYS file as a virtual table, then `INSERT … SELECT` only the needed fields into `dbA.voters`. I’ll show two variants:

* A: simplest (let vsv auto-name columns from a provided `schema`)
* B: same, but explicitly skip lines / customize separators if ever needed

I’ll assume:

* file path: `AllNYSVoters_20230306.txt`
* fields are double-quoted and comma-separated, 47 columns total
* no header row (matches your sample)

GitHub docs for Sqlean + `vsv` and examples of `vsv` params (`filename`, `header`, `fsep`, `rsep`, `skip`, `schema`) are here. ([GitHub][1])
(For reference, SQLite’s built-in csv vtable shows the idea of a `columns=N` arg; `vsv` focuses on `schema` and the CSV separators/skips. ([SQLite][2]))

---

# A) One-shot load with `vsv` (recommended)

### 1) Load the extension in the SQLite CLI

```sql
-- Option 1: load the full bundle (enables all Sqlean modules, including vsv)
.load ./sqlean

-- Option 2: load only vsv, if you have it split out
-- .load ./vsv
```

(See Sqlean README about `.load ./sqlean` and the bundled modules. ([GitHub][1]))

### 2) Make a virtual table over the text file

We’ll name columns `c1 .. c47` using `schema` so we can address by position:

```sql
CREATE VIRTUAL TABLE temp.nys_vsv USING vsv(
  filename='AllNYSVoters_20230306.txt',
  header=off,                  -- file has no header
  fsep=',',                    -- field separator (CSV)
  rsep='\n',                   -- record separator (default; safe to state)
  -- quote is double-quote by default for CSV; no need to set unless custom
  schema='create table nys(
    c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,c16,c17,c18,c19,c20,
    c21,c22,c23,c24,c25,c26,c27,c28,c29,c30,c31,c32,c33,c34,c35,c36,c37,c38,
    c39,c40,c41,c42,c43,c44,c45,c46,c47
  )'
);
```

> Tip: If your file ever starts with a few metadata lines, add `skip=N`. Example usage of `skip`, `fsep`, `rsep`, `header` is shown in the SQLite users list examples for `vsv`. ([Mail Archive][3])

### 3) Insert only the columns you care about

Map fields by position (using your earlier table spec):

```sql
INSERT INTO dbA.voters
  (LASTNAME, FIRSTNAME, MIDDLENAME, VOTERID, PARTY,
   ADDRESS, CITY, STATE, ZIP, DATEOFBIRTH, REGISTRATIONDATE)
SELECT
  c1  AS LASTNAME,         -- LASTNAME
  c2  AS FIRSTNAME,        -- FIRSTNAME
  c3  AS MIDDLENAME,       -- MIDDLENAME
  c46 AS VOTERID,          -- SBOEID (unique voter id)
  CASE WHEN c22='OTH' AND c23 IS NOT NULL AND c23<>''
       THEN c23 ELSE c22 END AS PARTY,  -- ENROLLMENT / OTHERPARTY
  /* ADDRESS: prefer non-standard if present; else assemble parts */
  TRIM(
    CASE WHEN c12 IS NOT NULL AND c12<>''
         THEN c12
         ELSE TRIM(
           COALESCE(c5,'') || ' ' || COALESCE(c6,'') || ' ' || COALESCE(c7,'') || ' ' ||
           COALESCE(c8,'') || ' ' || COALESCE(c9,'') || ' ' ||
           CASE WHEN c10 IS NOT NULL AND c10<>'' THEN (c10 || ' ') ELSE '' END ||
           COALESCE(c11,'')
         )
    END
  ) AS ADDRESS,
  c13      AS CITY,
  'NY'     AS STATE,
  CASE WHEN c14 IS NOT NULL AND c14<>'' THEN CAST(c14 AS INTEGER) ELSE NULL END AS ZIP,
  CASE WHEN length(c20)=8                                  -- DOB is YYYYMMDD
       THEN substr(c20,1,4)||'-'||substr(c20,5,2)||'-'||substr(c20,7,2)
       ELSE NULL END AS DATEOFBIRTH,
  NULL AS REGISTRATIONDATE;                                -- keep as NULLs for now
```

Notes:

* If you need `REGISTRATIONDATE` later, it’s `c38` in `YYYYMMDD`; convert like DOB.
* **ZIP as INTEGER drops leading zeros** (common in NY). If you need exact ZIP strings, change your schema column `ZIP` to `TEXT` before this step.

That’s it. You never materialize the 47 columns; you only **read** them via `vsv` and **insert** the subset into `dbA.voters`.

---

# B) Same idea with optional `skip` / custom separators

If the file ever arrives with:

* a header row: set `header=on` (then column names come from row 1)
* odd separators: set `fsep` (field sep) and/or `rsep` (record sep)
* a few leading lines to ignore: set `skip=N`

Examples from the SQLite users list show:

```sql
CREATE VIRTUAL TABLE t USING vsv(
  filename='file.csv',
  header=on,
  fsep='|',
  rsep='~',
  skip=3
);
```

Then `SELECT` or `INSERT … SELECT` as above (use either your header names or `schema` names). ([Mail Archive][3])

---

## Practical tips

* **Performance**: wrap the `INSERT … SELECT` in a transaction if you didn’t disable journaling:

  ```sql
  BEGIN;
  INSERT … SELECT …;
  COMMIT;
  ```
* **Indexes**: add one post-load if you’ll query by voter id often:

  ```sql
  CREATE INDEX IF NOT EXISTS idx_voters_voterid ON dbA.voters(VOTERID);
  ```
* **Multiple files**: create another `vsv` table pointing at the other filename and run the same `INSERT` query.

---

If you want, tell me your OS and whether you’ve got `./sqlean` vs `./vsv` as a separate `.so/.dylib/.dll`, and I’ll tweak the exact `.load` line.

[1]: https://github.com/nalgeon/sqlean "GitHub - nalgeon/sqlean: The ultimate set of SQLite extensions"
[2]: https://www.sqlite.org/csv.html?utm_source=chatgpt.com "The CSV Virtual Table"
[3]: https://www.mail-archive.com/search?f=1&l=sqlite-users%40mailinglists.sqlite.org&o=newest&q=subject%3A%22Re%5C%3A+%5C%5Bsqlite%5C%5D+csv+extension%5C%2Ffeature+requests%5C%3A+new+options+for+field%09separator+different+from+default+%27%2C%09%27+and+skip%3DN+to+skip+first+N+lines%22&utm_source=chatgpt.com "subject:\"Re\\: \\[sqlite\\] csv extension\\/feature requests"

