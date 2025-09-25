# Prompt
This is awesome.  In some database systems, there is something like a virtual table or a view where an operation is run before querying it.

Would it be possible to store the data as the dictionaries and dehydrated tables and create some sort of virtual table or view when it needs to be used to minimize memory overhead?

# Response
Yep—this is a perfect fit for SQLite **views** (and, if you want to edit through them, **INSTEAD OF triggers**). You can keep only the compact tables + dictionaries on disk, and expose “rehydrated” rows on demand via views. SQLite does **not** materialize a view; it rewrites your query, so memory overhead stays minimal. Add a few indexes and the joins stay fast.

Below is a drop-in setup:

---

# 1) Helpful indexes (speed up the joins)

```sqlite
-- On compact tables (foreign-key-like columns)
CREATE INDEX IF NOT EXISTS idx_vc_last ON voters_compact(lastname_i);
CREATE INDEX IF NOT EXISTS idx_vc_first ON voters_compact(firstname_i);
CREATE INDEX IF NOT EXISTS idx_vc_mid ON voters_compact(middlename_i);
CREATE INDEX IF NOT EXISTS idx_vc_street ON voters_compact(street_i);
CREATE INDEX IF NOT EXISTS idx_vc_city ON voters_compact(city_i);
CREATE INDEX IF NOT EXISTS idx_vc_state ON voters_compact(state_i);

CREATE INDEX IF NOT EXISTS idx_ac_street ON addresses_compact(street_i);
CREATE INDEX IF NOT EXISTS idx_ac_city ON addresses_compact(city_i);
CREATE INDEX IF NOT EXISTS idx_ac_state ON addresses_compact(state_i);

-- On dictionary names (optional but can help if you ever look them up by text)
CREATE INDEX IF NOT EXISTS idx_df_name ON dict_firstname(name);
CREATE INDEX IF NOT EXISTS idx_dm_name ON dict_middlename(name);
CREATE INDEX IF NOT EXISTS idx_dl_name ON dict_lastname(name);
CREATE INDEX IF NOT EXISTS idx_dc_name ON dict_city(name);
CREATE INDEX IF NOT EXISTS idx_ds_name ON dict_state(name);
CREATE INDEX IF NOT EXISTS idx_dstr_name ON dict_street(name);
```

---

# 2) Read-only “rehydrated” views

These return your original row shapes without storing them.

```sqlite
-- Voters view (rehydrated fields)
CREATE VIEW IF NOT EXISTS voters_v AS
SELECT
  vc.xid,
  dln.name  AS LASTNAME,
  dfn.name  AS FIRSTNAME,
  dmn.name  AS MIDDLENAME,
  CAST(vc.VOTERID AS TEXT) AS VOTERID,
  vc.PARTY,
  TRIM(
    COALESCE(NULLIF(vc.housenumber,''),'')
    || CASE WHEN NULLIF(vc.housenumber,'') IS NOT NULL AND dstr.name IS NOT NULL THEN ' ' ELSE '' END
    || COALESCE(dstr.name,'')
  ) AS ADDRESS,
  dcity.name  AS CITY,
  dstate.name AS STATE,
  vc.ZIP,
  CASE
    WHEN vc.DATEOFBIRTH IS NOT NULL AND vc.DATEOFBIRTH BETWEEN 10000101 AND 99991231
      THEN substr(CAST(vc.DATEOFBIRTH AS TEXT),1,4) || '-' ||
           substr(CAST(vc.DATEOFBIRTH AS TEXT),5,2) || '-' ||
           substr(CAST(vc.DATEOFBIRTH AS TEXT),7,2)
    ELSE NULL
  END AS DATEOFBIRTH,
  NULL AS REGISTRATIONDATE
FROM voters_compact vc
LEFT JOIN dict_lastname   dln  ON dln.rowid  = vc.lastname_i
LEFT JOIN dict_firstname  dfn  ON dfn.rowid  = vc.firstname_i
LEFT JOIN dict_middlename dmn  ON dmn.rowid  = vc.middlename_i
LEFT JOIN dict_street     dstr ON dstr.rowid = vc.street_i
LEFT JOIN dict_city       dcity ON dcity.rowid = vc.city_i
LEFT JOIN dict_state      dstate ON dstate.rowid = vc.state_i;

-- Addresses view (rehydrated)
CREATE VIEW IF NOT EXISTS address_v AS
SELECT
  TRIM(
    COALESCE(NULLIF(ac.housenumber,''),'')
    || CASE WHEN NULLIF(ac.housenumber,'') IS NOT NULL AND dstr.name IS NOT NULL THEN ' ' ELSE '' END
    || COALESCE(dstr.name,'')
  ) AS ADDRESS,
  dcity.name  AS CITY,
  dstate.name AS STATE,
  ac.ZIP,
  ac.RATING,
  ac.X / 1000000.0 AS X,
  ac.Y / 1000000.0 AS Y
FROM addresses_compact ac
LEFT JOIN dict_street dstr ON dstr.rowid = ac.street_i
LEFT JOIN dict_city   dcity ON dcity.rowid = ac.city_i
LEFT JOIN dict_state  dstate ON dstate.rowid = ac.state_i;
```

