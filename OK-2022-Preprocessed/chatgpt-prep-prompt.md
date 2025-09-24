I'm working with a sqlite3 database, and am getting ready to convert it to be stored in protobufs.  The data set contains a large quantity of people's names and addresses.  Since those have a lot of repeating components, we will create dictionaries to store numeric indexes into the data.  The dictionaries have already been created, and the format of the tables has been defined.

So we need to write SQL to 


voter_shared.db contains the following tables, which contain the voter rolls and geocoded addresses:
```
table|voters_shared|voters_shared|2|CREATE TABLE voters_shared (
            xid INTEGER PRIMARY KEY AUTOINCREMENT,
            LASTNAME TEXT,
            FIRSTNAME TEXT,
            MIDDLENAME TEXT,
            VOTERID TEXT,
            PARTY TEXT,
            ADDRESS TEXT,
            CITY TEXT,
            STATE TEXT,
            ZIP INTEGER,
            DATEOFBIRTH TEXT,
            REGISTRATIONDATE TEXT
        )
table|address|address|4|CREATE TABLE address (
            ADDRESS TEXT,
            CITY TEXT,
            STATE TEXT,
            ZIP INTEGER,
            RATING INTEGER,
            X REAL,
            Y REAL
        )
```
I want to store this more efficiently, in protobufs, but use dictionaries to simplify storage of the following fields:
```sqlite3
attach 'voter_shared.db' as db1;
attach 'dict.db' as dbD;
attach 'voter_compact.db' as dbV;
attach 'address_compact.db' as dbA;
```
## Part 1: Create dictionaries, and tables to hold the indexed data
```sqlite3
CREATE TABLE dbD.dict_firstname AS SELECT firstname AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;
CREATE TABLE dbD.dict_middlename AS SELECT middlename AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;
CREATE TABLE dbD.dict_lastname AS SELECT lastname AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;
CREATE TABLE dbD.dict_city AS SELECT lastname AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;
CREATE TABLE dbD.dict_state AS SELECT lastname AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;

CREATE TABLE dict_street AS
SELECT 
    substr(address, instr(address, ' ') + 1) AS street_name,
    COUNT(*) AS freq
FROM address
GROUP BY street_name
ORDER BY freq DESC;

--VoterID is an integer in Oklahoma
--Zip is an integer in the USA
--Can we convert the date to something more useful
--Convert date to ISO 8601 integer.
--Registration date is missing from the dataset, so we won't store it.
--house number is text as it sometimes contains a letter.  Profiling may suggest we index them, but this is too much effort and only makes sense if the dictionary creation is entirely automatic as the data is small.
--split street and house number to use dict_street above.
CREATE TABLE dbV.voter (
            xid INTEGER PRIMARY KEY AUTOINCREMENT,
            lastname_i INTEGER,
            firstname_i INTEGER,
            middlename_i INTEGER,
            VOTERID INTEGER,
            PARTY TEXT,
            housenumber TEXT,
            street_i INTEGER,
            city_i INTEGER,
            state_i INTEGER,
            zip INTEGER,
            DATEOFBIRTH INTEGER
        );
--split street and house number to use dict_street above.
--5 decimal places = 0.00001 deg = 1.11 meter = individual trees, houses = Multiply by 100,000
--6 decimal places = 0.000001 deg = 0.11 meter/10 cm = individual human = Multiply by 1,000,000.  This still fits in a 32-bit integer.
--X and Y are REAL lat and lon.  Multiply it by 1 Million and CAST AS INTEGER.
CREATE TABLE dbA.address (
            housenumber TEXT,
            street_i INTEGER,
            city_i INTEGER,
            state_i INTEGER,
            zip INTEGER,
            RATING INTEGER,
            X INTEGER,
            Y INTEGER
        );
```
Please use your expertise to write the necessary SQL statements to populate the table two tables.

Then provide the .proto files for the new address and voter tables, the commands to export those two tables into pipe-separated value files (like a CSV but using a pipe instead of a comma), and to use protoc to create the protobuf files for those.

The dictionaries should be dumped as simply text files with one string per line to minimize processing.

# Response
Awesome project. Below is a complete, copy-pasteable playbook that:

1. fixes/creates the dictionaries,
2. populates your two compact tables using dictionary **rowid**s as the integer indexes,
3. dumps the dictionaries (one string per line),
4. exports the two compact tables as pipe-separated values, and
5. defines protobuf schemas + shows a zero-dependency way to turn your SQLite rows into protobuf binaries using `protoc` (by emitting textproto from SQLite and piping it to `protoc --encode`).

