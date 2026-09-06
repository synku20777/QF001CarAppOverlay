#!/usr/bin/env python3
"""Validate overlay sources and refresh the translation ledger."""

from __future__ import annotations

import csv
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OVERLAYS = ROOT / "english-overlays"
AUDIT = OVERLAYS / "audit"
ANDROID = "{http://schemas.android.com/apk/res/android}"
FORMAT = re.compile(r"%(?!%)(?:\d+\$)?[-+# 0,(]*\d*(?:\.\d+)?[a-zA-Z]")
TARGETS = {
    "launcher-black-blue": ("com.android.launcher.black.blue", "Black/Blue launcher"),
    "backcar": ("com.qf.backcar", "Reverse and auxiliary camera UI"),
    "bluetooth": ("com.qf.bluetooth", "Bluetooth phone and audio UI"),
    "carsettings": ("com.qf.carsettings", "Head-unit and vehicle settings UI"),
    "fancontrol": ("com.qf.fancontrol", "Cooling-fan control UI"),
    "keystudy": ("com.qf.keystudy", "Steering-wheel button learning UI"),
    "musicplayer": ("com.qf.musicplayer", "Local music player UI"),
    "panelkeystudy": ("com.qf.panelkeystudy", "Panel button learning UI"),
    "soundeffect": ("com.qf.soundeffect", "DSP and sound settings UI"),
    "videoplayer": ("com.qf.videoplayer", "Local video player UI"),
}


def load_originals() -> dict[tuple[str, str, str], str]:
    path = AUDIT / "original-values.csv"
    if not path.is_file():
        raise FileNotFoundError(f"Run tools/export-apk-audit.py first: {path}")
    originals: dict[tuple[str, str, str], str] = {}
    with path.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            if row["config"] == "default":
                originals.setdefault((row["target"], row["type"], row["name"]), row["value"])
    return originals


def main() -> int:
    originals = load_originals()
    errors: list[str] = []
    ledger: list[dict[str, str]] = []
    replacements: dict[tuple[str, str], str] = {}

    for slug, (target_package, context) in TARGETS.items():
        source = OVERLAYS / slug
        manifest = ET.parse(source / "AndroidManifest.xml").getroot()
        overlay = manifest.find("overlay")
        package = manifest.attrib.get("package", "")
        actual_target = "" if overlay is None else overlay.attrib.get(ANDROID + "targetPackage", "")
        if package != f"{target_package}.english.overlay":
            errors.append(f"{slug}: unexpected overlay package {package!r}")
        if actual_target != target_package:
            errors.append(f"{slug}: manifest targets {actual_target!r}, expected {target_package!r}")

        strings_path = source / "res" / "values" / "strings.xml"
        root = ET.parse(strings_path).getroot()
        seen: set[str] = set()
        for element in root:
            name = element.attrib.get("name", "")
            if element.tag != "string":
                errors.append(f"{slug}/{name}: only string resources are allowed in this release")
                continue
            if not name or name in seen:
                errors.append(f"{slug}: missing or duplicate resource name {name!r}")
                continue
            seen.add(name)
            key = (slug, "string", name)
            if key not in originals:
                errors.append(f"{slug}/{name}: resource is absent from the supplied target APK")
                continue
            replacement = "".join(element.itertext())
            original = originals[key]
            replacements[(slug, name)] = replacement
            if sorted(FORMAT.findall(original)) != sorted(FORMAT.findall(replacement)):
                errors.append(
                    f"{slug}/{name}: format arguments changed from "
                    f"{FORMAT.findall(original)} to {FORMAT.findall(replacement)}"
                )
            ledger.append(
                {
                    "package": target_package,
                    "resource": name,
                    "original": original,
                    "replacement": replacement,
                    "context": context,
                    "status": "built; device verification pending",
                }
            )

    for slug in ("launcher-black-blue", "carsettings"):
        target_package, _ = TARGETS[slug]
        source = OVERLAYS / "pilot" / slug
        manifest = ET.parse(source / "AndroidManifest.xml").getroot()
        overlay = manifest.find("overlay")
        if manifest.attrib.get("package") != f"{target_package}.english.overlay":
            errors.append(f"pilot/{slug}: unexpected overlay package")
        if overlay is None or overlay.attrib.get(ANDROID + "targetPackage") != target_package:
            errors.append(f"pilot/{slug}: unexpected target package")
        pilot_root = ET.parse(source / "res" / "values" / "strings.xml").getroot()
        pilot_names: set[str] = set()
        for element in pilot_root:
            name = element.attrib.get("name", "")
            replacement = "".join(element.itertext())
            if element.tag != "string" or not name or name in pilot_names:
                errors.append(f"pilot/{slug}: invalid or duplicate resource {name!r}")
                continue
            pilot_names.add(name)
            original = originals.get((slug, "string", name))
            if original is None:
                errors.append(f"pilot/{slug}/{name}: resource is absent from the supplied APK")
            elif sorted(FORMAT.findall(original)) != sorted(FORMAT.findall(replacement)):
                errors.append(f"pilot/{slug}/{name}: format arguments changed")
            if replacements.get((slug, name)) != replacement:
                errors.append(f"pilot/{slug}/{name}: replacement differs from the full overlay")

    if errors:
        print("Overlay validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    ledger.sort(key=lambda row: (row["package"], row["resource"]))
    with (AUDIT / "translations.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=("package", "resource", "original", "replacement", "context", "status"),
        )
        writer.writeheader()
        writer.writerows(ledger)
    print(f"Validated {len(ledger)} corrections across {len(TARGETS)} overlays.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
