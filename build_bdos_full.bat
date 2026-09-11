@echo off
zmac -8 --od . --oo cim,lst bdos_full.z80
if errorlevel 1 (echo [ERROR] bdos_full.z80 & exit /b 1)
echo [OK] bdos_full.cim
