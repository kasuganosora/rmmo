#!/usr/bin/env bash
# Headless Godot regression runner for /workspace/rmmo/tools/test_*.gd (SceneTree only).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
  if [[ -x /workspace/godot/Godot_v4.7.2-stable_linux.x86_64 ]]; then
    GODOT=/workspace/godot/Godot_v4.7.2-stable_linux.x86_64
  elif [[ -x /home/box/.local/bin/godot ]]; then
    GODOT=/home/box/.local/bin/godot
  else
    echo "ERROR: Godot binary not found" >&2
    exit 127
  fi
fi
TIMEOUT_SEC="${TIMEOUT_SEC:-90}"
OUT_DIR="${OUT_DIR:-/tmp/rmmo_test_logs}"
mkdir -p "$OUT_DIR"
SUMMARY="$OUT_DIR/summary.tsv"
: > "$SUMMARY"

pass=0; fail=0; timeout=0; skip=0; total=0
shopt -s nullglob
mapfile -t tests < <(printf '%s\n' "$ROOT"/tools/test_*.gd | sort)

echo "Godot: $GODOT"
echo "Root:  $ROOT"
echo "Tests: ${#tests[@]}"
echo "Timeout: ${TIMEOUT_SEC}s each"
echo

for t in "${tests[@]}"; do
  base="$(basename "$t")"
  # Skip non-SceneTree stubs (e.g. collision helpers loaded by other tests).
  if ! head -n 5 "$t" | grep -q 'extends SceneTree'; then
    echo "[skip] $base (not SceneTree)"
    skip=$((skip+1))
    printf 'SKIP\t0\t0\t%s\n' "$base" >> "$SUMMARY"
    continue
  fi
  total=$((total+1))
  log="$OUT_DIR/${base%.gd}.log"
  echo -n "[$total] $base ... "
  start=$(date +%s)
  set +e
  timeout --signal=KILL "${TIMEOUT_SEC}s" "$GODOT" --path "$ROOT" --headless -s "res://tools/$base" >"$log" 2>&1
  ec=$?
  set -e
  end=$(date +%s)
  elapsed=$((end-start))
  if [[ $ec -eq 124 || $ec -eq 137 ]]; then
    status=TIMEOUT
    timeout=$((timeout+1))
  elif [[ $ec -eq 0 ]]; then
    status=PASS
    pass=$((pass+1))
  else
    status=FAIL
    fail=$((fail+1))
  fi
  echo "$status (exit=$ec, ${elapsed}s)"
  printf '%s\t%s\t%s\t%s\n' "$status" "$ec" "$elapsed" "$base" >> "$SUMMARY"
done

echo
echo "==== SUMMARY ===="
echo "PASS=$pass FAIL=$fail TIMEOUT=$timeout SKIP=$skip RUN=$total"
echo "Log dir: $OUT_DIR"
echo "TSV: $SUMMARY"
if [[ $fail -gt 0 || $timeout -gt 0 ]]; then
  exit 1
fi
exit 0
