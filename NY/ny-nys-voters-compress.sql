-- 0) Attach DBs
-- In sqlite3 shell: sqlite3
ATTACH DATABASE 'NY_voters.db' AS v;        -- contains table v.V
ATTACH DATABASE 'ny_dict.db'   AS d;        -- will hold dict tables
ATTACH DATABASE 'ny_compact.db' AS c;       -- will hold compressed table

-- 1) Build dictionaries (FIRSTNAME, LASTNAME, MIDDLENAME, RSTREETNAME, RCITY)
-- (Re)create dict tables
DROP TABLE IF EXISTS d.dict_firstname;
DROP TABLE IF EXISTS d.dict_lastname;
DROP TABLE IF EXISTS d.dict_middlename;
DROP TABLE IF EXISTS d.dict_street;   -- from RSTREETNAME
DROP TABLE IF EXISTS d.dict_city;     -- from RCITY

CREATE TABLE d.dict_firstname AS
SELECT TRIM(FIRSTNAME) AS name, COUNT(*) AS c
FROM v.V
WHERE INACT_DATE = 0 AND FIRSTNAME IS NOT NULL AND TRIM(FIRSTNAME) <> ''
GROUP BY name
ORDER BY c DESC;

CREATE TABLE d.dict_lastname AS
SELECT TRIM(LASTNAME) AS name, COUNT(*) AS c
FROM v.V
WHERE INACT_DATE = 0 AND LASTNAME IS NOT NULL AND TRIM(LASTNAME) <> ''
GROUP BY name
ORDER BY c DESC;

CREATE TABLE d.dict_middlename AS
SELECT TRIM(MIDDLENAME) AS name, COUNT(*) AS c
FROM v.V
WHERE INACT_DATE = 0 AND MIDDLENAME IS NOT NULL AND TRIM(MIDDLENAME) <> ''
GROUP BY name
ORDER BY c DESC;

CREATE TABLE d.dict_street AS
SELECT TRIM(RSTREETNAME) AS name, COUNT(*) AS c
FROM v.V
WHERE INACT_DATE = 0 AND RSTREETNAME IS NOT NULL AND TRIM(RSTREETNAME) <> ''
GROUP BY name
ORDER BY c DESC;

CREATE TABLE d.dict_city AS
SELECT TRIM(RCITY) AS name, COUNT(*) AS c
FROM v.V
WHERE INACT_DATE = 0 AND RCITY IS NOT NULL AND TRIM(RCITY) <> ''
GROUP BY name
ORDER BY c DESC;

-- (Optional but helpful) indexes for faster joins
CREATE INDEX IF NOT EXISTS idx_d_fn  ON d.dict_firstname(name);
CREATE INDEX IF NOT EXISTS idx_d_ln  ON d.dict_lastname(name);
CREATE INDEX IF NOT EXISTS idx_d_mn  ON d.dict_middlename(name);
CREATE INDEX IF NOT EXISTS idx_d_st  ON d.dict_street(name);
CREATE INDEX IF NOT EXISTS idx_d_ct  ON d.dict_city(name);

-- 2) Create the dictionary-compressed voter table
DROP TABLE IF EXISTS c.voters_ny_compact;
CREATE TABLE c.voters_ny_compact (
  -- Dictionary-backed fields
  lastname_i     INTEGER,
  firstname_i    INTEGER,
  middlename_i   INTEGER,
  street_i       INTEGER,   -- from RSTREETNAME
  city_i         INTEGER,   -- from RCITY

  -- Keep remaining fields compact but readable
  namesuffix     TEXT,      -- NAMESUFFIX
  raddnumber     TEXT,
  rhalfcode      TEXT,
  rpredirection  TEXT,
  rpostdirection TEXT,
  rapartmenttype TEXT,
  rapartment     TEXT,
  raddrnonstd    TEXT,

  rzip5          INTEGER,
  rzip4          INTEGER,

  dob            INTEGER,   -- already INT (YYYYMMDD typically)
  gender         TEXT,
  party          TEXT,
  otherparty     TEXT,
  countycode     TEXT,
  ed             INTEGER,
  ld             INTEGER,
  towncity       TEXT,
  ward           TEXT,
  cd             INTEGER,
  sd             INTEGER,
  ad             INTEGER,
  lastvoterdate  INTEGER,
  status         TEXT,
  reasoncode     TEXT,
  purge_date     INTEGER,

  sboeid_i       INTEGER     -- INTEGER voter id (SBOEID sans "NY" and leading zeros)
);

