# Different attempts of compacting the Oklahoma voter data and rehydrating it. 

For archival, the best result is to use the dictionary compression, dump voters and addresses to text.  This compressed the entire state to a 44MB 7-zip file.  Making a protobuf slightly reduced the file, but was much more complex.

For a usable database, a flat database was around 243MB. (70MB compressed) Zstd extension made a 436MB file, the keys are too small.  It might work better with a VFS compression that compresses entire pages.  Rehydrating from the 7-ziped text files is fairly quick.

It is possible there is a scenario where using the dictionary in some other way will yield a better result for a running database.

Files:
* 2022-Geocoded-OK-Voter-Dictionary-Compressed.7z - 7zip of OK voter data, addresses table, and dictionaries from 2022.
* import.sql - import the contents of the 7z into a new database.  (sqite3, then paste into console)
* import-dictionary-readonly.sql - import the contents of the 7z into a new database, but use views to extract data from dictionaries on the fly.
* import-dictionary-rw.sql - import the contents of the 7z into a new database, but use views to extract data from dictionaries on the fly.  There are triggers so editing the contents of the voter_v and address_v views will update dictionaries correctly.
* sqlite-zstd-on-flat-db.sql - use Zstd extension to assist compression, but this worked poorly for this data.
* ok-process.md - code to make and use dictionaries.

Quick start:
* extract 7z archive.
* sqlite3 < import.sql

# Import and create an OK voter data for the demo-walker
* Extract `2022-Geocoded-OK-Voter-Dictionary-Compressed.7z` to a 'temp' subdirectory in the OK-roads directory.
* Run `sqlite3` in the directory that has the extracted contents of the 7-zip, paste the contents of `import.sql` into the console window.  A new database will be created (filename can be changed in ATTACH line in import.sql if needed)
* Produces voter_new.db, which contains address and voter table.

## Add the roads
You can use `..\OK-roads\Oklahoma-Roads-Only-20240916.pbf` as a source for road data.  Convert it to local_roads.db and import it into the database by doing the following:
```
REM (in the OK-2022-Preprocessed directory)
set S_OSMNET_EXE=C:\local\git-sys\dot-files\windows\wbin\spatialite_osm_net.exe
set OUT_PBF=..\OK-roads\Oklahoma-Roads-Only-20240916.pbf
%S_OSMNET_EXE% -o %OUT_PBF% -d local_roads.db -T roads -jo
```

If you need to create it from Oklahoma-latest.osm.pbf from Geofabrik download server, use these steps instead:
```
set OSMIUM_EXE=C:\local\git\OK_Mini\osmium_1.16.0_win64\osmium.exe
set S_OSMNET_EXE=C:\local\git-sys\dot-files\windows\wbin\spatialite_osm_net.exe
set IN_PBF=oklahoma-latest.osm.pbf
set OUT_PBF=Oklahoma-Roads-Only-20240916.pbf
%OSMIUM_EXE% tags-filter %IN_PBF% -o %OUT_PBF% w/highway!=bus_guideway,path,cycleway,footway,byway,steps,service,bridleway,construction,proposed,motorway,motorway_link
%S_OSMNET_EXE% -o %OUT_PBF% -d local_roads.db -T roads -jo
```

Then run sptaialite in the OK-roads directory to copy the roads into voters_new.db (adjust the attach paths if needed).  This needs to be done in spatialite to do the conversions, but we don't need spatialite to make geospatial metadata tables in the database for the application.
```
ATTACH DATABASE 'local_roads.db' AS roads;
ATTACH DATABASE 'temp\voters_new.db' AS app;
CREATE TABLE app.roads (
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
INSERT INTO app.roads (id, osm_id, class, node_from, node_to, oneway_fromto, oneway_tofrom, length, cost, twkb) SELECT id, osm_id, class, node_from, node_to, oneway_fromto, oneway_tofrom, length, cost, AsTWKB(geometry, 5) FROM roads.roads;
CREATE TABLE app.roads_nodesxy (node_id INTEGER NOT NULL PRIMARY KEY, osm_id INTEGER, cardinality INTEGER NOT NULL, X FLOAT, Y FLOAT);
INSERT INTO app.roads_nodesxy (node_id, osm_id, cardinality, X, Y) SELECT node_id, osm_id, cardinality, ST_X( geometry), ST_Y (geometry) FROM roads.roads_nodes;
```
Roads_nodesxy is only used for diagnostics if you open it in a GIS program.  If you are going to do diagnostics, you can also add the requisite geospatial metadata to the database with spatialite.  Note this will significantly enlarge the database, and should not be used for production.

