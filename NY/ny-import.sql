-- 4) Import (PSV + dicts) into a fresh DB and rehydrate
-- You can do this in a single new DB, e.g. ny_store.db.
-- New DB session, or continue and DETACH/ATTACH as needed
-- We'll create three groups:
--   a) dict tables
--   b) compact table
--   c) rehydrated outputs (materialized + views)

-- a) Dict tables to receive text files
DROP TABLE IF EXISTS dict_firstname;
DROP TABLE IF EXISTS dict_lastname;
DROP TABLE IF EXISTS dict_middlename;
DROP TABLE IF EXISTS dict_street;
DROP TABLE IF EXISTS dict_city;

CREATE TABLE dict_firstname (name TEXT);
CREATE TABLE dict_lastname  (name TEXT);
CREATE TABLE dict_middlename(name TEXT);
CREATE TABLE dict_street    (name TEXT);
CREATE TABLE dict_city      (name TEXT);

.mode csv
.separator "\n"

.import dict_firstname.txt dict_firstname
.import dict_lastname.txt  dict_lastname
.import dict_middlename.txt dict_middlename
.import dict_street.txt    dict_street
.import dict_city.txt      dict_city

-- b) Compact table
DROP TABLE IF EXISTS voters_ny_compact;
CREATE TABLE voters_ny_compact (
  lastname_i     INTEGER,
  firstname_i    INTEGER,
  middlename_i   INTEGER,
  street_i       INTEGER,
  city_i         INTEGER,
  namesuffix     TEXT,
  raddnumber     TEXT,
  rhalfcode      TEXT,
  rpredirection  TEXT,
  rpostdirection TEXT,
  rapartmenttype TEXT,
  rapartment     TEXT,
  raddrnonstd    TEXT,
  rzip5          INTEGER,
  rzip4          INTEGER,
  dob            INTEGER,
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
  sboeid_i       INTEGER
);

.mode csv
.separator "|"
.import voters_ny_compact.psv voters_ny_compact

-- 4.1 Rehydrate into a materialized flat table (close to original V)
DROP TABLE IF EXISTS V_rehydrated;
CREATE TABLE V_rehydrated (
  LASTNAME TEXT,
  FIRSTNAME TEXT,
  MIDDLENAME TEXT,
  NAMESUFFIX TEXT,
  RADDNUMBER TEXT,
  RHALFCODE TEXT,
  RPREDIRECTION TEXT,
  RSTREETNAME TEXT,
  RPOSTDIRECTION TEXT,
  RAPARTMENTTYPE TEXT,
  RAPARTMENT TEXT,
  RADDRNONSTD TEXT,
  RCITY TEXT,
  RZIP5 INT,
  RZIP4 INT,
  DOB INT,
  GENDER TEXT,
  PARTY TEXT,
  OTHERPARTY TEXT,
  COUNTYCODE TEXT,
  ED INT,
  LD INT,
  TOWNCITY TEXT,
  WARD TEXT,
  CD INT,
  SD INT,
  AD INT,
  LASTVOTERDATE INT,
  STATUS TEXT,
  REASONCODE TEXT,
  INACT_DATE INT,          -- always 0 in this rehydration
  PURGE_DATE INT,
  SBOEID TEXT
);

INSERT INTO V_rehydrated
SELECT
  dln.name AS LASTNAME,
  dfn.name AS FIRSTNAME,
  dmn.name AS MIDDLENAME,
  vc.namesuffix,
  vc.raddnumber,
  vc.rhalfcode,
  vc.rpredirection,
  dst.name AS RSTREETNAME,
  vc.rpostdirection,
  vc.rapartmenttype,
  vc.rapartment,
  vc.raddrnonstd,
  dct.name AS RCITY,
  vc.rzip5,
  vc.rzip4,
  vc.dob,
  vc.gender,
  vc.party,
  vc.otherparty,
  vc.countycode,
  vc.ed, vc.ld, vc.towncity, vc.ward, vc.cd, vc.sd, vc.ad,
  vc.lastvoterdate,
  vc.status,
  vc.reasoncode,
  0 AS INACT_DATE,
  vc.purge_date,
  CASE
    WHEN vc.sboeid_i IS NULL THEN NULL
    ELSE 'NY' || CAST(vc.sboeid_i AS TEXT)
  END AS SBOEID
