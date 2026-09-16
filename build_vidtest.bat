@echo off
zmac --od . --oo cim,lst vidtest.z80
if errorlevel 1 (echo [ERROR] vidtest.z80 & exit /b 1)
copy /y vidtest.cim vidtest.bin >nul
echo [OK] vidtest.bin
