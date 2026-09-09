#!/usr/bin/env bash
# =============================================================================
# build_and_flash_dualboot.sh — M5Stack Cardputer / Cardputer ADV dual-boot
#
# Self-contained builder of this repository. It clones the two upstream
# firmware sources (if not present), stages the dual-boot overlay (partition
# tables, sdkconfig overrides, build fixes, Bruce menu patch) and flashes
# everything in one go:
#
#   ota_0  = ElicoftZ Flipper Zero port   (default boot target)
#   ota_1  = Bruce firmware
#
# Switching afterwards happens on-device:
#   Flipper port : Lock menu  -> "Switch to Bruce"      (reboots into ota_1)
#   Bruce        : Config/Others -> "Switch to Flipper Port" (reboots into ota_0)
#
# Usage:
#   ./build_and_flash_dualboot.sh                        # build both + flash if a device is found
#   ./build_and_flash_dualboot.sh --flash-size 16mb      # force the 16 MB table (default: auto/8mb)
#   ./build_and_flash_dualboot.sh --build-only           # build, never touch a device
#   PORT=/dev/ttyACM0 ./build_and_flash_dualboot.sh      # explicit serial port
#
# Requirements:
#   - git
#   - ESP-IDF v5.4.x for the Flipper port (export.sh at $HOME/esp/esp-idf or $IDF_EXPORT_SCRIPT)
#   - PlatformIO (pio) for Bruce (installs its toolchain on first build)
#   - esptool (pip install esptool) — falls back to the ESP-IDF / PlatformIO copy
#
# First run clones:
#   - ElicoftZ/Flipper-Zero-meets-M5Stack-Cardputer (branch main) -> ./flipper-port
#   - pr3y/Bruce (master)                                        -> ./bruce
# Both are gitignored; patches from this repo are re-applied on every run.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"   # this repository

FLIPPER_DIR="${REPO_ROOT}/flipper-port"
BRUCE_DIR="${REPO_ROOT}/bruce"
OUT_DIR="${REPO_ROOT}/dist"

FLIPPER_REPO_URL="https://github.com/ElicoftZ/Flipper-Zero-meets-M5Stack-Cardputer.git"
FLIPPER_BRANCH="main"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
die()  { echo -e "${RED}[ERROR] $*${NC}" >&2; exit 1; }
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
info() { echo -e "${CYAN}  --> $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }

PORT="${PORT:-}"
FLASH_SIZE="auto"
BOARD="cardputer_adv"
BUILD_ONLY=0

usage() {
    sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --flash-size)    FLASH_SIZE="$2"; shift 2 ;;
        --board)         BOARD="$2"; shift 2 ;;
        --build-only|-b) BUILD_ONLY=1; shift ;;
        -p|--port)       PORT="$2"; shift 2 ;;
        -h|--help)       usage ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# 0. Fetch / refresh the upstream checkouts
# ---------------------------------------------------------------------------
ensure_flipper_checkout() {
    if [[ ! -d "${FLIPPER_DIR}/.git" ]]; then
        if [[ -d "${FLIPPER_DIR}" ]]; then
            die "${FLIPPER_DIR} exists but is not a git checkout. Remove it and rerun."
        fi
        info "Cloning ElicoftZ Flipper port (${FLIPPER_BRANCH}) ..."
        git clone --depth 1 --branch "${FLIPPER_BRANCH}" "${FLIPPER_REPO_URL}" "${FLIPPER_DIR}"
    fi
    # Stage the dual-boot overlay (partition tables + sdkconfig overrides).
    # Idempotent: the repo files are the single source of truth.
    ( cd "${REPO_ROOT}" && cp -f \
        config/partitions_dualboot_8mb.csv \
        config/partitions_dualboot_8mb_bruce.csv \
        config/partitions_dualboot_16mb.csv \
        config/partitions_dualboot_16mb_bruce.csv \
        config/sdkconfig.dualboot_8mb \
        config/sdkconfig.dualboot_16mb \
        "${FLIPPER_DIR}/" )

    # Apply the upstream build fixes (fam_config.py tagtinker entry removed,
    # rgb_led icon symbol added). Detects "already applied" via reverse check.
    ( cd "${FLIPPER_DIR}" || exit 1
      if git apply --check "${REPO_ROOT}/patches/flipper_port_fixes.patch" >/dev/null 2>&1; then
          git apply "${REPO_ROOT}/patches/flipper_port_fixes.patch"
          ok "Applied flipper_port_fixes.patch"
      elif git apply --reverse --check "${REPO_ROOT}/patches/flipper_port_fixes.patch" >/dev/null 2>&1; then
          info "flipper_port_fixes.patch already applied"
      else
          die "flipper_port_fixes.patch does not apply cleanly (upstream moved?)"
      fi )
}

