# ISOLATED ONLY: DDR usr_clk=133.333 MHz, data bounds <=7.5-0.3 ns.
# Declarations precede all clock collection lookups.
# DDR APB now uses pll_clk_100m. The vendor IP specifies APB as asynchronous
# to its user interface; retain finite physical bounds, not whole-domain cuts.
create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]
derive_clocks
rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]
rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]
set_max_delay -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] 7.200 -datapath_only
set_max_delay -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {HDMI_PIXEL_CLK}] 7.200 -datapath_only
set_max_delay -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] 7.200 -datapath_only
set_max_delay -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {MIPI_RX_BYTE_CLK}] 7.200 -datapath_only
set_max_delay -from [get_clocks {pll_clk_100m}] -to [get_clocks {MIPI_RX_BYTE_CLK}] 9.700 -datapath_only
set_max_delay -from [get_clocks {pll_clk_100m}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] 7.200 -datapath_only
set_max_delay -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {pll_clk_100m}] 7.200 -datapath_only
set_max_delay -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {pll_clk_24m}] 13.033 -datapath_only
set_max_delay -from [get_clocks {pll_clk_24m}] -to [get_clocks {HDMI_PIXEL_CLK}] 13.033 -datapath_only
