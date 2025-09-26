# Initial considerations
* The format of the NY Voter ID (SBOEID) seems to be "NY", some number of zeroes, and then a number.  To confirm this:
```
select substr(sboeid, 0, 3) as s, count(*) as c from v group by s order by c desc;
```
Result:
```
s|c
NY|21473816
|25
20|3
|3
GE|1
```
Perhaps we just ignore anything that doesn't meet that format.  We can also ignore voters that are marked as inactive.
```
select count(*) from v where INACT_DATE = 0;
count(*)
19856144
```
