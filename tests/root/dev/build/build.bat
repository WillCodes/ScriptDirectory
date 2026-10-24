@echo off
:: Build the project
echo build.bat: %*
bash "%~dp0build.sh" %*
exit /b %ERRORLEVEL%
