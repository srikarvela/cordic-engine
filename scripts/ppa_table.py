"""Join reports/ppa.csv (Vivado post-route numbers, written by tcl/cordic_synth.tcl)
with docs/quantization_sweep.csv (MATLAB accuracy numbers) into docs/ppa_table.md:
area and Fmax versus accuracy, one row per synthesized configuration.
"""
import csv
import math
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def main():
    with open(os.path.join(ROOT, "docs", "quantization_sweep.csv"), newline="") as f:
        acc = {(r["N"], r["W"]): r for r in csv.DictReader(f)}
    with open(os.path.join(ROOT, "reports", "ppa.csv"), newline="") as f:
        ppa = sorted(csv.DictReader(f), key=lambda r: (float(r["period_ns"]), int(r["W"]), int(r["N"])))

    lines = [
        "| N_ITER | W | latency (cycles) | LUT | FF | CARRY4 | DSP | WNS @ period (ns) | Fmax (MHz) "
        "| max sin/cos error | effective bits | max phase error (rad) |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in ppa:
        a = acc[(r["N"], r["W"])]
        err = float(a["max_err_sincos"])
        lut = int(r["LUT"]) + int(r["SRL"])
        lines.append(
            f"| {r['N']} | {r['W']} | {int(r['N']) + 6} | {lut} | {r['FF']} | {r['CARRY4']} | {r['DSP']} "
            f"| {float(r['WNS_ns']):+.3f} @ {float(r['period_ns']):.3f} | {float(r['Fmax_MHz']):.1f} "
            f"| {err:.2e} | {-math.log2(err):.1f} | {float(a['max_err_phase_rad']):.2e} |"
        )
    out = os.path.join(ROOT, "docs", "ppa_table.md")
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
