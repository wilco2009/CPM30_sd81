@echo off
zmac -8 --od . --oo cim,lst CCP3.ASM
if errorlevel 1 (echo [ERROR] CCP3.ASM & exit /b 1)

REM ccp_image.z80 lleva los bytes de CCP3.cim y su tamano en dos equates.
REM Se rehacian a mano; ahora lo hace el script (y avisa si la imagen
REM desborda $C800, donde empiezan los ALV).
python mkccpimg.py
if errorlevel 1 (echo [ERROR] mkccpimg.py & exit /b 1)
echo [OK] CCP3.cim + ccp_image.z80