Run `spatialite voters_new.db`.
```
SELECT InitSpatialMetadata();
SELECT AddGeometryColumn('address', 'g', 4269, 'POINT');
UPDATE address SET g = MakePoint(x, y);
```
## Making a new database with a subset of data - by city
First dump the table headers
```cmd
sqlite3 temp\voters_new.db "SELECT sql || ';' FROM sqlite_master WHERE type='table' AND name IN ('voters','address','roads');" > schema.sql

sqlite3 norman.db < schema.sql
sqlite3 norman.db "ATTACH DATABASE 'temp\\voters_new.db' AS dbA; INSERT INTO address SELECT * FROM dbA.address WHERE CITY IN ('NORMAN', 'MOORE');"
sqlite3 norman.db "ATTACH DATABASE 'temp\\voters_new.db' AS dbA; INSERT INTO voters SELECT * FROM dbA.voters WHERE CITY IN ('NORMAN', 'MOORE');"
spatialite norman.db "ATTACH DATABASE 'temp\\voters_new.db' AS dbA; INSERT INTO roads SELECT * FROM dbA.roads AS r WHERE MBRIntersects(  GeomFromTWKB(r.twkb),  BuildMBR(    (SELECT MIN(X) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),    (SELECT MIN(Y) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),    (SELECT MAX(X) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),    (SELECT MAX(Y) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),    4326  ));";
sqlite3 norman.db "ALTER TABLE ROADS ADD COLUMN NAME TEXT; UPDATE ROADS SET NAME = '';"
```

Or running it in the console after creating a database by piping in the schema:
`spatialite` 
sqlite3 norman2.db < schema.sql
```
CREATE TABLE cities (name TEXT);
INSERT INTO cities (name) VALUES ('NORMAN'),('MOORE');

ATTACH DATABASE 'norman2.db' AS dbB;
ATTACH DATABASE 'temp\\voters_new.db' AS dbA;
INSERT INTO dbB.address SELECT * FROM dbA.address WHERE CITY IN (SELECT name FROM CITIES);
INSERT INTO dbB.voters SELECT * FROM dbA.voters WHERE CITY IN ('NORMAN', 'MOORE');

SELECT MIN(X), MIN(Y), MAX(X), MAX(Y) FROM (SELECT * FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0);
-- dynamic bbox from ADDRESS (ignoring X/Y = 0.0)
INSERT INTO dbB.roads
SELECT *
FROM dbA.roads AS r
WHERE MBRIntersects(
  GeomFromTWKB( r.twkb ),
  BuildMBR(
    (SELECT MIN(X) FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MIN(Y) FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MAX(X) FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MAX(Y) FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0),
    4326
  )
);
```

## Geopsatial version
Create the schema:
```
sqlite3 beaver_texas.db < schema.sql
```
Then run `spatialite`.
```
--sqlite3 beaver_texas.db < schema.sql
CREATE TABLE geos (ID INTEGER PRIMARY KEY AUTOINCREMENT, NAME TEXT);
SELECT AddGeometryColumn('geos', 'g', 4269, 'GEOMETRY');
.loadshp 'C:\gisdata\www2.census.gov\geo\tiger\TIGER_RD18\LAYER\tl_rd22_us_county\tl_rd22_us_county' county UTF-8 4269 g

INSERT INTO geos (g) SELECT g FROM county WHERE statefp = 40 AND name IN ('Beaver', 'Texas');
ATTACH DATABASE 'beaver_texas.db' AS dbB;
ATTACH DATABASE 'temp\\voters_new.db' AS dbA;
CREATE TABLE address_temp AS SELECT * FROM dbA.address WHERE 
    X > (SELECT Min( MbrMinX( g ) ) FROM geos)
AND X < (SELECT Max( MbrMaxX( g ) ) FROM geos)
AND Y > (SELECT Min( MbrMinY( g ) ) FROM geos)
AND Y < (SELECT Max( MbrMaxY( g ) ) FROM geos);
SELECT AddGeometryColumn('address_temp', 'g', 4269, 'POINT');
UPDATE address_temp SET g = MakePoint( X, Y, 4269);
--select count(*) from address_temp where ST_Intersects( g, (Select st_Union(g) FROM geos) );
--Insert into address_temp (Address, City, State, Zip, Rating, X, Y) SELECT Address, City, State, Zip, Rating, X, Y FROM dbA.Address where CITY = 'TULSA';

--SELECT * FROM dbA.address WHERE ST_CONTAINS( MakePoint(X, Y), Envelope( (SELECT g FROM geos WHERE ID = 1))) LIMIT 1;
--SELECT count(*) FROM dbA.address WHERE ST_CONTAINS( (SELECT g FROM geos WHERE ROWID = 0), MakePoint(X, Y, 4269));

INSERT INTO dbB.address (Address, City, State, Zip, Rating, X, Y) SELECT Address, City, State, Zip, Rating, X, Y FROM address_temp WHERE ST_Intersects( g, (SELECT ST_UNION(g) FROM geos) );
CREATE TABLE voter_temp AS SELECT * FROM dBA.voters WHERE CITY IN (SELECT DISTINCT CITY FROM dbB.address) AND STATE IN (SELECT DISTINCT STATE FROM dbB.address);
INSERT INTO dbB.voters (LASTNAME,FIRSTNAME,MIDDLENAME,VOTERID,PARTY,ADDRESS,CITY,STATE,ZIP,DATEOFBIRTH,REGISTRATIONDATE) SELECT v.LASTNAME,v.FIRSTNAME,v.MIDDLENAME,v.VOTERID,v.PARTY,v.ADDRESS,v.CITY,v.STATE,v.ZIP,v.DATEOFBIRTH,v.REGISTRATIONDATE FROM voter_temp as v, dbB.address as a WHERE a.city = v.city AND a.state = v.state AND a.address = v.address;

SELECT MIN(X), MIN(Y), MAX(X), MAX(Y) FROM (SELECT * FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0);
-- dynamic bbox from ADDRESS (ignoring X/Y = 0.0)
INSERT INTO dbB.roads
SELECT *
FROM dbA.roads AS r
WHERE MBRIntersects(
  GeomFromTWKB( r.twkb ),
  BuildMBR(
    (SELECT MIN(X) FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MIN(Y) FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MAX(X) FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MAX(Y) FROM dbB.ADDRESS WHERE X != 0.0 AND Y != 0.0),
    4326
  )
);
ALTER TABLE ROADS ADD COLUMN NAME TEXT; UPDATE ROADS SET NAME = '';
```

