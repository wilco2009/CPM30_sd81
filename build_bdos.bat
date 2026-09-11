@echo off
zmac -8 --od . --oo cim,lst BDOS.ASM
if errorlevel 1 (echo [ERROR] BDOS.ASM & exit /b 1)
echo [OK] BDOS.cim
