tool_sim:
	cd $(BUILD) && \
	xrun $(XRUN_FLAGS) $(DEFINES) \
	-top $(TOP) \
	$(addprefix -f ,$(FILELIST_SV)) \
	$(addprefix -f ,$(FILELIST_VHDL))