-- Populate (ignore rows where INACT_DATE != 0)
INSERT INTO c.voters_ny_compact (
  lastname_i, firstname_i, middlename_i, street_i, city_i,
  namesuffix, raddnumber, rhalfcode, rpredirection, rpostdirection,
  rapartmenttype, rapartment, raddrnonstd,
  rzip5, rzip4,
  dob, gender, party, otherparty, countycode, ed, ld, towncity, ward, cd, sd, ad,
  lastvoterdate, status, reasoncode, purge_date,
  sboeid_i
)
SELECT
  ln.rowid,
  fn.rowid,
  mn.rowid,
  st.rowid,
  ct.rowid,

  v.NAMESUFFIX,
  v.RADDNUMBER, v.RHALFCODE, v.RPREDIRECTION, v.RPOSTDIRECTION,
  v.RAPARTMENTTYPE, v.RAPARTMENT, v.RADDRNONSTD,
  v.RZIP5, v.RZIP4,
  v.DOB, v.GENDER, v.PARTY, v.OTHERPARTY, v.COUNTYCODE, v.ED, v.LD, v.TOWNCITY, v.WARD, v.CD, v.SD, v.AD,
  v.LASTVOTERDATE, v.STATUS, v.REASONCODE, v.PURGE_DATE,

  -- SBOEID -> integer: strip "NY" prefix if present, then ltrim zeros
  CASE
    WHEN v.SBOEID LIKE 'NY%' THEN CAST(LTRIM(SUBSTR(v.SBOEID, 3), '0') AS INTEGER)
    ELSE CAST(LTRIM(v.SBOEID, '0') AS INTEGER)
  END AS sboeid_i
FROM v.V AS v
LEFT JOIN d.dict_lastname   ln ON ln.name = TRIM(v.LASTNAME)
LEFT JOIN d.dict_firstname  fn ON fn.name = TRIM(v.FIRSTNAME)
LEFT JOIN d.dict_middlename mn ON mn.name = TRIM(v.MIDDLENAME)
LEFT JOIN d.dict_street     st ON st.name = TRIM(v.RSTREETNAME)
LEFT JOIN d.dict_city       ct ON ct.name = TRIM(v.RCITY)
WHERE v.INACT_DATE = 0;

-- Create indexes (optional)
CREATE INDEX IF NOT EXISTS idx_c_vny_ln  ON c.voters_ny_compact(lastname_i);
CREATE INDEX IF NOT EXISTS idx_c_vny_fn  ON c.voters_ny_compact(firstname_i);
CREATE INDEX IF NOT EXISTS idx_c_vny_mn  ON c.voters_ny_compact(middlename_i);
CREATE INDEX IF NOT EXISTS idx_c_vny_st  ON c.voters_ny_compact(street_i);
CREATE INDEX IF NOT EXISTS idx_c_vny_ct  ON c.voters_ny_compact(city_i);
CREATE INDEX IF NOT EXISTS idx_c_vny_id  ON c.voters_ny_compact(sboeid_i);

-- 3) Export to pipe-separated values
.mode csv
.separator |

-- Dicts (one column each, in rowid order)
.once dict_firstname.txt
SELECT name FROM d.dict_firstname ORDER BY rowid;

.once dict_lastname.txt
SELECT name FROM d.dict_lastname ORDER BY rowid;

.once dict_middlename.txt
SELECT name FROM d.dict_middlename ORDER BY rowid;

.once dict_street.txt
SELECT name FROM d.dict_street ORDER BY rowid;

.once dict_city.txt
SELECT name FROM d.dict_city ORDER BY rowid;


-- Compact voters (export columns in defined order)
.once voters_ny_compact.psv
SELECT
  lastname_i, firstname_i, middlename_i, street_i, city_i,
  namesuffix, raddnumber, rhalfcode, rpredirection, rpostdirection,
  rapartmenttype, rapartment, raddrnonstd,
  rzip5, rzip4,
  dob, gender, party, otherparty, countycode, ed, ld, towncity, ward, cd, sd, ad,
  lastvoterdate, status, reasoncode, purge_date,
  sboeid_i
FROM c.voters_ny_compact;

.mode list
