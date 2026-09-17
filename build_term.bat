@echo off
REM ---------------------------------------------------------------
REM  build_term.bat - ensambla TERM.COM, el terminal de AUX:
REM  Mismo patron que build_mount3.bat.
REM ---------------------------------------------------------------

zmac --od . --oo cim,lst term.z80
if errorlevel 1 (echo [ERROR] term.z80 & exit /b 1)
copy /y term.cim TERM.COM >nul

echo [OK] TERM.COM
