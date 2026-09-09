# Cardputer Dual-Boot: Flipper Zero Port ⇄ Bruce Firmware

**Two firmwares on one M5Stack Cardputer / Cardputer ADV — one flash, two
systems, switching via menu button. No loss of functionality on either side.**

The [ElicoftZ Flipper Zero Port](https://github.com/ElicoftZ/Flipper-Zero-meets-M5Stack-Cardputer)
(ota_0) and the [Bruce Firmware](https://github.com/pr3y/Bruce) (ota_1) live in
separate OTA slots on the same ESP32-S3. Each side retains **alle** ihre
hardware functions (Display, Keyboard-Matrix, Power-Management, WiFi-Pentest,
BadUSB, BadBLE, BLE-Spam, IR, CC1101 Sub-GHz, nRF24 2.4 GHz, PN532 NFC …) und
can reboot into the other firmware at runtime — **without reflashing**.

```
┌─────────────────────────── 16 MB (ADV mit 16 MB) ─────────────────────────┐
│ 0x000000 bootloader    0x008000 Partitionstabelle   0x009000 nvs           │
│ 0x00D000 otadata        0x00F000 phy_init                                  │
│ 0x020000 ota_0 (7 MB) = Flipper Zero Port     ← Standard-Boot             │
│ 0x720000 ota_1 (7 MB) = Bruce Firmware                                     │
│ 0xE20000 storage (FAT, 1.875 MB) + spiffs (LittleFS für Bruce)             │
├───────────────────────────  8 MB (offizieller Cardputer / ADV) ───────────┤
│ 0x020000 ota_0 (3.0 MB) = Flipper Zero Port     ← Standard-Boot           │
│ 0x320000 ota_1 (3.94 MB) = Bruce Firmware                                  │
│ 0x710000 storage (FAT) + spiffs (768 KB LittleFS für Bruce)                │
└────────────────────────────────────────────────────────────────────────────┘
```

> ⚠️ **Flash-Größe:** The offizielle M5Stack Cardputer **und** der Cardputer
> ADV haben **8 MB Flash** (ESP32-S3FN8). Die 16-MB-Tabelle ist nur für
> Boards mit *echten* 16 MB gedacht. Beide Layouts sind enthalten.

---

## 🚀 Quick Start (without building yourself)

The folder [prebuilt/](prebuilt/) contains **ready-to-use, tested 8-MB images**
(identical to those verified on a real device):

| Datei | Zweck |
|---|---|
| `cardputer_dualboot_8mb_merged.bin` | ⭐ Alles in einer Datei (Bootloader + Tabelle + beide Firmwares) |
| `bootloader.bin` / `partition-table.bin` | Einzel-Images für manuelles Flashen |
| `flipper_ota_0.bin` / `bruce_ota_1.bin` | Die beiden Apps |
| `flash_dualboot.sh` / `flash_dualboot.bat` | Ein-Klick-Flash (Linux/macOS/Windows) |
| [prebuilt/README.md](prebuilt/README.md) | Ausführliche Flash-Anleitung |

**Linux/macOS:**

```bash
cd prebuilt
./flash_dualboot.sh                 # Port automatisch finden
./flash_dualboot.sh /dev/ttyACM0    # oder explizit
```

**Windows:** `flash_dualboot.bat` (port optional as an argument: `flash_dualboot.bat COM7`)

**Manuell (esptool):**

```bash
esptool.py --chip esp32s3 --port /dev/ttyACM0 --baud 460800 \
  --before default_reset --after hard_reset \
  write_flash --erase-all --flash_mode keep 0x0 cardputer_dualboot_8mb_merged.bin
```

The Flash löscht den gesamten Flash (`--erase-all`): otadata remains blank →
the device boots into the **Flipper Port** on first startup. Bruce formats
its internal LittleFS automatically on first boot — **no manual reset required**.

> 💡 You can generate the 16-MB images mit dem Build-Skript unten
> (`--flash-size 16mb`) — dafür muss das Board wirklich 16 MB Flash haben.

---

## 🔄 Switching Firmware

| Richtung | Weg |
|---|---|
| Flipper → Bruce | Ein/Aus-Taste → **Lock** → **Switch to Bruce** |
| Bruce → Flipper | Hauptmenü → **Config** (oder **Others**) → **Switch to Flipper Port** → Bestätigen |

Hintergrund (nur falls es dich interessiert): The Flipper-Port nutzt
`esp_ota_set_boot_partition()` (kompatibles otadata-Format). Bruce umgekehrt
**löscht das otadata** — ohne gültige OTA-Auswahl bootet der Bootloader
garantiert ota_0. So kann Bruce's abweichende CRC-Berechnung nie wieder einen
Wechsel blockieren.

---

## 🔧 Build Yourself (everything from source)

The repo is an **overlay**: It contains no upstream sources, only
Partitionstabellen, sdkconfig-Overrides, Patches und Skripte. The Builder
automatically fetches both upstream repositories.

### Requirements

- **ESP-IDF v5.4.x** (Flipper-Port) — `export.sh` unter `~/esp/esp-idf` oder
  `IDF_EXPORT_SCRIPT=/pfad/zu/export.sh`
- **PlatformIO** (`pip install platformio`) für Bruce
- **esptool** (`pip install esptool`), if flashing is required
- git, python3, zip

### Build & Flash

```bash
./build_and_flash_dualboot.sh                        # baut beide + flasht, wenn ein Gerät dranhängt
./build_and_flash_dualboot.sh --build-only           # nur bauen, nichts flashen
./build_and_flash_dualboot.sh --flash-size 16mb      # 16-MB-Layout (nur für echte 16-MB-Boards)
PORT=/dev/ttyACM0 ./build_and_flash_dualboot.sh      # Port explizit setzen
```

The Ablauf:

1. Clones `ElicoftZ/…-Cardputer` (Branch `main`) into `flipper-port/` und
   `pr3y/Bruce` into `bruce/` (beide sind gitignored).
2. Copies die Overlay-Dateien (`config/*`) in den Flipper-Checkout und
   wendet `patches/flipper_port_fixes.patch` an (Upstream-Buildfixes).
3. `patchBruce.py` patches Bruce (Menüeinträge „Switch to Flipper Port“ +
   LittleFS-Selbstheilung) und places the matching partition table.
4. Builds Flipper (ESP-IDF) und Bruce (PlatformIO).
5. Flashes Bootloader @0x0, Tabelle @0x8000, Flipper @0x20000 (ota_0),
   Bruce @0x320000/0x720000 (ota_1) — immer mit **DIO** und `--erase-all`.
6. Creates `dist/cardputer_dualboot_<größe>_merged.bin` + Flash-Paket (ZIP).

---

## 📁 Repository-Struktur

```
cardputer-dualboot/
├── build_and_flash_dualboot.sh   Self-contained Builder + Flasher
├── patchBruce.py                  Patcht/kopiert den Bruce-Checkout
├── config/                        Partitionstabellen + sdkconfig-Overrides
│   ├── partitions_dualboot_8mb.csv        Flipper-Sicht (ota_0/ota_1/storage)
│   ├── partitions_dualboot_8mb_bruce.csv  Bruce-Sicht (+ spiffs-LittleFS)
│   ├── partitions_dualboot_16mb.csv       16-MB-Twin
│   ├── partitions_dualboot_16mb_bruce.csv
│   ├── sdkconfig.dualboot_8mb             ESP-IDF-Overrides (DIO, Tabelle)
│   └── sdkconfig.dualboot_16mb
├── patches/
│   ├── bruce_cardputer_dualboot.patch     Menüeinträge + LittleFS-Fix für Bruce
│   └── flipper_port_fixes.patch           Upstream-Buildfixes (FAM)
├── prebuilt/                     Fertige, getestete 8-MB-Images + Flash-Skripte
└── dist/                         (vom Builder erzeugt, gitignored)
```

---

## ⚠️ Important: DIO Flash Mode — not QIO!

All images are built for **DIO** and flashed in DIO. **Never flash with
`--flash_mode qio` flashen** — auch wenn das Board-JSON von M5Stack QIO sagt:

> The 2nd-Stage-Bootloader hängt dann in der Flash-Initialisierung → harter
> WDT-Boot-Loop (`rst:0x7 TG0WDT_SYS_RST`, alle ~1,2 s) → **black
> screen**, obwohl das Flashen selbst erfolgreich war.

Therefore: `sdkconfig.dualboot_*` and the Bruce-`ini` enforce DIO, der Builder
flasht mit `--flash_mode dio`, and the Merged-BIN hat DIO eingebacken
(`--flash_mode keep` beim manuellen Flashen verhindert versehentliches
Umpatchen).

---

## ❓ Troubleshooting

| Symptom | Ursache / Lösung |
|---|---|
| **Schwarzer screen into Flash** | Image mit QIO geflasht → erneut mit `--flash_mode dio` bzw. `keep` flashen (Merged-BIN oder Builder). |
| **„LittleFS is full“ beim ersten Bruce-Boot** | Veraltete Tabelle (192 KB spiffs) → neu flashen. Aktuelle Tabellen geben Bruce **768 KB** LittleFS; beim ersten Boot into `--erase-all` formatiert sich die Partition selbst (kein manueller Reset mehr nötig). |
| **Bruce → Flipper startet nicht** | Veraltetes Bruce-Image (alter `esp_ota_set_boot_partition`-Pfad). Neues Image flashen — der Fix löscht das otadata statt eines inkompatiblen CRC-Writes. |
| **Gerät bleibt into abgebrochenem Flash stumm** | otadata löschen → bootet garantiert ota_0: `esptool.py --port PORT erase_region 0xd000 0x2000`, oder einfach einmal komplett neu flashen (Builder macht `--erase-all`). |
| **No serial port** | Use a data USB-C cable directly (no hub); if needed, enter download mode: **G0** halten + **RST** tippen, dann G0 loslassen. |

---

## 🔄 Updating Patches (if upstream changes)

`build_and_flash_dualboot.sh` stops with an error, wenn `git apply` fehlschlägt —
dann hat sich Upstream geändert and the Patches müssen intogezogen werden:

- **Bruce:** manually make the desired changes, dann in
  `bruce/`:
  ```bash
  git add -N src/core/FlipperOsMenu.h src/core/FlipperOsMenu.cpp
  git diff src/core/FlipperOsMenu.h src/core/FlipperOsMenu.cpp \
           src/core/menu_items/ConfigMenu.cpp src/core/menu_items/OthersMenu.cpp \
           src/core/sd_functions.cpp > ../patches/bruce_cardputer_dualboot.patch
  ```
- **Flipper-Port:** `fam_config.py` (tagtinker-Eintrag) und
  `applications_user/flipper_zero_rgb_led/application.fam` check, Diff in
  `patches/flipper_port_fixes.patch` apply.

---

## ⚖️ License & Acknowledgements

This repo is an **overlay** (MIT, siehe [LICENSE](LICENSE)) und enthält
keine Upstream-Quellen. The firmwares come from:

- [ElicoftZ/Flipper-Zero-meets-M5Stack-Cardputer](https://github.com/ElicoftZ/Flipper-Zero-meets-M5Stack-Cardputer)
- [pr3y/Bruce](https://github.com/pr3y/Bruce) (GNU AGPL-3.0)

The `.patch` files and `prebuilt/` images concern/contain their code and
are subject to the respective upstream licenses — check the upstream
Upstream-Repos check.

**Verwendung auf eigene Gefahr.** Kein offizielles M5Stack- oder
Flipper-Zero-Projekt.
