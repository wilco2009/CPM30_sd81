@echo off
zmac --od . --oo cim,lst system.z80
if errorlevel 1 (echo [ERROR] system.z80 & exit /b 1)
copy /y system.cim system.bin >nul

REM Dos "org" que se solapan NO dan error en zmac: el listado muestra una
REM cosa y el binario tiene otra. checkimg.py compara los dos y lo caza.
REM Ver la cabecera de checkimg.py para el caso que motivo esto.
python checkimg.py
if errorlevel 1 (echo [ERROR] el binario no coincide con el listado & exit /b 1)

REM El emulador arranca su propia copia, no esta. Copiarla a mano se
REM olvida, y entonces se prueba un binario viejo creyendo que es el
REM nuevo -- paso una vez y costo un diagnostico entero (se dio por
REM bueno un arreglo que en realidad venia de la version anterior).
set SD81DIR=C:\ClaudeCode\Eightyone2\EightyOne\SD81
if not exist "%SD81DIR%\" (
  echo [AVISO] no existe %SD81DIR% -- system.bin NO copiado al emulador
  echo [OK] system.bin
  exit /b 0
)
copy /y system.bin "%SD81DIR%\system.bin" >nul
if errorlevel 1 (echo [ERROR] no se pudo copiar a %SD81DIR% & exit /b 1)

echo [OK] system.bin ^(y copiado a %SD81DIR%^)
