--Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
----------------------------------------------------------------------------------
--Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
--Date        : Thu Jan 15 16:12:12 2026
--Host        : DESKTOP-APAIK78 running 64-bit major release  (build 9200)
--Command     : generate_target hog_wrapper_wrapper.bd
--Design      : hog_wrapper_wrapper
--Purpose     : IP block netlist
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity hog_wrapper_wrapper is
end hog_wrapper_wrapper;

architecture STRUCTURE of hog_wrapper_wrapper is
  component hog_wrapper is
  end component hog_wrapper;
begin
hog_wrapper_i: component hog_wrapper
 ;
end STRUCTURE;