---

# 0) Open all DBs

```sqlite
-- from the sqlite3 shell:
ATTACH DATABASE 'voter_shared.db'  AS db1;
ATTACH DATABASE 'dict.db'          AS dbD;
ATTACH DATABASE 'voter_compact.db' AS dbV;
ATTACH DATABASE 'address_compact.db' AS dbA;
```

---

# 1) (Re)create dictionaries

> We’ll build dictionaries from **both** the voter rolls and the geocoded address table (so we don’t miss cities/streets that only appear in one source). The integer index you’ll store in protobufs is the **rowid** of each dict row.

```sqlite
-- Drop if re-running
DROP TABLE IF EXISTS dbD.dict_firstname;
DROP TABLE IF EXISTS dbD.dict_middlename;
DROP TABLE IF EXISTS dbD.dict_lastname;
DROP TABLE IF EXISTS dbD.dict_city;
DROP TABLE IF EXISTS dbD.dict_state;
DROP TABLE IF EXISTS dbD.dict_street;

-- First/Last/Middle from voter rolls
CREATE TABLE dbD.dict_firstname AS
SELECT firstname AS name, COUNT(*) AS c
FROM db1.voters_shared
WHERE firstname IS NOT NULL AND TRIM(firstname) <> ''
GROUP BY name
ORDER BY c DESC;

CREATE TABLE dbD.dict_middlename AS
SELECT middlename AS name, COUNT(*) AS c
FROM db1.voters_shared
WHERE middlename IS NOT NULL AND TRIM(middlename) <> ''
GROUP BY name
ORDER BY c DESC;

CREATE TABLE dbD.dict_lastname AS
SELECT lastname AS name, COUNT(*) AS c
FROM db1.voters_shared
WHERE lastname IS NOT NULL AND TRIM(lastname) <> ''
GROUP BY name
ORDER BY c DESC;

-- City/state from both sources (voters + address)
CREATE TABLE dbD.dict_city AS
WITH all_cities(name) AS (
  SELECT city FROM db1.voters_shared
  UNION ALL
  SELECT city FROM db1.address
)
SELECT TRIM(name) AS name, COUNT(*) AS c
FROM all_cities
WHERE name IS NOT NULL AND TRIM(name) <> ''
GROUP BY name
ORDER BY c DESC;

CREATE TABLE dbD.dict_state AS
WITH all_states(name) AS (
  SELECT state FROM db1.voters_shared
  UNION ALL
  SELECT state FROM db1.address
)
SELECT TRIM(name) AS name, COUNT(*) AS c
FROM all_states
WHERE name IS NOT NULL AND TRIM(name) <> ''
GROUP BY name
ORDER BY c DESC;

-- Street dictionary: split at the first space, take the remainder as street name,
-- from BOTH sources (addresses on voter rows + the geocoder table)
CREATE TABLE dbD.dict_street AS
WITH addr_strings(addr) AS (
  SELECT address FROM db1.voters_shared
  UNION ALL
  SELECT address FROM db1.address
),
split AS (
  SELECT
    TRIM(
      CASE
        WHEN addr GLOB '* *'
          THEN SUBSTR(addr, INSTR(addr, ' ')+1)
        ELSE addr
      END
    ) AS street_name
  FROM addr_strings
)
SELECT street_name AS name, COUNT(*) AS c
FROM split
WHERE street_name IS NOT NULL AND street_name <> ''
GROUP BY street_name
ORDER BY c DESC;
```

> **Note**: These are plain tables created via `CREATE TABLE … AS SELECT`. In SQLite, each row has a `rowid`. We’ll use that `rowid` as the integer dictionary index when we populate the compact tables.

---

# 2) Populate the compact tables

We’ll split `ADDRESS` into `housenumber` and `street_name`, then look up the dictionary indexes via joins (`rowid`).

### 2a) `dbV.voter`

