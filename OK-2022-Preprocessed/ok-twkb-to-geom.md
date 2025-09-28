Use this to look at a database for the demo in GIS.
```
SELECT InitSpatialMetadata();
SELECT AddGeometryColumn('address', 'g', 4326, 'POINT');
UPDATE address set g = MakePoint(X, Y, 4326);
SELECT AddGeometryColumn('roads', 'g', 4326, 'GEOMETRY');
UPDATE roads set g = GeomFromTWKB(twkb, 4326);
```
