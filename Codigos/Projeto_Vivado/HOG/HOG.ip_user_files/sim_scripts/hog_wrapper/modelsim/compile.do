vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xilinx_vip
vlib modelsim_lib/msim/xpm
vlib modelsim_lib/msim/xil_defaultlib
vlib modelsim_lib/msim/lib_cdc_v1_0_2
vlib modelsim_lib/msim/proc_sys_reset_v5_0_13

vmap xilinx_vip modelsim_lib/msim/xilinx_vip
vmap xpm modelsim_lib/msim/xpm
vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib
vmap lib_cdc_v1_0_2 modelsim_lib/msim/lib_cdc_v1_0_2
vmap proc_sys_reset_v5_0_13 modelsim_lib/msim/proc_sys_reset_v5_0_13

vlog -work xilinx_vip  -incr -mfcu  -sv -L axi_vip_v1_1_13 -L smartconnect_v1_0 -L zynq_ultra_ps_e_vip_v1_0_13 -L xilinx_vip "+incdir+C:/Xilinx/Vivado/2022.2/data/xilinx_vip/include" \
"C:/Xilinx/Vivado/2022.2/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"C:/Xilinx/Vivado/2022.2/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"C:/Xilinx/Vivado/2022.2/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"C:/Xilinx/Vivado/2022.2/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"C:/Xilinx/Vivado/2022.2/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"C:/Xilinx/Vivado/2022.2/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"C:/Xilinx/Vivado/2022.2/data/xilinx_vip/hdl/axi_vip_if.sv" \
"C:/Xilinx/Vivado/2022.2/data/xilinx_vip/hdl/clk_vip_if.sv" \
"C:/Xilinx/Vivado/2022.2/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm  -incr -mfcu  -sv -L axi_vip_v1_1_13 -L smartconnect_v1_0 -L zynq_ultra_ps_e_vip_v1_0_13 -L xilinx_vip "+incdir+../../../../HOG.gen/sources_1/bd/hog_wrapper/ipshared/ec67/hdl" "+incdir+../../../../HOG.gen/sources_1/bd/hog_wrapper/ipshared/abef/hdl" "+incdir+../../../../HOG.gen/sources_1/bd/hog_wrapper/ipshared/f0b6/hdl/verilog" "+incdir+../../../../HOG.gen/sources_1/bd/hog_wrapper/ipshared/66be/hdl/verilog" "+incdir+C:/Xilinx/Vivado/2022.2/data/xilinx_vip/include" \
"C:/Xilinx/Vivado/2022.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"C:/Xilinx/Vivado/2022.2/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"C:/Xilinx/Vivado/2022.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm  -93  \
"C:/Xilinx/Vivado/2022.2/data/ip/xpm/xpm_VCOMP.vhd" \

vcom -work xil_defaultlib  -93  \
"../../../bd/hog_wrapper/ipshared/0e7b/hogpack.vhd" \
"../../../bd/hog_wrapper/ipshared/0e7b/win_cross_taps.vhd" \
"../../../bd/hog_wrapper/ipshared/0e7b/grad_mag_bin.vhd" \
"../../../bd/hog_wrapper/ipshared/0e7b/block_binarize_v3.vhd" \
"../../../bd/hog_wrapper/ipshared/0e7b/hog_block_assemble.vhd" \
"../../../bd/hog_wrapper/ipshared/0e7b/hog_cell_histogram.vhd" \
"../../../bd/hog_wrapper/ipshared/0e7b/axis_block_serializer.vhd" \
"../../../bd/hog_wrapper/ipshared/0e7b/hog_pipeline_link.vhd" \
"../../../bd/hog_wrapper/ipshared/0e7b/hog_ip_axi_Nathan.vhd" \
"../../../bd/hog_wrapper/ip/hog_wrapper_hog_ip_axi_Nathan_0_0/sim/hog_wrapper_hog_ip_axi_Nathan_0_0.vhd" \
"d:/TCC/NathanZeidan/NathanSZeidan_TCC/HOG/HOG.gen/sources_1/bd/hog_wrapper/ip/hog_wrapper_zynq_ultra_ps_e_0_0/hog_wrapper_zynq_ultra_ps_e_0_0_sim_netlist.vhdl" \
"d:/TCC/NathanZeidan/NathanSZeidan_TCC/HOG/HOG.gen/sources_1/bd/hog_wrapper/ip/hog_wrapper_axi_dma_0_0/hog_wrapper_axi_dma_0_0_sim_netlist.vhdl" \
"d:/TCC/NathanZeidan/NathanSZeidan_TCC/HOG/HOG.gen/sources_1/bd/hog_wrapper/ip/hog_wrapper_xbar_0/hog_wrapper_xbar_0_sim_netlist.vhdl" \
"d:/TCC/NathanZeidan/NathanSZeidan_TCC/HOG/HOG.gen/sources_1/bd/hog_wrapper/ip/hog_wrapper_auto_ds_0/hog_wrapper_auto_ds_0_sim_netlist.vhdl" \
"d:/TCC/NathanZeidan/NathanSZeidan_TCC/HOG/HOG.gen/sources_1/bd/hog_wrapper/ip/hog_wrapper_auto_pc_0/hog_wrapper_auto_pc_0_sim_netlist.vhdl" \
"d:/TCC/NathanZeidan/NathanSZeidan_TCC/HOG/HOG.gen/sources_1/bd/hog_wrapper/ip/hog_wrapper_auto_ds_1/hog_wrapper_auto_ds_1_sim_netlist.vhdl" \
"d:/TCC/NathanZeidan/NathanSZeidan_TCC/HOG/HOG.gen/sources_1/bd/hog_wrapper/ip/hog_wrapper_auto_pc_1/hog_wrapper_auto_pc_1_sim_netlist.vhdl" \

vcom -work lib_cdc_v1_0_2  -93  \
"../../../../HOG.gen/sources_1/bd/hog_wrapper/ipshared/ef1e/hdl/lib_cdc_v1_0_rfs.vhd" \

vcom -work proc_sys_reset_v5_0_13  -93  \
"../../../../HOG.gen/sources_1/bd/hog_wrapper/ipshared/8842/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib  -93  \
"../../../bd/hog_wrapper/ip/hog_wrapper_rst_ps8_0_99M_0/sim/hog_wrapper_rst_ps8_0_99M_0.vhd" \
"d:/TCC/NathanZeidan/NathanSZeidan_TCC/HOG/HOG.gen/sources_1/bd/hog_wrapper/ip/hog_wrapper_axi_smc_0/hog_wrapper_axi_smc_0_sim_netlist.vhdl" \
"../../../bd/hog_wrapper/sim/hog_wrapper.vhd" \

vlog -work xil_defaultlib \
"glbl.v"