ensure_bruce_checkout() {
    # patchBruce.py clones ./bruce (pr3y/Bruce, master) when missing, resets,
    # pulls and re-applies patches/bruce_cardputer_dualboot.patch + the
    # matching partition table. DUALBOOT_FLASH selects 8mb/16mb.
    ( cd "${REPO_ROOT}" && DUALBOOT_FLASH="${FLASH_SIZE}" python3 patchBruce.py )
}

# ---------------------------------------------------------------------------
# 1. Detect the target flash size (16 MB only exists on 16 MB hardware; the
#    official Cardputer / Cardputer ADV are 8 MB).
# ---------------------------------------------------------------------------
if [[ "${FLASH_SIZE}" == "auto" ]]; then
    if [[ -f "${OUT_DIR}/flash_size" ]]; then
        FLASH_SIZE="$(cat "${OUT_DIR}/flash_size")"
    else
        FLASH_SIZE="8mb"
        warn "Flash size not specified — defaulting to 8mb (real Cardputer hardware)."
        warn "For a 16 MB board run with:  --flash-size 16mb"
    fi
fi
case "${FLASH_SIZE,,}" in
    8|8mb)  FLASH_SIZE="8mb"  ; FLASH_SIZE_ESPTOOL="8MB"  ;;
    16|16mb) FLASH_SIZE="16mb"; FLASH_SIZE_ESPTOOL="16MB" ;;
    *) die "--flash-size must be 8mb or 16mb" ;;
esac

# OTA slot offsets/sizes for the selected layout (used for size checks,
# flashing and the merged-image package).
if [[ "${FLASH_SIZE}" == "16mb" ]]; then
    OTA0_OFFSET="0x20000";  OTA0_MAX="0x700000"
    OTA1_OFFSET="0x720000"; OTA1_MAX="0x700000"
else
    OTA0_OFFSET="0x20000";  OTA0_MAX="0x300000"
    OTA1_OFFSET="0x320000"; OTA1_MAX="0x3f0000"
fi
mkdir -p "${OUT_DIR}"
echo "${FLASH_SIZE}" > "${OUT_DIR}/flash_size"
info "Dual-boot layout: ${FLASH_SIZE}  (ota_0 = Flipper port, ota_1 = Bruce)"
[[ "${FLASH_SIZE}" == "16mb" ]] && warn \
    "16 MB layout selected — verify the chip really has 16 MB flash, otherwise writes beyond 8 MB will fail."

# ---------------------------------------------------------------------------
# 2. esptool helper (standalone, then IDF, then PlatformIO package)
# ---------------------------------------------------------------------------
ESPTOOL=""
find_esptool() {
    if command -v esptool >/dev/null 2>&1;        then ESPTOOL="esptool"; return 0; fi
    if command -v esptool.py >/dev/null 2>&1;     then ESPTOOL="esptool.py"; return 0; fi
    if python3 -m esptool version >/dev/null 2>&1; then ESPTOOL="python3 -m esptool"; return 0; fi
    local script="${HOME}/esp/esp-idf/components/esptool_py/esptool/esptool.py"
    if [[ -f "${script}" ]]; then ESPTOOL="python3 ${script}"; return 0; fi
    local pio_pkg="${HOME}/.platformio/packages/tool-esptoolpy/esptool.py"
    if [[ -f "${pio_pkg}" ]]; then ESPTOOL="python3 ${pio_pkg}"; return 0; fi
    return 1
}