```sqlite
--VoterID is an integer in Oklahoma
--Zip is an integer in the USA
--Can we convert the date to something more useful
--Convert date to ISO 8601 integer.
--Registration date is missing from the dataset, so we won't store it.
--house number is text as it sometimes contains a letter.  Profiling may suggest we index them, but this is too much effort and only makes sense if the dictionary creation is entirely automatic as the data is small.
--split street and house number to use dict_street above.
CREATE TABLE IF NOT EXISTS dbV.voter (
            xid INTEGER PRIMARY KEY AUTOINCREMENT,
            lastname_i INTEGER,
            firstname_i INTEGER,
            middlename_i INTEGER,
            VOTERID INTEGER,
            PARTY TEXT,
            housenumber TEXT,
            street_i INTEGER,
            city_i INTEGER,
            state_i INTEGER,
            zip INTEGER,
            DATEOFBIRTH INTEGER
        );
-- Clean target if re-running
DELETE FROM dbV.voter;

WITH split AS (
  SELECT
    v.*,
    -- house number is the leading token before the first space (or the whole thing if no space)
    TRIM(CASE WHEN v.address GLOB '* *' THEN SUBSTR(v.address, 1, INSTR(v.address, ' ')-1) ELSE v.address END) AS housenumber,
    -- street name is remainder after first space (or empty if none)
    TRIM(CASE WHEN v.address GLOB '* *' THEN SUBSTR(v.address, INSTR(v.address, ' ')+1) ELSE '' END) AS street_name
  FROM db1.voters_shared v
)
INSERT INTO dbV.voter (
  lastname_i, firstname_i, middlename_i,
  VOTERID, PARTY, housenumber, street_i, city_i, state_i, zip, DATEOFBIRTH
)
SELECT
  ln.rowid  AS lastname_i,
  fn.rowid  AS firstname_i,
  mn.rowid  AS middlename_i,
  CAST(s.VOTERID AS INTEGER) AS VOTERID,
  s.PARTY,
  s.housenumber,
  st.rowid  AS street_i,
  ct.rowid  AS city_i,
  stt.rowid AS state_i,
  s.ZIP     AS zip,
  -- Convert DOB text to ISO 8601 integer YYYYMMDD if possible.
  -- If it is already ISO-like, this works. If it's e.g. MM/DD/YYYY, try a fallback.
  CASE
    WHEN strftime('%Y%m%d', s.DATEOFBIRTH) IS NOT NULL
      THEN CAST(strftime('%Y%m%d', s.DATEOFBIRTH) AS INTEGER)
    WHEN s.DATEOFBIRTH GLOB '??/??/????'
      THEN CAST(substr(s.DATEOFBIRTH,7,4) || substr(s.DATEOFBIRTH,1,2) || substr(s.DATEOFBIRTH,4,2) AS INTEGER)
    ELSE NULL
  END AS DATEOFBIRTH
FROM split s
LEFT JOIN dbD.dict_lastname  ln ON ln.name = s.LASTNAME
LEFT JOIN dbD.dict_firstname fn ON fn.name = s.FIRSTNAME
LEFT JOIN dbD.dict_middlename mn ON mn.name = s.MIDDLENAME
LEFT JOIN dbD.dict_street    st ON st.name = s.street_name
LEFT JOIN dbD.dict_city      ct ON ct.name = s.CITY
LEFT JOIN dbD.dict_state     stt ON stt.name = s.STATE;
```

### 2b) `dbA.address`

```sqlite
--split street and house number to use dict_street above.
--5 decimal places = 0.00001 deg = 1.11 meter = individual trees, houses = Multiply by 100,000
--6 decimal places = 0.000001 deg = 0.11 meter/10 cm = individual human = Multiply by 1,000,000.  This still fits in a 32-bit integer.
--X and Y are REAL lat and lon.  Multiply it by 1 Million and CAST AS INTEGER.
CREATE TABLE IF NOT EXISTS dbA.address (
            housenumber TEXT,
            street_i INTEGER,
            city_i INTEGER,
            state_i INTEGER,
            zip INTEGER,
            RATING INTEGER,
            X INTEGER,
            Y INTEGER
        );
-- Clean target if re-running
DELETE FROM dbA.address;

WITH split AS (
  SELECT
    a.*,
    TRIM(CASE WHEN a.address GLOB '* *' THEN SUBSTR(a.address, 1, INSTR(a.address, ' ')-1) ELSE a.address END) AS housenumber,
    TRIM(CASE WHEN a.address GLOB '* *' THEN SUBSTR(a.address, INSTR(a.address, ' ')+1) ELSE '' END) AS street_name
  FROM db1.address a
)
INSERT INTO dbA.address (
  housenumber, street_i, city_i, state_i, zip, RATING, X, Y
)
SELECT
  s.housenumber,
  st.rowid                                                AS street_i,
  ct.rowid                                                AS city_i,
  stt.rowid                                               AS state_i,
  s.ZIP,
  s.RATING,
  CAST(ROUND(s.X * 1000000.0) AS INTEGER)                 AS X,  -- scale to microdegrees
  CAST(ROUND(s.Y * 1000000.0) AS INTEGER)                 AS Y
FROM split s
LEFT JOIN dbD.dict_street st ON st.name = s.street_name
LEFT JOIN dbD.dict_city   ct ON ct.name = s.CITY
LEFT JOIN dbD.dict_state  stt ON stt.name = s.STATE;
```

