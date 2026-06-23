#!/usr/bin/env bash
set -u

# Pokretanje iz root direktorijuma projekta:
#   chmod +x checkit-g2.sh
#   sudo ./checkit-g2.sh pg20220043

if [[ $# -ne 1 ]]; then
  echo "Upotreba: sudo $0 <username>"
  exit 1
fi

U="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

if ! [[ "$U" =~ ^[a-z]{2}[0-9]{8}$ ]]; then
  echo "[GREŠKA] Username mora biti u formatu dve slovne oznake i osam cifara."
  echo "Primer: pg20220043"
  exit 1
fi

IMG="${U}-backend"
TEST_CONT="${U}-test"
BACK_CONT="${U}-back"
FRONT_CONT="${U}-front"
DB_CONT="${U}-db"
NET="${U}-network"
PROJECT="${U}-app"

BACK_FILE="${U}-backend.txt"
STATUS_FILE="${U}.txt"
SUMMARY="sumarna-provera-g2-${U}.txt"
ZIP_FILE="dokazi-integralni-g2-${U}.zip"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

: > "$SUMMARY"

declare -a P N
for i in {1..10}; do
  P[$i]="0.00"
  N[$i]=""
done

log(){ echo "$*"; }
add(){ python3 - "$1" "$2" <<'PY'
import sys
print(f"{float(sys.argv[1])+float(sys.argv[2]):.2f}")
PY
}
cap(){ python3 - "$1" "$2" <<'PY'
import sys
print(f"{min(float(sys.argv[1]),float(sys.argv[2])):.2f}")
PY
}
setp(){ P[$1]="$2"; N[$1]="$3"; }
full_score(){ python3 - "$1" <<'PY'
import sys
try:
    ok=abs(float(sys.argv[1])-1.0) < 1e-9
except Exception:
    ok=False
raise SystemExit(0 if ok else 1)
PY
}
summary_note(){
  local req="$1" score="$2"
  if full_score "$score"; then echo "OK"; return; fi
  case "$req" in
    1) echo "Proveriti backend Dockerfile: Node image, slojeve, port i komandu za pokretanje." ;;
    2) echo "Proveriti da li postoji backend image sa tačno definisanim nazivom." ;;
    3) echo "Proveriti testni kontejner, detached režim, mapiranje porta 4001 i /health endpoint." ;;
    4) echo "Proveriti dokazni fajl za backend i sve četiri zahtevane sekcije." ;;
    5) echo "Proveriti Compose fajl, naziv aplikacije i servise backend, frontend i database." ;;
    6) echo "Proveriti image/build, nazive kontejnera, env fajlove i DB_HOST konfiguraciju." ;;
    7) echo "Proveriti portove, eksplicitnu mrežu i depends_on uslove." ;;
    8) echo "Proveriti bind mount/volume konfiguraciju i PostgreSQL healthcheck." ;;
    9) echo "Proveriti pokretanje aplikacije i zapis sa studentskim podacima i svrhom 'ispit'." ;;
    10) echo "Proveriti statusni fajl i relevantan sadržaj svih pet sekcija." ;;
    *) echo "Proveriti ovaj zahtev detaljno." ;;
  esac
}

