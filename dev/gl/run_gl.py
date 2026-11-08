"""Gate-level check, as Tiny Tapeout's GL test runs it, but stricter.

Synthesises the design to GF180 cells (dev/synth/netlist.ys), simulates the
netlist with the cells' functional models alongside the RTL, and checks over
900,000 clocks (two frames) that the outputs never go X/Z and that the
gate-level outputs equal the RTL outputs on every clock.
Needs dev/pdk (python3 dev/tools/setup_pdk.py), yosys and iverilog.
    python3 dev/gl/run_gl.py [cycles]
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEV = os.path.join(HERE, "..")
PDK = os.path.join(DEV, "pdk", "sc7")
BUILD = os.path.join(HERE, "build")
os.makedirs(BUILD, exist_ok=True)
cycles = sys.argv[1] if len(sys.argv) > 1 else "900000"

# 1. gate-level netlist
subprocess.run(["yosys", "-q", "netlist.ys"], cwd=os.path.join(DEV, "synth"), check=True,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
netlist = os.path.join(DEV, "synth", "netlist.v")

# 2. functional models of the cells it uses. The flip-flop models refer to a
# primitive by an older name, so an alias of the current primitive is written.
used = sorted(set(re.findall(r"gf180mcu_fd_sc_mcu7t5v0__\w+", open(netlist).read())))
files = []
for cell in used:
    base = re.sub(r"_\d+$", "", cell.replace("gf180mcu_fd_sc_mcu7t5v0__", ""))
    path = os.path.join(PDK, "cells", base, cell + ".functional.v")
    if not os.path.exists(path):
        sys.exit("missing cell model " + path)
    files.append(path)
udp = open(os.path.join(PDK, "models", "udp_n_iq_ff", "gf180mcu_mcu7t5v0__udp_n_iq_ff.v")).read()
alias = os.path.join(BUILD, "udp_alias.v")
open(alias, "w").write(udp.replace("gf180mcu_fd_sc_mcu7t5v0__udp_n_iq_ff",
                                   "UDP_GF018hv5v_mcu_sc7_TT_1P8V_25C_verilog_nonpg_MGM_N_IQ_FF_UDP")
                          .replace("GF180MCU_FD_SC_MCU7T5V0__UDP_N_IQ_FF_V", "UDP_ALIAS_N_IQ_FF"))
files.append(alias)

# 3. the RTL as a second copy, renamed so both can sit in one testbench
sys.path.insert(0, os.path.join(DEV, "tools"))
import combine
rtl_text, _top = combine.build()
rtl = os.path.join(BUILD, "rtl_top.v")
open(rtl, "w").write(re.sub(r"^module tt_um_\w+", "module rtl_top", rtl_text, count=1, flags=re.M))

exe = os.path.join(BUILD, "gl.vvp")
# The cell models rely on implicit wires, so they go first: the design files
# set `default_nettype none`, which would otherwise carry over into them.
subprocess.run(["iverilog", "-g2012", "-DFUNCTIONAL", "-DCYCLES=" + cycles, "-o", exe] + files +
               [os.path.join(HERE, "tb_gl.v"), netlist, rtl], check=True)
out = subprocess.run(["vvp", "-n", exe], capture_output=True, text=True).stdout
print("\n".join(l for l in out.splitlines() if not l.startswith("tb_gl.v")))
ok = "X/Z on outputs in 0 clocks" in out and "mismatches 0" in out
print("GATE-LEVEL PASS" if ok else "GATE-LEVEL FAIL")
sys.exit(0 if ok else 1)
