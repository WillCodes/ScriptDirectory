@echo off
:: TODO: describe this script
setlocal

:: Windows-specific setup goes here.

bash "%~dp0<name>.sh" %*
exit /b %ERRORLEVEL%