**Use them like tables:**

```sql
SELECT * FROM voters_v WHERE LASTNAME='SMITH' AND CITY='TULSA' LIMIT 20;
SELECT AVG(RATING) FROM address_v WHERE STATE='OK';
```

---

# 3) Make the views **updatable** (optional)

If you also want to `INSERT/UPDATE/DELETE` through the views, add **INSTEAD OF** triggers that translate changes into dictionary lookups + compact table writes. Below is a practical pattern for `voters_v`:

### 3a) INSERT into `voters_v`

```sqlite
DROP TRIGGER IF EXISTS ins_voters_v;
CREATE TRIGGER ins_voters_v INSTEAD OF INSERT ON voters_v
BEGIN
  -- Ensure dict entries exist for each text field we map to an index
  INSERT INTO dict_lastname(name)  SELECT NEW.LASTNAME  WHERE NEW.LASTNAME  IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_lastname  WHERE name=NEW.LASTNAME);
  INSERT INTO dict_firstname(name) SELECT NEW.FIRSTNAME WHERE NEW.FIRSTNAME IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_firstname WHERE name=NEW.FIRSTNAME);
  INSERT INTO dict_middlename(name) SELECT NEW.MIDDLENAME WHERE NEW.MIDDLENAME IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_middlename WHERE name=NEW.MIDDLENAME);

  -- Split ADDRESS into house number + street name (first space rule).
  -- Compute street name first:
  INSERT INTO dict_street(name)
  SELECT TRIM(
           CASE
             WHEN NEW.ADDRESS IS NOT NULL AND NEW.ADDRESS GLOB '* *'
               THEN SUBSTR(NEW.ADDRESS, INSTR(NEW.ADDRESS, ' ')+1)
             ELSE NEW.ADDRESS
           END
         )
  WHERE NEW.ADDRESS IS NOT NULL
    AND TRIM(
          CASE
            WHEN NEW.ADDRESS GLOB '* *'
              THEN SUBSTR(NEW.ADDRESS, INSTR(NEW.ADDRESS, ' ')+1)
            ELSE NEW.ADDRESS
          END
        ) <> ''
    AND NOT EXISTS (
          SELECT 1 FROM dict_street
          WHERE name = TRIM(
                     CASE
                       WHEN NEW.ADDRESS GLOB '* *'
                         THEN SUBSTR(NEW.ADDRESS, INSTR(NEW.ADDRESS, ' ')+1)
                       ELSE NEW.ADDRESS
                     END
                   )
        );

  INSERT INTO dict_city(name)  SELECT NEW.CITY  WHERE NEW.CITY  IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_city  WHERE name=NEW.CITY);
  INSERT INTO dict_state(name) SELECT NEW.STATE WHERE NEW.STATE IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_state WHERE name=NEW.STATE);

  INSERT INTO voters_compact (
    xid, lastname_i, firstname_i, middlename_i,
    VOTERID, PARTY, housenumber, street_i, city_i, state_i, zip, DATEOFBIRTH
  )
  SELECT
    NEW.xid,
    (SELECT rowid FROM dict_lastname  WHERE name=NEW.LASTNAME),
    (SELECT rowid FROM dict_firstname WHERE name=NEW.FIRSTNAME),
    (SELECT rowid FROM dict_middlename WHERE name=NEW.MIDDLENAME),
    CAST(NEW.VOTERID AS INTEGER),
    NEW.PARTY,
    -- housenumber from ADDRESS (text before first space)
    TRIM(CASE
           WHEN NEW.ADDRESS IS NOT NULL AND NEW.ADDRESS GLOB '* *'
             THEN SUBSTR(NEW.ADDRESS, 1, INSTR(NEW.ADDRESS, ' ')-1)
           ELSE NEW.ADDRESS
         END),
    (SELECT rowid FROM dict_street WHERE name =
       TRIM(CASE
              WHEN NEW.ADDRESS IS NOT NULL AND NEW.ADDRESS GLOB '* *'
                THEN SUBSTR(NEW.ADDRESS, INSTR(NEW.ADDRESS, ' ')+1)
              ELSE NEW.ADDRESS
            END)
    ),
    (SELECT rowid FROM dict_city  WHERE name=NEW.CITY),
    (SELECT rowid FROM dict_state WHERE name=NEW.STATE),
    NEW.ZIP,
    -- date text 'YYYY-MM-DD' -> integer YYYYMMDD (or keep NULL)
    CASE
      WHEN NEW.DATEOFBIRTH GLOB '????-??-??'
        THEN CAST(replace(NEW.DATEOFBIRTH,'-','') AS INTEGER)
      ELSE NULL
    END;
END;
```

### 3b) UPDATE through `voters_v`

