#!/usr/bin/env bash
set -u

fail() {
  printf 'PDF_STATUS: FAILED\nREASON: %s\n' "$1"
  exit 1
}

[ "$#" -eq 1 ] || fail 'usage: prepare_pdf.sh <paper.pdf>'

paper_file=$1
[ -f "$paper_file" ] || fail 'PDF file not found'
command -v pdfinfo >/dev/null 2>&1 || fail 'pdfinfo is unavailable; install Poppler'
command -v pdftotext >/dev/null 2>&1 || fail 'pdftotext is unavailable; install Poppler'

if command -v shasum >/dev/null 2>&1; then
  pdf_sha256=$(shasum -a 256 "$paper_file" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  pdf_sha256=$(sha256sum "$paper_file" | awk '{print $1}')
elif command -v openssl >/dev/null 2>&1; then
  pdf_sha256=$(openssl dgst -sha256 "$paper_file" | awk '{print $NF}')
else
  fail 'no SHA-256 command is available'
fi

pdf_sha256=$(printf '%s' "$pdf_sha256" | tr 'A-F' 'a-f')
printf '%s\n' "$pdf_sha256" | grep -Eq '^[0-9a-f]{64}$' || fail 'could not calculate PDF SHA-256'

pdf_meta=$(pdfinfo "$paper_file" 2>&1) || fail 'pdfinfo could not read the PDF'
pages=$(printf '%s\n' "$pdf_meta" | awk '/^Pages:/ {print $2; exit}')
encrypted=$(printf '%s\n' "$pdf_meta" | awk '/^Encrypted:/ {print $2; exit}')

case "$pages" in
  ''|*[!0-9]*) fail 'PDF page count is unavailable' ;;
  0) fail 'PDF has no pages' ;;
esac

[ "$encrypted" != 'yes' ] || fail 'PDF is encrypted'

temp_dir=$(mktemp -d /tmp/paper-ingest.XXXXXX) || fail 'could not create a temporary directory'
text_path="$temp_dir/paper.txt"

if ! pdftotext -layout "$paper_file" "$text_path"; then
  fail 'pdftotext could not extract the PDF'
fi

text_chars=$(wc -m < "$text_path" | tr -d ' ')
text_lines=$(wc -l < "$text_path" | tr -d ' ')
chars_per_page=$((text_chars / pages))

if [ "$text_chars" -lt 500 ] || [ "$chars_per_page" -lt 80 ]; then
  status='NEEDS_OCR'
  text_mode='sparse'
elif [ "$text_chars" -gt 200000 ]; then
  status='OK'
  text_mode='large'
else
  status='OK'
  text_mode='normal'
fi

printf 'PDF_STATUS: %s\n' "$status"
printf 'PDF_SHA256: %s\n' "$pdf_sha256"
printf 'TEXT_PATH: %s\n' "$text_path"
printf 'PAGES: %s\n' "$pages"
printf 'TEXT_CHARS: %s\n' "$text_chars"
printf 'TEXT_LINES: %s\n' "$text_lines"
printf 'CHARS_PER_PAGE: %s\n' "$chars_per_page"
printf 'TEXT_MODE: %s\n' "$text_mode"