## Diagnostics: add geometry columns to view database in GIS
`spatialite norman.db`.  Note this will significantly enlarge the database.
```
SELECT InitSpatialMetadata();
SELECT AddGeometryColumn('address', 'g', 4326, 'POINT');
UPDATE address set g = MakePoint(X, Y, 4326);
SELECT AddGeometryColumn('roads', 'g', 4326, 'GEOMETRY');
UPDATE roads set g = GeomFromTWKB(twkb, 4326);
```
Debug the MBR:
```
CREATE TABLE IF NOT EXISTS mbr1 (ID INTEGER PRIMARY KEY AUTOINCREMENT);
--SELECT DiscardGeometryColumn('mbr1', 'g');
--SELECT RecoverGeometryColumn('mbr1', 'g', 4269, 'POLYGON');
SELECT AddGeometryColumn('mbr1', 'g', 4269, 'POINT');
INSERT INTO mbr1 (g) VALUES ( BuildMBR(
    (SELECT MIN(X) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MIN(Y) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MAX(X) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MAX(Y) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),
    4269) );
SELECT count(*) FROM roads WHERE MBRIntersects( GeomFromTwkb(twkb) , (SELECT g FROM mbr1 LIMIT 1)); 
```
```
SELECT DiscardGeometryColumn('roads', 'g');
DROP TABLE roads;
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
```

## Delete data outside of a geography
spatialite
```
ATTACH DATABASE 'norman.db' AS dbB;
ATTACH DATABASE 'temp\voters_new.db' AS dbA;
.loadshp 'C:\gisdata\www2.census.gov\geo\tiger\TIGER_RD18\LAYER\tl_rd22_us_county\tl_rd22_us_county' county UTF-8 4269 g

DELETE FROM roads WHERE 
```
## Making a new database with a subset of data - by geography

spatialite
```
ATTACH DATABASE 'norman.db' AS dbB;
ATTACH DATABASE 'temp\voters_new.db' AS dbA;
.loadshp 'C:\gisdata\www2.census.gov\geo\tiger\TIGER_RD18\LAYER\tl_rd22_us_county\tl_rd22_us_county' county UTF-8 4269 g
--SELECT sql FROM dbA.sqlite_master WHERE type='table' AND name IN ('voters', 'address', 'roads');
--SELECT count(*) FROM ADDRESS WHERE CITY IN ('NORMAN', 'MOORE');


```
.loadshp 'C:\gisdata\www2.census.gov\geo\tiger\TIGER_RD18\LAYER\tl_rd22_us_county\tl_rd22_us_county' county UTF-8 4269 g

# Theory for how to make this server side
* Allow creation/ dropping a database.  Run processing in the background.  (node JS)
* The client should download a fresh geojson dump of the database every so often.  
* The server can use multiple cpus. 
* Sqlite management table with jobs queue, or use something like redis to be reasonable.
* Management page to see jobs in process, that have happened, that are scheduled, and click to view results in viewer.
* Write a handler that just dumps the db into a geojson by invoking sqlite3 command?  And returns it.
* Every so often, update the layer in the client.
* on the admin page, allow jobs control.

TODO: Do something to fix the tall vertical lines.
