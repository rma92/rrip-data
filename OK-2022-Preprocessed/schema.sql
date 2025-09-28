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
  DATEOFBIRTH     INTEGER,                    -- text; we emit ISO 8601 "YYYY-MM-DD"
  REGISTRATIONDATE INTEGER                    -- original had it; keep column as NULLs
);
CREATE TABLE address (
  ADDRESS TEXT,
  CITY    TEXT,
  STATE   TEXT,
  ZIP     INTEGER,
  RATING  INTEGER,
  X       REAL,      -- back to degrees
  Y       REAL
);
CREATE TABLE roads (
id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
osm_id INTEGER NOT NULL,
class TEXT NOT NULL,
node_from INTEGER NOT NULL,
node_to INTEGER NOT NULL,
--name TEXT NOT NULL,
oneway_fromto INTEGER NOT NULL,
oneway_tofrom INTEGER NOT NULL,
length DOUBLE NOT NULL,
cost DOUBLE NOT NULL,
twkb BLOB);
