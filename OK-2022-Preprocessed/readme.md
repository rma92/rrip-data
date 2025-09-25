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

