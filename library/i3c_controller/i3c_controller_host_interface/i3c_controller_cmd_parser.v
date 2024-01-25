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
 * Parse commands.
 * When the first command indicates a pair command (e.g. CCC), await next
 * command to complete request (e.g. add CCC ID to parsed CCC command).
 * If it is a simple command (e.g. private transfer), a "blank" command
 * is not required.
 * cmdr (Command receipts) are transfered at the end of a transer, with
 * updated lenght field indicating the number of bytes actually transfered,
 * since the peripheral shall cancel the transfer.
 */

`timescale 1ns/100ps

module i3c_controller_cmd_parser (
  input  clk,
  input  reset_n,

  // Command FIFO

  output cmd_ready,
  input  cmd_valid,
  input  [31:0] cmd,

  input  cmdr_ready,
  output cmdr_valid,
  output [31:0] cmdr,

  // Command parsed

  input          cmdp_ready,
  output         cmdp_valid,
  output  [30:0] cmdp,
  input   [2:0]  cmdp_error,

  output rd_bytes_stop,
  input  [11:0] rd_bytes_lvl,
  input  wr_bytes_stop,
  input  [11:0] wr_bytes_lvl
);
  wire        cmdp_rnw;
  wire [11:0] cmdp_buffer_len;
  wire        cmdp_ccc;
  wire [6:0]  cmdp_ccc_id;
  wire error_nack_bcast;
  wire error_unknown_da;
  wire error_nack_resp;

  wire [11:0] cmdr1_len;
  reg  [31:0] cmdr1;
  reg  [7:0]  cmdr2;

  reg error_nack_bcast_reg;
  reg error_nack_resp_reg;
  reg error_unknown_da_reg;

  reg [3:0] cmdr_error;
  reg [7:0] cmdr_sync;

  // Check bit 3 for any type of NACK (CE2_ERROR + NACK_RESP).
  // Check bit 4 for unknown address.
  // CE1_ERROR and CE3_ERROR are not implemented.
  localparam [3:0]
    NO_ERROR  = 4'd0,
    CE0_ERROR = 4'd1,
    CE2_ERROR = 4'd4,
    NACK_RESP = 4'd6,
    UDA_ERROR = 4'd8;

  localparam [6:0]
    CCC_ENTDAA = 'h07;

  reg [2:0] sm;
  localparam [2:0]
    receive          = 0,
    xfer_await       = 1,
    xfer_await_ready = 2,
    ccc_await        = 3,
    pre_receipt      = 4,
    receipt          = 5;

  always @(posedge clk) begin
    if (!reset_n) begin
      sm  <= receive;
      cmdr_error <= NO_ERROR;
      cmdr_sync  <= 8'd0;
    end else begin
      case (sm)
        receive: begin
          cmdr_error <= NO_ERROR;
          cmdr2 <= 8'd0;
          if (cmd_valid) begin
            cmdr1 <= cmd;
            /* cmd[22] is cmdp_ccc */
            sm <= cmd[22] ? ccc_await : xfer_await;
          end else begin
            sm <= receive;
          end
          error_nack_bcast_reg <= 1'b0;
          error_unknown_da_reg <= 1'b0;
          error_nack_resp_reg  <= 1'b0;
          end
        xfer_await: begin
          sm <= cmdp_ready ? xfer_await_ready : sm;
          end
        xfer_await_ready: begin
          if (cmdp_ready) begin
            sm <= pre_receipt;
          end

          if (error_nack_bcast) begin
            error_nack_bcast_reg <= error_nack_bcast;
          end
          if (error_unknown_da) begin
            error_unknown_da_reg <= error_unknown_da;
          end
          if (error_nack_resp) begin
            error_nack_resp_reg <= error_nack_resp;
          end
          end
        ccc_await: begin
          cmdr2 <= cmd[7:0];
          if (cmd_valid) begin
            sm <= xfer_await;
          end
          end
        pre_receipt: begin
          // CE1_ERROR and CE3_ERROR not implemented.
          if (cmdp_ccc & |wr_bytes_lvl) begin
            cmdr_error <= CE0_ERROR;
          end else if (error_nack_bcast_reg) begin
            cmdr_error <= CE2_ERROR;
          end else if (error_unknown_da_reg) begin
            cmdr_error <= UDA_ERROR;
          end else if (error_nack_resp_reg) begin
            cmdr_error <= NACK_RESP;
          end
          // Ensure all receipt content is ok
          sm <= receipt;
          end
        receipt: begin
          if (cmdr_ready) begin
            sm <= receive;
            cmdr_sync <= cmdr_sync + 1;
          end
          end
        default: begin
          sm <= receive;
          end
      endcase
    end
  end

  // Lock on last sdi_bytes_lvl for the cmd
  // Since level increment on get state and is cleared by last on put phase,
  // delay i clock cycle.
  // Clear when cmr is read, since some RX transfer might get NACKed at
  // 0 bytes (no sdi_last).
  reg wr_bytes_stop_reg;
  reg [11:0] wr_bytes_lvl_reg;
  always @(posedge clk) begin
    wr_bytes_stop_reg <= wr_bytes_stop;
    if (cmdr_valid & cmdr_ready) begin
      wr_bytes_lvl_reg <= 0;
    end else if (wr_bytes_stop_reg) begin
      wr_bytes_lvl_reg <= wr_bytes_lvl;
    end
  end

  assign cmd_ready  = (sm == receive || sm == ccc_await) & reset_n;
  assign cmdp_valid = (sm == xfer_await & reset_n);

  assign cmdr = {8'd0, cmdr_error, cmdr1_len, cmdr_sync};
  assign cmdr_valid = sm == receipt;

  // For read bytes (write to peripheral), it is either all transferred or none,
  // since the peripheral can only reject during the address ACK.
  // For write bytes (read from peripheral), the peripheral shall cancel
  // before finishing the transfer.
  assign cmdr1_len = cmdp_rnw ?
                       wr_bytes_lvl_reg :
                       (error_nack_bcast_reg | error_nack_resp_reg ?
                         12'd0 : cmdp_buffer_len
                       );

  assign rd_bytes_stop = (cmdp_buffer_len == rd_bytes_lvl) & |rd_bytes_lvl;

  assign cmdp_rnw        = cmdr1[0];
  assign cmdp_ccc        = cmdr1[22];
  // The Linux implementation sets ENTDAA buffer length to 0,
  // but we need with 1 to contiguously fetch the DAs.
  assign cmdp_buffer_len = cmdp_ccc_id == CCC_ENTDAA ? 1 : cmdr1[19:08];
  assign cmdp_ccc_id     = cmdr2[6:0];

  assign error_nack_bcast = cmdp_error[0];
  assign error_unknown_da = cmdp_error[1];
  assign error_nack_resp  = cmdp_error[2];

  // Remove reserved bits.
  assign cmdp = {
    cmdr2[7:0],
    cmdr1[22:0]
  };

endmodule
