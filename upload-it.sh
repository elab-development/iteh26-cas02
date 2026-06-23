#!/usr/bin/env bash
set -u

# Pokretanje:
#   chmod +x upload-integralni.sh
#   sudo ./upload-integralni.sh g1 tn20185005
#   sudo ./upload-integralni.sh g2 tn20185005
# Opcioni treći argument je direktorijum sa rezultatima.

GOOGLE_SCRIPT_URL="https://script.google.com/macros/s/AKfycbwsTCEWOfnLPDhY1rGJZwZ7E0LoVT5wgv8XHbTZAC2fXJ4LSHX07knvxHXw5DvmWKzw/exec"
ASSIGNMENT="integralni"

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Upotreba: sudo $0 <g1|g2> <username> [folder-sa-rezultatima]"
  echo "Primer G1: sudo $0 g1 tn20185005"
  echo "Primer G2: sudo $0 g2 tn20185005"
  exit 1
fi

GROUP="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
USERNAME="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
RESULTS_DIR="${3:-.}"

case "$GROUP" in
  g1|g2) ;;
  *)
    echo "[GREŠKA] Grupa mora biti g1 ili g2."
    exit 1
    ;;
esac

if ! [[ "$USERNAME" =~ ^[a-z]{2}[0-9]{8}$ ]]; then
  echo "[GREŠKA] Username mora biti u formatu dve slovne oznake i osam cifara."
  echo "Primer: tn20185005"
  exit 1
fi

if [[ "$GOOGLE_SCRIPT_URL" == "OVDE_UNESI_WEB_APP_URL_KOJI_SE_ZAVRSAVA_SA_EXEC" ]] ||
   [[ ! "$GOOGLE_SCRIPT_URL" =~ /exec$ ]]; then
  echo "[GREŠKA] U skripti nije podešen ispravan GOOGLE_SCRIPT_URL."
  echo "Unesi Web App URL koji se završava sa /exec."
  exit 1
fi

SUMMARY_FILE="${RESULTS_DIR}/sumarna-provera-${GROUP}-${USERNAME}.txt"
ZIP_FILE="${RESULTS_DIR}/dokazi-integralni-${GROUP}-${USERNAME}.zip"
UPLOAD_RESPONSE_FILE="${RESULTS_DIR}/google-upload-integralni-${GROUP}-${USERNAME}.json"

echo "============================================================"
echo "UPLOAD REZULTATA INTEGRALNOG ZADATKA"
echo "============================================================"
echo "Grupa:      ${GROUP^^}"
echo "Username:   $USERNAME"
echo "Assignment: $ASSIGNMENT"
echo ""

if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "[GREŠKA] Nije pronađen sumarni izveštaj:"
  echo "$SUMMARY_FILE"
  exit 1
fi

if [[ ! -f "$ZIP_FILE" ]]; then
  echo "[GREŠKA] Nije pronađen ZIP sa dokazima:"
  echo "$ZIP_FILE"
  echo "Prvo pokreni odgovarajuću check skriptu koja kreira ZIP."
  exit 1
fi

GRADE="$(
  grep -E '^UKUPNO:[[:space:]]*[0-9]+([.][0-9]+)?[[:space:]]*/[[:space:]]*10([.]00)?' "$SUMMARY_FILE" |
    tail -n 1 |
    sed -E 's/^UKUPNO:[[:space:]]*([0-9]+([.][0-9]+)?).*/\1/'
)"

