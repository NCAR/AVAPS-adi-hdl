// ***************************************************************************
// ***************************************************************************
// Copyright (C) 2024 Analog Devices, Inc. All rights reserved.
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
//      https://github.com/analogdevicesinc/hdl/blob/main/LICENSE_ADIBSD
//      This will allow to generate bit files and not release the source code,
//      as long as it attaches to an ADI device.
//
// ***************************************************************************
// ***************************************************************************
/**
 * Modulates the SDA and SCL lanes.
 * SCL high time is always 4 clock cycles, 40ns at 100MHz clk.
 */

`timescale 1ns/100ps

`include "i3c_controller_bit_mod_cmd.v"

module i3c_controller_bit_mod (
  input reset_n,
  input clk,

  // Bit Modulation Command

  input  [`MOD_BIT_CMD_WIDTH:0] cmd,
  input  cmd_valid,
  output cmd_ready,

  // Mux to alternative logic to support I²C devices.
  input  cmd_i2c_mode,
  // Indicates that the bus is not transfering,
  // is *not* bus idle condition because does not wait 200us after P.
  output cmd_nop,
  // 0:  1.56MHz
  // 1:  3.12MHz
  // 2:  6.25MHz
  // 3: 12.50MHz
  input [1:0] scl_pp_sg, // SCL push-pull speed grade.

  output     rx,
  output reg rx_raw,
  output     rx_valid,

  // Bus drive signals

  output     scl,
  output reg sdo,
  input      sdi,
  output reg t
);

  reg [`MOD_BIT_CMD_WIDTH:0] cmd_r;
  reg [1:0] pp_sg;
  reg [5:0] count; // Worst-case: 1.56MHz, 32-bits per half-bit.
  reg sr;
  reg i2c_mode;

  wire t_w;
  wire t_w2;
  wire sdo_w;
  wire [1:0] st = cmd_r[1:0];
  wire [`MOD_BIT_CMD_WIDTH:2] sm;
  wire scl_posedge;
  wire [3:0] scl_posedge_multi;
  wire [1:0] count_high;

  wire sr_sda;
  wire sr_scl;
  wire i3c_scl_posedge;
  wire i2c_scl;
  wire i2c_scl_posedge;

  reg  i2c_scl_reg;
  reg  [3:0] count_delay;

  reg [1:0] smt;
  localparam [1:0]
    setup = 0,
    stall = 1,
    scl_low = 2,
    scl_high = 3;

  always @(posedge clk) begin
    count <= 4;
    i2c_scl_reg <= i2c_scl;
    count_delay <= {count_delay[2:0], count[5]};
    if (!reset_n) begin
      smt <= setup;
      cmd_r <= {`MOD_BIT_CMD_NOP_, 2'b01};
      pp_sg <= 2'b00;
      sr <= 1'b0;
      i2c_mode <= 1'b0;
    end else begin
      if (smt == setup & cmd_valid) begin
          i2c_mode <= cmd_i2c_mode;
      end

      case (smt)
        scl_low: begin
          if (scl_posedge) begin
            smt <= scl_high;
          end
          end
        scl_high: begin
          if (&count_high) begin
            if (sm == `MOD_BIT_CMD_STOP_) begin
              smt <= setup;
            end else begin
              smt <= stall;
            end
          end
          end
        setup: begin
          sr <= 1'b0;
          end
        stall: begin
          end
      endcase

      if (cmd_ready) begin
        if (cmd_valid) begin
          cmd_r <= cmd[4:2] != `MOD_BIT_CMD_START_ ? cmd : {cmd[4:2], 1'b0, cmd[0]};
          // CMDW_MSG_RX is push-pull, but the Sr to stop from the controller side is open drain.
          pp_sg <= cmd[1] & cmd[4:2] != `MOD_BIT_CMD_START_ ? scl_pp_sg : 2'b00;
          smt <= scl_low;
        end else begin
          cmd_r <= {`MOD_BIT_CMD_NOP_, 2'b01};
        end
      end

      if (!cmd_ready) begin
          count <= count + 1;
      end

      if (smt == setup) begin
        sr <= 1'b0;
      end else if (cmd_ready) begin
        sr <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    rx_raw <= sdi === 1'b0 ? 1'b0 : 1'b1;
    // To guarantee thd_pp > 3ns.
    sdo <= sdo_w;
    t <= t_w2;
  end

  genvar i;
  for (i = 0; i < 4; i = i+1) begin
    assign scl_posedge_multi[i] = &count[i+2:0];
  end

  assign scl_posedge = scl_posedge_multi[3-pp_sg];
  assign count_high = count[1:0];
  assign cmd_ready = (smt == setup) ||
                     (smt == stall) ||
                     (smt == scl_high & &count_high);
  assign st = cmd_r[1:0];
  assign sm = cmd_r[`MOD_BIT_CMD_WIDTH:2];

  // Used to generate Sr with generous timing (locked in open drain speed).
  assign sr_sda = ((~count[4] & count[5]) | ~count[5]) & smt == scl_low;
  assign sr_scl = count[5] | smt == scl_high;
  assign i2c_scl = count_delay[3];

  assign i2c_scl_posedge = i2c_scl & ~i2c_scl_reg;
  assign i3c_scl_posedge = (smt == scl_high & &(~count_high));

  // Multi-cycle-path worst-case: 4 clks (12.5MHz, half-bit ack)
  assign rx = rx_raw;
  assign rx_valid = i2c_mode ? i2c_scl_posedge : i3c_scl_posedge;

  assign sdo_w = sm == `MOD_BIT_CMD_START_   ? sr_sda :
                 sm == `MOD_BIT_CMD_STOP_    ? 1'b0 :
                 sm == `MOD_BIT_CMD_WRITE_   ? st[0] :
                 sm == `MOD_BIT_CMD_ACK_SDR_ ?
                   (i2c_mode ? 1'b1 : (smt == scl_high ? rx   : 1'b1)) :
                 sm == `MOD_BIT_CMD_ACK_IBI_ ?
                   (smt == scl_high ? 1'b1 : 1'b0) :
                 1'b1;

  // Expression ...
  //assign t_w = sm == `MOD_BIT_CMD_STOP_    ? 1'b0 :
  //             sm == `MOD_BIT_CMD_START_   ? 1'b0 :
  //             sm == `MOD_BIT_CMD_READ_    ? 1'b0 :
  //             sm == `MOD_BIT_CMD_ACK_SDR_ ? 1'b0 :
  //             st[1];
  // ... gets optimized to
  assign t_w  = sm[4] ? 1'b0 : st[1];
  assign t_w2 = ~t_w & sdo_w ? 1'b1 : 1'b0;

  assign scl = sm == `MOD_BIT_CMD_START_ ? (sr ? sr_scl : 1'b1) :
               i2c_mode ? (i2c_scl || smt == setup) :
               (~(smt == scl_low || smt == stall));

  assign cmd_nop = sm == `MOD_BIT_CMD_NOP_ & smt == setup;

endmodule
