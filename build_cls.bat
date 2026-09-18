@echo off
REM ---------------------------------------------------------------
REM  build_cls.bat - ensambla CLS.COM
REM ---------------------------------------------------------------

zmac --od . --oo cim,lst cls.z80
if errorlevel 1 (echo [ERROR] cls.z80 & exit /b 1)
copy /y cls.cim CLS.COM >nul

echo [OK] CLS.COM
