Roads for Oklahoma, extracted from oklahoma-latest.osm.pbf

# Make this:
```
set OSMIUM_EXE=C:\local\git\OK_Mini\osmium_1.16.0_win64\osmium.exe
%OSMIUM_EXE% tags-filter %IN_PBF% -o Oklahoma-Roads-Only-20240916.pbf w/highway!=bus_guideway,path,cycleway,footway,byway,steps,service,bridleway,construction,proposed,motorway,motorway_link
```

# Convert this to Sqlite
```
spatialite_osm_net -o Oklahoma-Roads-Only-20240916.pbf -d local_roads.db -T roads -jo
```

# Import the Sqlite as a TWKB into the repository database
This needs to be run in spatialite to use geospatial functions to do the conversion, but we should attach the databases as the databases themselves will not contain native geospatial data and spatialite usually creates 6MB of data for this.
```
ATTACH DATABASE 'local_roads.db' AS roads;
ATTACH DATABASE 'voters_new.db' AS app;
CREATE TABLE app.roadst (
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
INSERT INTO app.roadst (id, osm_id, class, node_from, node_to, oneway_fromto, oneway_tofrom, length, cost, twkb) SELECT id, osm_id, class, node_from, node_to, oneway_fromto, oneway_tofrom, length, cost, AsTWKB(geometry, 5) FROM roads.roads;
CREATE TABLE app.roads_nodesxy (node_id INTEGER NOT NULL PRIMARY KEY, osm_id INTEGER, cardinality INTEGER NOT NULL, X FLOAT, Y FLOAT);
INSERT INTO app.roads_nodesxy (node_id, osm_id, cardinality, X, Y) SELECT node_id, osm_id, cardinality, ST_X( geometry), ST_Y (geometry) FROM roads.roads_nodes;
```
(roads_nodes isn't strictly required as it can be recomputed if needed, however it's a quick way to do a bounding box search while testing things)
