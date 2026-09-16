@echo off
zmac --od . --oo cim,lst vidtest4.z80
if errorlevel 1 (echo [ERROR] vidtest4.z80 & exit /b 1)
copy /y vidtest4.cim vidtest4.bin >nul
echo [OK] vidtest4.bin
