--I have a version of the database that's been fully rehydrated into two tables (voter rolls + the addresses and geocoded coordinates). Write steps to set this up with sqlite_zstd. I put this sqlite_zstd.dll in the directory with the databases, which is where I'm running the shell from.
--This seems to not work well for this.  It made a 250MB file into a 450MB file.
-- Optional but recommended while compressing:
PRAGMA synchronous=OFF;
PRAGMA count_changes=OFF;
--PRAGMA journal_mode=OFF;
PRAGMA journal_mode=WAL;
PRAGMA temp_store=OFF;
PRAGMA auto_vacuum=FULL;         -- so space can be reclaimed on VACUUM
PRAGMA trusted_schema=ON;        -- required in newer sqlite3 shells
PRAGMA busy_timeout = 2000;          -- avoids "database is locked" during maintenance
-- Load the extension (adjust the path if needed)
.load ./sqlite_zstd.dll
--Inspect if text or blob
PRAGMA table_info(voters);
PRAGMA table_info(address);

-- VOTERS
SELECT zstd_enable_transparent('{
  "table": "voters",
  "column": "LASTNAME",
  "compression_level": 19,
  "dict_chooser": "''a''"
}');
SELECT zstd_enable_transparent('{
  "table": "voters",
  "column": "FIRSTNAME",
  "compression_level": 19,
  "dict_chooser": "''a''"
}');
SELECT zstd_enable_transparent('{
  "table": "voters",
  "column": "MIDDLENAME",
  "compression_level": 19,
  "dict_chooser": "''a''"
}');
SELECT zstd_enable_transparent('{
  "table": "voters",
  "column": "VOTERID",
  "compression_level": 19,
  "dict_chooser": "''b''"
}');
SELECT zstd_enable_transparent('{
  "table": "voters",
  "column": "ADDRESS",
  "compression_level": 19,
  "dict_chooser": "''c''"
}');
SELECT zstd_enable_transparent('{
  "table": "voters",
  "column": "CITY",
  "compression_level": 19,
  "dict_chooser": "''d''"
}');

-- Make address table a new one with an id column.
-- 1. Rename the old table
ALTER TABLE dbA.address RENAME TO address_old;

-- 2. Create the new table with an explicit PK
CREATE TABLE dbA.address (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    ADDRESS TEXT,
    CITY    TEXT,
    STATE   TEXT,
    ZIP     INTEGER,
    RATING  INTEGER,
    X       REAL,      -- degrees
    Y       REAL
);

-- 3. Copy data from the old table into the new one
INSERT INTO dbA.address (ADDRESS, CITY, STATE, ZIP, RATING, X, Y)
SELECT ADDRESS, CITY, STATE, ZIP, RATING, X, Y
FROM dbA.address_old;

-- 4. (Optional) Drop the old table once you’re happy with the migration
DROP TABLE dbA.address_old;

-- ADDRESS
SELECT zstd_enable_transparent('{
  "table": "address",
  "column": "ADDRESS",
  "compression_level": 19,
  "dict_chooser": "''c''"
}');
SELECT zstd_enable_transparent('{
  "table": "address",
  "column": "CITY",
  "compression_level": 19,
  "dict_chooser": "''aC''"
}');

SELECT zstd_incremental_maintenance(NULL, 1);  -- run to completion
VACUUM;                                        -- shrink the file

