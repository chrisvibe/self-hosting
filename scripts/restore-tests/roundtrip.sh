#!/usr/bin/env bash
# Restore round-trip test against REAL production backups, run ON elis.
#
# SAFETY: never touches prod data. It (a) triggers a fresh, non-destructive backup_db dump via
# the existing backup sidecar, (b) restores it into a THROWAWAY postgres container (bkptest-*),
# (c) fingerprint-compares the throwaway against the LIVE prod DB using READ-ONLY queries, and
# (d) for tar services, extracts the archive into a THROWAWAY dir and checks an immutable anchor
# file against the live volume mounted READ-ONLY. Prod containers/volumes are never written.
#
# Usage: bkptest.sh [parvis|nextcloud|matrix|immich|all]
set -uo pipefail

SERVICES="${1:-all}"
[ "$SERVICES" = "all" ] && SERVICES="parvis nextcloud matrix immich"
REPO_BASE=/home/elis/self-hosting/services
FP_SQL=/tmp/bkptest/fp.sql
TESTPW=bkptest_pw
RC_TOTAL=0

c_red() { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn() { printf '\033[32m%s\033[0m\n' "$*"; }
hr() { echo "============================================================"; }

# Read-only fingerprint of a LIVE prod DB (peer/trust via unix socket, its own env user).
fp_prod() { docker exec -i "$1" sh -c 'psql -U "$POSTGRES_USER" -d "'"$2"'" -tA' < "$FP_SQL" 2>/dev/null | tr -d '[:space:]'; }
# Fingerprint of the throwaway DB (localhost trust).
fp_thr()  { docker exec -i "$1" sh -c 'psql -U "'"$3"'" -d "'"$2"'" -h 127.0.0.1 -tA' < "$FP_SQL" 2>/dev/null | tr -d '[:space:]'; }

wait_ready() {
  for _ in $(seq 1 90); do
    docker exec "$1" pg_isready -h 127.0.0.1 -U "$2" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

# ---- per-service DB restore test ------------------------------------------------------------
test_db() {
  svc="$1"; img="$2"; db="$3"; user="$4"; prodc="$5"; vol="$6"; kind="$7"; net="$8"; bimg="$9"
  ct="bkptest-${svc}-db"
  echo "--- DB restore: $svc (restore-img=$img db=$db user=$user kind=$kind) ---"
  docker rm -f "$ct" >/dev/null 2>&1 || true

  # Fresh dump via a THROWAWAY backup container on the prod DB network (pg_dump/pg_dumpall are
  # read-only on prod). We don't exec the deployed sidecar because its /scripts bind mount went
  # stale after the scripts dir was rewritten; this also re-proves the deployed backup_db.sh.
  echo "[1] fresh non-destructive dump via throwaway backup container on net=$net (host=$prodc)"
  PW="$(docker exec "$prodc" printenv POSTGRES_PASSWORD)"
  if ! docker run --rm --network "$net" \
        -e POSTGRES_HOST="$prodc" -e POSTGRES_PORT=5432 \
        -e POSTGRES_USER="$user" -e POSTGRES_DB="$db" -e POSTGRES_PASSWORD="$PW" \
        -e SERVICE_NAME="$svc" -e BACKUP_DIR=/backups \
        -v "${vol}":/backups -v "${REPO_BASE}/${svc}/scripts":/scripts:ro \
        "$bimg" sh /scripts/backup_db.sh >/dev/null 2>&1; then
    c_red "FAIL: fresh backup_db.sh errored"; return 1
  fi

  echo "[2] read-only prod fingerprint (before)"
  fp_before="$(fp_prod "$prodc" "$db")"; echo "    prod  = $fp_before"

  echo "[3] start throwaway container + wait ready"
  docker run -d --name "$ct" \
    -e POSTGRES_USER="$user" -e POSTGRES_PASSWORD="$TESTPW" -e POSTGRES_DB="$db" \
    -v "${vol}":/backups:ro -v "${REPO_BASE}/${svc}/scripts":/scripts:ro -v /tmp/bkptest:/work:ro \
    "$img" >/dev/null
  wait_ready "$ct" "$user" || { c_red "FAIL: throwaway never became ready"; return 1; }

  echo "[4] locate latest dump"
  if [ "$kind" = "dumpall" ]; then
    dump="$(docker exec "$ct" sh -c "ls -t /backups/${svc}_db_*.sql.gz 2>/dev/null | head -1")"
  else
    dump="$(docker exec "$ct" sh -c "ls -t /backups/${svc}_db_*.dump 2>/dev/null | head -1")"
  fi
  [ -n "$dump" ] || { c_red "FAIL: no dump found in $vol"; return 1; }
  echo "    dump = $dump"

  echo "[5] run DEPLOYED restore_db.sh into throwaway (FORCE=1)"
  if ! docker exec \
        -e POSTGRES_HOST=127.0.0.1 -e POSTGRES_PORT=5432 \
        -e POSTGRES_DB="$db" -e POSTGRES_USER="$user" -e POSTGRES_PASSWORD="$TESTPW" \
        -e SERVICE_NAME="$svc" -e FORCE=1 \
        "$ct" sh /scripts/restore_db.sh "$dump"; then
    c_red "FAIL: restore_db.sh returned non-zero"; return 1
  fi

  echo "[6] fingerprint compare (throwaway vs live prod)"
  fp_thr_v="$(fp_thr "$ct" "$db" "$user")"; echo "    restored = $fp_thr_v"
  fp_after="$(fp_prod "$prodc" "$db")";     echo "    prod(after) = $fp_after"

  # tables|rows|exts. tables+exts must match exactly; rows must lie within the prod before/after
  # bracket (live writes between dump and now are legitimate drift, not a restore bug).
  IFS='|' read -r t_t r_t e_t <<EOF
$fp_thr_v
EOF
  IFS='|' read -r t_b r_b e_b <<EOF
$fp_before
EOF
  IFS='|' read -r t_a r_a e_a <<EOF
$fp_after
EOF
  ok=1
  [ "$t_t" = "$t_b" ] && [ "$t_t" = "$t_a" ] || { c_red "    tables mismatch: thr=$t_t before=$t_b after=$t_a"; ok=0; }
  [ "$e_t" = "$e_b" ] && [ "$e_t" = "$e_a" ] || { c_red "    extensions mismatch: thr=[$e_t] prod=[$e_b]"; ok=0; }
  lo=$r_b; hi=$r_a; [ "$lo" -gt "$hi" ] 2>/dev/null && { lo=$r_a; hi=$r_b; }
  if [ "$r_t" -ge "$lo" ] 2>/dev/null && [ "$r_t" -le "$hi" ] 2>/dev/null; then :; else
    # exact equality also acceptable (quiet DB)
    [ "$r_t" = "$r_b" ] || { c_red "    rows out of bracket: restored=$r_t prod=[$lo,$hi]"; ok=0; }
  fi
  [ "$ok" = 1 ] && { c_grn "    PASS db: $svc (tables=$t_t rows=$r_t exts ok)"; return 0; } || return 1
}

# ---- tar / config restore test --------------------------------------------------------------
test_tar() {
  svc="$1"; vol="$2"; livevol="$3"; script="$4"; dirvar="$5"; pat="$6"; anchor="$7"; dotfile="$8"; liveanchor="$9"
  echo "--- archive restore: $svc ($script, anchor=$anchor) ---"
  # Runs entirely in a throwaway alpine container: preseed junk in /target, restore the real
  # archive into it, prove the wipe removed junk + the archive extracted faithfully (diff vs an
  # independent extraction), and that the immutable anchor matches the LIVE volume (ro).
  docker run --rm -i \
    -v "${vol}":/backups:ro \
    -v "${REPO_BASE}/${svc}/scripts":/scripts:ro \
    -v "${livevol}":/live:ro \
    -e "${dirvar}=/target" -e FORCE=1 \
    alpine sh -s -- "$svc" "$pat" "$anchor" "$dotfile" "$script" "$dirvar" "$liveanchor" <<'INNER'
set -eu
svc="$1"; pat="$2"; anchor="$3"; dotfile="$4"; script="$5"; dirvar="$6"; liveanchor="$7"
arch="$(ls -t /backups/${svc}_${pat}_*.tar.gz 2>/dev/null | head -1)"
[ -n "$arch" ] || { echo "FAIL: no archive ${svc}_${pat}_*.tar.gz"; exit 1; }
echo "    archive = $arch"
mkdir -p /target /ref
echo "JUNK-SHOULD-BE-WIPED" > /target/_junk_stale_file
# run the DEPLOYED restore script (DATA_DIR/CONFIG_DIR=/target already in env)
sh "/scripts/$script" "$arch"
[ -e /target/_junk_stale_file ] && { echo "FAIL: wipe did not remove pre-seeded junk"; exit 1; }
# independent extraction for a faithful-extract diff (incl dotfiles)
tar xzf "$arch" -C /ref
if ! diff -r /target /ref >/dev/null 2>&1; then echo "FAIL: restored tree != archive contents"; diff -r /target /ref | head; exit 1; fi
# dotfile present?
[ -n "$dotfile" ] && { [ -e "/target/$dotfile" ] || { echo "FAIL: dotfile $dotfile missing after restore"; exit 1; }; }
# immutable anchor must match the LIVE volume byte-for-byte
a_new="$(sha256sum /target/$anchor | cut -d" " -f1)"
a_live="$(sha256sum /live/$liveanchor | cut -d" " -f1)"
echo "    anchor restored=$a_new"
echo "    anchor live    =$a_live"
[ "$a_new" = "$a_live" ] || { echo "FAIL: anchor $anchor differs from live volume"; exit 1; }
echo "PASS-INNER"
INNER
}

for svc in $SERVICES; do
  hr; echo "SERVICE: $svc"; hr
  rc=0
  case "$svc" in
    parvis)    test_db parvis    postgres:18-alpine   parvis    parvis    parvis-db      parvis_backups    fc      parvis_internal   postgres:18-alpine   || rc=1 ;;
    nextcloud) test_db nextcloud postgres:18-alpine   nextcloud nextcloud nextcloud-db   nextcloud_backups fc      nextcloud_default postgres:18-alpine   || rc=1
               out="$(test_tar nextcloud nextcloud_backups nextcloud_app restore_config.sh CONFIG_DIR config config.php .htaccess config/config.php 2>&1)"; echo "$out"
               echo "$out" | grep -q PASS-INNER && c_grn "    PASS config: nextcloud" || { c_red "    FAIL config: nextcloud"; rc=1; } ;;
    matrix)    test_db matrix    postgres:18.1-alpine synapse   synapse   matrix-db-1    matrix_backups    fc      matrix_net        postgres:18.1-alpine || rc=1
               out="$(test_tar matrix matrix_backups synapse_data restore_data.sh DATA_DIR data tubiformis.work.signing.key '' tubiformis.work.signing.key 2>&1)"; echo "$out"
               echo "$out" | grep -q PASS-INNER && c_grn "    PASS data: matrix" || { c_red "    FAIL data: matrix"; rc=1; } ;;
    immich)    test_db immich    ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0 immich postgres immich_postgres immich_backups dumpall immich_default postgres:14-alpine || rc=1 ;;
  esac
  docker rm -f "bkptest-${svc}-db" >/dev/null 2>&1 || true
  [ "$rc" = 0 ] && c_grn ">>> $svc: ALL CHECKS PASSED" || { c_red ">>> $svc: FAILED"; RC_TOTAL=1; }
done

hr
[ "$RC_TOTAL" = 0 ] && c_grn "OVERALL: ALL RESTORE TESTS PASSED" || c_red "OVERALL: FAILURES PRESENT"
exit $RC_TOTAL
