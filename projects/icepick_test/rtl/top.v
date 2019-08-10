/*
 * top.v
 *
 * vim: ts=4 sw=4
 *
 * Copyright (C) 2019  Sylvain Munaut <tnt@246tNt.com>
 * All rights reserved.
 *
 * BSD 3-clause, see LICENSE.bsd
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

`default_nettype none

module top (
	// IOs
	inout  wire [5:0] io_d_a,
	inout  wire [5:0] io_p_a,
	inout  wire [3:0] io_d_b,
	inout  wire [3:0] io_p_b,

	// USB
	output wire usb_dp,
	output wire usb_dn,
	output wire usb_pu,

	// Sense
	output wire sense_ctrl,
	output wire [3:0] sense_mux,
	output wire sense_ena_n,
	inout  wire sense_hi,
//	inout  wire sense_lo,

	// Vio
	output wire vio_pdm,

	// Button
	input  wire btn,

	// LED
	output wire [2:0] rgb,

	// Clock
	input  wire clk_in
);

	// Signals
	// -------

	// Sensing
	reg [5:0] meas_sel;

	wire [3:0] sc_chan;
	wire sc_go;
	wire sc_rdy;

	wire [17:0] sm_chg;
	wire [17:0] sm_dis;
	wire sm_stb;

	reg [39:0] result_data;
	reg  [4:0] result_val;

	// Pull control
	wire pull_ena;
	wire pull_dir;

	// UART
	wire [7:0] uart_txf_wdata;
	wire uart_txf_wren;
	wire uart_txf_full;

	wire [7:0] uart_txf_rdata;
	wire uart_txf_rden;
	wire uart_txf_empty;

	// VIO
	wire [7:0] vio;
	wire vio_pdm_i;

	// DFU reboot
	wire btn_iob;
	wire btn_v;
	wire boot_now;

	// LEDs
	wire [2:0] rgb_pwm;

	// Clock / Reset
	reg [7:0] cnt_reset;
	wire rst;
	wire clk;


	// Sensing
	// -------

	SB_IO #(
		.PIN_TYPE(6'b101000),
		.PULLUP(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) io_d_a_I[5:0] (
		.PACKAGE_PIN(io_d_a),
		.OUTPUT_ENABLE(1'b1),
		.D_OUT_0(1'b0)
	);

	// Select and control
	always @(posedge clk or posedge rst)
		if (rst)
			meas_sel <= 6'h0;
		else if (sm_stb)
			meas_sel <= meas_sel + ((meas_sel[1:0] == 2'b00) ? 6'h02 : 6'h01);

	assign sc_go = sc_rdy;
`define CALIB
`ifndef CALIB
	assign sc_chan  = meas_sel[5:2];
	assign pull_ena = meas_sel[1];
	assign pull_dir = meas_sel[0];
`else
	assign sc_chan  = 4'h2;
	assign pull_ena = 1'b0;
	assign pull_dir = 1'b0;
`endif

	reg [12:0] calib_cyc;

	always @(posedge clk or posedge rst)
		if (rst)
			calib_cyc <= 13'h0000;
		else if (sm_stb)
			calib_cyc <= (calib_cyc[12] & uart_txf_empty) ? 13'h0000 : (calib_cyc + 1);

	assign vio = calib_cyc[11:4];

	// Core
	sense sense_I (
		.sense_ctrl(sense_ctrl),
		.sense_mux(sense_mux),
		.sense_ena_n(sense_ena_n),
		.sense_hi(sense_hi),
		//.sense_lo(sense_lo),
		.ctrl_chan(sc_chan),
		.ctrl_go(sc_go),
		.ctrl_rdy(sc_rdy),
		.meas_chg(sm_chg),
		.meas_dis(sm_dis),
		.meas_stb(sm_stb),
		.debug(io_d_b[3]),
		.clk(clk),
		.rst(rst)
	);

	// Send data
	always @(posedge clk)
		if (rst) begin
			result_data <= 40'h0000000000;
			result_val  <= 5'b0000;
		end else begin
			if (sm_stb) begin
				result_data <= { meas_sel, sm_dis, sm_chg[15:0] };
				result_val  <= 5'b11111;
			end else if (uart_txf_wren) begin
				result_data <= { result_data[31:0], 8'h00 };
				result_val  <= { result_val[3:0], 1'b0 };
			end
		end


	// Pull Up/Down IOs
	// ----------------

	SB_IO #(
		.PIN_TYPE(6'b101000),
		.PULLUP(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) io_p_a_I[5:0] (
		.PACKAGE_PIN(io_p_a),
		.OUTPUT_ENABLE(pull_ena),
		.D_OUT_0(pull_dir)
	);

	SB_IO #(
		.PIN_TYPE(6'b101000),
		.PULLUP(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) io_p_b_I[3:0] (
		.PACKAGE_PIN(io_p_b),
		.OUTPUT_ENABLE(pull_ena),
		.D_OUT_0(pull_dir)
	);


	// UART
	// ----

	assign uart_txf_wdata = result_data[39:32];
	assign uart_txf_wren  = result_val[4] & ~uart_txf_full & (calib_cyc[3:2] == 2'b11) & ~calib_cyc[12];

	// Vio
	pdm #(
    	.WIDTH(8)
	) vio_pdm_I (
		.in(vio),
		.pdm(vio_pdm_i),
		.oe(1'b1),
		.clk(clk),
		.rst(rst)
	);

	assign vio_pdm = vio_pdm_i | calib_cyc[12];

	// TX FIFO
	fifo_sync_ram #(
		.DEPTH(8192),
		.WIDTH(8)
	) uart_tx_fifo_I (
		.wr_data(uart_txf_wdata),
		.wr_ena(uart_txf_wren),
		.wr_full(uart_txf_full),
		.rd_data(uart_txf_rdata),
		.rd_ena(uart_txf_rden),
		.rd_empty(uart_txf_empty),
		.clk(clk),
		.rst(rst)
	);

	// TX core
	uart_tx #(
		.DIV_WIDTH(8)
	) uart_tx_I (
		.tx(io_d_b[0]),
		.data(uart_txf_rdata),
		.valid(~uart_txf_empty & calib_cyc[12]),
		.ack(uart_txf_rden),
		.div(8'd46),
		.clk(clk),
		.rst(rst)
	);

	// RX core + FIFO
	// uart_rx =  io_d_b[1]

	assign io_d_b[1] = 1'b0;
	assign io_d_b[2] = 1'b0;



	// DFU reboot
	// ----------

	// Button
	SB_IO #(
		.PIN_TYPE(6'b000000),
		.PULLUP(1'b1),
		.IO_STANDARD("SB_LVCMOS")
	) btn_iob_I (
		.PACKAGE_PIN(btn),
		.INPUT_CLK(clk),
		.D_IN_0(btn_iob)
	);

	glitch_filter #(
		.L(4)
	) btn_flt_I (
		.pin_iob_reg(btn_iob),
		.cond(1'b1),
		.val(btn_v),
		.clk(clk),
		.rst(1'b0)	// Ensure the glitch filter has settled
					// before logic here engages
	);

	// Reboot command
	assign boot_now = ~rst & ~btn_v;

	// IP
	SB_WARMBOOT warmboot (
		.BOOT(boot_now),
		.S0(1'b1),
		.S1(1'b0)
	);


	// LED
	// ---

	reg [23:0] blink;
	always @(posedge clk)
		blink <= blink + 1;

	assign rgb_pwm[0] = 1'b0;		// Blue
	assign rgb_pwm[1] = blink[23];	// Green
	assign rgb_pwm[2] = 1'b0;		// Red

	// Driver
	SB_RGBA_DRV #(
		.CURRENT_MODE("0b1"),
		.RGB0_CURRENT("0b000001"),
		.RGB1_CURRENT("0b000001"),
		.RGB2_CURRENT("0b000001")
	) rgb_drv_I (
		.RGBLEDEN(1'b1),
		.RGB0PWM(rgb_pwm[0]),
		.RGB1PWM(rgb_pwm[1]),
		.RGB2PWM(rgb_pwm[2]),
		.CURREN(1'b1),
		.RGB0(rgb[0]),
		.RGB1(rgb[1]),
		.RGB2(rgb[2])
	);


	// Dummy USB
	// ---------
	// (to avoid pullups triggering detection)

	SB_IO #(
		.PIN_TYPE(6'b101000),
		.PULLUP(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) usb[2:0] (
		.PACKAGE_PIN({usb_dp, usb_dn, usb_pu}),
		.OUTPUT_ENABLE(1'b0),
		.D_OUT_0(1'b0)
	);


	// Clock / Reset
	// -------------

	always @(posedge clk)
		if (cnt_reset[7] == 1'b0)
			cnt_reset <= cnt_reset + 1;

`define HFO
`ifdef HFO
	SB_HFOSC #(
		.CLKHF_DIV("0b00")
	) osc_I (
		.CLKHFPU(1'b1),
		.CLKHFEN(1'b1),
		.CLKHF(clk)
	);
`else
	SB_GB clk_gbuf_I (
		.USER_SIGNAL_TO_GLOBAL_BUFFER(clk_in),
		.GLOBAL_BUFFER_OUTPUT(clk)
	);
`endif

	SB_GB rst_gbuf_I (
		.USER_SIGNAL_TO_GLOBAL_BUFFER(~cnt_reset[7]),
		.GLOBAL_BUFFER_OUTPUT(rst)
	);

endmodule // top
