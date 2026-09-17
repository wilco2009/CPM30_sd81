@echo off
REM ---------------------------------------------------------------
REM  build_nettime.bat - ensambla NETTIME.COM, la medida de comandos
REM  MCU por segundo. Mismo patron que build_term.bat.
REM ---------------------------------------------------------------

zmac --od . --oo cim,lst nettime.z80
if errorlevel 1 (echo [ERROR] nettime.z80 & exit /b 1)
copy /y nettime.cim NETTIME.COM >nul

echo [OK] NETTIME.COM
