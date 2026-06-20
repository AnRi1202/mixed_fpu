### Adding a New RTL with the Same Testbench

1. Choose a target name
2. Add `<target>_sv.f` and/or `<target>_vhdl.f` to `filelists/`
3. Add the created files to the above `.f` file lists
4. Add a `` `define `` for the target name in the wrapper


### Adding a New Testbench


---

## Using Makefile.cocotb

### Basic Usage

```bash
cd simulation/
make -f Makefile.cocotb
```

Defaults: `SIM=xcelium`, `TARGET=6Ops`, `TEST_UNIT=fp32_add`

### Waveform Viewing (xrun)
Change `XRUN_FLAGS` to:
```
XRUN_FLAGS := -v200x -64bit -sv -access +rwc -input "@run 150112ns; exit" -gui
```


### Parameters

| Variable | Default | Description |
|---|---|---|
| `SIM` | `xcelium` | Simulator (only xcelium supported) |
| `TARGET` | `6Ops` | RTL build target. Same options as the Makefile |
| `TEST_UNIT` | `fp32_add` | Test target. Sets TOPLEVEL=`<TEST_UNIT>_wrapper`, MODULE=`<TEST_UNIT>_test` |

### TARGET Options (shared with Makefile)

| `TARGET` | define |
|---|---|
| `v2_1_bf16_add` | `V2_1_BF16_ADD` |
| `v2_2_bf16_mult` | `V2_2_BF16_MULT` |
| `4Ops` | `FOUROPS` |
| `6Ops` | `SIXOPS` |
| `fp8x4` | `FP8X4` |
| `mixed_addmult` | `MIXED_ADDMULT` |

Changing `TARGET` requires a matching `filelists/cocotb/<TARGET>_sv.f`.

```bash
# Example: run bf16_add test with v2_1_bf16_add target
make -f Makefile.cocotb TARGET=v2_1_bf16_add TEST_UNIT=bf16_add

# Example: run fp32_add test with 4Ops target
make -f Makefile.cocotb TARGET=4Ops TEST_UNIT=fp32_add
```

### TEST_UNIT Options

| `TEST_UNIT` | Test script | DUT |
|---|---|---|
| `fp32_add` | `fp32_add_test.py` | `fp32_add_wrapper` |
| `fp32_mult` | `fp32_mult_test.py` | `fp32_mult_wrapper` |
| `bf16_add` | `bf16_add_test.py` | `bf16_add_wrapper` |
| `bf16_mult` | `bf16_mult_test.py` | `bf16_mult_wrapper` |
| `fp8_add` | `fp8_add_test.py` | `fp8_add_wrapper`  |
| `fp8_mult` | `fp8_mult_test.py` | `fp8_mult_wrapper`|

```bash
# Example: run bf16 add test
make -f Makefile.cocotb TEST_UNIT=bf16_add
```

Build output: `build/<SIM>/<TARGET>/<TEST_UNIT>_cocotb/results.xml`

### Test File Locations

- Python tests: `src/tb/cocotb/<TEST_UNIT>_test.py`
- SV wrappers: `src/tb/cocotb_wrapper.sv` (all wrapper definitions)
- File lists: `filelists/cocotb/<TARGET>_sv.f`

### Adding a New Test

1. Create `src/tb/cocotb/<test_unit>_test.py` (define tests with `@cocotb.test()`)
2. Add a `<test_unit>_wrapper` module to `src/tb/cocotb_wrapper.sv`
3. Run with `make -f Makefile.cocotb TEST_UNIT=<test_unit>`



make TARGET=original_sv TOP=tb_fpadd_fp32
