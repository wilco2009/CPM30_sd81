@echo off
zmac -8 --od . --oo cim,lst CCP3.ASM
if errorlevel 1 (echo [ERROR] CCP3.ASM & exit /b 1)
echo [OK] CCP3.cim
