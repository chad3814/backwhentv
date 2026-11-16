#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_FILE="$ROOT/open-metadata-api-key"
OUT_DIR="$ROOT/Config"
OUT_FILE="$OUT_DIR/Local.xcconfig"

if [ ! -f "$KEY_FILE" ]; then
  echo "No $KEY_FILE; OpenMetadata lookups will be disabled."
  exit 0
fi

KEY="$(tr -d '\r\n' < "$KEY_FILE")"
if [ -z "$KEY" ]; then
  echo "$KEY_FILE is empty; OpenMetadata lookups will be disabled."
  exit 0
fi

mkdir -p "$OUT_DIR"
printf 'OPEN_METADATA_API_KEY = %s\n' "$KEY" > "$OUT_FILE"
echo "Wrote Config/Local.xcconfig"