---

# 3) Dump dictionaries (one string per line)

```sqlite
.mode list

.once dict_firstname.txt
SELECT name FROM dbD.dict_firstname ORDER BY rowid;

.once dict_middlename.txt
SELECT name FROM dbD.dict_middlename ORDER BY rowid;

.once dict_lastname.txt
SELECT name FROM dbD.dict_lastname ORDER BY rowid;

.once dict_city.txt
SELECT name FROM dbD.dict_city ORDER BY rowid;

.once dict_state.txt
SELECT name FROM dbD.dict_state ORDER BY rowid;

.once dict_street.txt
SELECT name FROM dbD.dict_street ORDER BY rowid;
```

Each file will contain exactly one string per line (no separators since it’s a single column).

---

# 4) Export pipe-separated value (PSV) files for the compact tables

```sqlite
.mode csv
.separator |

-- Voters (export all columns, preserving order)
.once voters_compact.psv
SELECT xid, lastname_i, firstname_i, middlename_i, VOTERID, PARTY,
       housenumber, street_i, city_i, state_i, zip, DATEOFBIRTH
FROM dbV.voter
ORDER BY xid;

-- Addresses
.once addresses_compact.psv
SELECT housenumber, street_i, city_i, state_i, zip, RATING, X, Y
FROM dbA.address;
```

---

# 5) Protobuf schemas & creating `.pb` files with `protoc`

We’ll define one schema per dataset and include a tiny “container” message so we can bulk-encode using `protoc --encode=<Container>`.

### 5a) `voter.proto`

```proto
syntax = "proto3";
package voterpack;

message Voter {
  int64  xid          = 1;  // from AUTOINCREMENT
  int32  lastname_i   = 2;  // dictionary rowid
  int32  firstname_i  = 3;  // dictionary rowid
  int32  middlename_i = 4;  // dictionary rowid
  int64  voterid      = 5;
  string party        = 6;
  string housenumber  = 7;
  int32  street_i     = 8;  // dictionary rowid
  int32  city_i       = 9;  // dictionary rowid
  int32  state_i      = 10; // dictionary rowid
  int32  zip          = 11;
  int32  dateofbirth  = 12; // YYYYMMDD as integer
}

message VoterDataset {
  repeated Voter records = 1;
}
```

### 5b) `address.proto`

```proto
syntax = "proto3";
package addresspack;

message Address {
  string housenumber = 1;
  int32  street_i    = 2;  // dictionary rowid
  int32  city_i      = 3;  // dictionary rowid
  int32  state_i     = 4;  // dictionary rowid
  int32  zip         = 5;
  int32  rating      = 6;
  sint32 x           = 7;  // microdegrees (scaled REAL), signed
  sint32 y           = 8;  // microdegrees (scaled REAL), signed
}

message AddressDataset {
  repeated Address records = 1;
}
```

> `sint32` uses zig-zag encoding, which is efficient for small signed values (good for ±microdegrees).

---

## 5c) Emit **textproto** directly from SQLite, then use `protoc --encode` to make `.pb`

`protoc` can read protobuf **text format** from stdin and write binary protobufs. We can have SQLite generate that text format.

### Generate `voters.textproto`

