# Cardputer Dual-Boot: Flipper Zero Port ⇄ Bruce Firmware

**Two firmwares on one M5Stack Cardputer / Cardputer ADV — one flash, two
systems, switch with a menu button. Without losing any functionality on
either side.**

The [ElicoftZ Flipper Zero Port](https://github.com/ElicoftZ/Flipper-Zero-meets-M5Stack-Cardputer)
(ota_0) and the [Bruce firmware](https://github.com/pr3y/Bruce) (ota_1) live in
separate OTA slots on the same ESP32-S3. Each side keeps **all** of its
hardware features (display, keyboard matrix, power management, WiFi pentest,
BadUSB, BadBLE, BLE spam, IR, CC1101 Sub-GHz, nRF24 2.4 GHz, PN532 NFC …) and
can reboot into the other firmware at runtime — **no re-flashing required**.

```
┌──────────────────────────── 16 MB (ADV with 16 MB) ────────────────────────┐
│ 0x000000 bootloader    0x008000 partition table   0x009000 nvs             │
│ 0x00D000 otadata        0x00F000 phy_init                                  │
│ 0x020000 ota_0 (7 MB) = Flipper Zero Port      ← default boot             │
│ 0x720000 ota_1 (7 MB) = Bruce firmware                                     │
│ 0xE20000 storage (FAT, 1.875 MB) + spiffs (LittleFS for Bruce)             │
├────────────────────────────  8 MB (official Cardputer / ADV) ─────────────┤
│ 0x020000 ota_0 (3.0 MB) = Flipper Zero Port      ← default boot           │
│ 0x320000 ota_1 (3.94 MB) = Bruce firmware                                  │
│ 0x710000 storage (FAT) + spiffs (768 KB LittleFS for Bruce)                │
└────────────────────────────────────────────────────────────────────────────┘
```

> ⚠️ **Flash size:** The official M5Stack Cardputer **and** the Cardputer ADV
> have **8 MB flash** (ESP32-S3FN8). The 16 MB table is only for boards with
> *genuine* 16 MB flash. Both layouts are included.

---

## 🚀 Quick start (no building required)

The [prebuilt/](prebuilt/) folder contains **ready-made, tested 8 MB images**
(identical to the ones verified on real hardware):

| File | Purpose |
|---|---|
| `cardputer_dualboot_8mb_merged.bin` | ⭐ Everything in one file (bootloader + table + both firmwares) |
| `bootloader.bin` / `partition-table.bin` | Individual images for manual flashing |
| `flipper_ota_0.bin` / `bruce_ota_1.bin` | The two apps |
| `flash_dualboot.sh` / `flash_dualboot.bat` | One-click flash (Linux/macOS/Windows) |
| [prebuilt/README.md](prebuilt/README.md) | Detailed flashing guide |

**Linux/macOS:**

```bash
cd prebuilt
./flash_dualboot.sh                 # auto-detect the port
./flash_dualboot.sh /dev/ttyACM0    # or specify it
```

**Windows:** `flash_dualboot.bat` (optional port argument: `flash_dualboot.bat COM7`)

**Manual (esptool):**

```bash
esptool.py --chip esp32s3 --port /dev/ttyACM0 --baud 460800 \
  --before default_reset --after hard_reset \
  write_flash --erase-all --flash_mode keep 0x0 cardputer_dualboot_8mb_merged.bin
```

The flash erases the whole chip (`--erase-all`): otadata stays blank, so the
device boots into the **Flipper Port** on first start. Bruce formats its
internal LittleFS by itself on first boot — **no manual reset needed**.

> 💡 Generate the 16 MB images with the build script below
> (`--flash-size 16mb`) — the board must actually have 16 MB flash.

---

## 🔄 Switching firmware

| Direction | How |
|---|---|
| Flipper → Bruce | Power button → **Lock** → **Switch to Bruce** |
| Bruce → Flipper | Main menu → **Config** (or **Others**) → **Switch to Flipper Port** → Confirm |

Background (in case you care): The Flipper port uses
`esp_ota_set_boot_partition()` (compatible otadata format). Bruce, in the
other direction, **erases the otadata** — with no valid OTA selection the
bootloader is guaranteed to boot ota_0. This way Bruce's divergent CRC
calculation can never block the switch again.

---

## 🔧 Building from source

This repo is an **overlay**: it does not contain the upstream sources, only
partition tables, sdkconfig overrides, patches and scripts. The builder fetches
the two upstream repositories automatically.

### Requirements

- **ESP-IDF v5.4.x** (Flipper port) — `export.sh` under `~/esp/esp-idf`, or set
  `IDF_EXPORT_SCRIPT=/path/to/export.sh`
- **PlatformIO** (`pip install platformio`) for Bruce
- **esptool** (`pip install esptool`) if you want to flash
- git, python3, zip

### Build & flash

```bash
./build_and_flash_dualboot.sh                        # builds both + flashes if a device is attached
./build_and_flash_dualboot.sh --build-only           # build only, never touch a device
./build_and_flash_dualboot.sh --flash-size 16mb      # 16 MB layout (genuine 16 MB boards only)
PORT=/dev/ttyACM0 ./build_and_flash_dualboot.sh      # explicit serial port
```

What it does:

1. Clones `ElicoftZ/…-Cardputer` (branch `main`) into `flipper-port/` and
   `pr3y/Bruce` into `bruce/` (both gitignored).
2. Copies the overlay files (`config/*`) into the Flipper checkout and applies
   `patches/flipper_port_fixes.patch` (upstream build fixes).
3. `patchBruce.py` patches Bruce (the “Switch to Flipper Port” menu entries +
   LittleFS self-healing) and installs the matching partition table.
4. Builds Flipper (ESP-IDF) and Bruce (PlatformIO).
5. Flashes bootloader @0x0, table @0x8000, Flipper @0x20000 (ota_0),
   Bruce @0x320000/0x720000 (ota_1) — always with **DIO** and `--erase-all`.
6. Produces `dist/cardputer_dualboot_<size>_merged.bin` + a flash package (ZIP).

---

## 📁 Repository layout

```
cardputer-dualboot/
├── build_and_flash_dualboot.sh   Self-contained builder + flasher
├── patchBruce.py                  Patches/copies the Bruce checkout
├── config/                        Partition tables + sdkconfig overrides
│   ├── partitions_dualboot_8mb.csv        Flipper view (ota_0/ota_1/storage)
│   ├── partitions_dualboot_8mb_bruce.csv  Bruce view (+ spiffs LittleFS)
│   ├── partitions_dualboot_16mb.csv       16 MB twin
│   ├── partitions_dualboot_16mb_bruce.csv
│   ├── sdkconfig.dualboot_8mb             ESP-IDF overrides (DIO, table)
│   └── sdkconfig.dualboot_16mb
├── patches/
│   ├── bruce_cardputer_dualboot.patch     Menu entries + LittleFS fix for Bruce
│   └── flipper_port_fixes.patch           Upstream build fixes (FAM)
├── prebuilt/                     Ready-made, tested 8 MB images + flash scripts
└── dist/                         (created by the builder, gitignored)
```

---

## ⚠️ Important: flash mode DIO — not QIO!

All images are built for and flashed with **DIO**. **Never flash with
`--flash_mode qio`** — even though the M5Stack board JSON says QIO:

> The 2nd-stage bootloader then hangs in flash initialization → hard WDT boot
> loop (`rst:0x7 TG0WDT_SYS_RST`, every ~1.2 s) → **black screen**, even
> though flashing itself succeeded.

That is why `sdkconfig.dualboot_*` and the Bruce `ini` force DIO, the builder
flashes with `--flash_mode dio`, and the merged BIN has DIO baked in
(`--flash_mode keep` for manual flashing prevents accidental re-patching).

---

## ❓ Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **Black screen after flashing** | Image flashed with QIO → re-flash with `--flash_mode dio` / `keep` (merged BIN or builder). |
| **“LittleFS is full” on first Bruce boot** | Outdated table (192 KB spiffs) → re-flash. Current tables give Bruce **768 KB** LittleFS; after `--erase-all` the partition formats itself on first boot (no manual reset needed anymore). |
| **Bruce → Flipper does not boot** | Outdated Bruce image (old `esp_ota_set_boot_partition` path). Flash the new image — the fix erases otadata instead of an incompatible CRC write. |
| **Device silent after an aborted flash** | Erase otadata to boot ota_0 for sure: `esptool.py --port PORT erase_region 0xd000 0x2000`, or simply flash everything again (the builder does `--erase-all`). |
| **No serial port** | Data USB-C cable plugged directly (no hub); if needed, enter download mode: hold **G0** + tap **RST**, then release G0. |

---

## 🔄 Updating the patches (if upstream moves)

`build_and_flash_dualboot.sh` aborts loudly when `git apply` fails — that means
upstream changed and the patches must be refreshed:

- **Bruce:** redo the wanted changes by hand, then inside `bruce/`:
  ```bash
  git add -N src/core/FlipperOsMenu.h src/core/FlipperOsMenu.cpp
  git diff src/core/FlipperOsMenu.h src/core/FlipperOsMenu.cpp \
           src/core/menu_items/ConfigMenu.cpp src/core/menu_items/OthersMenu.cpp \
           src/core/sd_functions.cpp > ../patches/bruce_cardputer_dualboot.patch
  ```
- **Flipper port:** check `fam_config.py` (tagtinker entry) and
  `applications_user/flipper_zero_rgb_led/application.fam`, port the diff into
  `patches/flipper_port_fixes.patch`.

---

## ⚖️ License & credits

This repo is an **overlay** (MIT, see [LICENSE](LICENSE)) and does not contain
any upstream sources. The firmwares come from:

- [ElicoftZ/Flipper-Zero-meets-M5Stack-Cardputer](https://github.com/ElicoftZ/Flipper-Zero-meets-M5Stack-Cardputer)
- [pr3y/Bruce](https://github.com/pr3y/Bruce) (GNU AGPL-3.0)

The `.patch` files and `prebuilt/` images relate to / contain their code and
are subject to the respective upstream licenses — check the upstream
repositories before redistributing.

**Use at your own risk.** Not an official M5Stack or Flipper Zero project.
