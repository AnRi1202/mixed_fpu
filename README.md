# mixed_fpu

Mixed-precision floating-point unit RTL and verification scripts.

## Repository Layout

- `src/rtl/`: SystemVerilog/VHDL RTL
  - `4Ops/`: 4-operation FPU target
  - `6Ops/`: 6-operation shared FPU target
  - `mixed_addmult/`: add/multiply-only mixed target
- `src/tb/`: SystemVerilog, VHDL, and cocotb testbenches
- `simulation/`: Makefiles, filelists, and input vectors for simulation
- `synopsysDC/`: Design Compiler synthesis scripts

## Simulation

Run from `simulation/`.

```bash
cd simulation
make TARGET=6Ops TOP=tb_fpadd_fp32
```

cocotb tests use `Makefile.cocotb`.

```bash
cd simulation
make -f Makefile.cocotb TARGET=6Ops TEST_UNIT=fp32_add
```

Available targets: `v2_1_bf16_add`, `v2_2_bf16_mult`, `4Ops`, `6Ops`, `fp8x4`, `mixed_addmult`.

See [simulation/README.md](simulation/README.md) for TARGET/TEST_UNIT options, waveform viewing, file locations, and how to add new targets or tests.

## Synthesis

Design Compiler scripts live in `synopsysDC/`.

Before running synthesis, edit `synopsysDC/library_setup.tcl` and set your own `.db` library paths.

Example:

```tcl
set target_library_files [list \
    "/path/to/your/standard_cell_typical.db" \
]

set extra_link_library_files [list]
lappend extra_link_library_files "/path/to/your/memory_macro.db"
```

Then run one of:

```bash
dc_shell -f 4Ops.tcl
dc_shell -f 6Ops.tcl
dc_shell -f mixed_addmult.tcl
```

## Notes

- Generated simulation output is ignored under `simulation/build/`.
- DC reports and run directories are ignored under `synopsysDC/run-*`.
- `synopsysDC/library_setup.tcl` contains placeholder library paths and must be edited for your environment.
