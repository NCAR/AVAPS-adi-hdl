// ***************************************************************************
// ***************************************************************************
// Copyright 2014 - 2023 (c) Analog Devices, Inc. All rights reserved.
//
// In this HDL repository, there are many different and unique modules, consisting
// of various HDL (Verilog or VHDL) components. The individual modules are
// developed independently, and may be accompanied by separate and unique license
// terms.
//
// The user should read each of these license terms, and understand the
// freedoms and responsibilities that he or she has by using this source/core.
//
// This core is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
// A PARTICULAR PURPOSE.
//
// Redistribution and use of source or resulting binaries, with or without modification
// of this file, are permitted under one of the following two license terms:
//
//   1. The GNU General Public License version 2 as published by the
//      Free Software Foundation, which can be found in the top level directory
//      of this repository (LICENSE_GPL2), and also online at:
//      <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>
//
// OR
//
//   2. An ADI specific BSD license, which can be found in the top level directory
//      of this repository (LICENSE_ADIBSD), and also on-line at:
//      https://github.com/analogdevicesinc/hdl/blob/master/LICENSE_ADIBSD
//      This will allow to generate bit files and not release the source code,
//      as long as it attaches to an ADI device.
//
// ***************************************************************************
// ***************************************************************************

`timescale 1ns/100ps

module system_top  #(
  parameter RX_JESD_L = 8,
  parameter RX_NUM_LINKS = 1,
  parameter JESD_MODE = "8B10B"
) (
  inout   [14:0]                        ddr_addr,
  inout   [ 2:0]                        ddr_ba,
  inout                                 ddr_cas_n,
  inout                                 ddr_ck_n,
  inout                                 ddr_ck_p,
  inout                                 ddr_cke,
  inout                                 ddr_cs_n,
  inout   [ 3:0]                        ddr_dm,
  inout   [31:0]                        ddr_dq,
  inout   [ 3:0]                        ddr_dqs_n,
  inout   [ 3:0]                        ddr_dqs_p,
  inout                                 ddr_odt,
  inout                                 ddr_ras_n,
  inout                                 ddr_reset_n,
  inout                                 ddr_we_n,

  inout                                 fixed_io_ddr_vrn,
  inout                                 fixed_io_ddr_vrp,
  inout   [53:0]                        fixed_io_mio,
  inout                                 fixed_io_ps_clk,
  inout                                 fixed_io_ps_porb,
  inout                                 fixed_io_ps_srstb,

  inout   [14:0]                        gpio_bd,

  output                                hdmi_out_clk,
  output                                hdmi_vsync,
  output                                hdmi_hsync,
  output                                hdmi_data_e,
  output  [23:0]                        hdmi_data,

  output                                spdif,

  inout                                 iic_scl,
  inout                                 iic_sda,

  // FMC HPC IOs
  input   [ 1:0]                        agc0,
  input   [ 1:0]                        agc1,
  input   [ 1:0]                        agc2,
  input   [ 1:0]                        agc3,
  input                                 clkin10_n,
  input                                 clkin10_p,
  input                                 fpga_refclk_in_n,
  input                                 fpga_refclk_in_p,
  input   [RX_JESD_L*RX_NUM_LINKS-1:0]  rx_data_n,
  input   [RX_JESD_L*RX_NUM_LINKS-1:0]  rx_data_p,
  output                                fpga_syncout_0_n,
  output                                fpga_syncout_0_p,
  inout                                 fpga_syncout_1_n,
  inout                                 fpga_syncout_1_p,
  inout   [10:0]                        gpio,
  inout                                 hmc_gpio1,
  output                                hmc_sync,
  input   [ 1:0]                        irqb,
  output                                rstb,
  output  [ 1:0]                        rxen,
  output                                spi0_csb,
  input                                 spi0_miso,
  output                                spi0_mosi,
  output                                spi0_sclk,
  output                                spi1_csb,
  output                                spi1_sclk,
  inout                                 spi1_sdio,
  input                                 sysref2_n,
  input                                 sysref2_p
);

  // internal signals

  wire  [63:0]              gpio_i;
  wire  [63:0]              gpio_o;
  wire  [63:0]              gpio_t;
  wire  [ 2:0]              spi0_csn;

  wire  [ 2:0]              spi1_csn;
  wire                      spi1_mosi;
  wire                      spi1_miso;

  wire                      ref_clk;
  wire                      sysref;
  wire  [RX_NUM_LINKS-1:0]  rx_syncout;

  wire  [7:0]               rx_data_p_loc;
  wire  [7:0]               rx_data_n_loc;

  wire                      clkin10;
  wire                      rx_device_clk;

  assign iic_rstn = 1'b1;

  // instantiations

  IBUFDS_GTE2 i_ibufds_ref_clk (
    .CEB (1'd0),
    .I (fpga_refclk_in_p),
    .IB (fpga_refclk_in_n),
    .O (ref_clk),
    .ODIV2 ());

  IBUFDS i_ibufds_sysref (
    .I (sysref2_p),
    .IB (sysref2_n),
    .O (sysref));

  IBUFDS i_ibufds_rx_device_clk (
    .I (clkin10_p),
    .IB (clkin10_n),
    .O (clkin10));

  OBUFDS i_obufds_syncout_0 (
    .I (rx_syncout[0]),
    .O (fpga_syncout_0_p),
    .OB (fpga_syncout_0_n));

  BUFG i_rx_device_clk (
    .I (clkin10),
    .O (rx_device_clk));

  // spi

  assign spi0_csb   = spi0_csn[0];
  assign spi1_csb   = spi1_csn[0];

  ad_3w_spi #(
    .NUM_OF_SLAVES(1)
  ) i_spi (
    .spi_csn (spi1_csn[0]),
    .spi_clk (spi1_sclk),
    .spi_mosi (spi1_mosi),
    .spi_miso (spi1_miso),
    .spi_sdio (spi1_sdio),
    .spi_dir ());

  // gpios

  ad_iobuf #(
    .DATA_WIDTH(12)
  ) i_iobuf (
    .dio_t (gpio_t[43:32]),
    .dio_i (gpio_o[43:32]),
    .dio_o (gpio_i[43:32]),
    .dio_p ({hmc_gpio1,       // 43
             gpio[10:0]}));   // 42-32

  assign gpio_i[44] = agc0[0];
  assign gpio_i[45] = agc0[1];
  assign gpio_i[46] = agc1[0];
  assign gpio_i[47] = agc1[1];
  assign gpio_i[48] = agc2[0];
  assign gpio_i[49] = agc2[1];
  assign gpio_i[50] = agc3[0];
  assign gpio_i[51] = agc3[1];
  assign gpio_i[52] = irqb[0];
  assign gpio_i[53] = irqb[1];

  assign hmc_sync   = gpio_o[54];
  assign rstb       = gpio_o[55];
  assign rxen[0]    = gpio_o[56];
  assign rxen[1]    = gpio_o[57];

  generate
  if (RX_NUM_LINKS > 1 & JESD_MODE == "8B10B") begin
    assign fpga_syncout_1_p = rx_syncout[1];
    assign fpga_syncout_1_n = 0;
  end else begin
    ad_iobuf #(
      .DATA_WIDTH(2)
    ) i_syncout_iobuf (
      .dio_t (gpio_t[63:62]),
      .dio_i (gpio_o[63:62]),
      .dio_o (gpio_i[63:62]),
      .dio_p ({fpga_syncout_1_n,      // 63
               fpga_syncout_1_p}));   // 62
  end
  endgenerate

  ad_iobuf #(
    .DATA_WIDTH(15)
  ) i_iobuf_bd (
    .dio_t (gpio_t[0+:15]),
    .dio_i (gpio_o[0+:15]),
    .dio_o (gpio_i[0+:15]),
    .dio_p (gpio_bd));

  // Unused GPIOs
  assign gpio_i[59:54] = gpio_o[59:54];
  assign gpio_i[31:16] = gpio_o[31:16];

  system_wrapper i_system_wrapper (
    .ddr_addr (ddr_addr),
    .ddr_ba (ddr_ba),
    .ddr_cas_n (ddr_cas_n),
    .ddr_ck_n (ddr_ck_n),
    .ddr_ck_p (ddr_ck_p),
    .ddr_cke (ddr_cke),
    .ddr_cs_n (ddr_cs_n),
    .ddr_dm (ddr_dm),
    .ddr_dq (ddr_dq),
    .ddr_dqs_n (ddr_dqs_n),
    .ddr_dqs_p (ddr_dqs_p),
    .ddr_odt (ddr_odt),
    .ddr_ras_n (ddr_ras_n),
    .ddr_reset_n (ddr_reset_n),
    .ddr_we_n (ddr_we_n),
    .fixed_io_ddr_vrn (fixed_io_ddr_vrn),
    .fixed_io_ddr_vrp (fixed_io_ddr_vrp),
    .fixed_io_mio (fixed_io_mio),
    .fixed_io_ps_clk (fixed_io_ps_clk),
    .fixed_io_ps_porb (fixed_io_ps_porb),
    .fixed_io_ps_srstb (fixed_io_ps_srstb),
    .gpio_i (gpio_i),
    .gpio_o (gpio_o),
    .gpio_t (gpio_t),
    .hdmi_data (hdmi_data),
    .hdmi_data_e (hdmi_data_e),
    .hdmi_hsync (hdmi_hsync),
    .hdmi_out_clk (hdmi_out_clk),
    .hdmi_vsync (hdmi_vsync),
    .iic_main_scl_io (iic_scl),
    .iic_main_sda_io (iic_sda),
    .spdif (spdif),
    .spi0_clk_i (spi0_sclk),
    .spi0_clk_o (spi0_sclk),
    .spi0_csn_0_o (spi0_csn[0]),
    .spi0_csn_1_o (spi0_csn[1]),
    .spi0_csn_2_o (spi0_csn[2]),
    .spi0_csn_i (1'b1),
    .spi0_sdi_i (spi0_miso),
    .spi0_sdo_i (spi0_mosi),
    .spi0_sdo_o (spi0_mosi),
    .spi1_clk_i (spi1_sclk),
    .spi1_clk_o (spi1_sclk),
    .spi1_csn_0_o (spi1_csn[0]),
    .spi1_csn_1_o (spi1_csn[1]),
    .spi1_csn_2_o (spi1_csn[2]),
    .spi1_csn_i (1'b1),
    .spi1_sdi_i (spi1_miso),
    .spi1_sdo_i (spi1_mosi),
    .spi1_sdo_o (spi1_mosi),
    // FMC HPC
    .rx_data_0_n (rx_data_n_loc[0]),
    .rx_data_0_p (rx_data_p_loc[0]),
    .rx_data_1_n (rx_data_n_loc[1]),
    .rx_data_1_p (rx_data_p_loc[1]),
    .rx_data_2_n (rx_data_n_loc[2]),
    .rx_data_2_p (rx_data_p_loc[2]),
    .rx_data_3_n (rx_data_n_loc[3]),
    .rx_data_3_p (rx_data_p_loc[3]),
    .rx_data_4_n (rx_data_n_loc[4]),
    .rx_data_4_p (rx_data_p_loc[4]),
    .rx_data_5_n (rx_data_n_loc[5]),
    .rx_data_5_p (rx_data_p_loc[5]),
    .rx_data_6_n (rx_data_n_loc[6]),
    .rx_data_6_p (rx_data_p_loc[6]),
    .rx_data_7_n (rx_data_n_loc[7]),
    .rx_data_7_p (rx_data_p_loc[7]),
    .ref_clk_q0 (ref_clk),
    .ref_clk_q1 (ref_clk),
    .rx_device_clk (rx_device_clk),
    .rx_sync_0 (rx_syncout),
    .rx_sysref_0 (sysref));

  assign rx_data_p_loc[RX_JESD_L*RX_NUM_LINKS-1:0] = rx_data_p[RX_JESD_L*RX_NUM_LINKS-1:0];
  assign rx_data_n_loc[RX_JESD_L*RX_NUM_LINKS-1:0] = rx_data_n[RX_JESD_L*RX_NUM_LINKS-1:0];

endmodule
