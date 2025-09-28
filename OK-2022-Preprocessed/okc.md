-- sqlite3 okc.db < schema.sql
-- spatialite
CREATE TABLE geos (ID INTEGER PRIMARY KEY AUTOINCREMENT, NAME TEXT);
SELECT AddGeometryColumn('geos', 'g', 4269, 'GEOMETRY');
.loadshp 'C:\gisdata\www2.census.gov\geo\tiger\TIGER_RD18\LAYER\tl_rd22_us_county\tl_rd22_us_county' county UTF-8 4269 g

INSERT INTO geos (g) SELECT g FROM county WHERE statefp = 40 AND name IN ('Oklahoma');
ATTACH DATABASE 'okc.db' AS dbB;
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

