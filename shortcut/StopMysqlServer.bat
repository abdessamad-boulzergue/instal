@echo off

set databaseServersPath=

set PORT=3305

@echo on
"%databaseServersPath%\mysql\bin\mysqladmin" --user=root --host=localhost --port=%PORT% shutdown
@echo off

exit
