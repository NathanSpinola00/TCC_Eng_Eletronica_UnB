// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
// Date        : Thu Jan 15 16:16:44 2026
// Host        : DESKTOP-APAIK78 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/TCC/NathanZeidan/NathanSZeidan_TCC/HOG/HOG.gen/sources_1/bd/hog_wrapper/ip/hog_wrapper_hog_ip_axi_Nathan_0_0/hog_wrapper_hog_ip_axi_Nathan_0_0_stub.v
// Design      : hog_wrapper_hog_ip_axi_Nathan_0_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xck26-sfvc784-2LV-c
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "hog_ip_axi_Nathan,Vivado 2022.2" *)
module hog_wrapper_hog_ip_axi_Nathan_0_0(aclk, aresetn, s_axis_tdata, s_axis_tvalid, 
  s_axis_tready, s_axis_tlast, m_axis_tdata, m_axis_tvalid, m_axis_tready, m_axis_tlast, 
  s_axi_awaddr, s_axi_awvalid, s_axi_awready, s_axi_wdata, s_axi_wstrb, s_axi_wvalid, 
  s_axi_wready, s_axi_bresp, s_axi_bvalid, s_axi_bready, s_axi_araddr, s_axi_arvalid, 
  s_axi_arready, s_axi_rdata, s_axi_rresp, s_axi_rvalid, s_axi_rready)
/* synthesis syn_black_box black_box_pad_pin="aclk,aresetn,s_axis_tdata[7:0],s_axis_tvalid,s_axis_tready,s_axis_tlast,m_axis_tdata[31:0],m_axis_tvalid,m_axis_tready,m_axis_tlast,s_axi_awaddr[7:0],s_axi_awvalid,s_axi_awready,s_axi_wdata[31:0],s_axi_wstrb[3:0],s_axi_wvalid,s_axi_wready,s_axi_bresp[1:0],s_axi_bvalid,s_axi_bready,s_axi_araddr[7:0],s_axi_arvalid,s_axi_arready,s_axi_rdata[31:0],s_axi_rresp[1:0],s_axi_rvalid,s_axi_rready" */;
  input aclk;
  input aresetn;
  input [7:0]s_axis_tdata;
  input s_axis_tvalid;
  output s_axis_tready;
  input s_axis_tlast;
  output [31:0]m_axis_tdata;
  output m_axis_tvalid;
  input m_axis_tready;
  output m_axis_tlast;
  input [7:0]s_axi_awaddr;
  input s_axi_awvalid;
  output s_axi_awready;
  input [31:0]s_axi_wdata;
  input [3:0]s_axi_wstrb;
  input s_axi_wvalid;
  output s_axi_wready;
  output [1:0]s_axi_bresp;
  output s_axi_bvalid;
  input s_axi_bready;
  input [7:0]s_axi_araddr;
  input s_axi_arvalid;
  output s_axi_arready;
  output [31:0]s_axi_rdata;
  output [1:0]s_axi_rresp;
  output s_axi_rvalid;
  input s_axi_rready;
endmodule
