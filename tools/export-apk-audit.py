#!/usr/bin/env python3
"""Export the supplied APK resource inventory using the bundled aapt."""

from __future__ import annotations

import csv
import hashlib
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AAPT = ROOT / ".compiler" / "aapt.exe"
OUTPUT = ROOT / "english-overlays" / "audit"
APKS = (
    ("launcher-black-blue", ROOT / "launcher-dump" / "QF_Launcher_BlackBlue.apk"),
    ("backcar", ROOT / "qf-apks" / "com.qf.backcar.apk"),
    ("bluetooth", ROOT / "qf-apks" / "com.qf.bluetooth.apk"),
    ("carsettings", ROOT / "qf-apks" / "com.qf.carsettings.apk"),
    ("fancontrol", ROOT / "qf-apks" / "com.qf.fancontrol.apk"),
    ("keystudy", ROOT / "qf-apks" / "com.qf.keystudy.apk"),
    ("musicplayer", ROOT / "qf-apks" / "com.qf.musicplayer.apk"),
    ("panelkeystudy", ROOT / "qf-apks" / "com.qf.panelkeystudy.apk"),
    ("soundeffect", ROOT / "qf-apks" / "com.qf.soundeffect.apk"),
    ("videoplayer", ROOT / "qf-apks" / "com.qf.videoplayer.apk"),
)

SPEC = re.compile(r"spec resource [^ ]+ ([^:]+):([^/]+)/([^:]+):")
RESOURCE = re.compile(r"resource [^ ]+ ([^:]+):([^/]+)/([^:]+):")
CONFIG = re.compile(r"\s*config (?:\((default)\)|([^:]+)):")
STRING = re.compile(r'\(string(?:8|16)\) (".*")$')


def decode_string(quoted: str) -> str:
    try:
        return json.loads(quoted)
    except json.JSONDecodeError:
        return quoted[1:-1]


def inspect(slug: str, apk: Path) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    result = subprocess.run(
        [str(AAPT), "dump", "--values", "resources", str(apk)],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    specs: dict[tuple[str, str], str] = {}
    configurations: dict[tuple[str, str], set[str]] = {}
    values: list[dict[str, str]] = []
    config = ""
    active: tuple[str, str, str] | None = None

    for line in result.stdout.splitlines():
        if match := SPEC.search(line):
            package, resource_type, name = match.groups()
            specs[(resource_type, name)] = package
            configurations.setdefault((resource_type, name), set())
            continue
        if match := CONFIG.match(line):
            config = "default" if match.group(1) else match.group(2).strip()
            active = None
            continue
        if match := RESOURCE.search(line):
            package, resource_type, name = match.groups()
            active = (package, resource_type, name)
            configurations.setdefault((resource_type, name), set()).add(config)
            continue
        if active and (match := STRING.search(line.strip())):
            package, resource_type, name = active
            values.append(
                {
                    "target": slug,
                    "package": package,
                    "type": resource_type,
                    "name": name,
                    "config": config,
                    "value": decode_string(match.group(1)),
                }
            )

    inventory = [
        {
            "target": slug,
            "package": package,
            "type": resource_type,
            "name": name,
            "configs": ";".join(sorted(configurations[(resource_type, name)])),
        }
        for (resource_type, name), package in sorted(specs.items())
    ]
    return inventory, values


def write_csv(path: Path, rows: list[dict[str, str]], fields: list[str]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    inventory: list[dict[str, str]] = []
    values: list[dict[str, str]] = []
    hashes: list[str] = []

    for slug, apk in APKS:
        if not apk.is_file():
            raise FileNotFoundError(apk)
        apk_inventory, apk_values = inspect(slug, apk)
        inventory.extend(apk_inventory)
        values.extend(apk_values)
        digest = hashlib.sha256(apk.read_bytes()).hexdigest().upper()
        hashes.append(f"{digest}  {apk.relative_to(ROOT).as_posix()}")

    write_csv(
        OUTPUT / "inventory.csv",
        inventory,
        ["target", "package", "type", "name", "configs"],
    )
    write_csv(
        OUTPUT / "original-values.csv",
        values,
        ["target", "package", "type", "name", "config", "value"],
    )
    (OUTPUT / "source-apks.sha256").write_text("\n".join(hashes) + "\n", encoding="ascii")
    print(f"Exported {len(inventory)} resources and {len(values)} values from {len(APKS)} APKs.")


if __name__ == "__main__":
    main()
