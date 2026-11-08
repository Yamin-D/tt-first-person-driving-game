# Development commands. Run from dev/:  make <target>
#
#   setup     fetch the GF180 cell library into dev/pdk (needed by area/sta/gl)
#   model     run the Python model: frames.png, drive.gif, engine.wav in dev/model
#   units     unit tests of each block against the model (Icarus Verilog)
#   chip      whole chip from dev/rtl (both wheel versions), frames read from the VGA pins vs the model (Verilator)
#   project   regenerate ../src/project.v from dev/rtl (the file Tiny Tapeout builds)
#   check     src/project.v is up to date, and the whole-chip test passes on it
#   area      cell area per block and % of a 1x1 tile (Yosys on GF180 cells)
#   sta       slow-corner setup timing estimate (OpenSTA)
#   gl        gate-level simulation vs RTL, no X/Z on the outputs
#   all       everything above except setup and model, in order
#
# Before pushing a design change: make all

PY ?= python3

.PHONY: setup model units chip project check area sta gl all

setup:
	$(PY) tools/setup_pdk.py

model:
	cd model && $(PY) road_model.py

units:
	$(PY) test/check_units.py

chip:
	ROAD_FULL=0 $(PY) test/check_chip.py
	ROAD_FULL=1 $(PY) test/check_chip.py

project:
	$(PY) tools/combine.py

check:
	$(PY) tools/combine.py --check
	ROAD_SRC=project $(PY) test/check_chip.py

area:
	$(PY) tools/report.py area

sta:
	$(PY) tools/report.py sta

gl:
	$(PY) gl/run_gl.py

all: units chip project check area sta gl
