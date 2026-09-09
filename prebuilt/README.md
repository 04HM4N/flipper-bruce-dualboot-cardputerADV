# Cardputer Dual-Boot — Fertiges Flash-Paket (8 MB)

Fertige, getestete Images für den **M5Stack Cardputer / Cardputer ADV (8 MB Flash)**:

| Inhalt | Offset | Firmware |
|---|---|---|
| `bootloader.bin` | 0x00000 | ESP-IDF-Bootloader (DIO) |
| `partition-table.bin` | 0x08000 | Dual-Boot-Tabelle (ota_0 + ota_1 + spiffs + storage) |
| `flipper_ota_0.bin` | 0x20000 | **ElicoftZ Flipper Zero Port** (Standard-Boot) |
| `bruce_ota_1.bin` | 0x320000 | **Bruce Firmware** |
| `cardputer_dualboot_8mb_merged.bin` | 0x0 | **alles in einer Datei** |

## So flasht du (eine Datei, ein Befehl)

**Linux/macOS:**
```bash
./flash_dualboot.sh              # Port wird automatisch gefunden
./flash_dualboot.sh /dev/ttyACM0 # oder explizit
```

**Windows:**
```bat
flash_dualboot.bat
flash_dualboot.bat COM7
```

Der Flash **löscht den kompletten Flash** (otadata blank) → das Gerät bootet
beim ersten Start in den **Flipper Port**. Danach einfach per Menü wechseln.

## Ohne Skript (manuell, esptool)

```bash
esptool.py --chip esp32s3 --port /dev/ttyACM0 --baud 460800 \
  --before default_reset --after hard_reset \
  write_flash --erase-all --flash_mode keep 0x0 cardputer_dualboot_8mb_merged.bin
```

## Firmware wechseln

| Richtung | Weg |
|---|---|
| Flipper → Bruce | Ein/Aus-Taste → **Lock** → **Switch to Bruce** |
| Bruce → Flipper | Hauptmenü → **Config** (oder **Others**) → **Switch to Flipper Port** → Bestätigen |

## WICHTIG — Flash-Modus

Alle Images sind für **DIO** gebaut und werden in DIO geflasht. **Niemals mit
`--flash_mode qio` flashen**: Der 2nd-Stage-Bootloader hängt dann in der
Flash-Initialisierung → harter WDT-Boot-Loop (`rst:0x7 TG0WDT_SYS_RST`) →
**schwarzer Bildschirm**, obwohl das Flashen selbst erfolgreich war.
Die Merged-BIN hat DIO bereits eingebacken; `--flash_mode keep` im Befehl
verhindert versehentliches Umpatchen.

## Hinweise

- Die **spiffs-Partition (768 KB)** ist Bruce's internes LittleFS — wird beim
  ersten Boot automatisch formatiert (selbstheilend, kein manueller Reset nötig).
- Dateien/Scripts auf der SD-Karte speichern (Flipper nutzt SD als `/ext`).
- 16-MB-Boards: Skript `build_and_flash_dualboot.sh --flash-size 16mb` im
  Projekt-Repo verwenden (erzeugt ein entsprechendes Paket).