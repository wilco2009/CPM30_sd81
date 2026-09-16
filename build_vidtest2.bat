@echo off
zmac --od . --oo cim,lst vidtest2.z80
if errorlevel 1 (echo [ERROR] vidtest2.z80 & exit /b 1)
copy /y vidtest2.cim vidtest2.bin >nul
echo [OK] vidtest2.bin
