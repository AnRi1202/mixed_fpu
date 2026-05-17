# ======================================================================
# DC script (retiming for AddMulOnlyRet.sv - mixed_addmult)
# ======================================================================
set_host_options -max_cores 8

remove_design -all

# --- Pipeline Stage Selection ---
set num_pipe [expr {[info exists env(PARAM_PIPE)] ? $env(PARAM_PIPE) : 1}]
set main_clock_period 0.5

set tag [clock format [clock seconds] -format "%m%d-%H%M"]
set run_dir [file normalize "run-mixed_addmult-P${num_pipe}-T${main_clock_period}-${tag}"]
set WORK_DIR [file normalize "${run_dir}/WORK"]

file mkdir $run_dir
file mkdir $WORK_DIR

define_design_lib WORK -path $WORK_DIR
set_app_var alib_library_analysis_path $WORK_DIR

# ----------------------------------------------------------------------
# Libraries
# ----------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set library_setup_file "$script_dir/library_setup.tcl"

if {![file exists $library_setup_file]} {
    error "Missing $library_setup_file. Create it and set your local .db library paths."
}

source $library_setup_file

if {![info exists target_library_files] || [llength $target_library_files] == 0} {
    error "target_library_files must be set in $library_setup_file"
}
if {![info exists extra_link_library_files]} {
    set extra_link_library_files [list]
}

set search_path [list .]
foreach lib_file [concat $target_library_files $extra_link_library_files] {
    if {![file exists $lib_file]} {
        error "Library file not found: $lib_file"
    }
    lappend search_path [file dirname $lib_file]
}
set search_path [lsort -unique $search_path]
set target_library $target_library_files
set link_library [concat [list *] $target_library_files $extra_link_library_files]

# ----------------------------------------------------------------------
# Analyze & Elaborate
# ----------------------------------------------------------------------
set rtl_dir "../src/rtl"
set mixed_addmult_dir "$rtl_dir/mixed_addmult"
set sixops_dir "$rtl_dir/6Ops"

analyze -library WORK -format vhdl "$sixops_dir/utils.vhdl"
analyze -library WORK -format sverilog "$rtl_dir/FpuPkg.sv"
analyze -library WORK -format sverilog "$sixops_dir/utils/AbsComparator.sv"
analyze -library WORK -format sverilog "$sixops_dir/utils/BarrelShifter.sv"
analyze -library WORK -format sverilog "$sixops_dir/utils/Normalizer.sv"
analyze -library WORK -format sverilog "$mixed_addmult_dir/AddMulOnly.sv"
analyze -library WORK -format sverilog "$mixed_addmult_dir/AddMulOnlyRet.sv"

elaborate AddMulOnlyRet -parameters "NUM_PIPE_STAGES=${num_pipe}"
current_design AddMulOnlyRet

link
check_design

# ----------------------------------------------------------------------
# Constraints
# ----------------------------------------------------------------------
create_clock -name clk -period $main_clock_period [get_ports clk]
set_clock_uncertainty 0.0 clk

set inputs_no_clk [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay      -clock clk 0.1 $inputs_no_clk
set_output_delay     -clock clk 0.1 [all_outputs]
set_input_transition 0.05 $inputs_no_clk
set_load 0.1 [all_outputs]

# Enable retiming infrastructure 
set_optimize_registers true
set_app_var compile_enable_register_merging true
set_app_var compile_sequential_area_recovery true

# ----------------------------------------------------------------------
# Compile
# ----------------------------------------------------------------------
compile_ultra -retime

# Export reports
write_file -format verilog -hierarchy -output "$run_dir/out_afterRetime.v"
report_area  -hierarchy > $run_dir/area.rpt
report_power            > $run_dir/power.rpt
report_timing -delay_type max -max_paths 1 > $run_dir/timing_setup.rpt
report_register         > $run_dir/registers.rpt
exit
