/*
 * wb_calib.v
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module wb_calib (
	// IO ports
	inout  wire [5:0] io_d_a,
	inout  wire [5:0] io_p_a,
	inout  wire [3:0] io_d_b,
	inout  wire [3:0] io_p_b,

	// Sense IO
	output wire sense_ctrl,
	output wire [3:0] sense_mux,
	output wire sense_ena_n,
	inout  wire sense_hi,

	input  wire clk_12m,

	input  wire [ 3:0] bus_addr,
	input  wire [31:0] bus_wdata,
	output wire [31:0] bus_rdata,
	input  wire bus_cyc,
	output wire bus_ack,
	input  wire bus_we,

	input wire clk,
	input wire rst
);

	// Signals
	// -------

	// Bus interface
	reg  [31:0] rmux;
	reg  ack;
	wire wsr;

	// IO control
	reg  [3:0] io_wstb;

	wire [9:0] io_drive_di;
	reg  [9:0] io_drive_do;
	reg  [9:0] io_drive_oe;
	reg  [9:0] io_pull_do;
	reg  [9:0] io_pull_oe;

	// Sense
	reg si_wstb;
	wire [31:0] si_status;
	wire [31:0] si_charge;
	wire [31:0] si_discharge;

	reg  sc_go;
	wire sc_rdy;
	reg  [3:0] sc_chan;

	wire [17:0] sm_chg;
	wire [17:0] sm_dis;
	wire sm_stb;

	reg  [17:0] sm_chg_r;
	reg  [17:0] sm_dis_r;
	reg  sm_valid;

	// Clock
	reg  [31:0] ci_xo;
	reg  [31:0] ci_hf;
	reg  [31:0] ci_lf;
	reg  [ 4:0] ci_wstb;
	reg  [ 9:0] clk_hf_trim;

	wire clk_10m;
	wire clk_10m_buf;
	wire clk_hf;
	wire clk_lf;

	reg  [23:0] cc_len;
	reg  cc_stb_xo;
	reg  cc_stb_hf;
	reg  cc_stb_lf;

	wire [31:0] cr_cnt_xo;
	wire [31:0] cr_cnt_hf;
	wire [31:0] cr_cnt_lf;
	wire cr_stb_xo;
	wire cr_stb_hf;
	wire cr_stb_lf;


	// Shared bus interface
	// --------------------

	always @(posedge clk)
		case (bus_addr)
			4'h0:		rmux <= { 22'h000000, io_drive_di };
			4'h4:		rmux <= si_status;
			4'h6:		rmux <= si_charge;
			4'h7:		rmux <= si_discharge;
			4'h8:		rmux <= ci_xo;
			4'h9:		rmux <= ci_hf;
			4'ha:		rmux <= ci_lf;
			default:	rmux <= 32'hxxxxxxxx;
		endcase

	always @(posedge clk)
		ack <= bus_cyc & ~ack;

	assign wsr = ~bus_cyc | ~bus_we | ack;

	assign bus_ack = ack;
	assign bus_rdata = ack ? rmux : 32'h00000000;


	// IO Control
	// ----------

	// Bus interface
	always @(posedge clk)
		if (wsr)
			io_wstb <= 4'b0000;
		else
			io_wstb <= {
				bus_addr[3:0] == 4'h3,
				bus_addr[3:0] == 4'h2,
				bus_addr[3:0] == 4'h1,
				bus_addr[3:0] == 4'h0
			};

	always @(posedge clk)
	begin
		if (io_wstb[0])
			io_drive_do <= bus_wdata[9:0];
		if (io_wstb[1])
			io_drive_oe <= bus_wdata[9:0];
		if (io_wstb[2])
			io_pull_do  <= bus_wdata[9:0];
		if (io_wstb[3])
			io_pull_oe  <= bus_wdata[9:0];
	end

	// IO buffers
	SB_IO #(
		.PIN_TYPE(6'b110101),
		.PULLUP(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) iob_d_I[9:0] (
		.PACKAGE_PIN({io_d_b, io_d_a}),
		.INPUT_CLK(clk),
		.OUTPUT_CLK(clk),
		.OUTPUT_ENABLE(io_drive_oe),
		.D_OUT_0(io_drive_do),
		.D_IN_0(io_drive_di)
	);

	SB_IO #(
		.PIN_TYPE(6'b110100),
		.PULLUP(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) iob_p_I[9:0] (
		.PACKAGE_PIN({io_p_b, io_p_a}),
		.INPUT_CLK(clk),
		.OUTPUT_CLK(clk),
		.OUTPUT_ENABLE(io_pull_oe),
		.D_OUT_0(io_pull_do),
		.D_IN_0()
	);


	// Sense
	// -----

	// Bus interface
	assign si_status    = { sc_rdy, sm_valid, 26'h0000000, sc_chan };
	assign si_charge    = { sm_valid, 13'h0000, sm_chg_r };
	assign si_discharge = { sm_valid, 13'h0000, sm_dis_r };

	always @(posedge clk)
		if (wsr)
			si_wstb <= 1'b0;
		else
			si_wstb <= bus_addr == 4'h4;

	always @(posedge clk)
	begin
		sc_go <= si_wstb & bus_wdata[31];
		if (si_wstb)
			sc_chan <= bus_wdata[3:0];
	end

	// Instance
	sense sense_I (
		.sense_ctrl(sense_ctrl),
		.sense_mux(sense_mux),
		.sense_ena_n(sense_ena_n),
		.sense_hi(sense_hi),
		.ctrl_chan(sc_chan),
		.ctrl_go(sc_go),
		.ctrl_rdy(sc_rdy),
		.meas_chg(sm_chg),
		.meas_dis(sm_dis),
		.meas_stb(sm_stb),
		.debug(),
		.clk(clk),
		.rst(rst)
	);

	// Response capture
	always @(posedge clk or posedge rst)
		if (rst)
			sm_valid <= 1'b0;
		else
			sm_valid <= (sm_valid | sm_stb) & ~sc_go;

	always @(posedge clk)
		if (sm_stb) begin
			sm_chg_r <= sm_chg;
			sm_dis_r <= sm_dis;
		end


	// Clock
	// -----

	// Reference buffer
//	assign clk_10m = clk;
	assign clk_10m = io_drive_di[0];

	SB_GB clk_10m_gbuf_I (
        .USER_SIGNAL_TO_GLOBAL_BUFFER(clk_10m),
        .GLOBAL_BUFFER_OUTPUT(clk_10m_buf)
	);

	// Bus interface
	always @(posedge clk)
		if (wsr)
			ci_wstb <= 5'b00000;
		else
			ci_wstb <= {
				(bus_addr[3:2] == 2'b10) & (bus_addr[1:0] != 2'b11),
				bus_addr[3:0] == 4'hb,
				bus_addr[3:0] == 4'ha,
				bus_addr[3:0] == 4'h9,
				bus_addr[3:0] == 4'h8
			};

	always @(posedge clk)
	begin
		cc_stb_xo <= ci_wstb[0];
		cc_stb_hf <= ci_wstb[1];
		cc_stb_lf <= ci_wstb[2];

		if (ci_wstb[3])
			clk_hf_trim <= bus_wdata[9:0];

		if (ci_wstb[4])
			cc_len <= bus_wdata[23:0];
	end

	// 12 MHz OSC
	clk_meas cm_xo_I (
		.clk_ref(clk_10m_buf),
		.clk_meas(clk_12m),
		.cmd_len(cc_len),
		.cmd_stb(cc_stb_xo),
		.resp_cnt(cr_cnt_xo),
		.resp_stb(cr_stb_xo),
		.clk(clk),
		.rst(rst)
	);

	always @(posedge clk)
		if (cc_stb_xo)
			ci_xo <= 32'h00000000;
		else if (cr_stb_xo)
			ci_xo <= { 1'b1, cr_cnt_xo[30:0] };

	// HF OSC
	SB_HFOSC #(
		.TRIM_EN("0b0"),
		.CLKHF_DIV("0b00")
	) hfosc_I (
		.TRIM0(clk_hf_trim[0]),
		.TRIM1(clk_hf_trim[1]),
		.TRIM2(clk_hf_trim[2]),
		.TRIM3(clk_hf_trim[3]),
		.TRIM4(clk_hf_trim[4]),
		.TRIM5(clk_hf_trim[5]),
		.TRIM6(clk_hf_trim[6]),
		.TRIM7(clk_hf_trim[7]),
		.TRIM8(clk_hf_trim[8]),
		.TRIM9(clk_hf_trim[9]),
		.CLKHFEN(1'b1),
		.CLKHFPU(1'b1),
		.CLKHF(clk_hf)
	);

	clk_meas cm_hf_I (
		.clk_ref(clk_10m),
		.clk_meas(clk_hf),
		.cmd_len(cc_len),
		.cmd_stb(cc_stb_hf),
		.resp_cnt(cr_cnt_hf),
		.resp_stb(cr_stb_hf),
		.clk(clk),
		.rst(rst)
	);

	always @(posedge clk)
		if (cc_stb_hf)
			ci_hf <= 32'h00000000;
		else if (cr_stb_hf)
			ci_hf <= { 1'b1, cr_cnt_hf[30:0] };

	// LF OSC
	SB_LFOSC lfosc_I (
		.CLKLFEN(1'b1),
		.CLKLFPU(1'b1),
		.CLKLF(clk_lf)
	);

	clk_meas cm_lf_I (
		.clk_ref(clk_10m),
		.clk_meas(clk_lf),
		.cmd_len(cc_len),
		.cmd_stb(cc_stb_lf),
		.resp_cnt(cr_cnt_lf),
		.resp_stb(cr_stb_lf),
		.clk(clk),
		.rst(rst)
	);

	always @(posedge clk)
		if (cc_stb_lf)
			ci_lf <= 32'h00000000;
		else if (cr_stb_lf)
			ci_lf <= { 1'b1, cr_cnt_lf[30:0] };

endmodule // wb_calib
