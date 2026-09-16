@echo off
zmac --od . --oo cim,lst vidtest5.z80
if errorlevel 1 (echo [ERROR] vidtest5.z80 & exit /b 1)
copy /y vidtest5.cim vidtest5.bin >nul
echo [OK] vidtest5.bin
