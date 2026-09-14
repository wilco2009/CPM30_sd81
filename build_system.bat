@echo off
zmac --od . --oo cim,lst system.z80
if errorlevel 1 (echo [ERROR] system.z80 & exit /b 1)
copy /y system.cim system.bin >nul

REM Dos "org" que se solapan NO dan error en zmac: el listado muestra una
REM cosa y el binario tiene otra. checkimg.py compara los dos y lo caza.
REM Ver la cabecera de checkimg.py para el caso que motivo esto.
python checkimg.py
if errorlevel 1 (echo [ERROR] el binario no coincide con el listado & exit /b 1)

echo [OK] system.bin
