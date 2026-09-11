@echo off
zmac --od . --oo cim,lst system.z80
if errorlevel 1 (echo [ERROR] system.z80 & exit /b 1)
copy /y system.cim system.bin >nul
echo [OK] system.bin
