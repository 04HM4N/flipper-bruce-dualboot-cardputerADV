#!/usr/bin/env python3
"""Prepare the Bruce firmware checkout for the Cardputer dual-boot.

Standalone tool of the cardputer-dualboot repo. What it does
(idempotent, safe to run before every build):

  1. locates (or clones) the Bruce firmware checkout. Default: ./bruce
     next to this repo. Override with the BRUCE_DIR environment variable.
  2. resets the working tree to a pristine state
  3. `git pull --ff-only` so a build always picks up upstream changes
  4. re-applies patches/bruce_cardputer_dualboot.patch (adds the
     "Switch to Flipper Port" entries in Bruce's Config and Others menus
     that reboot into the ota_0 slot, plus the "LittleFS is Full"
     self-healing fix)
  5. copies the dual-boot partition table (Bruce view) over Bruce's tree
     so both firmwares are built against matching layouts:
       DUALBOOT_FLASH=8mb  -> config/partitions_dualboot_8mb_bruce.csv
                              (default: real Cardputer / Cardputer ADV, 8 MB flash)
       DUALBOOT_FLASH=16mb -> config/partitions_dualboot_16mb_bruce.csv (16 MB boards)

Exits non-zero (loudly) if the patch no longer applies — that means upstream
Bruce moved the menu/config code and the patch must be regenerated.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent
DEFAULT_BRUCE_DIR = REPO_ROOT / "bruce"
BRUCE_REPO_URL = "https://github.com/pr3y/Bruce.git"
PATCH_FILE = REPO_ROOT / "patches" / "bruce_cardputer_dualboot.patch"

PARTITION_TABLES = {
    "8mb": REPO_ROOT / "config" / "partitions_dualboot_8mb_bruce.csv",
    "16mb": REPO_ROOT / "config" / "partitions_dualboot_16mb_bruce.csv",
}
# Stable name referenced by bruce/boards/m5stack-cardputer/m5stack-cardputer.ini
PARTITIONS_DST_NAME = "partitions_dualboot_bruce.csv"

# Files that patches/bruce_cardputer_dualboot.patch *creates* (as opposed to
# modifies). `git reset --hard` won't remove untracked files, so we delete
# them explicitly before re-applying the patch to keep the operation
# idempotent.
PATCH_CREATED_FILES = [
    "src/core/FlipperOsMenu.h",
    "src/core/FlipperOsMenu.cpp",
]


def run(cmd):
    print("+ " + " ".join(str(c) for c in cmd))
    subprocess.run(cmd, check=True)


def git(*args, check=True):
    cmd = ["git", "-C", str(BRUCE_DIR), *args]
    print("+ " + " ".join(cmd))
    return subprocess.run(cmd, check=check)


def reset_worktree():
    # `git reset --hard` restores all modified upstream files; files CREATED by
    # the patch are untracked and must be removed explicitly so `git apply`
    # can re-create them (idempotency).
    git("reset", "--hard", "HEAD")
    for rel in PATCH_CREATED_FILES:
        path = BRUCE_DIR / rel
        if path.exists():
            print(f"  rm {rel}")
            path.unlink()


def main():
    global BRUCE_DIR

    if not PATCH_FILE.is_file():
        sys.exit(f"error: missing patch file: {PATCH_FILE}")

    BRUCE_DIR = Path(os.environ.get("BRUCE_DIR", DEFAULT_BRUCE_DIR)).resolve()

    flash_mode = os.environ.get("DUALBOOT_FLASH", "8mb").lower()
    if flash_mode not in PARTITION_TABLES:
        sys.exit(f"error: DUALBOOT_FLASH must be one of {sorted(PARTITION_TABLES)}")
    partitions_src = PARTITION_TABLES[flash_mode]
    if not partitions_src.is_file():
        sys.exit(f"error: missing partition table: {partitions_src}")

    if not (BRUCE_DIR / ".git").is_dir():
        if BRUCE_DIR.exists():
            if any(BRUCE_DIR.iterdir()):
                sys.exit(
                    f"error: {BRUCE_DIR} exists but is not a git checkout. "
                    "Remove it and rerun, or run patchBruce.py manually."
                )
            BRUCE_DIR.rmdir()  # leftover empty dir — git clone wants it gone
        print(f"Bruce checkout not found, cloning into {BRUCE_DIR} ...")
        BRUCE_DIR.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--depth", "1", BRUCE_REPO_URL, str(BRUCE_DIR)])

    # 1) pristine tree
    reset_worktree()

    # 2) keep Bruce current
    if git("pull", "--ff-only", check=False).returncode != 0:
        print(
            "warning: 'git pull' failed (offline / non-ff?), continuing with the "
            "local Bruce checkout",
            file=sys.stderr,
        )
        reset_worktree()

    # 3) apply the dual-boot menu patch
    if git("apply", "--whitespace=nowarn", str(PATCH_FILE), check=False).returncode != 0:
        sys.exit(
            "\nerror: patches/bruce_cardputer_dualboot.patch did not apply.\n"
            "Upstream Bruce most likely changed src/core/main_menu.{h,cpp},\n"
            "src/core/menu_items/{ConfigMenu,OthersMenu}.cpp or src/core/config.*.\n"
            "Regenerate the patch — see the README section 'Patches aktualisieren'."
        )

    # 4) single-source the partition table (name kept for Bruce's build system)
    shutil.copyfile(partitions_src, BRUCE_DIR / PARTITIONS_DST_NAME)
    print(f"copied {partitions_src.name} -> {BRUCE_DIR / PARTITIONS_DST_NAME}")

    # 5) pin the Cardputer env to the dual-boot layout. `git reset --hard`
    #    above restores the upstream .ini, so re-apply the three lines that
    #    matter for dual-boot (idempotent).
    ini = BRUCE_DIR / "boards/m5stack-cardputer/m5stack-cardputer.ini"
    if ini.is_file():
        text = ini.read_text()
        lines = [
            "board_build.partitions = " + PARTITIONS_DST_NAME,
            "board_build.app_partition_name = ota_1",
            "board_build.flash_mode = dio  ; DIO REQUIRED - QIO causes a WDT boot loop",
        ]
        # drop any stale dual-boot lines first (in case a previous run left
        # an older variant), then insert after the [env:] header
        text = "\n".join(
            ln for ln in text.splitlines() if not ln.lstrip().startswith((
                "board_build.partitions",
                "board_build.app_partition_name",
                "board_build.flash_mode",
            ))
        )
        header = "[env:m5stack-cardputer]"
        text = text.replace(header, header + "\n" + "\n".join(lines), 1)
        ini.write_text(text)
        print(f"pinned {ini.name} to dual-boot layout (DIO flash mode)")
    else:
        print(f"warning: {ini} not found - board config not pinned", file=sys.stderr)

    print(
        "Bruce checkout is patched and ready for dual-boot "
        f"(DUALBOOT_FLASH={flash_mode})."
    )


if __name__ == "__main__":
    main()
