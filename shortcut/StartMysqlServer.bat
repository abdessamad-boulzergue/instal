@echo off

set databaseServersPath=
@echo on
"%databaseServersPath%\mysql\bin\mysqld" --defaults-file="%databaseServersPath%\mysql\apos.opt"
@echo off

exit
