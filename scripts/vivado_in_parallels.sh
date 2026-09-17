#!/usr/bin/env bash
# Run tcl/cordic_synth.tcl inside a Parallels Windows VM from macOS (Apple
# Silicon hosts can't run Vivado natively) and copy reports/ back.
#
#   ./scripts/vivado_in_parallels.sh 17 15            # make vm-synth
#   ./scripts/vivado_in_parallels.sh 17 8 12 16 20    # make vm-sweep
#
# The working tree (rtl/, tcl/, constraints/ -- no commit needed) is zipped into
# a folder the VM sees through Parallels shared folders, unzipped to a local VM
# disk, built with `prlctl exec --current-user`, and reports/ is copied back
# the same way. One Vivado process per N_ITER, so a flaky run under x86
# emulation ("couldn't read file ...") only repeats that configuration.
#
# Environment overrides:
#   CORDIC_VM          Parallels VM name             (default "Windows 11")
#   CORDIC_VIVADO      vivado.bat inside the VM      (default C:\Xilinx\Vivado\2024.1\bin\vivado.bat)
#   CORDIC_VM_WORKDIR  build directory inside the VM (default C:\cordic)
#   CORDIC_SHARE_MAC   macOS side of a shared folder (default ~/Downloads/cordic-vm-transfer)
#   CORDIC_SHARE_VM    same folder as the VM sees it (default Z:\Downloads\cordic-vm-transfer)
#   CORDIC_TRIES       attempts per configuration    (default 3)
set -euo pipefail
cd "$(dirname "$0")/.."

PERIOD=""
case "${1:-}" in period:*) PERIOD="$1"; shift ;; esac      # optional: period:4.000 overrides the XDC clock (':' because cmd.exe splits args on '=')
[ $# -ge 2 ] || { echo "usage: $0 [period:<ns>] <W> <N_ITER> [<N_ITER> ...]"; exit 2; }
W="$1"; shift
VM="${CORDIC_VM:-Windows 11}"
VIVADO="${CORDIC_VIVADO:-C:\\Xilinx\\Vivado\\2024.1\\bin\\vivado.bat}"
WORK="${CORDIC_VM_WORKDIR:-C:\\cordic}"
SHARE_MAC="${CORDIC_SHARE_MAC:-$HOME/Downloads/cordic-vm-transfer}"
SHARE_VM="${CORDIC_SHARE_VM:-Z:\\Downloads\\cordic-vm-transfer}"
TRIES="${CORDIC_TRIES:-3}"

command -v prlctl >/dev/null || { echo "prlctl not found (Parallels Desktop Pro/Business required)"; exit 1; }
state="$(prlctl list -a -o status,name | awk -v vm="$VM" '$0 ~ vm {print $1}')"
case "$state" in
  running)   ;;
  suspended) echo "resuming VM '$VM'"; prlctl resume "$VM" >/dev/null ;;
  stopped)   echo "starting VM '$VM'"; prlctl start  "$VM" >/dev/null ;;
  paused)    prlctl unpause "$VM" >/dev/null ;;
  *) echo "Parallels VM '$VM' not found (set CORDIC_VM)"; exit 1 ;;
esac

vm() { prlctl exec "$VM" --current-user "$@"; }
for _ in $(seq 1 30); do vm cmd /c "echo ready" >/dev/null 2>&1 && break; sleep 5; done

mkdir -p "$SHARE_MAC" reports build
rm -rf "$SHARE_MAC/out" "$SHARE_MAC/cordic.zip"
zip -qr "$SHARE_MAC/cordic.zip" rtl tcl constraints reports
vm powershell -NoProfile -Command "Remove-Item -Recurse -Force '$WORK' -ErrorAction SilentlyContinue; Expand-Archive -Path '$SHARE_VM\\cordic.zip' -DestinationPath '$WORK'" >/dev/null
echo "Copied working tree to $VM:$WORK"

status=0
for n in "$@"; do
  ok=1
  for i in $(seq 1 "$TRIES"); do
    log="vivado_N${n}_W${W}${PERIOD:+_${PERIOD#period:}ns}_try$i.log"
    echo "== Vivado OOC N_ITER=$n W=$W, attempt $i/$TRIES (log: build/$log)"
    vm cmd /c "cd /d $WORK && \"$VIVADO\" -mode batch -nolog -nojournal -source tcl/cordic_synth.tcl -tclargs $PERIOD $W $n > $log 2>&1" || true
    vm cmd /c "mkdir \"$SHARE_VM\\out\" 2>nul & xcopy /e /y /i /q \"$WORK\\reports\" \"$SHARE_VM\\out\\reports\" >nul & copy /y \"$WORK\\$log\" \"$SHARE_VM\\out\\\" >nul" || true
    cp "$SHARE_MAC/out/$log" build/ 2>/dev/null || true
    grep -E "^ERROR|^=== N_ITER" "build/$log" | head -10 || true
    if grep -q "^=== N_ITER=$n W=$W:" "build/$log" 2>/dev/null; then ok=0; break; fi
    echo "-- run did not complete, retrying"
  done
  [ "$ok" -eq 0 ] || { echo "-- N_ITER=$n failed after $TRIES attempts (see build/)"; status=1; }
done

cp -R "$SHARE_MAC/out/reports/." reports/ 2>/dev/null || true
rm -rf "$SHARE_MAC"
[ "$status" -eq 0 ] && echo "Done: reports/ppa.csv + reports/N*_W$W/"
exit "$status"
