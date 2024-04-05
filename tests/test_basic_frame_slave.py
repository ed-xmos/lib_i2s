# Copyright 2015-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
from i2s_master_checker import Clock
from i2s_slave_checker import I2SSlaveChecker
from pathlib import Path
import Pyxsim
import pytest

DEBUG = False

num_in_out_args = {"4ch_in,4ch_out": (4, 4),
                   "2ch_in,2ch_out": (2, 2),
                   "1ch_in,1ch_out": (1, 1),
                   "4ch_in,0ch_out": (4, 0),
                   "0ch_in,4ch_out": (0, 4)}

bitdepth_args = {"8b": 8,
                 "16b": 16,
                 "32b": 32}

@pytest.mark.parametrize("bitdepth", bitdepth_args.values(), ids=bitdepth_args.keys())
@pytest.mark.parametrize(("num_in", "num_out"), num_in_out_args.values(), ids=num_in_out_args.keys())
def test_i2s_basic_frame_slave(capfd, request, nightly, bitdepth, num_in, num_out):
    testlevel = '0' if nightly else '1'
    id_string = f"{bitdepth}_{num_in}_{num_out}"
    id_string += "_smoke" if testlevel == '1' else ""

    cwd = Path(request.fspath).parent
    binary = f'{cwd}/i2s_frame_slave_test/bin/{id_string}/i2s_frame_slave_test_{id_string}.xe'

    clk = Clock("tile[0]:XS1_PORT_1A")

    checker = I2SSlaveChecker(
        "tile[0]:XS1_PORT_1B",
        "tile[0]:XS1_PORT_1C",
        ["tile[0]:XS1_PORT_1H","tile[0]:XS1_PORT_1I","tile[0]:XS1_PORT_1J", "tile[0]:XS1_PORT_1K"],
        ["tile[0]:XS1_PORT_1D","tile[0]:XS1_PORT_1E","tile[0]:XS1_PORT_1F", "tile[0]:XS1_PORT_1G"],
        "tile[0]:XS1_PORT_1L",
        "tile[0]:XS1_PORT_16A",
        "tile[0]:XS1_PORT_1M",
         clk,
         frame_based=True)  # We're running the frame-based master, so can have variable data widths

    tester = Pyxsim.testers.AssertiveComparisonTester(
        f'{cwd}/expected/slave_test.expect',
        regexp = True,
        ordered = True,
        suppress_multidrive_messages=True,
        ignore=["CONFIG:.*"]
    )

    if DEBUG:
        Pyxsim.run_on_simulator(
            binary,
            tester=tester,
            simthreads=[clk, checker],
            build_env = {"BITDEPTHS":f"{bitdepth}", "NUMS_IN_OUT":f'{num_in};{num_out}', "SMOKE":testlevel},
            #clean_before_build=True,
            simargs=[
                "--vcd-tracing",
                f"-o i2s_trace_{num_in}_{num_out}.vcd -tile tile[0] -cycles -ports -ports-detailed -cores -instructions",
                "--trace-to",
                f"i2s_trace_{num_in}_{num_out}.txt",
            ],
            capfd=capfd
        )
    else:
        Pyxsim.run_on_simulator(
            binary,
            tester=tester,
            simthreads=[clk, checker],
            #clean_before_build=True,
            build_env = {"BITDEPTHS":f"{bitdepth}", "NUMS_IN_OUT":f'{num_in};{num_out}', "SMOKE":testlevel},
            simargs=[],
            capfd=capfd
        )
