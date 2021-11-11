set DIR=install_DIR
set PORT=3306
set DB_NAME=apos
set HOST=127.0.0.1
set USER=root
set PWD=@p0s

IF "%PWD%" NEQ "1" IF NOT EXIST "%DIR%\home\database\data\%DB_NAME%" (
"%DIR%\home\database\mysql\bin\mysqladmin" --wait=10 --force --user=root --host=localhost --port=%PORT% create %DB_NAME% 2>NUL
"%DIR%\home\database\mysql\bin\mysql" -h localhost -u root --port=%PORT% -e "GRANT ALL PRIVILEGES ON *.* TO '%USER%'@'%%' IDENTIFIED BY '%PWD%' WITH GRANT OPTION;GRANT ALL PRIVILEGES ON *.* TO '%USER%'@'localhost' IDENTIFIED BY '%PWD%' WITH GRANT OPTION;"
)