```sqlite
UPDATE dbV.voter SET housenumber = REPLACE(housenumber, '\', '\\');
.mode list
.output voters_body.textproto
SELECT 'records {'
     || ' xid: '         || xid
     || ' lastname_i: '  || COALESCE(lastname_i, 0)
     || ' firstname_i: ' || COALESCE(firstname_i, 0)
     || ' middlename_i: '|| COALESCE(middlename_i, 0)
     || ' voterid: '     || COALESCE(VOTERID, 0)
     || ' party: "'      || REPLACE(REPLACE(COALESCE(PARTY,''), '\\', '\\\\'), '"', '\\"') || '"'
     || ' housenumber: "'|| REPLACE(REPLACE(COALESCE(housenumber,''), '\\', '\\\\'), '"', '\\"') || '"'
     || ' street_i: '    || COALESCE(street_i, 0)
     || ' city_i: '      || COALESCE(city_i, 0)
     || ' state_i: '     || COALESCE(state_i, 0)
     || ' zip: '         || COALESCE(zip, 0)
     || CASE WHEN dateofbirth IS NOT NULL THEN ' dateofbirth: '||dateofbirth ELSE '' END
     || ' }'
FROM dbV.voter
ORDER BY xid;
.output stdout
```

Wrap it with the container field and save as `voters.textproto`:

```bash
(echo "records: []" | sed 's/\[\]/{}/' > voters.textproto.header)  # harmless header
cat voters.textproto.header > voters.textproto
cat voters_body.textproto >> voters.textproto
rm voters_body.textproto
# Make the top-level object: just a block with repeated 'records { ... }'
# voters.textproto now contains: multiple "records { ... }" entries, which is valid for VoterDataset
```

(You can skip the header entirely; a file consisting solely of repeated `records { ... }` blocks is valid for parsing as `VoterDataset`.)

Now encode:

```bash
./protoc --encode=voterpack.VoterDataset voter.proto < voters.textproto > voters.pb
```

### Generate `addresses.textproto`

```sqlite
UPDATE dbA.address SET housenumber = REPLACE(housenumber, '\', '\\');
.mode list
.output addresses_body.textproto
SELECT 'records {'
     || ' housenumber: "'|| REPLACE(REPLACE(COALESCE(housenumber,''), '\\', '\\\\'), '"', '\\"') || '"'
     || ' street_i: '    || COALESCE(street_i, 0)
     || ' city_i: '      || COALESCE(city_i, 0)
     || ' state_i: '     || COALESCE(state_i, 0)
     || ' zip: '         || COALESCE(zip, 0)
     || ' rating: '      || COALESCE(RATING, 0)
     || ' x: '           || COALESCE(X, 0)
     || ' y: '           || COALESCE(Y, 0)
     || ' }'
FROM dbA.address;
.output stdout
```

Encode:

```bash
#cat addresses_body.textproto > addresses.textproto
mv addresses_body.textproto addresses.textproto
./protoc --encode=addresspack.AddressDataset address.proto < addresses.textproto > addresses.pb
```

> You can later verify by decoding:
>
> ```bash
> protoc --decode=voterpack.VoterDataset   voter.proto   < voters.pb
> protoc --decode=addresspack.AddressDataset address.proto < addresses.pb
> ```

---

## Notes & tips

* **Why use `rowid` as dictionary index?** It’s inherent to these SQLite tables created via `CREATE TABLE … AS SELECT`. Faster and simpler than manufacturing an `id`. If you prefer stable IDs across rebuilds, create explicit `INTEGER PRIMARY KEY` columns and load with a consistent ordering rule.

* **Dates**: The DOB conversion includes a fallback for `MM/DD/YYYY`. If your source has other quirks, add more cases in that `CASE` block.

* **Lat/Lon scaling**: You asked for ×1,000,000; we used `ROUND(real*1e6)` and stored in `sint32`. That keeps typical US lat/lon within ±90, ±180 well inside `int32`.

* **Re-running**: If you’ll iterate, consider adding `CREATE INDEX` on the `name` column of each dict table to speed up the joins:

  ```sqlite
  CREATE INDEX IF NOT EXISTS idx_dict_firstname_name ON dbD.dict_firstname(name);
  -- repeat for other dict_* tables
  ```

That’s it—run sections 0→5 in order and you’ll have compact tables, human-readable dicts, PSV exports, and protobuf binaries.

# Results
address_compact.db 37708KB
address_compact.db.xz 12667KB
addresses.pb 33910KB
addresses.pb.xz 10233KB
address_compact.psv 48181KB
address_compact.psv.xz 9167KB
dict.db 7068KB
dict.db.xz 2465KB
6 dict txt files 3716KB
dict-txt-only.7z 1218KB
voters.pb 102035KB
voters.pb.xz 38334KB
voters_compact.psv 138391KB
voters_compact.psv.xz 34443KB
voter_compact.db 98144KB
voter_compact.db.xz 39054KB
7z of dictionary txt and two PSV files 45,231KB

