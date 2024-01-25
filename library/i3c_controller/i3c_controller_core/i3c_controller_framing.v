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
 * Frames commands to the word module.
 * That means, cojoins cmdp and sdio bus into single interface cmdw.
 * It is the main state-machine for the Command Descriptors received.
 *
 * The Dynamic Address Assigment (DAA) procedure is:
 * Controller       | Peripheral  | Flow
 * -----------------|-------------|---------
 * S,0x7e,RnW=0     |             |    │
 *                  | ACK         |    │
 * ENTDAA,T         |             |    │
 * Sr               |             | ┌─►│
 * 0x7e,RnW=1       |             | │  ▼
 *                  | ACK         | │  A──┐
 *                  | PID+BCR+DCR | │  │  │
 * DA, Par          |             | │  ▼  │
 *                  | ACK         | └──B  │
 * P                |             |    C◄─┘
 *
 * Notes
 * From A with ACK, continue flow to B, or with NACK, goto C Stop,
 * finishing the DAA. At B, goto on sm state before A, Sr.
 * The first and last ACK are mandatory in the flowchart, if a NACK is received,
 * it is considered an error and the module resets.
 * The whole DAA occurs in OD, hence the Start as Sr in the SM below.
 */

`timescale 1ns/100ps

`include "i3c_controller_word_cmd.v"