if ! [[ "$GRADE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "[GREŠKA] Nije moguće pročitati broj poena iz:"
  echo "$SUMMARY_FILE"
  echo "Očekivani format je: UKUPNO: 8.90 / 10.00"
  exit 1
fi

GRADE_VALID="$(python3 - "$GRADE" <<'PY'
import sys
try:
    grade = float(sys.argv[1])
except ValueError:
    print("false")
    raise SystemExit
print("true" if 0 <= grade <= 10 else "false")
PY
)"

if [[ "$GRADE_VALID" != "true" ]]; then
  echo "[GREŠKA] Broj poena mora biti između 0 i 10."
  exit 1
fi

ZIP_FILE_NAME="$(basename "$ZIP_FILE")"
ZIP_SIZE="$(du -h "$ZIP_FILE" | awk '{print $1}')"

echo "[OK] Sumarni izveštaj: $SUMMARY_FILE"
echo "[OK] ZIP dokazi:       $ZIP_FILE"
echo "[OK] Veličina ZIP-a:    $ZIP_SIZE"
echo "[OK] Broj poena:        $GRADE"
echo ""

read -r -s -p "Unesite upload šifru: " UPLOAD_SECRET
echo ""
echo ""

if [[ -z "$UPLOAD_SECRET" ]]; then
  echo "[GREŠKA] Upload šifra nije uneta."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
PAYLOAD_FILE="${TMP_DIR}/payload.json"
RESPONSE_RAW="${TMP_DIR}/response.txt"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Pripremam ZIP i JSON zahtev..."

python3 - \
  "$UPLOAD_SECRET" \
  "$USERNAME" \
  "$GRADE" \
  "$ASSIGNMENT" \
  "$GROUP" \
  "$ZIP_FILE_NAME" \
  "$ZIP_FILE" \
  "$PAYLOAD_FILE" <<'PY'
import base64
import json
import sys
from pathlib import Path

secret, username, grade, assignment, group, zip_file_name, zip_path, payload_path = sys.argv[1:]
zip_bytes = Path(zip_path).read_bytes()
payload = {
    "secret": secret,
    "username": username,
    "grade": float(grade),
    "assignment": assignment,
    "group": group,
    "zipFileName": zip_file_name,
    "zipBase64": base64.b64encode(zip_bytes).decode("ascii"),
}
Path(payload_path).write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
PY

if [[ $? -ne 0 || ! -s "$PAYLOAD_FILE" ]]; then
  echo "[GREŠKA] Kreiranje JSON zahteva nije uspelo."
  exit 1
fi

echo "[OK] Zahtev je pripremljen."
echo "Šaljem rezultat na Google Apps Script..."
echo ""

HTTP_STATUS="$(
  curl -L -sS \
    --connect-timeout 20 \
    --max-time 180 \
    -o "$RESPONSE_RAW" \
    -w '%{http_code}' \
    "$GOOGLE_SCRIPT_URL" \
    -H "Content-Type: application/json" \
    --data-binary "@${PAYLOAD_FILE}"
)"
CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  echo "[GREŠKA] Slanje zahteva nije uspelo. curl exit code: $CURL_EXIT"
  exit 1
fi

cp "$RESPONSE_RAW" "$UPLOAD_RESPONSE_FILE"

echo "Google Apps Script odgovor:"
cat "$UPLOAD_RESPONSE_FILE"
echo ""
echo ""

SUCCESS="$(python3 - "$UPLOAD_RESPONSE_FILE" <<'PY'
import json
import sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    print("true" if data.get("success") is True else "false")
except Exception:
    print("false")
PY
)"

if [[ "$HTTP_STATUS" == "200" && "$SUCCESS" == "true" ]]; then
  echo "============================================================"
  echo "[OK] UPLOAD JE USPEŠAN"
  echo "============================================================"
  echo "[OK] Grupa: $GROUP"
  echo "[OK] Username: $USERNAME"
  echo "[OK] Broj poena: $GRADE"
  echo "[OK] ZIP je sačuvan na Google Drive-u."
  echo "[OK] Rezultat je upisan u Google Sheet."
  echo "[OK] Odgovor je sačuvan u:"
  echo "     $UPLOAD_RESPONSE_FILE"
  exit 0
fi

echo "============================================================"
echo "[GREŠKA] UPLOAD NIJE USPEO"
echo "============================================================"
echo "HTTP status: $HTTP_STATUS"
echo "Odgovor je sačuvan u:"
echo "$UPLOAD_RESPONSE_FILE"
exit 1
