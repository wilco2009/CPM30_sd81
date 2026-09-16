@echo off
zmac --od . --oo cim,lst vidtest3.z80
if errorlevel 1 (echo [ERROR] vidtest3.z80 & exit /b 1)
copy /y vidtest3.cim vidtest3.bin >nul
echo [OK] vidtest3.bin
