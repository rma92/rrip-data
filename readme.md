# Repository to hold data and binary assets used by RRIP applications.

## Zpaq compress GIS zips
```
mkdir -p x && for f in *.zip; do unzip -d x "$f"; done && zpaq a archive.zpaq x -method 5 -summary 1
```
