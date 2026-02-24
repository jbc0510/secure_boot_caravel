// SPDX-FileCopyrightText: 2020 Efabless Corporation
// SPDX-License-Identifier: Apache-2.0
//
// BASE v2.0 – user_project_wrapper.v
//
// Changes from v1.0:
//   1. Removed conb_1 tie-offs for wbs_ack_o and wbs_dat_o[31:0]
//      (now driven by secure_boot_control_plane)
//   2. Removed user_irq[0] from gen_irq tie loop
//      (now driven by secure_boot_control_plane)
//   3. Replaced caravel_secure_boot u_secure_boot with
//      secure_boot_control_plane u_secure_boot_cp
//   4. VPWR/VGND ports removed from instantiation
//      (control plane does not expose power pins)
//
// Unchanged from v1.0:
//   - All GPIO tie-off generate blocks for unused pads
//   - io_in[7:20] / io_out[21:28] bit assignments
//   - la_data_out, io_out[0:20], io_out[29:37], io_oeb tie-offs
//   - user_irq[2:1] tie LOW
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
    // CONSTANT CELLS – unchanged from v1.0
    // -------------------------------------------------------------------------

    // la_data_out (128 bits, LOW)
    genvar i_la;
    generate
        for (i_la = 0; i_la < 128; i_la = i_la + 1) begin : gen_la
            sky130_fd_sc_hd__conb_1 u_tie_la (.HI(), .LO(la_data_out[i_la]));
        end
    endgenerate

    // user_irq[2:1] (LOW) – user_irq[0] driven by control plane
    genvar i_irq;
    generate
        for (i_irq = 1; i_irq < 3; i_irq = i_irq + 1) begin : gen_irq
            sky130_fd_sc_hd__conb_1 u_tie_irq (.HI(), .LO(user_irq[i_irq]));
        end
    endgenerate

    // io_out: unused pads tied LOW
    genvar i_io_out;
    generate
        for (i_io_out = 0; i_io_out <= 4; i_io_out = i_io_out + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_out_low0 (.HI(), .LO(io_out[i_io_out]));

        for (i_io_out = 5; i_io_out <= 20; i_io_out = i_io_out + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_out_low1 (.HI(), .LO(io_out[i_io_out]));

        for (i_io_out = 29; i_io_out <= 37; i_io_out = i_io_out + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_out_low2 (.HI(), .LO(io_out[i_io_out]));
    endgenerate

    // io_oeb: all pads HIGH (input direction)
    // NOTE: io_oeb[21:28] are LOW here, meaning the pads are configured as
    // inputs at the Caravel pad ring level. If io_out[21:28] need to drive
    // outputs (output-enabled). io_oeb LOW = output direction.
    // Verify with caravel/scripts/gen_gpio_defaults.py before tapeout.
    genvar i_io_oeb;
    generate
        for (i_io_oeb = 0; i_io_oeb <= 4; i_io_oeb = i_io_oeb + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_oeb_hi0 (.HI(io_oeb[i_io_oeb]), .LO());

        for (i_io_oeb = 5; i_io_oeb <= 20; i_io_oeb = i_io_oeb + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_oeb_hi1 (.HI(io_oeb[i_io_oeb]), .LO());

        for (i_io_oeb = 21; i_io_oeb <= 28; i_io_oeb = i_io_oeb + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_oeb_lo2 (.HI(), .LO(io_oeb[i_io_oeb]));

        for (i_io_oeb = 29; i_io_oeb <= 37; i_io_oeb = i_io_oeb + 1)
            sky130_fd_sc_hd__conb_1 u_tie_io_oeb_hi3 (.HI(io_oeb[i_io_oeb]), .LO());
    endgenerate

    // -------------------------------------------------------------------------
    // BASE v2.0 – Secure Boot Control Plane
    //
    // Replaces: caravel_secure_boot u_secure_boot
    // Adds:     Wishbone register file, shadow stickies, IRQ
    // -------------------------------------------------------------------------
    secure_boot_control_plane u_secure_boot_cp (
        // Wishbone slave interface
        .wb_clk_i       (wb_clk_i),
        .wb_rst_i       (wb_rst_i),
        .wb_adr_i       (wbs_adr_i),
        .wb_dat_i       (wbs_dat_i),
        .wb_sel_i       (wbs_sel_i),
        .wb_we_i        (wbs_we_i),
        .wb_stb_i       (wbs_stb_i),
        .wb_cyc_i       (wbs_cyc_i),
        .wb_dat_o       (wbs_dat_o),
        .wb_ack_o       (wbs_ack_o),

        // GPIO inputs (io_in[7:20]) – identical to v1.0 mapping
        .fw_ok          (io_in[7]),
        .fw_fail        (io_in[8]),
        .size_mismatch  (io_in[9]),
        .hdr_parse_fail (io_in[10]),
        .power_glitch   (io_in[11]),
        .clock_glitch   (io_in[12]),
        .warm_reset_req (io_in[13]),
        .cold_reset_req (io_in[14]),
        .global_pin_ok  (io_in[15]),
        .unlock_req     (io_in[16]),
        .file_denied    (io_in[17]),
        .group_autolock (io_in[18]),
        .tamper_in      (io_in[19]),
        .illegal_in     (io_in[20]),

        // GPIO outputs (io_out[21:28]) – identical to v1.0 mapping
        .unlock_enable  (io_out[21]),
        .debug_enable   (io_out[22]),
        .safe_led       (io_out[23]),
        .fsm_error      (io_out[24]),
        .security_breach(io_out[25]),
        .group_unlocked (io_out[26]),
        .group_suspended(io_out[27]),
        .group_error    (io_out[28]),

        // IRQ to management core
        .user_irq       (user_irq[0])
    );

endmodule

`default_nettype wire