# ---------------------------------------------------------------------------
# 3. Serial port detection (skipped for --build-only)
# ---------------------------------------------------------------------------
detect_port() {
    local matches=()
    shopt -s nullglob
    matches=(/dev/ttyACM* /dev/ttyUSB* /dev/cu.usbmodem* /dev/cu.usbserial*)
    shopt -u nullglob
    if [[ "${#matches[@]}" -eq 1 ]]; then
        printf '%s\n' "${matches[0]}"
    elif [[ "${#matches[@]}" -gt 1 ]]; then
        warn "Multiple serial ports found: ${matches[*]}"
        printf '%s\n' "${matches[0]}"
    fi
}

if [[ "${BUILD_ONLY}" -eq 0 && -z "${PORT}" ]]; then
    PORT="$(detect_port || true)"
    [[ -n "${PORT}" ]] && info "Serial port: ${PORT}" || warn "No serial port found — will build only."
fi
[[ "${BUILD_ONLY}" -eq 1 ]] && PORT=""

ensure_flipper_checkout
ensure_bruce_checkout

# ---------------------------------------------------------------------------
# 4. Build the Flipper port (ota_0) — ESP-IDF
# ---------------------------------------------------------------------------
build_flipper() {
    info "=== [1/2] Building Flipper port (ota_0) ==="
    local export_script="${IDF_EXPORT_SCRIPT:-${HOME}/esp/esp-idf/export.sh}"
    [[ -f "${export_script}" ]] || die "ESP-IDF export script not found: ${export_script}\n  Install ESP-IDF v5.4.x or set IDF_EXPORT_SCRIPT=/path/to/export.sh"

    # shellcheck source=/dev/null
    source "${export_script}"

    # The FAM icon generator needs Pillow inside the IDF python env.
    if ! python -c "import PIL" >/dev/null 2>&1; then
        warn "Installing Pillow into the ESP-IDF python env (needed by the icon generator)"
        python -m pip install pillow
    fi

    # Standard Cardputer vs Cardputer ADV — different board config name only;
    # the ADV is the fully equipped model (CC1101/nRF24/IR-RX/IMU/Codec).
    local board_name
    case "${BOARD}" in
        cardputer)     board_name="m5stack_cardputer" ;;
        cardputer_adv) board_name="m5stack_cardputer_adv" ;;
        *) die "Unknown board '${BOARD}' (cardputer|cardputer_adv)" ;;
    esac
    local build_dir="build_cardputer_dualboot"
    local sdkconfig_defaults="sdkconfig.defaults;sdkconfig.defaults.${board_name};sdkconfig.dualboot_${FLASH_SIZE}"

    # Drop a stale sdkconfig that was generated for a different partition
    # layout / flash size (idf.py caches it in the project root), so the
    # requested dualboot table actually gets applied.
    local root_sdk="${FLIPPER_DIR}/sdkconfig"
    if [[ -f "${root_sdk}" ]]; then
        if ! grep -q "CONFIG_PARTITION_TABLE_CUSTOM_FILENAME=\"partitions_dualboot_${FLASH_SIZE}.csv\"" "${root_sdk}" \
           || ! grep -q "CONFIG_ESPTOOLPY_FLASHSIZE=\"${FLASH_SIZE_ESPTOOL}\"" "${root_sdk}"; then
            warn "Removing stale sdkconfig (different flash size / partition table)"
            rm -f "${root_sdk}" "${FLIPPER_DIR}/sdkconfig.old"
        fi
    fi

    ( cd "${FLIPPER_DIR}" && \
      idf.py -B "${build_dir}" \
             -DFLIPPER_BOARD="${board_name}" \
             -DSDKCONFIG_DEFAULTS="${sdkconfig_defaults}" \
             set-target esp32s3 && \
      idf.py -B "${build_dir}" \
             -DFLIPPER_BOARD="${board_name}" \
             -DSDKCONFIG_DEFAULTS="${sdkconfig_defaults}" \
             build )

    FLIPPER_APP="${FLIPPER_DIR}/${build_dir}/furi_esp32.bin"
    FLIPPER_BOOTLOADER="${FLIPPER_DIR}/${build_dir}/bootloader/bootloader.bin"
    FLIPPER_PARTTABLE="${FLIPPER_DIR}/${build_dir}/partition_table/partition-table.bin"
    [[ -f "${FLIPPER_APP}" ]] || die "Flipper app binary missing: ${FLIPPER_APP}"
    ok "Flipper port built: ${FLIPPER_APP} ($(numfmt --to=iec --suffix=B "$(stat -c%s "${FLIPPER_APP}")" 2>/dev/null || stat -c%s "${FLIPPER_APP}"))"
}

