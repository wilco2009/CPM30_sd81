@echo off
zmac --od . --oo cim,lst vidtest6.z80
if errorlevel 1 (echo [ERROR] vidtest6.z80 & exit /b 1)
copy /y vidtest6.cim vidtest6.bin >nul
echo [OK] vidtest6.bin
