We will attempt to get ChatGPT to perform an analysis on where to campaign based on election results.

The following data is needed:
* Precinct Results (..\OK-Results)
* Precinct Geometry Well Known Binary (..\OK-Precinct)
* OK Voter Rolls (..\OK-2022-Preprocessed)
    * TODO: Bring in voter history.

For the test, we'll look for close precincts in 2020 for the presidential elelection.
Data prep:
* Extract the archives in each of those directories in this repo.
* Open bash, and grep 20201103_PrecinctResults.csv for "FOR ELECTORS FOR PRESIDENT AND VICE PRESIDENT".
* Make a precinct database with WKB instead of TWKB.
```
OUTCSV1='20201103_president.csv'
head -n 1 "../OK-Results/20201103_PrecinctResults.csv" > "$OUTCSV1"
grep "FOR ELECTORS FOR PRESIDENT AND VICE PRESIDENT" "../OK-Results/20201103_PrecinctResults.csv" >> "$OUTCSV1"
bzip2 -zk --best 20201103_president.csv

cp ../OK-Precinct/OK_precinct_t.db.xz .
xz -d OK_precinct_t.db.xz

spatialite :memory: "BEGIN;
ATTACH DATABASE 'OK_precinct_t.db' AS dbA;
ALTER TABLE dbA.OK_precinct_t ADD COLUMN wkb BLOB;

UPDATE dbA.OK_precinct_t
SET wkb = AsBinary(
      ST_SimplifyPreserveTopology(
        ST_SnapToGrid(
          GeomFromTWKB(t,4326),
          5, 5
        ),
        10
      )
);
UPDATE dbA.OK_precinct_t SET t = NULL;
COMMIT;
VACUUM;"
bzip2 -zk --best OK_precinct_t.db
```
* Upload the voter rolls as is (with address and voter separate):
    * Extract ..\OK-2022-Preprocessed\2022-Geocoded-OK-Voter-Dictionary-Compressed.7z to a temporary directory.
    * run `sqlite3` in that directory.
    * paste the contents of ..\OK-2022-Preprocessed\import.sql into the console.  You end up with a database.  Before closing sqlite3, paste this SQL in to put the coordinates into the voters table:
```sql
-- Speeds the lookup of matching address rows and lets SQLite satisfy X/Y from the index (covering)
CREATE INDEX IF NOT EXISTS idx_address_match_cover
ON address(ADDRESS, CITY, STATE, ZIP, X, Y);

-- Helps if SQLite needs to search voters by the 4-key (e.g., for EXISTS filtering / join planning)
CREATE INDEX IF NOT EXISTS idx_voters_addr_key
ON voters(ADDRESS, CITY, STATE, ZIP);

ALTER TABLE voters ADD COLUMN X REAL;
ALTER TABLE voters ADD COLUMN Y REAL;

BEGIN;
UPDATE voters AS v
SET X = (
      SELECT a.X
      FROM address a
      WHERE a.ADDRESS = v.ADDRESS
        AND a.CITY    = v.CITY
        AND a.STATE   = v.STATE
        AND a.ZIP     = v.ZIP
)
WHERE EXISTS (
      SELECT 1
      FROM address a
      WHERE a.ADDRESS = v.ADDRESS
        AND a.CITY    = v.CITY
        AND a.STATE   = v.STATE
        AND a.ZIP     = v.ZIP
);
UPDATE voters AS v
SET Y = (
      SELECT a.Y
      FROM address a
      WHERE a.ADDRESS = v.ADDRESS
        AND a.CITY    = v.CITY
        AND a.STATE   = v.STATE
        AND a.ZIP     = v.ZIP
)
WHERE EXISTS (
      SELECT 1
      FROM address a
      WHERE a.ADDRESS = v.ADDRESS
        AND a.CITY    = v.CITY
        AND a.STATE   = v.STATE
        AND a.ZIP     = v.ZIP
);
COMMIT;
DROP TABLE address;
VACUUM;
.mode csv
.separator |
.headers on
.once VotersXY.psv
SELECT * FROM VOTERS;
.mode list
```
    * `bzip2 -zk --best VotersXY.psv`
    * This makes a 55.3 MB bz2 file with all voters, or a 34.6 MB zpaq file.

