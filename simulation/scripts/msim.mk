tool_sim:
	cd $(BUILD) && vlib work
	cd $(BUILD) && vlog $(MSIM_VLOG_FLAGS) $(DEFINES) $(addprefix -f ,$(FILELIST_SV))
	cd $(BUILD) && vcom $(MSIM_VCOM_FLAGS) $(addprefix -f ,$(FILELIST_VHDL))
	cd $(BUILD) && vsim $(MSIM_VSIM_FLAGS) $(TOP)