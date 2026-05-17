# ======================================================================
# DC script for FpAllShared.sv - 6Ops
# Based on flopoco_synth/synopsysDC/run_ppa.tcl Task 14.
# ======================================================================
set_host_options -max_cores 8

remove_design -all

set main_clock_period 0.5

set tag [clock format [clock seconds] -format "%m%d-%H%M"]
set run_dir [file normalize "run-6Ops-T${main_clock_period}-${tag}"]
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
set sixops_dir "$rtl_dir/6Ops"

analyze -library WORK -format sverilog "$rtl_dir/FpuPkg.sv"
analyze -library WORK -format vhdl "$sixops_dir/utils.vhdl"
analyze -library WORK -format sverilog "$sixops_dir/utils/AbsComparator.sv"
analyze -library WORK -format sverilog "$sixops_dir/utils/BarrelShifter.sv"
analyze -library WORK -format sverilog "$sixops_dir/utils/Normalizer.sv"
analyze -library WORK -format sverilog "$sixops_dir/utils/SelFunctionFreq1Uid4.sv"
analyze -library WORK -format sverilog "$sixops_dir/FpAllShared.sv"

elaborate FpAllShared -library WORK
current_design FpAllShared

link
check_design
set_max_area 0

# ----------------------------------------------------------------------
# Clocks & Constraints
# ----------------------------------------------------------------------
create_clock -name clk -period $main_clock_period [get_ports clk]

set inputs_no_clk [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay      -clock clk 0.1 $inputs_no_clk
set_output_delay     -clock clk 0.1 [all_outputs]
set_input_transition 0.05 $inputs_no_clk
set_load 0.1 [all_outputs]

# ----------------------------------------------------------------------
# Compile
# ----------------------------------------------------------------------
compile_ultra

# Export reports
write_file -format verilog -hierarchy -output "$run_dir/out.v"
report_area  -hierarchy > $run_dir/area.rpt
report_power            > $run_dir/power.rpt
report_timing -delay_type max -max_paths 1 > $run_dir/timing_setup.rpt
report_register         > $run_dir/registers.rpt
exit
