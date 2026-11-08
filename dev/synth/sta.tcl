read_liberty ../pdk/gf180_ss_125C_3v00.lib
read_verilog netlist.v
link_design tt_um_road_racer
create_clock -name clk -period 40 [get_ports clk]
set_clock_uncertainty 0.25 [get_clocks clk]
set_clock_transition 0.15 [get_clocks clk]
set inputs [lsearch -inline -all -not -exact [all_inputs] [get_ports clk]]
set_input_delay 8 -clock clk $inputs
set_output_delay 8 -clock clk [all_outputs]
set_driving_cell -lib_cell gf180mcu_fd_sc_mcu7t5v0__inv_1 -pin ZN $inputs
set_load 0.07291 [all_outputs]
report_checks -path_delay max -group_path_count 12 -endpoint_path_count 1 -format end
report_checks -path_delay max -fields {fanout cap slew} -digits 2
report_wns
report_tns
