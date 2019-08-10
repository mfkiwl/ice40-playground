/*
 * clk_meas.v
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module clk_meas (
	// Clocks 
	input  wire clk_ref,			// Reference 10 MHz clock
	input  wire clk_meas,			// Clock to be measured

	// Control interface
	input  wire [23:0] cmd_len,		// Measurement length
	input  wire cmd_stb,			// Measurement start
	output wire [31:0] resp_cnt,	// Response count
	output wire resp_stb,			// Response strobe

	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	reg [24:0] meas_len_cnt;
	wire meas_start;
	reg  meas_state;

	reg [ 2:0] cnt_state;
	reg [31:0] cnt_val;
	wire cnt_done;


	// Measure logic
	// -------------

	// Send command
	xclk_strobe xcmd_I (
		.in_stb(cmd_stb),
		.in_clk(clk),
		.out_stb(meas_start), 
		.out_clk(clk_ref),
		.rst(rst)
	);

	// Measurement length in 'clk_ref' domain
	always @(posedge clk_ref or posedge rst)
		if (rst)
			meas_state <= 1'b0;
		else
 			meas_state <= (meas_state & meas_len_cnt[24]) | meas_start;

	always @(posedge clk_ref)
		if (meas_start)
			meas_len_cnt <= { 1'b1, cmd_len };
		else
			meas_len_cnt <= meas_len_cnt - meas_len_cnt[24];

	// Counter in 'clk_meas' domain
	always @(posedge clk_meas or posedge rst)
		if (rst)
			cnt_state <= 3'b00;
		else
			cnt_state <= { cnt_state[1:0], meas_state };

	always @(posedge clk_meas)
		if (cnt_state[1])
			cnt_val <= cnt_state[2] ? (cnt_val + 1) : 32'h00000000;

	// Send result strobe
	assign cnt_done = cnt_state[2] & ~cnt_state[1];

	xclk_strobe xrsp_I (
		.in_stb(cnt_done),
		.in_clk(clk_meas),
		.out_stb(resp_stb), 
		.out_clk(clk),
		.rst(rst)
	);

	// Output
	assign resp_cnt = cnt_val;

endmodule // clk_meas
