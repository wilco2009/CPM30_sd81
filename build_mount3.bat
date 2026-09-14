@echo off
REM ---------------------------------------------------------------
REM  build_mount3.bat - ensambla MOUNT3.COM (version CP/M 3)
REM  Requiere: zmac en el PATH.
REM
REM  El original para CP/M 2.2 sigue en CPM_SD81\mount.asm y no se toca.
REM  Lo que cambia aqui es DISKHANDLE ($E018 -> $F8FC): ver la cabecera
REM  de mount3.asm.
REM ---------------------------------------------------------------

zmac --od . --oo cim,lst mount3.asm
if errorlevel 1 (echo [ERROR] mount3.asm & exit /b 1)
copy /y mount3.cim MOUNT3.COM >nul

echo [OK] MOUNT3.COM
