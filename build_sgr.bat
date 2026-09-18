@echo off
REM ---------------------------------------------------------------
REM  build_sgr.bat - ensambla SGR.COM
REM ---------------------------------------------------------------

zmac --od . --oo cim,lst sgr.z80
if errorlevel 1 (echo [ERROR] sgr.z80 & exit /b 1)
copy /y sgr.cim SGR.COM >nul

echo [OK] SGR.COM
