"""Build reports/ppa.csv and docs/ppa_table.md from the committed Vivado reports.

Every number is parsed from reports/N<N>_W<W>[_<period>ns]/utilization.rpt and
timing_summary.rpt (written by tcl/cordic_synth.tcl) and joined with the MATLAB
accuracy numbers in docs/quantization_sweep.csv. Nothing is counted from the
netlist by other means, so the table, the CSV and the .rpt files cannot disagree.

Column meanings (Vivado report_utilization / report_timing_summary names):
  LUT      "Slice LUTs"      -- every LUT used, logic plus LUT-as-memory (SRL)
  LUT_logic "LUT as Logic"   -- the subset used as logic
  LUT_mem  "LUT as Memory"   -- the subset used as SRL/distributed RAM
  FF       "Slice Registers"
  CARRY4, DSP ("DSPs"), BRAM ("Block RAM Tile")
  WNS/WHS  worst setup / hold slack, with the failing-endpoint counts
  Fmax     1000 / (period - WNS): the setup-limited clock, from post-route slack
"""
import csv
import glob
import math
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

UTIL_FIELDS = {
    "LUT": "Slice LUTs",
    "LUT_logic": "LUT as Logic",
    "LUT_mem": "LUT as Memory",
    "FF": "Slice Registers",
    "CARRY4": "CARRY4",
    "DSP": "DSPs",
    "BRAM": "Block RAM Tile",
}


def util_field(text, name):
    m = re.search(r"^\|\s*" + re.escape(name) + r"\s*\|\s*(\d+)\s*\|", text, re.M)
    if not m:
        raise ValueError(f"'{name}' not found in utilization report")
    return int(m.group(1))


def parse_run(rdir):
    tag = os.path.basename(rdir)
    m = re.fullmatch(r"N(\d+)_W(\d+)(?:_([\d.]+)ns)?", tag)
    if not m:
        return None
    with open(os.path.join(rdir, "utilization.rpt")) as f:
        util = f.read()
    with open(os.path.join(rdir, "timing_summary.rpt")) as f:
        tim = f.read()
    row = {"N": int(m.group(1)), "W": int(m.group(2))}
    row.update({k: util_field(util, v) for k, v in UTIL_FIELDS.items()})

    clk = re.search(r"^clk\s+\{\d+\.\d+\s+\d+\.\d+\}\s+([\d.]+)\s", tim, re.M)
    setup = re.search(r"^Setup\s*:\s*(\d+)\s+Failing Endpoints,\s+Worst Slack\s+(-?[\d.]+)ns", tim, re.M)
    hold = re.search(r"^Hold\s*:\s*(\d+)\s+Failing Endpoints,\s+Worst Slack\s+(-?[\d.]+)ns", tim, re.M)
    if not (clk and setup and hold):
        raise ValueError(f"timing summary fields not found in {rdir}")
    row["period_ns"] = float(clk.group(1))
    row["WNS_ns"] = float(setup.group(2))
    row["setup_fail"] = int(setup.group(1))
    row["WHS_ns"] = float(hold.group(2))
    row["hold_fail"] = int(hold.group(1))
    row["constraints_met"] = "no" if "Timing constraints are not met" in tim else "yes"
    row["Fmax_MHz"] = round(1000.0 / (row["period_ns"] - row["WNS_ns"]), 1)
    return row


def main():
    runs = [parse_run(d) for d in sorted(glob.glob(os.path.join(ROOT, "reports", "N*_W*")))]
    runs = sorted((r for r in runs if r), key=lambda r: (r["period_ns"], r["W"], r["N"]))
    if not runs:
        raise SystemExit("no reports/N*_W*/ directories found (run `make sweep` first)")

    cols = ["N", "W", "LUT", "LUT_logic", "LUT_mem", "FF", "CARRY4", "DSP", "BRAM", "period_ns",
            "WNS_ns", "setup_fail", "WHS_ns", "hold_fail", "constraints_met", "Fmax_MHz"]
    csv_path = os.path.join(ROOT, "reports", "ppa.csv")
    with open(csv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(runs)

    with open(os.path.join(ROOT, "docs", "quantization_sweep.csv"), newline="") as f:
        acc = {(int(r["N"]), int(r["W"])): r for r in csv.DictReader(f)}

    lines = [
        "| N_ITER | W | latency (cycles) | Slice LUTs (logic + SRL) | FF | CARRY4 | DSP | period (ns) "
        "| WNS (ns) / failing | WHS (ns) / failing | Fmax (MHz) | max sin/cos error | effective bits "
        "| max phase error (rad) |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in runs:
        a = acc[(r["N"], r["W"])]
        err = float(a["max_err_sincos"])
        lines.append(
            f"| {r['N']} | {r['W']} | {r['N'] + 6} | {r['LUT']} ({r['LUT_logic']} + {r['LUT_mem']}) "
            f"| {r['FF']} | {r['CARRY4']} | {r['DSP']} | {r['period_ns']:.3f} "
            f"| {r['WNS_ns']:+.3f} / {r['setup_fail']} | {r['WHS_ns']:+.3f} / {r['hold_fail']} "
            f"| {r['Fmax_MHz']:.1f} | {err:.2e} | {-math.log2(err):.1f} | {float(a['max_err_phase_rad']):.2e} |"
        )
    out = os.path.join(ROOT, "docs", "ppa_table.md")
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"wrote {csv_path} and {out}")


if __name__ == "__main__":
    main()
