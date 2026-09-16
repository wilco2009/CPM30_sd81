@echo off
zmac --od . --oo cim,lst vidtest7.z80
if errorlevel 1 (echo [ERROR] vidtest7.z80 & exit /b 1)
copy /y vidtest7.cim vidtest7.bin >nul
echo [OK] vidtest7.bin
