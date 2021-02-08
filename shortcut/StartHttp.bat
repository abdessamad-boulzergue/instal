@echo off


set DIR=
set ServerStuff=%DIR%\home\ServerStuff
call "%ServerStuff%\SetHttp.bat"
echo %DIR%
set OP_DIR=%DIR%\Httpd

rem IF EXIST "%OP_DIR%\httpd\bin\httpd.exe" start "APACHE(%DIR%)" /MIN  "%HTTPD_HOME%/bin/httpd" -DWIN -f "%HTTPD_HOME%/conf/httpd.conf"

IF EXIST "%ServerStuff%\StartMysqlServer.bat" start /min "MYSQL" "%ServerStuff%\StartMysqlServer.bat"

set CATALINA_HOME=%TOMCAT_HOME%
IF EXIST "%TOMCAT_HOME%\bin\startup.bat" call "%TOMCAT_HOME%\bin\startup.bat"


