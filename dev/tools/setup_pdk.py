"""Fetch the GF180 7-track standard-cell files the local checks need.

Puts everything in dev/pdk/ (git-ignored):
  pdk/sc7/                     sparse clone of google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0
  pdk/gf180_tt_025C_3v30.lib   typical corner, used for area
  pdk/gf180_ss_125C_3v00.lib   slow corner (125 C, 3.0 V), used for timing
The cell library splits each corner's liberty into a header plus one file per
cell; this merges them into one library per corner.
    python3 dev/tools/setup_pdk.py
"""
import glob, os, subprocess

PDK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pdk")
REPO = "https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0.git"
CORNERS = ["tt_025C_3v30", "ss_125C_3v00"]

os.makedirs(PDK, exist_ok=True)
sc7 = os.path.join(PDK, "sc7")
if not os.path.isdir(os.path.join(sc7, ".git")):
    subprocess.run(["git", "clone", "--depth", "1", "--filter=blob:none", "--sparse", REPO, sc7], check=True)
patterns = ["/liberty/", "/models/", "/cells/*/*.functional.v"] + \
           ["/cells/*/*__%s.lib" % c for c in CORNERS]
subprocess.run(["git", "-C", sc7, "sparse-checkout", "set", "--no-cone"] + patterns, check=True)

for corner in CORNERS:
    head = open(os.path.join(sc7, "liberty", "gf180mcu_fd_sc_mcu7t5v0__%s.lib" % corner)).read().rstrip()
    assert head.endswith("}")
    cells = sorted(glob.glob(os.path.join(sc7, "cells", "*", "*__%s.lib" % corner)))
    body = "\n".join(open(c).read() for c in cells)
    out = os.path.join(PDK, "gf180_%s.lib" % corner)
    open(out, "w").write(head[:-1] + "\n" + body + "\n}\n")
    print("wrote %s (%d cells)" % (os.path.relpath(out), len(cells)))
