@echo off
zmac --od . --oo cim,lst blktest.z80
if errorlevel 1 (echo [ERROR] blktest.z80 & exit /b 1)
copy /y blktest.cim blktest.bin >nul
echo [OK] blktest.bin
