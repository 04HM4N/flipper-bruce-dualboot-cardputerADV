#!/usr/bin/env bash
# =============================================================================
# flash_dualboot.sh — Ein-Klick-Flash des fertigen Dual-Boot-Images
#                     (Flipper Port ota_0 + Bruce ota_1, 8 MB Cardputer)
#
# Nutzung:
#   ./flash_dualboot.sh                 # Port automatisch finden
#   ./flash_dualboot.sh /dev/ttyACM0    # Port explizit
#   PORT=/dev/ttyACM0 ./flash_dualboot.sh
#
# Voraussetzung: esptool (pip install esptool) ODER ESP-IDF (export.sh)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

PORT="${1:-${PORT:-}}"
if [[ -z "${PORT}" ]]; then
    shopt -s nullglob
    ports=(/dev/ttyACM* /dev/ttyUSB* /dev/cu.usbmodem* /dev/cu.usbserial*)
    shopt -u nullglob
    if [[ ${#ports[@]} -eq 0 ]]; then
        echo "[ERROR] Kein serieller Port gefunden. Cardputer per USB-C verbinden." >&2
        exit 1
    fi
    PORT="${ports[0]}"
fi

ESPTOOL=""
if command -v esptool >/dev/null 2>&1; then ESPTOOL="esptool"
elif command -v esptool.py >/dev/null 2>&1; then ESPTOOL="esptool.py"
elif [[ -f "${HOME}/esp/esp-idf/components/esptool_py/esptool/esptool.py" ]]; then
    ESPTOOL="python3 ${HOME}/esp/esp-idf/components/esptool_py/esptool/esptool.py"
else
    echo "[ERROR] esptool nicht gefunden (pip install esptool)" >&2
    exit 1
fi

IMG="$(ls cardputer_dualboot_*_merged.bin 2>/dev/null | head -1 || true)"
[[ -n "${IMG}" && -f "${IMG}" ]] || { echo "[ERROR] Keine cardputer_dualboot_*_merged.bin in diesem Ordner" >&2; exit 1; }

echo "==> Flashe Dual-Boot (Flipper ota_0 + Bruce ota_1) auf ${PORT}"
echo "    (loescht den gesamten Flash -- otadata blank => Boot in Flipper)"
$ESPTOOL --chip esp32s3 --port "${PORT}" --baud 460800 \
    --before default_reset --after hard_reset \
    write_flash --erase-all --flash_mode keep 0x0 "${IMG}"

echo ""
echo "==> Fertig! Das Geraet bootet jetzt in den Flipper Port."
echo "    Wechsel Flipper->Bruce: Lock-Menue -> Switch to Bruce"
echo "    Wechsel Bruce->Flipper: Config -> Switch to Flipper Port"