Dictionary compression makes sense.  It is not worthwhile going through the effort of making a protobuf.
It may make sense storing the result as an xz'd text.

# Import
Sweet—since your best win is the dictionary + PSV combo, here’s a clean, **single new SQLite DB** workflow you can copy-paste into the `sqlite3` shell. It:

1. creates empty tables to receive the 6 dict text files and the two PSV files,
2. imports everything, and
3. **rehydrates** to full-text `voters` and `addresses` tables using the dictionaries (matching your original schemas, with a sane ISO date text for DOB).

> Notes
> • Import uses shell commands (`.mode`, `.separator`, `.import`) alongside SQL, which is standard for SQLite.
> • We keep dictionary **rowid** as the index.
> • Empty strings in the import are normalized to `NULL` where appropriate using `NULLIF(...)`.
> • DOB in compact is `YYYYMMDD` (int); we emit `YYYY-MM-DD` text.

---

## 0) Create a fresh DB and tables to import into

```sqlite
-- Run this in a brand new DB (e.g., sqlite3 store.db)

-- -------------- Dictionary tables --------------
DROP TABLE IF EXISTS dict_firstname;
DROP TABLE IF EXISTS dict_middlename;
DROP TABLE IF EXISTS dict_lastname;
DROP TABLE IF EXISTS dict_city;
DROP TABLE IF EXISTS dict_state;
DROP TABLE IF EXISTS dict_street;

CREATE TABLE dict_firstname (name TEXT);
CREATE TABLE dict_middlename (name TEXT);
CREATE TABLE dict_lastname  (name TEXT);
CREATE TABLE dict_city      (name TEXT);
CREATE TABLE dict_state     (name TEXT);
CREATE TABLE dict_street    (name TEXT);

-- -------------- Compact import tables --------------
DROP TABLE IF EXISTS voters_compact;
CREATE TABLE voters_compact (
  xid           INTEGER,
  lastname_i    INTEGER,
  firstname_i   INTEGER,
  middlename_i  INTEGER,
  VOTERID       INTEGER,
  PARTY         TEXT,
  housenumber   TEXT,
  street_i      INTEGER,
  city_i        INTEGER,
  state_i       INTEGER,
  zip           INTEGER,
  DATEOFBIRTH   INTEGER    -- YYYYMMDD as integer; may be NULL
);

DROP TABLE IF EXISTS addresses_compact;
CREATE TABLE addresses_compact (
  housenumber TEXT,
  street_i    INTEGER,
  city_i      INTEGER,
  state_i     INTEGER,
  zip         INTEGER,
  RATING      INTEGER,
  X           INTEGER,     -- microdegrees
  Y           INTEGER      -- microdegrees
);
```

---

## 1) Import the dictionary text files (one string per line)

```sqlite
.mode line         -- ensures .import doesn't try to parse separators for dicts
.separator "\n"

.import dict_firstname.txt dict_firstname
.import dict_middlename.txt dict_middlename
.import dict_lastname.txt  dict_lastname
.import dict_city.txt      dict_city
.import dict_state.txt     dict_state
.import dict_street.txt    dict_street
```

*(Each file is one column; the insert order becomes the dictionary index via `rowid`.)*

---

## 2) Import the PSV compact tables

```sqlite
.mode csv
.separator |

.import voters_compact.psv voters_compact
.import addresses_compact.psv addresses_compact
```

---

## 3) Rehydrate to full text tables

### 3a) Rehydrate **voters** (like your original `voters_shared`)

