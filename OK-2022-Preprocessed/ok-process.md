# Processing pre-processed 2022 voter roles
I'm working with a sqlite3 database, and am getting ready to convert it to be stored in protobufs.  The data set contains a large quantity of people's names and addresses.  Since those have a lot of repeating components, we will create dictionaries to store numeric indexes into the data.  The dictionaries have already been created, and the format of the tables has been defined.

voter_shared.db contains the following tables, which contain the voter rolls and geocoded addresses:
```
table|voters_shared|voters_shared|2|CREATE TABLE voters_shared (
            xid INTEGER PRIMARY KEY AUTOINCREMENT,
            LASTNAME TEXT,
            FIRSTNAME TEXT,
            MIDDLENAME TEXT,
            VOTERID TEXT,
            PARTY TEXT,
            ADDRESS TEXT,
            CITY TEXT,
            STATE TEXT,
            ZIP INTEGER,
            DATEOFBIRTH TEXT,
            REGISTRATIONDATE TEXT
        )
table|address|address|4|CREATE TABLE address (
            ADDRESS TEXT,
            CITY TEXT,
            STATE TEXT,
            ZIP INTEGER,
            RATING INTEGER,
            X REAL,
            Y REAL
        )
```
I want to store this more efficiently, in protobufs, but use dictionaries to simplify storage of the following fields:
```sqlite3
attach 'voter_shared.db' as db1;
attach 'dict.db' as dbD;
attach 'voter_compact.db' as dbV;
attach 'address_compact.db' as dbA;
```
## Part 1: Create dictionaries, and tables to hold the indexed data
```sqlite3
CREATE TABLE dbD.dict_firstname AS SELECT firstname AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;
CREATE TABLE dbD.dict_middlename AS SELECT middlename AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;
CREATE TABLE dbD.dict_lastname AS SELECT lastname AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;
CREATE TABLE dbD.dict_city AS SELECT lastname AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;
CREATE TABLE dbD.dict_state AS SELECT lastname AS name, COUNT(*) AS C FROM db1.voters_shared GROUP BY NAME ORDER BY C DESC;

CREATE TABLE dict_street AS
SELECT 
    substr(address, instr(address, ' ') + 1) AS street_name,
    COUNT(*) AS freq
FROM address
GROUP BY street_name
ORDER BY freq DESC;

--VoterID is an integer in Oklahoma
--Zip is an integer in the USA
--Can we convert the date to something more useful
--Convert date to ISO 8601 integer.
--Registration date is missing from the dataset, so we won't store it.
--house number is text as it sometimes contains a letter.  Profiling may suggest we index them, but this is too much effort and only makes sense if the dictionary creation is entirely automatic as the data is small.
--split street and house number to use dict_street above.
CREATE TABLE dbV.voter (
            xid INTEGER PRIMARY KEY AUTOINCREMENT,
            lastname_i INTEGER,
            firstname_i INTEGER,
            middlename_i INTEGER,
            VOTERID INTEGER,
            PARTY TEXT,
            housenumber TEXT,
            street_i INTEGER,
            city_i INTEGER,
            state_i INTEGER,
            zip INTEGER,
            DATEOFBIRTH INTEGER
        );
--split street and house number to use dict_street above.
--5 decimal places = 0.00001 deg = 1.11 meter = individual trees, houses = Multiply by 100,000
--6 decimal places = 0.000001 deg = 0.11 meter/10 cm = individual human = Multiply by 1,000,000.  This still fits in a 32-bit integer.
--X and Y are REAL lat and lon.  Multiply it by 1 Million and CAST AS INTEGER.
CREATE TABLE dbA.address (
            housenumber TEXT,
            street_i INTEGER,
            city_i INTEGER,
            state_i INTEGER,
            zip INTEGER,
            RATING INTEGER,
            X INTEGER,
            Y INTEGER
        );
```
Please write the necessary SQL statements to populate the table.
