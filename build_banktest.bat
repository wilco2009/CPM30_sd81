@echo off
zmac --od . --oo cim,lst banktest.asm
if errorlevel 1 (echo [ERROR] banktest.asm & exit /b 1)
copy /y banktest.cim banktest.bin >nul
echo [OK] banktest.bin