module i3c_controller_framing #(
  parameter MAX_DEVS = 16
) (
  input clk,
  input reset_n,

  // Command parsed

  output        cmdp_ready,
  input         cmdp_valid,
  input  [30:0] cmdp,
  output [2:0]  cmdp_error,
  output reg    cmdp_daa_trigger,

  // Byte stream

  output sdo_ready,
  input  sdo_valid,
  input  [7:0] sdo,

  // Word command

  output cmdw_valid,
  input  cmdw_ready,
  output [`CMDW_HEADER_WIDTH+8:0] cmdw,
  input  cmdw_nack_bcast,
  input  cmdw_nack_resp,

  // Raw SDO input

  input rx_raw,

  input  cmd_nop,
  output reg cmd_i2c_mode,

  // IBI interface

  input       arbitration_valid,
  output      ibi_dev_is_attached,
  output      ibi_bcr_2,
  input       ibi_requested,
  output reg  ibi_requested_auto,
  input [6:0] ibi_da,

  // uP accessible info

  input  [1:0] rmap_ibi_config,
  output [6:0] rmap_dev_char_addr,
  input  [3:0] rmap_dev_char_data
);

  localparam IDLE_BUS_WIDTH = 7;

  wire ibi_enable;
  wire ibi_auto;

  wire        cmdp_rnw;
  wire [6:0]  cmdp_da;
  wire [11:0] cmdp_buffer_len;
  wire        cmdp_sr;
  wire        cmdp_bcast_header;
  wire        cmdp_ccc;
  wire [6:0]  cmdp_ccc_id;
  wire        cmdp_ccc_bcast;

  reg        cmdp_ccc_reg;
  reg        cmdp_ccc_bcast_reg;
  (* mark_debug = "true" *) reg [6:0]  cmdp_ccc_id_reg;
  reg        cmdp_bcast_header_reg;
  reg        cmdp_sr_reg;
  reg [11:0] cmdp_buffer_len_reg;
  reg [6:0]  cmdp_da_reg;
  reg        cmdp_rnw_reg;
  reg        cmdp_valid_reg;

  wire dev_is_attached;
  wire dev_is_i2c;

  reg [`CMDW_HEADER_WIDTH:0] sm;
  reg [7:0] cmdw_body;
  reg ctrl_daa;
  reg ctrl_validate;
  reg [3:0] j;

  reg [2:0] dev_char_len;
  reg daa_trigger;
  reg error_nack_bcast;
  reg error_unknown_da;
  reg error_nack_resp ;

  reg [2:0] smt;
  localparam [2:0]
    setup       = 0,
    validate    = 1,
    transfer    = 2,
    setup_sdo   = 3,
    cleanup     = 4,
    arbitration = 5;

  localparam [6:0]
    CCC_ENTDAA = 'h07;

  always @(posedge clk) begin
    error_unknown_da <= 1'b0;
    if (!reset_n) begin
      j <= 0;
      sm  <= `CMDW_NOP;
      smt <= setup;
      ctrl_daa <= 1'b0;
      ibi_requested_auto <= 1'b0;
      cmdp_sr_reg <= 0;
      daa_trigger <= 1'b0;
      cmd_i2c_mode <= 1'b0;
    end else if (cmdw_nack_bcast | cmdw_nack_resp) begin
      j <= 0;
      sm  <= `CMDW_NOP;
      smt <= cmdp_ccc_id_reg == CCC_ENTDAA ? setup :
             cmdp_rnw_reg ? setup : cleanup;
      ctrl_daa <= 1'b0;
    end else begin

      // Delay DAA trigger one word to match last SDI byte.
      cmdp_daa_trigger <= 1'b0;
      if (cmdw_ready) begin
        daa_trigger <= 1'b0;
        cmdp_daa_trigger <= daa_trigger;
      end

      // SDI Ready is are not checked, data will be lost
      // if it do not accept/provide data when needed.
      case (smt)
        setup: begin
          j <= 0;
          cmd_i2c_mode <= 1'b0;
          // Condition where a peripheral requested a IBI during quiet times.
          if (cmdp_valid) begin
            cmdp_sr_reg <= cmdp_sr;
            // Look last transfer SR flag.
            sm <= cmdp_sr_reg ? `CMDW_MSG_SR : `CMDW_START;
            // CCC Broadcast casts to all devices, validation not required.
            // Direct is CCC_BCAST 1'b1
            smt <= cmdp_ccc & ~cmdp_ccc_bcast ? transfer : validate;
            ctrl_validate <= 1'b0;
          end else if (ibi_auto & ibi_enable & rx_raw === 1'b0 & idle_bus) begin
            sm <= `CMDW_BCAST_7E_W0;
            smt <= transfer;
            ibi_requested_auto <= 1'b1;
          end
          cmdp_valid_reg        <= cmdp_valid;
          cmdp_ccc_reg          <= cmdp_ccc;
          cmdp_ccc_bcast_reg    <= cmdp_ccc_bcast;
          cmdp_ccc_id_reg       <= cmdp_ccc_id;
          cmdp_bcast_header_reg <= cmdp_bcast_header;
          cmdp_buffer_len_reg   <= cmdp_buffer_len;
          cmdp_da_reg           <= cmdp_da;
          cmdp_rnw_reg          <= cmdp_rnw;
          end
        validate: begin
          // Provide one clock cycle to read the BRAM and improve timing.
          ctrl_validate <= 1'b1;
          if (ctrl_validate) begin
            if (dev_is_i2c) begin
              cmd_i2c_mode <= 1'b1;
            end else begin
              cmd_i2c_mode <= 1'b0;
            end
            if (dev_is_attached) begin
              smt <= transfer;
            end else begin
              error_unknown_da <= 1'b1;
              smt <= cmdp_rnw_reg ? setup : cleanup;
            end
            end
        end
        transfer: begin
          if (cmdw_ready) begin
            ibi_requested_auto <= 1'b0;
            case(sm)
              `CMDW_NOP: begin
                smt <= setup;
                ctrl_daa <= 1'b0;
                end
              `CMDW_SR,
              `CMDW_START: begin
                cmdw_body <= {cmdp_da, cmdp_rnw}; // Attention to RnW here
                sm <= ctrl_daa ? `CMDW_BCAST_7E_W1 :
                      (~cmdp_bcast_header_reg & ~cmdp_ccc_reg) | dev_is_i2c ? `CMDW_TARGET_ADDR_OD :
                      `CMDW_BCAST_7E_W0;
                end
              `CMDW_BCAST_7E_W0: begin
                smt <= arbitration;
                cmdw_body <= {cmdp_ccc_bcast_reg, cmdp_ccc_id_reg}; // Attention to BCAST here
                end
              `CMDW_CCC_OD: begin
                // Occurs only during the DAA
                sm <= `CMDW_START;
                ctrl_daa <= 1'b1;
                end
              `CMDW_CCC_PP: begin
                if (cmdp_ccc_bcast_reg) begin
                  sm <= `CMDW_MSG_SR;
                end else if (~|cmdp_buffer_len_reg) begin
                  sm  <= `CMDW_STOP_PP;
                  if (cmdp_sr_reg) begin
                    smt <= setup;
                  end
                end else begin
                  sm <= `CMDW_MSG_TX;
                  smt <= setup_sdo;
                  cmdp_buffer_len_reg <= cmdp_buffer_len_reg - 1;
                end
                end
              `CMDW_BCAST_7E_W1: begin
                // Occurs only during the DAA
                dev_char_len <= 7;
                sm <= `CMDW_DAA_DEV_CHAR;
                end
              `CMDW_DAA_DEV_CHAR: begin
                dev_char_len <= dev_char_len - 1;
                if (~|dev_char_len) begin
                  sm  <= `CMDW_DYN_ADDR;
                  smt <= setup_sdo;
                  daa_trigger <= 1'b1;
                end
                end
              `CMDW_DYN_ADDR: begin
                sm <= j == MAX_DEVS - 1 ? `CMDW_STOP_OD : `CMDW_START;
                end
              `CMDW_MSG_SR: begin
                cmdw_body <= {cmdp_da, cmdp_rnw}; // Be aware of RnW here
                sm <= dev_is_i2c ? `CMDW_TARGET_ADDR_OD : `CMDW_TARGET_ADDR_PP;
                end
              `CMDW_TARGET_ADDR_OD,
              `CMDW_TARGET_ADDR_PP: begin
                if (cmdp_rnw_reg) begin
                  sm <= dev_is_i2c ? `CMDW_I2C_RX : `CMDW_MSG_RX;
                end else begin
                  sm <= dev_is_i2c ? `CMDW_I2C_TX : `CMDW_MSG_TX;
                  smt <= setup_sdo;
                end
                cmdp_buffer_len_reg <= cmdp_buffer_len_reg - 1;
                end
              `CMDW_I2C_RX,
              `CMDW_MSG_RX: begin
                // I²C read transfers cannot be stopped by the peripheral.
                cmdp_buffer_len_reg <= cmdp_buffer_len_reg - 1;
                if (~|cmdp_buffer_len_reg) begin
                  sm  <= dev_is_i2c ? `CMDW_STOP_OD :`CMDW_STOP_PP;
                  if (cmdp_sr_reg) begin
                    smt <= setup;
                  end
                end
                end
              `CMDW_I2C_TX,
              `CMDW_MSG_TX: begin
                cmdp_buffer_len_reg <= cmdp_buffer_len_reg - 1;
                if (~|cmdp_buffer_len_reg) begin
                  sm  <= dev_is_i2c ? `CMDW_STOP_OD :`CMDW_STOP_PP;
                  if (cmdp_sr_reg) begin
                    smt <= setup;
                  end
                end else begin
                  smt <= setup_sdo;
                end
                end
              `CMDW_STOP_OD,
              `CMDW_STOP_PP: begin
                smt <= setup;
                sm <= `CMDW_NOP;
                cmdp_sr_reg <= 1'b0;
                end
              `CMDW_IBI_MDB: begin
                sm <= cmdp_valid_reg ? `CMDW_SR : `CMDW_STOP_PP;
                end
              default: begin
                sm <= `CMDW_NOP;
                end
            endcase
          end
        end
        setup_sdo: begin
          if (sdo_valid) begin
            smt <= transfer;
          end
          cmdw_body <= sdo;
          end
        cleanup: begin
          // The peripheral did not ACK the transfer, so it is cancelled.
          // the SDO data is discarted
          if (sdo_valid) begin
            cmdp_buffer_len_reg <= cmdp_buffer_len_reg - 1;
          end
          if (cmdp_buffer_len_reg == 0) begin
            smt <= setup;
          end
          end
        arbitration: begin
          if (arbitration_valid) begin
            smt <= transfer;
            // IBI requested during CMDW_BCAST_7E_W0.
            // At the word module, was ACKed if IBI is enabled and DA is known, if not, NACKed.
            if (ibi_requested) begin
              // Receive MSB if IBI is enabled, dev is known and BCR[2] is 1'b1.
              if (dev_is_attached & ibi_enable & ibi_bcr_2) begin
                sm <= `CMDW_IBI_MDB;
              end else begin
                sm <= cmdp_valid_reg ? `CMDW_START : `CMDW_STOP_OD;
              end
            // No IBI requested during CMDW_BCAST_7E_W0.
            end else if (cmdp_valid_reg) begin
              sm <= cmdp_ccc_reg ?
                    (cmdp_ccc_id_reg == CCC_ENTDAA ? `CMDW_CCC_OD : `CMDW_CCC_PP) : `CMDW_MSG_SR;
            end else begin
              sm <= `CMDW_STOP_OD;
            end
          end
          end
        default: begin
          smt <= setup;
          end
      endcase
    end
    // Improve timing
    error_nack_resp <= cmdw_nack_resp;
    error_nack_bcast <= cmdw_nack_bcast;
  end

  // Idle bus condition

  wire idle_bus;
  reg [IDLE_BUS_WIDTH:0] idle_bus_reg;
  always @(posedge clk) begin
    if (!reset_n || !cmd_nop) begin
      idle_bus_reg <= 0;
    end else if (!idle_bus) begin
      idle_bus_reg <= idle_bus_reg + 1;
    end
  end
  assign idle_bus = &idle_bus_reg;

  // Device characteristics look-up.

  assign dev_is_i2c      = rmap_dev_char_data[0] === 1'b1;
  assign dev_is_attached = rmap_dev_char_data[1] === 1'b1;
  assign ibi_bcr_2       = rmap_dev_char_data[3] === 1'b1;

  assign ibi_dev_is_attached = dev_is_attached;
  assign rmap_dev_char_addr  = ibi_requested ? ibi_da : cmdp_da_reg;

  assign cmdp_ready = smt == setup & !cmdw_nack_bcast & !cmdw_nack_resp & reset_n;
  assign sdo_ready = (smt == setup_sdo | smt == cleanup) & !cmdw_nack_bcast & !cmdw_nack_resp & reset_n;
  assign cmdw = {sm, cmdw_body};
  assign cmdw_valid = smt == transfer;

  assign ibi_enable = rmap_ibi_config[0];
  assign ibi_auto   = rmap_ibi_config[1];

  assign cmdp_rnw          = cmdp[0];
  assign cmdp_da           = cmdp[7:1];
  assign cmdp_buffer_len   = cmdp[19:8];
  assign cmdp_sr           = cmdp[20];
  assign cmdp_bcast_header = cmdp[21];
  assign cmdp_ccc          = cmdp[22];
  assign cmdp_ccc_id       = cmdp[29:23];
  assign cmdp_ccc_bcast    = cmdp[30];

  assign cmdp_error = {error_nack_resp, error_unknown_da, error_nack_bcast};

endmodule