# ---------------------------------------------------------------------------
# 5. Build Bruce (ota_1) — PlatformIO (checkout already patched by patchBruce.py)
# ---------------------------------------------------------------------------
build_bruce() {
    info "=== [2/2] Building Bruce firmware (ota_1) ==="
    command -v pio >/dev/null 2>&1 || die "PlatformIO not found (pip install platformio)"

    ( cd "${BRUCE_DIR}" && pio run -e m5stack-cardputer )

    BRUCE_APP="${BRUCE_DIR}/.pio/build/m5stack-cardputer/firmware.bin"
    BRUCE_BOOTLOADER="${BRUCE_DIR}/.pio/build/m5stack-cardputer/bootloader.bin"
    BRUCE_PARTTABLE="${BRUCE_DIR}/.pio/build/m5stack-cardputer/partitions.bin"
    [[ -f "${BRUCE_APP}" ]] || die "Bruce firmware binary missing: ${BRUCE_APP}"
    ok "Bruce built: ${BRUCE_APP} ($(numfmt --to=iec --suffix=B "$(stat -c%s "${BRUCE_APP}")" 2>/dev/null || stat -c%s "${BRUCE_APP}"))"
}

build_flipper
build_bruce

# ---------------------------------------------------------------------------
# 6. Flash: use the Flipper build's bootloader + the shared partition table,
#    then write each app into its OTA slot. otadata stays erased -> boots ota_0.
# ---------------------------------------------------------------------------
if [[ -n "${PORT}" ]]; then
    find_esptool || die "esptool not found (pip install esptool)"

    # Sanity: app images must fit their slots.
    check_size() { # $1=file $2=slot $3=max_bytes
        local size; size="$(stat -c%s "$1")"
        if (( size > $3 )); then
            die "$1 ($size bytes) does not fit $2 (max $3 bytes)"
        fi
    }
    check_size "${FLIPPER_APP}" "ota_0 (${OTA0_MAX})" "$((OTA0_MAX))"
    check_size "${BRUCE_APP}"   "ota_1 (${OTA1_MAX})" "$((OTA1_MAX))"

    # IMPORTANT: flash mode MUST stay DIO. Both firmwares are built with the
    # ESP-IDF/Arduino default (DIO) and flashing the bootloader with
    # --flash_mode qio causes a hard WDT boot loop (rst:0x7 TG0WDT_SYS_RST)
    # on this hardware — the 2nd-stage bootloader hangs in flash init before
    # any output, leaving a black screen. DIO is universally supported and
    # verified working on both slots.

    # Verify the connected chip really is an ESP32-S3 (Cardputer) BEFORE
    # touching flash — protects against a different board plugged into the
    # port (e.g. a CH340/ESP32 dev board).
    info "Verifying ${PORT} is an ESP32-S3 (Cardputer)..."
    chip_out="$($ESPTOOL --chip esp32s3 --port "${PORT}" --before default_reset chip_id 2>&1 || true)"
    chip_ok=0
    if grep -q "ESP32-S3" <<<"${chip_out}"; then
        chip_ok=1
    else
        # Some USB-JTAG setups only answer with --before usb_reset.
        chip_out="$($ESPTOOL --chip esp32s3 --port "${PORT}" --before usb_reset chip_id 2>&1 || true)"
        grep -q "ESP32-S3" <<<"${chip_out}" && chip_ok=1
    fi
    if [[ "${chip_ok}" -ne 1 ]]; then
        echo "${chip_out}" | tail -3 >&2
        die "Port ${PORT} is not an ESP32-S3 (Cardputer)."
    fi

    flash_with_before() { # $1 = --before mode (default_reset|usb_reset|no_reset)
        # shellcheck disable=SC2086
        $ESPTOOL --chip esp32s3 --port "${PORT}" --baud 460800 \
            --before "$1" --after hard_reset \
            write_flash \
                --flash_mode dio --flash_freq 80m --flash_size "${FLASH_SIZE_ESPTOOL}" \
                --erase-all \
                0x0     "${FLIPPER_BOOTLOADER}" \
                0x8000  "${FLIPPER_PARTTABLE}" \
                "${OTA0_OFFSET}" "${FLIPPER_APP}" \
                "${OTA1_OFFSET}" "${BRUCE_APP}"
    }

    info "Flashing partition table + bootloader + both firmwares to ${PORT}"
    if ! flash_with_before default_reset; then
        warn "default_reset failed (common with USB-JTAG) — retrying with usb_reset..."
        flash_with_before usb_reset
    fi

    # otadata must be 0xFF (erased) so the bootloader picks ota_0 by default.
    # --erase-all above already guarantees a blank otadata on first install.
    ok "Flash complete! Rebooting into the Flipper port (ota_0)."
    info "Switch to Bruce anytime: Flipper lock menu -> 'Switch to Bruce'."
    info "Switch back:             Bruce Config menu -> 'Switch to Flipper Port'."
