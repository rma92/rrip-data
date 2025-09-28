# Oklahoma Precinct Data

## Make this from OK_precincts.zip/shp from the OK gov website
* Extract the zip.
* spatialite
```sqlite
.loadshp "S:\\voter\\Ok_Precincts" ok_precinct UTF-8 2267
ATTACH DATABASE 'OK_precinct_t' AS t;
CREATE TABLE t.Ok_precinct_T AS
SELECT
  "pk_uid",
  "precinct",
  "county",
  "cntyname",
  "cntyfips",
  "precode",
  "ag18d",
  "ag18r",
  "aud18l",
  "aud18r",
  "gov18d",
  "gov18r",
  "lg18d",
  "lg18r",
  "tre18i",
  "tre18r",
  "ush18d",
  "ush18r",
  "totpop",
  "nh_white",
  "nh_black",
  "nh_amin",
  "nh_asian",
  "nh_nhpi",
  "nh_other",
  "nh_2more",
  "hisp",
  "h_white",
  "h_black",
  "h_amin",
  "h_asian",
  "h_nhpi",
  "h_other",
  "h_2more",
  "vap",
  "hvap",
  "wvap",
  "bvap",
  "aminvap",
  "asianvap",
  "nhpivap",
  "othervap",
  "2morevap",
  "cd",
  "send",
  "hdist",
  AsTWKB( Transform( SetSRID("geometry", 2267), 4326 ), 6 ) AS "t"
FROM "ok_precinct";
```
## Make a WKB verison (for ChatGPT)
Spatialite
```
ATTACH DATABASE 'OK_precinct_t-wkb.db' AS dbA;
ALTER TABLE dbA.OK_precinct_t ADD wkb text;
UPDATE dbA.OK_precinct_t SET wkb = AsBinary(GeomFromTWKB(t));
```
Make a Bzip2 to upload to ChatGPT.
## Make a GeoJSON verison (for ChatGPT)
Spatialite
```
ATTACH DATABASE 'OK_precinct_t-gj.db' AS dbA;
ALTER TABLE dbA.OK_precinct_t ADD gj text;
UPDATE dbA.OK_precinct_t SET gj = AsGeoJSON(GeomFromTWKB(t));
```
