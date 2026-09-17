@echo off
REM ---------------------------------------------------------------
REM  build_termd.bat - ensambla TERMD.COM, el terminal experimental
REM  que habla con el MCU directamente. Ver la cabecera de termd.z80.
REM ---------------------------------------------------------------

zmac --od . --oo cim,lst termd.z80
if errorlevel 1 (echo [ERROR] termd.z80 & exit /b 1)
copy /y termd.cim TERMD.COM >nul

echo [OK] TERMD.COM
