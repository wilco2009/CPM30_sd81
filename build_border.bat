@echo off
REM ---------------------------------------------------------------
REM  build_border.bat - ensambla BORDER.COM
REM ---------------------------------------------------------------

zmac --od . --oo cim,lst border.z80
if errorlevel 1 (echo [ERROR] border.z80 & exit /b 1)
copy /y border.cim BORDER.COM >nul

echo [OK] BORDER.COM
