"""megaram.vhd (slot 1 / 2 cartridge RAM) with NVC + cocotb: the collection
modes KUC and Yamanooto (ZEMMIX-58x).  Run with the v9990 venv:
  ../../../v9990/.venv/bin/python run.py"""
from pathlib import Path
from cocotb_tools.runner import get_runner

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SRC = [ROOT / "ocm-pld-dev/esemsx3/src/peripheral/ram.vhd",
       ROOT / "ocm-pld-dev/esemsx3/src/sound/scc/scc_wave.vhd",
       ROOT / "misc/megaram.vhd"]

r = get_runner("nvc")
r.build(sources=SRC, hdl_toplevel="megaram", build_dir=HERE / "sim_build", always=True,
        build_args=["--std=2008"])
r.test(hdl_toplevel="megaram", test_module="test_megaram", test_dir=HERE,
       build_dir=HERE / "sim_build", test_args=["--ieee-warnings=off"])
