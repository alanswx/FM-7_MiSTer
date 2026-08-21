#!/usr/bin/env bash
#
# Re-OCR a Japanese PDF with Japanese language data.
#
#   tools/reocr.sh <file.pdf> [first-page] [last-page]
#
# Writes <file>.jpn.txt beside the PDF, one "=== page N ===" banner per page,
# and keeps per-page .txt files under <file>.jpn.d/ so an interrupted run
# resumes instead of starting over.
#
# WHY THIS EXISTS
#
# The `_djvu.txt` that ships with an archive.org scan of a Japanese book is
# frequently produced by running ENGLISH OCR over Japanese pages. It looks like
# a text layer and greps like one, so it is easy to trust. It is close to
# worthless: 330 pages of FM-7/8活用研究 yielded 1.4 MB in which every register
# name appears exactly once and the prose is shattered into per-character
# fragments. Compare one line, same page:
#
#   archive.org (eng OCR):  PE EE 所 / FM- フ / 日 62fkp オ / に に 還 叶 拉
#   this script (jpn+eng):  エディタ・アセンブラ マシン語ダンプ・リスト
#
# So: **a negative grep against a `_djvu.txt` is not evidence the book lacks the
# thing.** Re-OCR first, then grep, and prefer tools/ocrgrep.py over plain grep
# even afterwards, because OCR still confuses 0/O, 1/l/I, 5/S, 8/B and inserts
# spaces inside words.
#
# SCHEMATIC PAGES ARE DIFFERENT. OCR of a circuit diagram is worthless whatever
# the language -- the text is tiny, rotated and scattered among the symbols.
# Render those and LOOK at them:
#
#   pdftoppm -f 300 -l 300 -r 110 -png "book.pdf" /tmp/p && open /tmp/p-300.png
#
# 77AVEMU's comments cite this book's schematics by page ("pp.300", "pp.294").
#
# Needs: tesseract with jpn data. If `tesseract --list-langs` lacks jpn:
#   curl -sL -o /opt/homebrew/share/tessdata/jpn.traineddata \
#     https://github.com/tesseract-ocr/tessdata_best/raw/main/jpn.traineddata
set -uo pipefail

PDF=${1:?usage: reocr.sh <file.pdf> [first-page] [last-page]}
[ -f "$PDF" ] || { echo "no such file: $PDF" >&2; exit 1; }

tesseract --list-langs 2>/dev/null | grep -qx jpn || {
  echo "tesseract has no 'jpn' data -- see the header of this script" >&2; exit 1; }

TOTAL=$(pdfinfo "$PDF" 2>/dev/null | awk '/^Pages:/{print $2}')
FIRST=${2:-1}
LAST=${3:-${TOTAL:-1}}

OUT="${PDF%.pdf}.jpn.txt"
WORK="${PDF%.pdf}.jpn.d"
mkdir -p "$WORK"

echo "re-OCR $(basename "$PDF"): pages $FIRST-$LAST of ${TOTAL:-?}" >&2

for p in $(seq "$FIRST" "$LAST"); do
  txt="$WORK/$(printf '%05d' "$p").txt"
  [ -s "$txt" ] && continue                     # resume
  png="$WORK/tmp-$p"
  pdftoppm -f "$p" -l "$p" -r 300 -png "$PDF" "$png" 2>/dev/null
  img=$(ls "$png"*.png 2>/dev/null | head -1)
  [ -z "$img" ] && { : > "$txt"; continue; }
  # --psm 6 ("one uniform block") beats the default on scanned book pages;
  # jpn+eng because the register tables and mnemonics are Latin.
  tesseract "$img" "${txt%.txt}" -l jpn+eng --psm 6 >/dev/null 2>&1
  rm -f "$img"
  [ $((p % 25)) -eq 0 ] && echo "  ...page $p" >&2
done

: > "$OUT"
for txt in "$WORK"/[0-9]*.txt; do
  p=$(basename "$txt" .txt | sed 's/^0*//')
  printf '=== page %s ===\n' "${p:-0}" >> "$OUT"
  cat "$txt" >> "$OUT"
done
echo "wrote $OUT ($(wc -c < "$OUT") bytes)" >&2
