#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$root/build/registers"}
mkdir -p "$out"
out=$(cd "$out" && pwd)
verilator --binary --timing --assert -MAKEFLAGS OPT_GLOBAL=-O2 -j 2 --top-module register_contract_tb \
  -Wno-fatal -I"$root/HDL" --Mdir "$out/obj" \
  "$root/tests/register_contract_tb.sv" "$root"/HDL/*.sv > "$out/compile.log" 2>&1
exe="$out/obj/Vregister_contract_tb"
if [[ -f "$exe.exe" ]]; then exe="$exe.exe"; fi
"$exe" 2>&1 | tee "$out/test.log"