```sqlite
DROP TRIGGER IF EXISTS upd_voters_v;
CREATE TRIGGER upd_voters_v INSTEAD OF UPDATE ON voters_v
BEGIN
  -- Upsert dict entries as needed
  INSERT INTO dict_lastname(name)  SELECT NEW.LASTNAME  WHERE NEW.LASTNAME  IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_lastname  WHERE name=NEW.LASTNAME);
  INSERT INTO dict_firstname(name) SELECT NEW.FIRSTNAME WHERE NEW.FIRSTNAME IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_firstname WHERE name=NEW.FIRSTNAME);
  INSERT INTO dict_middlename(name) SELECT NEW.MIDDLENAME WHERE NEW.MIDDLENAME IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_middlename WHERE name=NEW.MIDDLENAME);
  INSERT INTO dict_street(name)
  SELECT TRIM(
           CASE
             WHEN NEW.ADDRESS IS NOT NULL AND NEW.ADDRESS GLOB '* *'
               THEN SUBSTR(NEW.ADDRESS, INSTR(NEW.ADDRESS, ' ')+1)
             ELSE NEW.ADDRESS
           END
         )
  WHERE NEW.ADDRESS IS NOT NULL
    AND TRIM(
          CASE
            WHEN NEW.ADDRESS GLOB '* *'
              THEN SUBSTR(NEW.ADDRESS, INSTR(NEW.ADDRESS, ' ')+1)
            ELSE NEW.ADDRESS
          END
        ) <> ''
    AND NOT EXISTS (
          SELECT 1 FROM dict_street
          WHERE name = TRIM(
                     CASE
                       WHEN NEW.ADDRESS GLOB '* *'
                         THEN SUBSTR(NEW.ADDRESS, INSTR(NEW.ADDRESS, ' ')+1)
                       ELSE NEW.ADDRESS
                     END
                   )
        );
  INSERT INTO dict_city(name)  SELECT NEW.CITY  WHERE NEW.CITY  IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_city  WHERE name=NEW.CITY);
  INSERT INTO dict_state(name) SELECT NEW.STATE WHERE NEW.STATE IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dict_state WHERE name=NEW.STATE);

  UPDATE voters_compact
  SET lastname_i   = (SELECT rowid FROM dict_lastname  WHERE name=NEW.LASTNAME),
      firstname_i  = (SELECT rowid FROM dict_firstname WHERE name=NEW.FIRSTNAME),
      middlename_i = (SELECT rowid FROM dict_middlename WHERE name=NEW.MIDDLENAME),
      VOTERID      = CAST(NEW.VOTERID AS INTEGER),
      PARTY        = NEW.PARTY,
      housenumber  = TRIM(CASE
                            WHEN NEW.ADDRESS IS NOT NULL AND NEW.ADDRESS GLOB '* *'
                              THEN SUBSTR(NEW.ADDRESS, 1, INSTR(NEW.ADDRESS, ' ')-1)
                            ELSE NEW.ADDRESS
                          END),
      street_i     = (SELECT rowid FROM dict_street WHERE name =
                        TRIM(CASE
                               WHEN NEW.ADDRESS IS NOT NULL AND NEW.ADDRESS GLOB '* *'
                                 THEN SUBSTR(NEW.ADDRESS, INSTR(NEW.ADDRESS, ' ')+1)
                               ELSE NEW.ADDRESS
                             END)),
      city_i       = (SELECT rowid FROM dict_city  WHERE name=NEW.CITY),
      state_i      = (SELECT rowid FROM dict_state WHERE name=NEW.STATE),
      zip          = NEW.ZIP,
      DATEOFBIRTH  = CASE
                       WHEN NEW.DATEOFBIRTH GLOB '????-??-??'
                         THEN CAST(replace(NEW.DATEOFBIRTH,'-','') AS INTEGER)
                       ELSE NULL
                     END
  WHERE xid = OLD.xid;
END;
```

### 3c) DELETE through `voters_v`

```sqlite
DROP TRIGGER IF EXISTS del_voters_v;
CREATE TRIGGER del_voters_v INSTEAD OF DELETE ON voters_v
BEGIN
  DELETE FROM voters_compact WHERE xid = OLD.xid;
END;
```

> You can add analogous triggers for `address_v` if you want that view writable. The pattern is the same: upsert dict entries for `CITY/STATE/STREET`, split `ADDRESS`, and maintain the `addresses_compact` row.

---

## Why this minimizes memory overhead

* The on-disk storage stays compact (integers + small text fields).
* Views don’t store anything: SQLite compiles your query over `*_compact` + `dict_*` and streams rows.
* Indexes allow SQLite to only touch the rows it needs, so joins are efficient even on large files.
* If you’re memory sensitive, you can also tune page/cache sizes (`PRAGMA cache_size`, `mmap_size`) without changing schema.

If you want, I can also add the writable triggers for `address_v`; otherwise, the read-only views already give you zero-copy rehydration on demand.