```sqlite
ATTACH DATABASE 'voters.db' AS dbA;

DROP TABLE IF EXISTS voters;
CREATE TABLE voters (
  xid             INTEGER PRIMARY KEY,     -- keeps original xid
  LASTNAME        TEXT,
  FIRSTNAME       TEXT,
  MIDDLENAME      TEXT,
  VOTERID         TEXT,                    -- original schema used TEXT
  PARTY           TEXT,
  ADDRESS         TEXT,
  CITY            TEXT,
  STATE           TEXT,
  ZIP             INTEGER,
  DATEOFBIRTH     TEXT,                    -- text; we emit ISO 8601 "YYYY-MM-DD"
  REGISTRATIONDATE TEXT                    -- original had it; keep column as NULLs
);

INSERT INTO voters (
  xid, LASTNAME, FIRSTNAME, MIDDLENAME, VOTERID, PARTY,
  ADDRESS, CITY, STATE, ZIP, DATEOFBIRTH, REGISTRATIONDATE
)
SELECT
  vc.xid,
  dln.name  AS LASTNAME,
  dfn.name  AS FIRSTNAME,
  dmn.name  AS MIDDLENAME,
  CAST(vc.VOTERID AS TEXT) AS VOTERID,              -- keep as TEXT to match original
  NULLIF(vc.PARTY,'') AS PARTY,
  -- ADDRESS: housenumber + space + street name (trim to avoid trailing/leading spaces)
  TRIM(
    COALESCE(NULLIF(vc.housenumber,''),'')
    || CASE WHEN NULLIF(vc.housenumber,'') IS NOT NULL AND dstr.name IS NOT NULL THEN ' ' ELSE '' END
    || COALESCE(dstr.name,'')
  ) AS ADDRESS,
  dcity.name  AS CITY,
  dstate.name AS STATE,
  vc.zip      AS ZIP,
  -- Convert YYYYMMDD int -> 'YYYY-MM-DD' text. If null or malformed, result is NULL.
  CASE
    WHEN vc.DATEOFBIRTH IS NOT NULL AND vc.DATEOFBIRTH BETWEEN 10000101 AND 99991231
      THEN substr(CAST(vc.DATEOFBIRTH AS TEXT),1,4) || '-' ||
           substr(CAST(vc.DATEOFBIRTH AS TEXT),5,2) || '-' ||
           substr(CAST(vc.DATEOFBIRTH AS TEXT),7,2)
    ELSE NULL
  END AS DATEOFBIRTH,
  NULL AS REGISTRATIONDATE
FROM voters_compact vc
LEFT JOIN dict_lastname  dln  ON dln.rowid  = vc.lastname_i
LEFT JOIN dict_firstname dfn  ON dfn.rowid  = vc.firstname_i
LEFT JOIN dict_middlename dmn ON dmn.rowid  = vc.middlename_i
LEFT JOIN dict_street    dstr ON dstr.rowid = vc.street_i
LEFT JOIN dict_city      dcity ON dcity.rowid = vc.city_i
LEFT JOIN dict_state     dstate ON dstate.rowid = vc.state_i;
```

### 3b) Rehydrate **addresses** (like your original `address` table)

```sqlite
DROP TABLE IF EXISTS address;
CREATE TABLE address (
  ADDRESS TEXT,
  CITY    TEXT,
  STATE   TEXT,
  ZIP     INTEGER,
  RATING  INTEGER,
  X       REAL,      -- back to degrees
  Y       REAL
);

INSERT INTO address (ADDRESS, CITY, STATE, ZIP, RATING, X, Y)
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
  -- microdegrees back to decimal degrees
  ac.X / 1000000.0 AS X,
  ac.Y / 1000000.0 AS Y
FROM addresses_compact ac
LEFT JOIN dict_street dstr ON dstr.rowid = ac.street_i
LEFT JOIN dict_city   dcity ON dcity.rowid = ac.city_i
LEFT JOIN dict_state  dstate ON dstate.rowid = ac.state_i;
```

---

## 4) (Optional) Post-import hygiene and speed-ups

```sqlite
-- Normalize empty strings to NULLs in voters where it matters (optional)
UPDATE voters
SET MIDDLENAME = NULLIF(MIDDLENAME,''),
    PARTY      = NULLIF(PARTY,'')
WHERE 1;

-- Helpful indexes if you’ll query a lot
CREATE INDEX IF NOT EXISTS idx_voters_last_first ON voters(LASTNAME, FIRSTNAME);
CREATE INDEX IF NOT EXISTS idx_address_city_state ON address(CITY, STATE);
```

---

## 5) Quick sanity checks

```sqlite
-- Counts should match:
SELECT (SELECT COUNT(*) FROM voters_compact) AS compact_rows,
       (SELECT COUNT(*) FROM voters)         AS rehydrated_rows;

SELECT (SELECT COUNT(*) FROM addresses_compact) AS compact_addr_rows,
       (SELECT COUNT(*) FROM address)           AS rehydrated_addr_rows;

-- Spot check a few joins
SELECT * FROM voters LIMIT 5;
SELECT * FROM address LIMIT 5;
```

That’s it—you’ll be able to round-trip from your PSV + dict text bundle back to full readable tables without protobuf in the loop.

