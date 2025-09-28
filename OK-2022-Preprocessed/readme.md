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
sqlite3 norman.db "ALTER TABLE ROADS ADD COLUMN NAME TEXT; UPDATE ROADS SET NAME = '';"
spatialite norman.db "ATTACH DATABASE 'temp\\voters_new.db' AS dbA; INSERT INTO roads SELECT * FROM dbA.roads AS r WHERE MBRIntersects(  r.twkb,  BuildMBR(    (SELECT MIN(X) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),    (SELECT MIN(Y) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),    (SELECT MAX(X) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),    (SELECT MAX(Y) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),    4326  ));";
```

Just the spatialite step:
```
ATTACH DATABASE 'temp\\voters_new.db' AS dbA;
SELECT MIN(X), MIN(Y), MAX(X), MAX(Y) FROM (SELECT * FROM ADDRESS WHERE X != 0.0 AND Y != 0.0);
-- dynamic bbox from ADDRESS (ignoring X/Y = 0.0)
INSERT INTO roads
SELECT *
FROM dbA.roads AS r
WHERE MBRIntersects(
  r.twkb,
  BuildMBR(
    (SELECT MIN(X) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MIN(Y) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MAX(X) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),
    (SELECT MAX(Y) FROM ADDRESS WHERE X != 0.0 AND Y != 0.0),
    4326
  )
);
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
