-- extract the 7z, run sqlite CLI and use this.
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

-- Import the dictionary text files (one string per file)
.mode line         -- ensures .import doesn't try to parse separators for dicts
--.separator "\n"

.import dict_firstname.txt dict_firstname
.import dict_middlename.txt dict_middlename
.import dict_lastname.txt  dict_lastname
.import dict_city.txt      dict_city
.import dict_state.txt     dict_state
.import dict_street.txt    dict_street

-- Import the PSV compact tables
.mode csv
.separator |

.import voters_compact.psv voters_compact
.import addresses_compact.psv addresses_compact

-- Rehydrate full text tables in attached db.
ATTACH DATABASE 'voters_new.db' AS dbA;

-- Rehydrate Voters
DROP TABLE IF EXISTS dbA.voters;
CREATE TABLE dbA.voters (
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

INSERT INTO dbA.voters (
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

-- Rehydrate Addresses

DROP TABLE IF EXISTS dbA.address;
CREATE TABLE dbA.address (
  ADDRESS TEXT,
  CITY    TEXT,
  STATE   TEXT,
  ZIP     INTEGER,
  RATING  INTEGER,
  X       REAL,      -- back to degrees
  Y       REAL
);

INSERT INTO dbA.address (ADDRESS, CITY, STATE, ZIP, RATING, X, Y)
SELECT
  TRIM(
    REPLACE(
      COALESCE(NULLIF(ac.housenumber,''),'')
      || CASE WHEN NULLIF(ac.housenumber,'') IS NOT NULL AND dstr.name IS NOT NULL THEN ' ' ELSE '' END
      || COALESCE(dstr.name,'')
    ,'"','')
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
