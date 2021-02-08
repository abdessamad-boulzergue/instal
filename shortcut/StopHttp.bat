@echo off

set DIR=
set ServerStuff=%DIR%\home\ServerStuff
call "%ServerStuff%\SetHttp.bat"

set CATALINA_HOME=%TOMCAT_HOME%
set JAVA_HOME=
 IF EXIST "%TOMCAT_HOME%\bin\shutdown.bat" call "%TOMCAT_HOME%\bin\shutdown.bat"
 set JAVA_HOME=%JRE_HOME%

set OP_DIR=%ServerStuff%\Httpd
IF EXIST "%OP_DIR%\httpd\bin\httpd.exe" TASKKILL /F /T /IM httpd.exe /fi "WINDOWTITLE eq APACHE(%ServerStuff%)" 

IF EXIST "%ServerStuff%\StopMysqlServer.bat" start "MYSQL" "%ServerStuff%\StopMysqlServer.bat"
