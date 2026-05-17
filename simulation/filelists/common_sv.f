# ROOT = mixed_fpu/simulation
# package
$ROOT/src/rtl/FpuPkg.sv


# $ROOT is determined by Makefile
##### tb  ###### 
### TODO: 本当はv2_bfにtbを置くのではなく、共通にするべき
$ROOT/src/tb/add_mult/tb_fpadd_bf16x2.sv
$ROOT/src/tb/add_mult/tb_fpadd_fp32.sv
$ROOT/src/tb/add_mult/tb_fpmult_bf16x2.sv
$ROOT/src/tb/add_mult/tb_fpmult_fp32.sv

# wrapper
$ROOT/src/tb/fpall_shared_logic_wrapper.sv 

