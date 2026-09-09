@echo off
REM ===========================================================================
REM flash_dualboot.bat - Ein-Klick-Flash des fertigen Dual-Boot-Images
REM                      (Flipper Port ota_0 + Bruce ota_1, 8 MB Cardputer)
REM
REM Nutzung:
REM   flash_dualboot.bat              - Port COM3 (Standard)
REM   flash_dualboot.bat COM7         - Port explizit
REM
REM Voraussetzung: esptool (pip install esptool)
REM ===========================================================================
cd /d "%~dp0"

set PORT=%1
if "%PORT%"=="" set PORT=COM3

if not exist cardputer_dualboot_8mb_merged.bin (
    echo [ERROR] cardputer_dualboot_8mb_merged.bin fehlt in diesem Ordner
    exit /b 1
)

echo ==^> Flashe Dual-Boot (Flipper ota_0 + Bruce ota_1) auf %PORT%
echo     (loescht den gesamten Flash -- otadata blank =^> Boot in Flipper)

esptool.py --chip esp32s3 --port %PORT% --baud 460800 ^
    --before default_reset --after hard_reset ^
    write_flash --erase-all --flash_mode keep 0x0 cardputer_dualboot_8mb_merged.bin

if errorlevel 1 (
    echo [ERROR] Flashen fehlgeschlagen. Port pruefen: Geräte-Manager -^> Anschluesse (COM amp; LPT^)
    exit /b 1
)

echo.
echo ==^> Fertig! Das Geraet bootet jetzt in den Flipper Port.
echo     Wechsel Flipper-^>Bruce: Lock-Menue -^> Switch to Bruce
echo     Wechsel Bruce-^>Flipper: Config -^> Switch to Flipper Port
pause