#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUBSPEC="$ROOT_DIR/pubspec.yaml"
VERSION_JSON="$ROOT_DIR/web/version.json"

python3 - "$PUBSPEC" "$VERSION_JSON" <<'PY'
import json
import pathlib
import re
import sys
from datetime import date

pubspec = pathlib.Path(sys.argv[1])
version_json = pathlib.Path(sys.argv[2])

text = pubspec.read_text()
version_match = re.search(r"^version:\s*([^\s]+)\s*$", text, re.MULTILINE)
if not version_match:
    raise SystemExit("Could not parse version")

current = version_match.group(1)
legacy = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)\+(\d+)", current)
date_based = re.fullmatch(r"(\d{2})\.(\d{1,2})\.(\d{1,2})\+(\d{6})(\d{2})", current)

today = date.today()
current_day_code = int(today.strftime("%y%m%d"))

same_day_counter = 1
if date_based:
    yy = int(date_based.group(1))
    mm = int(date_based.group(2))
    dd = int(date_based.group(3))
    parsed_date = date(2000 + yy, mm, dd)
    current_day_num = int(f"{yy:02d}{mm:02d}{dd:02d}")
    persisted_counter = int(date_based.group(5))
    if parsed_date == today and current_day_num == current_day_code:
        same_day_counter = persisted_counter + 1
elif legacy:
    same_day_counter = 1
else:
    same_day_counter = 1

display_yy = int(today.strftime("%y"))
display_mm = today.month
display_dd = today.day

display_version = f"{display_yy}.{display_mm}.{display_dd}"
date_num = int(today.strftime("%y%m%d"))
build = date_num * 100 + same_day_counter
new_version = f"{display_version}+{build}"

updated = re.sub(r"(?m)^version:\s*.*$", f"version: {new_version}", text, count=1)
if updated == text:
    raise SystemExit("Could not update pubspec version")
pubspec.write_text(updated)

version_json.write_text(json.dumps({
    "app_name": "bandroadie",
    "version": display_version,
    "build_number": str(build),
    "package_name": "bandroadie"
}, indent=2))

print(f"Updated version: {new_version}")
PY

echo "Generated version.json → $(grep '^version:' pubspec.yaml | awk '{print $2}')"