running(){ [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" == "true" ]]; }
http_ok(){ curl -fsS --max-time 8 "$1" >/dev/null 2>&1; }
health_running(){ curl -sS --max-time 8 "$1" 2>/dev/null | grep -Eqi '"status"[[:space:]]*:[[:space:]]*"running"'; }

find_compose(){
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  return 1
}

section_content(){
  local file="$1" start="$2" end="$3"
  [[ -f "$file" ]] || return 1
  awk -v s="$start" -v e="$end" '
    BEGIN{on=0; found=0}
    $0~s{on=1; next}
    on && e!="" && $0~e{exit}
    on{line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); if(line!="") found=1}
    END{exit(found?0:1)}
  ' "$file"
}

CJ="$TMP/compose.json"
CFILE="$(find_compose || true)"
CVALID=false
if [[ -n "$CFILE" ]] && docker compose -f "$CFILE" config >/dev/null 2>&1; then
  if docker compose -f "$CFILE" config --format json > "$CJ" 2>/dev/null; then CVALID=true; fi
fi

jqpy(){
  local expr="$1"
  python3 - "$CJ" "$expr" <<'PY'
import json,sys
try:
    data=json.load(open(sys.argv[1],encoding='utf-8'))
    v=eval(sys.argv[2],{'__builtins__':{}},{'data':data})
except Exception:
    v=None
if isinstance(v,bool): print('true' if v else 'false')
elif v is None: print('')
elif isinstance(v,(dict,list)): print(json.dumps(v,ensure_ascii=False))
else: print(v)
PY
}

svc_exists(){ [[ "$(jqpy "'$1' in data.get('services',{})")" == true ]]; }
svc_image(){ jqpy "data.get('services',{}).get('$1',{}).get('image','')"; }
svc_cont(){ jqpy "data.get('services',{}).get('$1',{}).get('container_name','')"; }
svc_build(){ [[ "$(jqpy "data.get('services',{}).get('$1',{}).get('build') not in (None, False, '', [], {})")" == true ]]; }

svc_port(){
  python3 - "$CJ" "$1" "$2" "$3" <<'PY'
import json,sys
p,svc,pub,target=sys.argv[1:]
d=json.load(open(p,encoding='utf-8')); ok=False
for x in d.get('services',{}).get(svc,{}).get('ports',[]):
    if isinstance(x,dict):
        ok |= str(x.get('published',''))==pub and str(x.get('target',''))==target
    elif isinstance(x,str):
        a=x.split(':'); ok |= len(a)>=2 and a[-2]==pub and a[-1].split('/')[0]==target
print('true' if ok else 'false')
PY
}

svc_env(){
  python3 - "$CFILE" "$1" "$2" <<'PY'
import os,re,sys
compose_path,svc,want=sys.argv[1:]
want=os.path.normpath(want).lstrip('./')
text=open(compose_path,encoding='utf-8').read()
try:
    import yaml
    d=yaml.safe_load(text) or {}
    v=d.get('services',{}).get(svc,{}).get('env_file',[])
    if isinstance(v,str): v=[v]
    vals=[x if isinstance(x,str) else x.get('path','') for x in v]
    def clean(path): return os.path.normpath(str(path)).lstrip('./')
    ok=any(clean(x)==want or clean(x).endswith('/'+want) for x in vals)
    print('true' if ok else 'false')
    raise SystemExit
except ImportError:
    pass
except Exception:
    pass
lines=text.splitlines()
sp=re.compile(rf'^\s{{2}}{re.escape(svc)}\s*:\s*$')
np=re.compile(r'^\s{2}[A-Za-z0-9_.-]+\s*:\s*$')
inside=False; block=[]
for line in lines:
    if sp.match(line): inside=True; continue
    if inside and np.match(line): break
    if inside: block.append(line)
joined='\n'.join(block).replace('\\','/')
print('true' if want.replace('\\','/') in joined else 'false')
PY
}

share_net(){
  python3 - "$CJ" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8')); ss=[]
for s in ('backend','frontend','database'):
    n=d.get('services',{}).get(s,{}).get('networks',{})
    ss.append(set(n if isinstance(n,list) else n.keys() if isinstance(n,dict) else []))
print('true' if all(ss) and set.intersection(*ss) else 'false')
PY
}

explicit_net(){
  python3 - "$CJ" "$NET" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8')); want=sys.argv[2]; ok=False
for k,v in d.get('networks',{}).items():
    ok |= k==want or (isinstance(v,dict) and v.get('name')==want)
print('true' if ok else 'false')
PY
}

dep_ok(){
  python3 - "$CJ" "$1" "$2" "$3" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8')); s,dep,want=sys.argv[2:]
v=d.get('services',{}).get(s,{}).get('depends_on',{}); ok=False
if isinstance(v,list): ok=dep in v and want in ('','service_started')
elif isinstance(v,dict) and dep in v:
    x=v[dep]; cond=x.get('condition','service_started') if isinstance(x,dict) else 'service_started'
    ok=(want=='' or cond==want)
print('true' if ok else 'false')
PY
}

vol_ok(){
  python3 - "$CJ" "$1" "$2" "${3:-}" "${4:-false}" <<'PY'
import json,sys
p,svc,target,suffix,needro=sys.argv[1:]
d=json.load(open(p,encoding='utf-8')); ok=False
for v in d.get('services',{}).get(svc,{}).get('volumes',[]):
    src=''; dst=''; ro=False
    if isinstance(v,str):
        a=v.split(':')
        if len(a)==1: dst=a[0]
        else: src,dst=a[0],a[1]; ro=len(a)>2 and 'ro' in a[2:]
    elif isinstance(v,dict):
        src=str(v.get('source','')); dst=str(v.get('target','')); ro=bool(v.get('read_only',False))
    if dst==target and (not suffix or src.endswith(suffix)) and (needro!='true' or ro): ok=True
print('true' if ok else 'false')
PY
}

hc_test(){
  python3 - "$CJ" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
t=d.get('services',{}).get('database',{}).get('healthcheck',{}).get('test',[])
text=' '.join(map(str,t))
r=['pg_isready','-U','student','-d','reservations']
print('true' if all(x in text for x in r) else 'false')
PY
}

hc_val(){
  python3 - "$CJ" "$1" "$2" <<'PY'
import json,re,sys
d=json.load(open(sys.argv[1],encoding='utf-8')); k,w=sys.argv[2:]
v=d.get('services',{}).get('database',{}).get('healthcheck',{}).get(k)
sv=str(v)
if w=='*s': ok=bool(re.fullmatch(r'\d+(?:\.\d+)?s',sv) or re.fullmatch(r'\d+',sv))
elif w=='*int': ok=bool(re.fullmatch(r'\d+',sv))
elif w=='10s': ok=sv in ('10s','10000000000')
else: ok=sv==w
print('true' if ok else 'false')
PY
}

log "G2 PROVERA - $U"
log "Direktorijum: $(pwd)"

# 1 -----------------------------------------------------------------
log ""
log "ZAHTEV 1"
DF="$(find backend -maxdepth 1 -type f -iname dockerfile 2>/dev/null | head -n1 || true)"
S=0
if [[ -n "$DF" ]]; then
  log "Dockerfile: $DF"
  grep -Eqi '^[[:space:]]*FROM[[:space:]]+(node:20-slim|public\.ecr\.aws/docker/library/node:20-slim|mirror\.gcr\.io/library/node:20-slim)' "$DF" && S=$(add "$S" .15)
  grep -Eqi '^[[:space:]]*WORKDIR[[:space:]]+/app' "$DF" && S=$(add "$S" .15)
  grep -Eqi '^[[:space:]]*(COPY|ADD)[[:space:]].*(package(-lock)?\.json|package\*\.json)' "$DF" && S=$(add "$S" .15)
  grep -Eqi 'npm[[:space:]]+install([[:space:]]|$)' "$DF" && S=$(add "$S" .20)
  grep -Eqi '^[[:space:]]*(COPY|ADD)[[:space:]]+\.[[:space:]]+\.?/?[[:space:]]*$' "$DF" && S=$(add "$S" .10)
  grep -Eqi '^[[:space:]]*EXPOSE[[:space:]]+5000([[:space:]]|$)' "$DF" && S=$(add "$S" .10)
  grep -Eqi '(CMD|ENTRYPOINT).*npm.*run.*dev' "$DF" && S=$(add "$S" .15)
  setp 1 "$S" "Dockerfile pronađen i analiziran."
else
  setp 1 0.00 "Backend Dockerfile nije pronađen."
fi

# 2 -----------------------------------------------------------------
log "ZAHTEV 2"
if docker image inspect "$IMG" >/dev/null 2>&1; then setp 2 1.00 "Backend image postoji."; else setp 2 0.00 "Backend image ne postoji."; fi

# 3 -----------------------------------------------------------------
log "ZAHTEV 3"
OK=true
docker container inspect "$TEST_CONT" >/dev/null 2>&1 || OK=false
running "$TEST_CONT" || OK=false
PB="$(docker inspect -f '{{json .HostConfig.PortBindings}}' "$TEST_CONT" 2>/dev/null || true)"
( grep -q '5000/tcp' <<<"$PB" && grep -q '4001' <<<"$PB" ) || OK=false
health_running http://localhost:4001/health || OK=false
if $OK; then setp 3 1.00 "Testni kontejner radi, port je mapiran i health ruta odgovara."; else setp 3 0.00 "Testni kontejner nije aktivan, port nije ispravan ili /health ne odgovara."; fi

# 4 -----------------------------------------------------------------
log "ZAHTEV 4"
S=0
if [[ -f "$BACK_FILE" ]]; then
  section_content "$BACK_FILE" '^BACKEND[[:space:]]+IMAGE[[:space:]]*$' '^BACKEND[[:space:]]+(CONTAINER|LOGS|HEALTH)[[:space:]]*$' && S=$(add "$S" .25)
  section_content "$BACK_FILE" '^BACKEND[[:space:]]+CONTAINER[[:space:]]*$' '^BACKEND[[:space:]]+(LOGS|HEALTH)[[:space:]]*$' && S=$(add "$S" .25)
  section_content "$BACK_FILE" '^BACKEND[[:space:]]+LOGS[[:space:]]*$' '^BACKEND[[:space:]]+HEALTH[[:space:]]*$' && S=$(add "$S" .25)
  section_content "$BACK_FILE" '^BACKEND[[:space:]]+HEALTH[[:space:]]*$' '' && S=$(add "$S" .25)
fi
setp 4 "$S" "0.25 po ispravno popunjenoj sekciji."

# 5 -----------------------------------------------------------------
log "ZAHTEV 5"
S=0
if $CVALID; then
  S=$(add "$S" .25)
  [[ "$(jqpy "data.get('name','')")" == "$PROJECT" ]] && S=$(add "$S" .25)
  svc_exists backend && S=$(add "$S" .15)
  svc_exists frontend && S=$(add "$S" .15)
  svc_exists database && S=$(add "$S" .20)
fi
setp 5 "$S" "Compose validnost, naziv aplikacije i definisana tri servisa."

# Gate 6-9 ------------------------------------------------------------
log "FUNKCIONALNI GATE 6-9"
GATE=true
$CVALID || GATE=false
if $GATE; then
  running "$BACK_CONT" || GATE=false
  running "$FRONT_CONT" || GATE=false
  running "$DB_CONT" || GATE=false
  http_ok http://localhost:7000 || GATE=false
fi

if ! $GATE; then
  for i in 6 7 8 9; do setp "$i" 0.00 "Compose aplikacija nije pokrenuta pre provere."; done
else
  # 6 ---------------------------------------------------------------
  S=0; BACKEND_BUILT=false
  if [[ "$(svc_image backend)" == "$IMG" ]] && ! svc_build backend; then S=$(add "$S" .35)
  elif svc_build backend; then S=$(add "$S" .15); BACKEND_BUILT=true
  fi
  svc_build frontend && S=$(add "$S" .15)
  DB_IMAGE="$(svc_image database)"
  if [[ "$DB_IMAGE" == postgres:16-alpine || "$DB_IMAGE" == public.ecr.aws/docker/library/postgres:16-alpine || "$DB_IMAGE" == mirror.gcr.io/library/postgres:16-alpine ]]; then S=$(add "$S" .15); fi
  [[ "$(svc_cont backend)" == "$BACK_CONT" && "$(svc_cont frontend)" == "$FRONT_CONT" && "$(svc_cont database)" == "$DB_CONT" ]] && S=$(add "$S" .15)
  [[ "$(svc_env backend env/backend.env)" == true && "$(svc_env frontend env/frontend.env)" == true && "$(svc_env database env/database.env)" == true ]] && S=$(add "$S" .10)
  DBH="$(grep -E '^[[:space:]]*DB_HOST=' env/backend.env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '\r"'"'"'[:space:]' || true)"
  [[ "$DBH" == "$DB_CONT" ]] && S=$(add "$S" .10)
  $BACKEND_BUILT && S=$(cap "$S" .65)
  setp 6 "$S" "Backend treba da koristi prethodno kreiran image, a ne Compose build."

  # 7 ---------------------------------------------------------------
  S=0; EXPL=true
  [[ "$(svc_port backend 5000 5000)" == true ]] && S=$(add "$S" .15)
  [[ "$(svc_port frontend 7000 3000)" == true ]] && S=$(add "$S" .15)
  VITE="$(grep -E '^[[:space:]]*VITE_API_URL=' env/frontend.env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '\r"'"'"'[:space:]' || true)"
  [[ "$VITE" == http://localhost:5000 ]] && S=$(add "$S" .10)
  [[ "$(share_net)" == true ]] && S=$(add "$S" .20)
  if [[ "$(explicit_net)" == true ]]; then S=$(add "$S" .20); else EXPL=false; fi
  [[ "$(dep_ok backend database service_healthy)" == true ]] && S=$(add "$S" .10)
  [[ "$(dep_ok frontend backend '')" == true ]] && S=$(add "$S" .10)
  $EXPL || S=$(cap "$S" .50)
  setp 7 "$S" "Bez eksplicitnog naziva mreže maksimalno 0.50."

  # 8 ---------------------------------------------------------------
  S=0
  for c in \
    "$(vol_ok backend /app backend false)" \
    "$(vol_ok backend /app/node_modules '' false)" \
    "$(vol_ok frontend /app frontend false)" \
    "$(vol_ok frontend /app/node_modules '' false)" \
    "$(vol_ok database /var/lib/postgresql/data postgres-data false)" \
    "$(vol_ok database /docker-entrypoint-initdb.d/init.sql init.sql true)" \
    "$(hc_test)"; do [[ "$c" == true ]] && S=$(add "$S" .10); done
  [[ "$(hc_val interval 10s)" == true ]] && S=$(add "$S" .10)
  [[ "$(hc_val timeout 10s)" == true ]] && S=$(add "$S" .10)
  [[ "$(hc_val retries 6)" == true ]] && S=$(add "$S" .10)
  setp 8 "$S" "0.10 po traženom volume ili healthcheck elementu."

  # 9 ---------------------------------------------------------------
  S=0; DBA=false
  running "$BACK_CONT" && running "$FRONT_CONT" && running "$DB_CONT" && S=$(add "$S" .15)
  http_ok http://localhost:7000 && S=$(add "$S" .10)
  HR="$(curl -sS --max-time 8 http://localhost:5000/health 2>/dev/null || true)"
  [[ -n "$HR" ]] && S=$(add "$S" .10)
  if grep -Eqi '"database"[[:space:]]*:[[:space:]]*"available"' <<<"$HR"; then S=$(add "$S" .20); DBA=true; fi
  RR="$(curl -sS --max-time 8 http://localhost:5000/reservations 2>/dev/null || true)"
  Y="${U:2:4}"; I="${U:6:4}"; IN="$(sed 's/^0*//' <<<"$I")"; [[ -n "$IN" ]] || IN=0
  API_STUDENT=false
  if grep -Fqi "$U" <<<"$RR" || grep -Fqi "$Y/$I" <<<"$RR" || grep -Fqi "$Y/$IN" <<<"$RR" || grep -Fqi "$I/$Y" <<<"$RR"; then API_STUDENT=true; fi
  API_PURPOSE=false
  grep -Eqi '"purpose"[[:space:]]*:[[:space:]]*"[^"]*ispit[^"]*"' <<<"$RR" && API_PURPOSE=true
  $API_STUDENT && $API_PURPOSE && S=$(add "$S" .25)
  DBR="$(docker exec "$DB_CONT" psql -U student -d reservations -tAc "SELECT COUNT(*) FROM reservations WHERE purpose ILIKE '%ispit%' AND (student_index ILIKE '%${U}%' OR student_index ILIKE '%${Y}/${I}%' OR student_index ILIKE '%${Y}/${IN}%' OR student_index ILIKE '%${I}/${Y}%');" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ "$DBR" =~ ^[0-9]+$ ]] && (( DBR > 0 )); then S=$(add "$S" .20); fi
  $DBA || S=$(cap "$S" .50)
  setp 9 "$S" "Provera servisa, health endpoint-a, API zapisa i direktnog PostgreSQL zapisa."
fi

# 10 ----------------------------------------------------------------
log "ZAHTEV 10"
S=0
if [[ -f "$STATUS_FILE" ]]; then
  sec_relevant(){
    local st="$1" en="$2" re="$3"
    section_content "$STATUS_FILE" "$st" "$en" || return 1
    awk -v s="$st" -v e="$en" '$0~s{on=1;next} on&&e!=""&&$0~e{exit} on{print}' "$STATUS_FILE" | grep -Eqi "$re"
  }
  sec_relevant '^IMAGES[[:space:]]*$' '^(CONTAINERS|VOLUMES|NETWORKS|COMPOSE)[[:space:]]*$' "${U}-backend|${U}-frontend|${PROJECT}-frontend" && S=$(add "$S" .20)
  sec_relevant '^CONTAINERS[[:space:]]*$' '^(VOLUMES|NETWORKS|COMPOSE)[[:space:]]*$' "${U}-(test|back|front|db)" && S=$(add "$S" .20)
  sec_relevant '^VOLUMES[[:space:]]*$' '^(NETWORKS|COMPOSE)[[:space:]]*$' "postgres-data|${PROJECT}.*postgres-data|${U}" && S=$(add "$S" .20)
  sec_relevant '^NETWORKS[[:space:]]*$' '^COMPOSE[[:space:]]*$' "${U}-network|${U}-app" && S=$(add "$S" .20)
  sec_relevant '^COMPOSE[[:space:]]*$' '' "backend|frontend|database|${U}-(back|front|db)" && S=$(add "$S" .20)
fi
setp 10 "$S" "0.20 po relevantnoj i popunjenoj sekciji."

TOTAL=0
for i in {1..10}; do TOTAL=$(add "$TOTAL" "${P[$i]}"); done
{
  echo "============================================================"
  echo "SUMARNA PROVERA G2 - $U"
  echo "============================================================"
  for i in {1..10}; do printf 'Zahtev %2d: %s / 1.00 - %s\n' "$i" "${P[$i]}" "$(summary_note "$i" "${P[$i]}")"; done
  echo "------------------------------------------------------------"
  echo "UKUPNO: $TOTAL / 10.00"
  echo "============================================================"
} | tee "$SUMMARY"

echo "Sumarni izveštaj: $SUMMARY"

# ZIP DOKAZA ---------------------------------------------------------
ZIP_STAGE="$TMP/zip-${U}"
mkdir -p "$ZIP_STAGE"

add_to_zip(){
  local src="$1"
  local dst="${2:-$1}"
  if [[ -f "$src" ]]; then
    mkdir -p "$ZIP_STAGE/$(dirname "$dst")"
    cp "$src" "$ZIP_STAGE/$dst"
    return 0
  fi
  return 1
}

echo ""
echo "KREIRANJE ZIP FAJLA SA DOKAZIMA"

if [[ -n "${DF:-}" && -f "$DF" ]]; then
  add_to_zip "$DF" "backend/$(basename "$DF")"
else
  echo "[UPOZORENJE] Backend Dockerfile nije pronađen."
fi

if [[ -n "${CFILE:-}" && -f "$CFILE" ]]; then
  add_to_zip "$CFILE" "$(basename "$CFILE")"
else
  echo "[UPOZORENJE] Compose fajl nije pronađen."
fi

for f in env/backend.env env/frontend.env env/database.env; do
  if ! add_to_zip "$f" "$f"; then echo "[UPOZORENJE] Nedostaje $f."; fi
done

for f in "$BACK_FILE" "$STATUS_FILE" "$SUMMARY"; do
  if ! add_to_zip "$f" "$(basename "$f")"; then echo "[UPOZORENJE] Nedostaje $f."; fi
done

rm -f "$ZIP_FILE"

if ! command -v zip >/dev/null 2>&1; then
  echo "[GREŠKA] Komanda zip nije instalirana."
  echo "Instalacija: sudo apt install zip"
  exit 1
fi

if [[ -z "$(find "$ZIP_STAGE" -type f -print -quit)" ]]; then
  echo "[GREŠKA] Nema pronađenih fajlova za kreiranje ZIP-a."
  exit 1
fi

(
  cd "$ZIP_STAGE" || exit 1
  zip -rq "$(pwd)/../$(basename "$ZIP_FILE")" .
)

TMP_ZIP="$TMP/$(basename "$ZIP_FILE")"
if [[ -f "$TMP_ZIP" ]]; then
  mv "$TMP_ZIP" "$ZIP_FILE"
else
  echo "[GREŠKA] ZIP fajl nije uspešno kreiran."
  exit 1
fi

echo "[OK] Kreiran ZIP fajl: $ZIP_FILE"
echo "[OK] Sadržaj ZIP fajla:"
unzip -l "$ZIP_FILE"