FROM voters_ny_compact vc
LEFT JOIN dict_lastname   dln ON dln.rowid = vc.lastname_i
LEFT JOIN dict_firstname  dfn ON dfn.rowid = vc.firstname_i
LEFT JOIN dict_middlename dmn ON dmn.rowid = vc.middlename_i
LEFT JOIN dict_street     dst ON dst.rowid = vc.street_i
LEFT JOIN dict_city       dct ON dct.rowid = vc.city_i;

-- 4.2 Rehydrate via views (on-the-fly, zero extra storage)
DROP VIEW IF EXISTS V_view;
CREATE VIEW V_view AS
SELECT
  dln.name AS LASTNAME,
  dfn.name AS FIRSTNAME,
  dmn.name AS MIDDLENAME,
  vc.namesuffix AS NAMESUFFIX,
  vc.raddnumber AS RADDNUMBER,
  vc.rhalfcode AS RHALFCODE,
  vc.rpredirection AS RPREDIRECTION,
  dst.name AS RSTREETNAME,
  vc.rpostdirection AS RPOSTDIRECTION,
  vc.rapartmenttype AS RAPARTMENTTYPE,
  vc.rapartment AS RAPARTMENT,
  vc.raddrnonstd AS RADDRNONSTD,
  dct.name AS RCITY,
  vc.rzip5 AS RZIP5,
  vc.rzip4 AS RZIP4,
  vc.dob AS DOB,
  vc.gender AS GENDER,
  vc.party AS PARTY,
  vc.otherparty AS OTHERPARTY,
  vc.countycode AS COUNTYCODE,
  vc.ed AS ED,
  vc.ld AS LD,
  vc.towncity AS TOWNCITY,
  vc.ward AS WARD,
  vc.cd AS CD,
  vc.sd AS SD,
  vc.ad AS AD,
  vc.lastvoterdate AS LASTVOTERDATE,
  vc.status AS STATUS,
  vc.reasoncode AS REASONCODE,
  0 AS INACT_DATE,                   -- filtered already
  vc.purge_date AS PURGE_DATE,
  CASE
    WHEN vc.sboeid_i IS NULL THEN NULL
    ELSE 'NY' || CAST(vc.sboeid_i AS TEXT)
  END AS SBOEID
FROM voters_ny_compact vc
LEFT JOIN dict_lastname   dln ON dln.rowid = vc.lastname_i
LEFT JOIN dict_firstname  dfn ON dfn.rowid = vc.firstname_i
LEFT JOIN dict_middlename dmn ON dmn.rowid = vc.middlename_i
LEFT JOIN dict_street     dst ON dst.rowid = vc.street_i
LEFT JOIN dict_city       dct ON dct.rowid = vc.city_i;

-- Example usage:
-- SELECT * FROM V_view WHERE LASTNAME='SMITH' AND RCITY='BROOKLYN' LIMIT 50;

--Notes / options
--Padding for SBOEID: if you need to restore exact width (e.g., 'NY' + 10 digits), replace the rehydration expression with e.g. 'NY' || printf('%010d', vc.sboeid_i)
-- Strict filtering: we used WHERE v.INACT_DATE = 0. If your file sometimes uses NULL, switch to WHERE COALESCE(v.INACT_DATE,0)=0.

-- Speed: add indexes on voters_ny_compact FK columns (shown above) and on dict_* (name) to keep joins snappy.

-- If you want writable INSTEAD OF triggers on V_view (so inserts/updates split into dict lookups automatically), I can add those too.