Export only addresses:
```
.mode csv
.separator |
.headers on
.once address.psv
SELECT * FROM ADDRESS;
.mode list
```
`bzip2 -zk --best address.psv` (This makes 11.4 MB bz2 and a  
# Do an OppScore analysis in ChatGPT
* Get all bills from the 119th Congress
* Get all votes from the 119th Congress
* Get oppscore challenge text
* Analyze each bill's text based on how it impacts each oppscore question (although some bills will have no score).  The bill itself will get an Opportunity _Impact_ Score, in each category what would happen if the bill is passed.
* TODO: Weight of bills?
* Start a rolling score for each member, iterate over all the bills.  A vote for will add that bill's score to the member in that category.  A vote against will add -1 * that bill's score to that member's score in that category.  A vote of present or absence will do nothing.  Keep a count of the votes done in each category.
* Divide the total scores in each category by the number of votes in that category.

# Prompt Test 1
I'm working on a political campaign in Oklahoma.  We want to perform targeted campaigning on voters.  I've attached data for the 2020 Presidential election.

Please perform the following tasks:
For each precinct, count the total votes for each candidate.


# Can ChatGPT figure out how to correlate a voter to a precinct using just voter data and the precinct data?
## Prompt 1
--Upload CD01_vr.csv.bz2 and OK_precinct_t.db.bz2.

CD01_vr.csv is voter rolls from Oklahoma's Congressional District 1 as provided by the State. This is a public record available to anyone on the internet. Is it possible to tell which precinct the voters live in? There's no geographic information in CD01_vr.csv, but I have a geocoded list of all the addresses if we need it. 

OK_precinct_t.db is a Sqlite database that contains information provided by the State on various precincts around the state. The state distributes it as a shape file, I archive it for my research as a Sqlite database containing TWKB for geography, but I converted it to WKB for your comprehension if you need to look at the geographies.
## Response 1
Short answer: yes. In fact, your `CD01_vr.csv` already has a **Precinct** code for each voter, and it lines up with the **`precode`** field in `ok_precinct_t` — so you don’t need geocodes just to know a voter’s precinct.

What I did right now:

* Peeked at both files. The voter file has a `Precinct` column (6-digit codes like `190111`). The precinct DB (`ok_precinct_t`) has `precode` (same 6-digit format), plus county/name/legislative-district fields and a `wkb` geometry.
* Performed a direct join on `CD01_vr.csv.Precinct = ok_precinct_t.precode` and produced a lookup for every voter.

Results (quick stats):

* Voters total: **441,992**
* Rows matched to precinct metadata: **337,442** (~76.35%)
* Rows without a match in the precinct table: **104,550** (likely code/version mismatches or precincts outside/updated since the DB snapshot)

You can grab the joined file here:
[Download the joined CSV](sandbox:/mnt/data/voters_with_precinct_lookup.csv)

### Why some rows didn’t match (and how to make it 100%)

* The precinct DB is statewide and looks like a snapshot; a portion of CD01 voter precinct codes aren’t present in its `precode` list (76 of the 294 distinct voter precinct codes in this file). That’s typical when precinct lines/codes change or when the DB snapshot and the roll aren’t the same vintage.
* Two ways to close the gap:

  1. **Use a newer precinct layer** (or the exact vintage that matches the roll) and re-run the same `Precinct ↔ precode` join.
  2. **Point-in-polygon** with your geocoded addresses: convert the lat/lon points to geometry and spatially join to `ok_precinct_t.wkb`. This ignores code text and uses the actual lines.

If you want, send me your geocoded address file (just needs `VoterID`, `lon`, `lat`), and I’ll run the spatial join to produce a 100% authoritative precinct assignment using the polygons you gave me.

## Prompt 2
This file contains the entire state's voters' addresses, mostaly geocoded.  Note this is all CDs, and a few addresses likely failed to geocode.  If the precinct in CD_01.csv is invalid, and the geocode data from address.psv is unavailable, we can ignore that voter.  (The data has some errors, but we just need to be reasonably good, not perfect).

## Response 2 [there was a mistake in the precinct geospatial db]
Got it — thanks for the extra context.

Here’s what I can do with what you’ve shared (and what I’ve already done):

### What’s possible right now

* Your CD01 voter file already carries a **`Precinct`** code per voter. That value directly matches the **`precode`** field in your statewide precinct table (`ok_precinct_t`).
* I’ve produced a joined dataset for **every CD01 voter whose `Precinct` value is valid in the precinct master**. For each, you get the county and legislative districts pulled from `ok_precinct_t`, plus the geocode (X/Y) I merged from `address.psv` for convenience.

### Output

* **Kept (valid code):** 337,446 voters
* **Dropped (invalid code):** 104,550 voters

  * Per your tolerance rule, those are ignored if their `Precinct` in the voter roll doesn’t match the precinct master. (I also tried the geocode fallback, but see note below.)

Download:

* **CD01 voters with precinct resolved (code matches only)**
  [cd01_voters_precinct_resolved.csv](sandbox:/mnt/data/cd01_voters_precinct_resolved.csv)

### Why I didn’t use the geocode fallback (yet)

I planned to do a point-in-polygon fallback for the invalid-code voters using `address.psv` X/Y against polygons in `ok_precinct_t.wkb`. However, the `wkb` column is essentially empty in this snapshot (only ~1 non-null row showed up), so there’s no usable geometry to intersect with. If you can provide:

* the same precinct table with **populated WKB** (or a shapefile/GeoPackage), or
* the original **TWKB** with a quick note on decoding,

…I’ll run the spatial join to recover precincts for most of those 104k invalid-code cases (and still ignore the ones that lack geocodes, as you requested).

### Next steps (you choose)

1. **Accept the “good enough” subset:** use the file above (337k voters), which meets your rule to ignore voters where the precinct code is invalid and geocode fallback isn’t available.
2. **Unlock the geocode fallback:** share a precinct geometry source with actual polygons (WKB/GeoPackage/shapefile). I’ll spatially assign precincts for the invalid-code voters that have X/Y and give you a single, complete output with a `source` flag (`code` vs `geocode`).

If you want me to try decoding TWKB from the `t` column in `ok_precinct_t`, I can take a stab at that too — just say the word.

## Prompt 3
--Upload Ok_precincts.shp.zip from Oklahoma's website.
Sorry about that!  To avoid any mishaps, here's the shapefile as distributed by the state (in 2025 - it is possible the precincts are wrong due to redistricting)

# old notes
Old Spatialite conversion without simplification:
```
spatialite :memory: "BEGIN;
ATTACH DATABASE 'OK_precinct_t.db' AS dbA;
ALTER TABLE dbA.OK_precinct_t ADD COLUMN wkb BLOB;
UPDATE dbA.OK_precinct_t SET wkb = AsBinary(GeomFromTWKB(t));
COMMIT;"
```
