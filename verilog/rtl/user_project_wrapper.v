// SPDX-FileCopyrightText: 2020 Efabless Corporation
// SPDX-License-Identifier: Apache-2.0
//
// BASE v3.0 – user_project_wrapper.v
// Integrates hsm_top (full HSM) into the Caravel wrapper.
// =============================================================================

`default_nettype none

module user_project_wrapper #(parameter BITS = 32) (
    inout vccd1, inout vssd1,
    input  wb_clk_i, input wb_rst_i,
    input  wbs_stb_i, input wbs_cyc_i, input wbs_we_i,
    input  [3:0]   wbs_sel_i,
    input  [31:0]  wbs_dat_i,
    input  [31:0]  wbs_adr_i,
    output [31:0]  wbs_dat_o,
    output         wbs_ack_o,
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,
    input  [`MPRJ_IO_PADS-1:0]    io_in,
    output [`MPRJ_IO_PADS-1:0]    io_out,
    output [`MPRJ_IO_PADS-1:0]    io_oeb,
    inout  [`MPRJ_IO_PADS-10:0]   analog_io,
    input  user_clock2,
    output [2:0] user_irq
);

    // -------------------------------------------------------------------------
    // CONSTANT CELLS – tie-offs
    // -------------------------------------------------------------------------

    // la_data_out (128 bits, LOW)
    genvar i_la;
    generate
        for (i_la = 0; i_la < 128; i_la = i_la + 1) begin : gen_la
            sky130_fd_sc_hd__conb_1 u_tie_la (.HI(), .LO(la_data_out[i_la]));
        end
    endgenerate

    // user_irq[2:1] (LOW) – user_irq[0] driven by HSM
    genvar i_irq;
    generate
        for (i_irq = 1; i_irq < 3; i_irq = i_irq + 1) begin : gen_irq
            sky130_fd_sc_hd__conb_1 u_tie_irq (.HI(), .LO(user_irq[i_irq]));
        end
    endgenerate

    // io_out[0:4] tied LOW
    genvar i_io;
    generate
        for (i_io = 0; i_io <= 4; i_io = i_io + 1) begin : gen_io_out_low0
            sky130_fd_sc_hd__conb_1 u_tie_io_out (.HI(), .LO(io_out[i_io]));
        end
    endgenerate

    // io_out[5:20] tied LOW
    generate
        for (i_io = 5; i_io <= 20; i_io = i_io + 1) begin : gen_io_out_low1
            sky130_fd_sc_hd__conb_1 u_tie_io_out (.HI(), .LO(io_out[i_io]));
        end
    endgenerate

    // io_out[27:28] tied LOW
    sky130_fd_sc_hd__conb_1 u_tie_io27 (.HI(), .LO(io_out[27]));
    sky130_fd_sc_hd__conb_1 u_tie_io28 (.HI(), .LO(io_out[28]));

    // io_out[29:37] tied LOW
    generate
        for (i_io = 29; i_io <= 37; i_io = i_io + 1) begin : gen_io_out_low2
            sky130_fd_sc_hd__conb_1 u_tie_io_out (.HI(), .LO(io_out[i_io]));
        end
    endgenerate

    // -------------------------------------------------------------------------
    // io_oeb: Output Enable Bar
    //   HIGH = input mode, LOW = output mode
    //   Pads 21-26: OUTPUT (driven by HSM) -> oeb LOW
    //   All others: INPUT -> oeb HIGH
    // -------------------------------------------------------------------------
    genvar i_oeb;

    // io_oeb[0:20] HIGH (input)
    generate
        for (i_oeb = 0; i_oeb <= 20; i_oeb = i_oeb + 1) begin : gen_oeb_hi0
            sky130_fd_sc_hd__conb_1 u_tie_oeb (.HI(io_oeb[i_oeb]), .LO());
        end
    endgenerate

    // io_oeb[21:26] LOW (output — HSM drives these pads)
    generate
        for (i_oeb = 21; i_oeb <= 26; i_oeb = i_oeb + 1) begin : gen_oeb_lo
            sky130_fd_sc_hd__conb_1 u_tie_oeb (.HI(), .LO(io_oeb[i_oeb]));
        end
    endgenerate

    // io_oeb[27:37] HIGH (input)
    generate
        for (i_oeb = 27; i_oeb <= 37; i_oeb = i_oeb + 1) begin : gen_oeb_hi1
            sky130_fd_sc_hd__conb_1 u_tie_oeb (.HI(io_oeb[i_oeb]), .LO());
        end
    endgenerate

    // -------------------------------------------------------------------------
    // HSM v3.0 – Hardware Security Module
    // -------------------------------------------------------------------------
    hsm_top u_hsm (
        .clk            (wb_clk_i),
        .reset          (wb_rst_i),

        // Wishbone slave interface
        .wb_cyc_i       (wbs_cyc_i),
        .wb_stb_i       (wbs_stb_i),
        .wb_we_i        (wbs_we_i),
        .wb_adr_i       (wbs_adr_i),
        .wb_dat_i       (wbs_dat_i),
        .wb_sel_i       (wbs_sel_i),
        .wb_dat_o       (wbs_dat_o),
        .wb_ack_o       (wbs_ack_o),

        // External signals from GPIO
        .global_pin_ok  (io_in[7]),
        .warm_reset_req (io_in[8]),
        .cold_reset_req (io_in[9]),

        // Status outputs -> GPIO (direct drive)
        .boot_valid     (io_out[21]),
        .boot_fail      (io_out[22]),
        .safe_led       (io_out[23]),
        .fsm_error      (io_out[24]),
        .security_breach(io_out[25]),
        .vault_is_locked(io_out[26]),

        // Unrouted outputs
        .global_state_bits (),
        .irq            (user_irq[0])
    );

endmodule

`default_nettype wire
