#!/usr/bin/env bash
set -u

fail() {
  printf 'INGEST_STATE: FAILED\nREASON: %s\n' "$1"
  exit 1
}

[ "$#" -eq 2 ] || fail 'usage: check_ingest_state.sh <pdf_sha256> <report.md>'

pdf_sha256=$(printf '%s' "$1" | tr 'A-F' 'a-f')
report_file=$2

printf '%s\n' "$pdf_sha256" | grep -Eq '^[0-9a-f]{64}$' || fail 'invalid PDF SHA-256'

if [ ! -f "$report_file" ]; then
  printf 'INGEST_STATE: NEW\n'
  exit 0
fi

report_sha256=$(awk '
  NR == 1 && $0 == "---" { in_frontmatter = 1; next }
  in_frontmatter && $0 == "---" { exit }
  in_frontmatter && /^[[:space:]]*source_sha256[[:space:]]*:/ {
    sub(/^[^:]*:[[:space:]]*/, "")
    gsub(/^[[:space:]"'\'' ]+|[[:space:]"'\'' ]+$/, "")
    print tolower($0)
    exit
  }
' "$report_file")

if [ -z "$report_sha256" ]; then
  printf 'INGEST_STATE: LEGACY\n'
elif ! printf '%s\n' "$report_sha256" | grep -Eq '^[0-9a-f]{64}$'; then
  fail 'report source_sha256 is invalid'
elif [ "$report_sha256" = "$pdf_sha256" ]; then
  printf 'INGEST_STATE: UNCHANGED\n'
else
  printf 'INGEST_STATE: CHANGED\n'
fi
