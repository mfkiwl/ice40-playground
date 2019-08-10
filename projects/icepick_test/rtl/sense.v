/*
 * sense.v
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

module sense (
	// Sense IO
	output reg  sense_ctrl,
	output reg  [3:0] sense_mux,
	output reg  sense_ena_n,
	inout  wire sense_hi,
//	inout  wire sense_lo,

	// Control
	input  wire [3:0] ctrl_chan,
	input  wire ctrl_go,
	output wire ctrl_rdy,

	output reg  [17:0] meas_chg,
	output wire [17:0] meas_dis,
	output wire meas_stb,

	// Debug
	output wire debug,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	// FSM
	localparam
		ST_IDLE      = 0,
		ST_SETUP     = 1,
		ST_CHARGE    = 2,
		ST_DISCHARGE = 3;

	reg [1:0] state;
	reg [1:0] state_nxt;

	// Timer
	reg  [17:0] timer;
	wire timer_trig;

	// IOB
	wire [1:0] sense_iob;
	reg  [1:0] sense_val;

	// Counter
	reg  [17:0] sense_cnt;


	// FSM
	// ---

	always @(posedge clk or posedge rst)
		if (rst)
			state <= ST_IDLE;
		else
			state <= state_nxt;

	always @(*)
	begin
		state_nxt = state;

		case (state_nxt)
			ST_IDLE:
				if (ctrl_go)
					state_nxt = ST_SETUP;

			ST_SETUP:
				if (timer_trig)
					state_nxt = ST_CHARGE;

			ST_CHARGE:
				if (timer_trig)
					state_nxt = ST_DISCHARGE;

			ST_DISCHARGE:
				if (timer_trig)
					state_nxt = ST_IDLE;
		endcase
	end


	// Timers
	// ------

	always @(posedge clk)
		if (state == ST_IDLE)
//			timer <= 18'h1f800;		// 2049 cycles ( ~ 42 us )
			timer <= 18'h18000;		// 2049 cycles ( ~ 42 us )
		else if (timer_trig)
			timer <= 18'h00000;		// 131073 cycle ( 2.7306875 ms )
		else
			timer <= timer + 1;

	assign timer_trig = timer[17];


	// Sense IO
	// --------

	SB_IO #(
		.PIN_TYPE(6'b0000_00),
		.IO_STANDARD("SB_LVDS_INPUT"),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0)
	) SB_IO (
		.PACKAGE_PIN(sense_hi),
		.INPUT_CLK(clk),
		.D_IN_0(sense_iob[0]),
		.D_IN_1(sense_iob[1])
	);

	always @(posedge clk)
		sense_val <= {
			sense_iob[0] & sense_iob[1],
			sense_iob[0] ^ sense_iob[1]
		};
	
	assign debug = sense_iob[0];


	// Measurement counters
	// --------------------

	always @(posedge clk)
		if (timer_trig)
			sense_cnt <= 0;
		else
			sense_cnt <= sense_cnt + sense_val;


	// Control hardware
	// ----------------

	always @(posedge clk or posedge rst)
	begin
		if (rst) begin
			sense_ctrl  <= 1'b0;
			sense_mux   <= 4'h0;	// GND
			sense_ena_n <= 1'b1;	// Disabled
		end else begin
			// Setup analog mux
			if (state == ST_IDLE) begin
				sense_mux   <= ctrl_go ? ctrl_chan : 4'h0;
				sense_ena_n <= ~ctrl_go;
			end

			// Charge // discharge
			sense_ctrl <= (state_nxt == ST_CHARGE);
		end
	end


	// User IF
	// -------

	assign ctrl_rdy = (state == ST_IDLE);

	always @(posedge clk)
		if ((state == ST_CHARGE) & timer_trig)
			meas_chg <= sense_cnt;

	assign meas_dis = sense_cnt;

	assign meas_stb = (state == ST_DISCHARGE) & timer_trig;

endmodule // sense