else
    warn "Build-only mode: nothing flashed."
    info "Flash later with e.g.: PORT=/dev/ttyACM0 ./build_and_flash_dualboot.sh"
fi

# ---------------------------------------------------------------------------
# 7. Collect artifacts + build the single-file flash package
# ---------------------------------------------------------------------------
cp -f "${FLIPPER_APP}"        "${OUT_DIR}/flipper_ota_0.bin"      2>/dev/null || true
cp -f "${BRUCE_APP}"          "${OUT_DIR}/bruce_ota_1.bin"        2>/dev/null || true
cp -f "${FLIPPER_PARTTABLE}"  "${OUT_DIR}/partition-table.bin"    2>/dev/null || true
cp -f "${FLIPPER_BOOTLOADER}" "${OUT_DIR}/bootloader.bin"         2>/dev/null || true

# One-file image for flashing with a single command. DIO is baked in at merge
# time — NEVER merge/flash with qio (WDT boot loop on this hardware).
MERGED="${OUT_DIR}/cardputer_dualboot_${FLASH_SIZE}_merged.bin"
find_esptool || true
if [[ -n "${ESPTOOL}" ]]; then
    # shellcheck disable=SC2086
    $ESPTOOL --chip esp32s3 merge_bin -o "${MERGED}" \
        --flash_mode dio --flash_freq 80m --flash_size "${FLASH_SIZE_ESPTOOL}" \
        0x0     "${FLIPPER_BOOTLOADER}" \
        0x8000  "${FLIPPER_PARTTABLE}" \
        "${OTA0_OFFSET}" "${FLIPPER_APP}" \
        "${OTA1_OFFSET}" "${BRUCE_APP}" >/dev/null 2>&1 || \
        warn "merge_bin failed — merged image not created"
    [[ -f "${MERGED}" ]] && ok "Merged image: ${MERGED##*/} ($(numfmt --to=iec --suffix=B "$(stat -c%s "${MERGED}")" 2>/dev/null || stat -c%s "${MERGED}"))"
fi

if command -v zip >/dev/null 2>&1 && [[ -f "${MERGED}" ]]; then
    # One-click flash helpers live in prebuilt/ — stage them next to the images.
    cp -f "${REPO_ROOT}/prebuilt/flash_dualboot.sh"   "${OUT_DIR}/" 2>/dev/null || true
    cp -f "${REPO_ROOT}/prebuilt/flash_dualboot.bat"  "${OUT_DIR}/" 2>/dev/null || true
    cp -f "${REPO_ROOT}/prebuilt/README.md"           "${OUT_DIR}/" 2>/dev/null || true
    ZIP="${OUT_DIR}/cardputer_dualboot_${FLASH_SIZE}_flashpak.zip"
    ( cd "${OUT_DIR}" && rm -f "${ZIP}" && zip -q -j "${ZIP}" \
        "${MERGED##*/}" bootloader.bin partition-table.bin \
        flipper_ota_0.bin bruce_ota_1.bin \
        flash_dualboot.sh flash_dualboot.bat README.md ) \
        && ok "Flash package: ${ZIP##*/}" || warn "zip failed — no package"
fi

ok "Artifacts in ${OUT_DIR}/"
