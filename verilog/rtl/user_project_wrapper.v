// SPDX-FileCopyrightText: 2020 Efabless Corporation
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

module user_project_wrapper #(parameter BITS = 32) (
    inout vccd1, inout vssd1,
    input wb_clk_i, input wb_rst_i,
    input wbs_stb_i, input wbs_cyc_i, input wbs_we_i,
    input [3:0] wbs_sel_i, input [31:0] wbs_dat_i, input [31:0] wbs_adr_i,
    output [31:0] wbs_dat_o,
    output wbs_ack_o,
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,
    inout  [`MPRJ_IO_PADS-10:0] analog_io,
    input user_clock2,
    output [2:0] user_irq
);

    // ------------------------------------------------------------
    // CONSTANT CELLS (one per bit)
    // ------------------------------------------------------------

    // wbs_ack_o (1 bit, LOW)
    sky130_fd_sc_hd__conb_1 u_tie_wbs_ack (.HI(), .LO(wbs_ack_o));

    // wbs_dat_o (32 bits, LOW)
    genvar i_wbs;
    generate
        for (i_wbs = 0; i_wbs < 32; i_wbs = i_wbs + 1) begin : gen_wbs_dat
            sky130_fd_sc_hd__conb_1 u_tie_wbs_dat (.HI(), .LO(wbs_dat_o[i_wbs]));
        end
    endgenerate

    // user_irq (3 bits, LOW)
    genvar i_irq;
    generate
        for (i_irq = 0; i_irq < 3; i_irq = i_irq + 1) begin : gen_irq
            sky130_fd_sc_hd__conb_1 u_tie_irq (.HI(), .LO(user_irq[i_irq]));
        end
    endgenerate

    // la_data_out (128 bits, LOW)
    genvar i_la;
    generate
        for (i_la = 0; i_la < 128; i_la = i_la + 1) begin : gen_la
            sky130_fd_sc_hd__conb_1 u_tie_la (.HI(), .LO(la_data_out[i_la]));
        end
    endgenerate

    // io_out (bits 0–4, 5–20, 29–37 LOW)
    genvar i_io_out;
    generate
        for (i_io_out = 0; i_io_out <= 4; i_io_out = i_io_out + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_out_low0 (.HI(), .LO(io_out[i_io_out]));

        for (i_io_out = 5; i_io_out <= 20; i_io_out = i_io_out + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_out_low1 (.HI(), .LO(io_out[i_io_out]));

        for (i_io_out = 29; i_io_out <= 37; i_io_out = i_io_out + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_out_low2 (.HI(), .LO(io_out[i_io_out]));
    endgenerate

    // io_oeb (bits 0–4, 5–20, 21–28, 29–37 HIGH)
    genvar i_io_oeb;
    generate
        for (i_io_oeb = 0; i_io_oeb <= 4; i_io_oeb = i_io_oeb + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_oeb_hi0 (.HI(io_oeb[i_io_oeb]), .LO());

        for (i_io_oeb = 5; i_io_oeb <= 20; i_io_oeb = i_io_oeb + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_oeb_hi1 (.HI(io_oeb[i_io_oeb]), .LO());

        for (i_io_oeb = 21; i_io_oeb <= 28; i_io_oeb = i_io_oeb + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_oeb_hi2 (.HI(io_oeb[i_io_oeb]), .LO());

        for (i_io_oeb = 29; i_io_oeb <= 37; i_io_oeb = i_io_oeb + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_oeb_hi3 (.HI(io_oeb[i_io_oeb]), .LO());
    endgenerate

    // ------------------------------------------------------------
    // SECURE BOOT BLOCK
    // ------------------------------------------------------------

    caravel_secure_boot u_secure_boot (
    .VPWR           (vccd1),
    .VGND           (vssd1),
    .clk             (wb_clk_i),
    .reset           (wb_rst_i),
    .fw_ok           (io_in[7]),
    .fw_fail         (io_in[8]),
    .size_mismatch   (io_in[9]),
    .hdr_parse_fail  (io_in[10]),
    .power_glitch    (io_in[11]),
    .clock_glitch    (io_in[12]),
    .warm_reset_req  (io_in[13]),
    .cold_reset_req  (io_in[14]),
    .global_pin_ok   (io_in[15]),
    .unlock_req      (io_in[16]),
    .file_denied     (io_in[17]),
    .group_autolock  (io_in[18]),
    .tamper_in       (io_in[19]),
    .illegal_in      (io_in[20]),
    .unlock_enable   (io_out[21]),
    .debug_enable    (io_out[22]),
    .safe_led        (io_out[23]),
    .fsm_error       (io_out[24]),
    .security_breach (io_out[25]),
    .group_unlocked  (io_out[26]),
    .group_suspended (io_out[27]),
    .group_error     (io_out[28])
);


endmodule

`default_nettype wire
