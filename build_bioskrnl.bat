@echo off
zmac -8 --rel --od . --oo rel,lst BIOSKRNL.ASM
if errorlevel 1 (echo [ERROR] BIOSKRNL.ASM & exit /b 1)
echo [OK] BIOSKRNL.rel
