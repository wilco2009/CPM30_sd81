@echo off
REM ---------------------------------------------------------------
REM  build_termb.bat - ensambla TERMB.COM, el terminal que llama al
REM  BIOS CONOUT directamente (sin BDOS ni RESBDOS). Ver la cabecera
REM  de termb.z80 -- es el tercer peldano de la escalera TERM/TERMD/TERMB.
REM ---------------------------------------------------------------

zmac --od . --oo cim,lst termb.z80
if errorlevel 1 (echo [ERROR] termb.z80 & exit /b 1)
copy /y termb.cim TERMB.COM >nul

echo [OK] TERMB.COM
