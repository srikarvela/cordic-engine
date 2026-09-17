"""Bit-exact diff of the RTL simulation output (build/cordic_hw_N<N>_W<W>.csv,
written by tb/tb_cordic_sweep.sv) against the MATLAB fixed-point golden model
(tb/vectors/cordic_N<N>_W<W>.csv, written by matlab/export_vectors.m). Both
implement the identical integer algorithm (truncating shifts, round-half-up,
saturate), so a correct RTL matches row-for-row exactly, not within a tolerance.

    python3 matlab/diff_cordic.py            # every config that has been simulated
    python3 matlab/diff_cordic.py 15 17      # one config
"""
import csv
import glob
import os
import re
import sys

KEYS = ["xo", "yo", "zo"]


def load_csv(path):
    with open(path, newline="") as f:
        return {int(r["seq"]): r for r in csv.DictReader(f)}


def diff(root, n, w):
    tag = f"N{n}_W{w}"
    hw_path = os.path.join(root, "build", f"cordic_hw_{tag}.csv")
    golden_path = os.path.join(root, "tb", "vectors", f"cordic_{tag}.csv")
    for path, hint in ((golden_path, "make matlab"), (hw_path, "make sim")):
        if not os.path.exists(path):
            print(f"FAIL {tag}: {path} not found (run `{hint}` first)")
            return False

    hw, golden = load_csv(hw_path), load_csv(golden_path)
    if set(hw) != set(golden):
        print(f"FAIL {tag}: row count/seq mismatch (hw={len(hw)} rows, golden={len(golden)} rows)")
        return False

    mismatches = [s for s in sorted(hw) if any(int(hw[s][k]) != int(golden[s][k]) for k in KEYS)]
    if mismatches:
        print(f"FAIL {tag}: {len(mismatches)}/{len(hw)} rows mismatched")
        for s in mismatches[:10]:
            g = golden[s]
            print(f"  seq={s} mode={g['mode']} in=({g['x']},{g['y']},{g['z']}) "
                  f"hw=({hw[s]['xo']},{hw[s]['yo']},{hw[s]['zo']}) golden=({g['xo']},{g['yo']},{g['zo']})")
        if len(mismatches) > 10:
            print(f"  ... and {len(mismatches) - 10} more")
        return False

    sat = sum(1 for g in golden.values() if any(abs(int(g[k]) + 0.5) >= 2 ** (w - 1) - 1 for k in KEYS[:2]))
    nvec = sum(1 for g in golden.values() if g["mode"] == "1")
    print(f"PASS {tag}: {len(hw)}/{len(hw)} rows bit-exact "
          f"({len(hw) - nvec} rotation, {nvec} vectoring, {sat} saturated)")
    return True


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    if len(sys.argv) == 3:
        cfgs = [(int(sys.argv[1]), int(sys.argv[2]))]
    else:
        found = (re.search(r"cordic_hw_N(\d+)_W(\d+)\.csv$", p)
                 for p in glob.glob(os.path.join(root, "build", "cordic_hw_*.csv")))
        cfgs = sorted((int(m.group(1)), int(m.group(2))) for m in found if m)
        if not cfgs:
            print("FAIL: no build/cordic_hw_*.csv found (run `make sim` first)")
            sys.exit(1)
    ok = [diff(root, n, w) for n, w in cfgs]
    sys.exit(0 if all(ok) else 1)


if __name__ == "__main__":
    main()
