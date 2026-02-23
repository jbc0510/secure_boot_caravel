`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// secure_boot_control_plane.sv
// BASE v2.0 – Wishbone Control Plane Wrapper
//
// Wraps secure_boot_system_wrapper and exposes a 32-bit Wishbone slave
// register file for management-core firmware access.
//
// Register map (wb_adr_i[3:2] selects):
//   0x00  GLOBAL_STATE  R    FSM state bits and decoded flags
//   0x04  STATUS_FLAGS  R    Shadow sticky flags + core sticky + live signals
//   0x08  TIMEOUTS      R    global_timeout_count [15:0], group_timeout_count [31:16]
//   0x0C  CONTROL       W1C  Write-one-to-clear shadow sticky flags [4:0]
//
// GPIO mapping preserved identically from v1.0 caravel_secure_boot:
//   Inputs:  fw_ok(io_in[7]) .. illegal_in(io_in[20])
//   Outputs: unlock_enable(io_out[21]) .. group_error(io_out[28])
//
// Security:
//   - All registers except CONTROL are read-only; writes silently ignored.
//   - CONTROL only clears software-owned shadow stickies.
//   - Core sticky latches (sticky_tamper, sticky_illegal) are reset-only.
//   - No write path can force an FSM state or assert unlock_enable.
// =============================================================================

module secure_boot_control_plane (
    // ── Wishbone slave interface ───────────────────────────────────────────
    input  wire         wb_clk_i,
    input  wire         wb_rst_i,
    input  wire [31:0]  wb_adr_i,
    input  wire [31:0]  wb_dat_i,
    input  wire [3:0]   wb_sel_i,
    input  wire         wb_we_i,
    input  wire         wb_stb_i,
    input  wire         wb_cyc_i,
    output reg  [31:0]  wb_dat_o,
    output reg          wb_ack_o,

    // ── GPIO inputs (io_in[7:20]) ──────────────────────────────────────────
    input  wire         fw_ok,           // io_in[7]
    input  wire         fw_fail,         // io_in[8]
    input  wire         size_mismatch,   // io_in[9]
    input  wire         hdr_parse_fail,  // io_in[10]
    input  wire         power_glitch,    // io_in[11]
    input  wire         clock_glitch,    // io_in[12]
    input  wire         warm_reset_req,  // io_in[13]
    input  wire         cold_reset_req,  // io_in[14]
    input  wire         global_pin_ok,   // io_in[15]
    input  wire         unlock_req,      // io_in[16]
    input  wire         file_denied,     // io_in[17]
    input  wire         group_autolock,  // io_in[18]
    input  wire         tamper_in,       // io_in[19]
    input  wire         illegal_in,      // io_in[20]

    // ── GPIO outputs (io_out[21:28]) ───────────────────────────────────────
    output wire         unlock_enable,   // io_out[21]
    output wire         debug_enable,    // io_out[22]
    output wire         safe_led,        // io_out[23]
    output wire         fsm_error,       // io_out[24]
    output wire         security_breach, // io_out[25]
    output wire         group_unlocked,  // io_out[26]
    output wire         group_suspended, // io_out[27]
    output wire         group_error,     // io_out[28]

    // ── IRQ to management core ─────────────────────────────────────────────
    output wire         user_irq         // user_irq[0]
);

    // =========================================================================
    // Internal wires from secure_boot_system_wrapper
    // =========================================================================

    // Global FSM state
    wire [4:0]  global_state_bits;
    wire        global_state_boot;
    wire        global_state_locked;
    wire        global_state_authorized;
    wire        global_state_safe_mode;
    wire        global_state_escalated;
    wire [15:0] global_timeout_count;

    // Group FSM state
    wire [3:0]  group_state_bits;
    wire        group_state_disabled;
    wire        group_state_locked;
    wire        group_state_unlocked;
    wire        group_state_suspended;
    wire        group_locked_int;
    wire [15:0] group_timeout_count;

    // Core sticky latches (reset-only, NOT software-clearable)
    wire        sticky_tamper_core;
    wire        sticky_illegal_core;

    // Core outputs routed to GPIO
    wire        unlock_enable_int;
    wire        debug_enable_int;
    wire        safe_led_int;
    wire        fsm_error_int;
    wire        security_breach_int;
    wire        group_unlocked_int;
    wire        group_suspended_int;
    wire        group_error_int;

    // ── GPIO output assignments ────────────────────────────────────────────
    assign unlock_enable   = unlock_enable_int;
    assign debug_enable    = debug_enable_int;
    assign safe_led        = safe_led_int;
    assign fsm_error       = fsm_error_int;
    assign security_breach = security_breach_int;
    assign group_unlocked  = group_unlocked_int;
    assign group_suspended = group_suspended_int;
    assign group_error     = group_error_int;

    // =========================================================================
    // Instantiate secure_boot_system_wrapper
    // Core logic is entirely unchanged from v1.0.
    // =========================================================================
    secure_boot_system_wrapper u_system (
        .clk                     (wb_clk_i),
        .reset                   (wb_rst_i),

        // Global FSM inputs
        .fw_ok                   (fw_ok),
        .fw_fail                 (fw_fail),
        .size_mismatch           (size_mismatch),
        .hdr_parse_fail          (hdr_parse_fail),
        .power_glitch            (power_glitch),
        .clock_glitch            (clock_glitch),
        .warm_reset_req          (warm_reset_req),
        .cold_reset_req          (cold_reset_req),
        .global_pin_ok           (global_pin_ok),

        // Group FSM inputs
        .unlock_req              (unlock_req),
        .file_denied             (file_denied),
        .group_autolock          (group_autolock),

        // Tamper / illegal inputs
        .tamper_in               (tamper_in),
        .illegal_in              (illegal_in),

        // Global FSM outputs – GPIO
        .unlock_enable           (unlock_enable_int),
        .debug_enable            (debug_enable_int),
        .safe_led                (safe_led_int),
        .fsm_error               (fsm_error_int),
        .security_breach         (security_breach_int),

        // Global FSM outputs – register visibility
        .global_state_bits       (global_state_bits),
        .global_state_boot       (global_state_boot),
        .global_state_locked     (global_state_locked),
        .global_state_authorized (global_state_authorized),
        .global_state_safe_mode  (global_state_safe_mode),
        .global_state_escalated  (global_state_escalated),
        .global_timeout_count    (global_timeout_count),

        // Group FSM outputs – GPIO
        .group_unlocked          (group_unlocked_int),
        .group_locked            (group_locked_int),
        .group_suspended         (group_suspended_int),
        .group_error             (group_error_int),

        // Group FSM outputs – register visibility
        .group_state_bits        (group_state_bits),
        .group_state_disabled    (group_state_disabled),
        .group_state_locked      (group_state_locked),
        .group_state_unlocked    (group_state_unlocked),
        .group_state_suspended   (group_state_suspended),
        .group_timeout_count     (group_timeout_count),

        // Core sticky latches (reset-only)
        .sticky_tamper           (sticky_tamper_core),
        .sticky_illegal          (sticky_illegal_core)
    );

    // =========================================================================
    // Software-owned shadow sticky flags
    //
    // These mirror core events but are OWNED BY THE CONTROL PLANE:
    //   - Set when the corresponding core signal asserts (any cycle)
    //   - Cleared ONLY via CONTROL register write-one-to-clear
    //   - Clearing these does NOT affect the core's own sticky latches
    //   - IRQ is driven by the OR of all shadow stickies
    //
    // This two-layer design means:
    //   - Core tamper/illegal latches can never be erased by software
    //   - SW can still ACK and re-arm the IRQ for logging purposes
    // =========================================================================
    reg sw_sticky_tamper;
    reg sw_sticky_illegal;
    reg sw_sticky_fsm_error;
    reg sw_sticky_breach;
    reg sw_sticky_group_error;

    // One-cycle clear pulses decoded from CONTROL register writes
    reg [4:0] ctrl_clear_pulse;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            sw_sticky_tamper      <= 1'b0;
            sw_sticky_illegal     <= 1'b0;
            sw_sticky_fsm_error   <= 1'b0;
            sw_sticky_breach      <= 1'b0;
            sw_sticky_group_error <= 1'b0;
        end else begin
            // ── Set on core events ─────────────────────────────────────────
            // Use core sticky for tamper/illegal (already latched in wrapper)
            if (sticky_tamper_core)
                sw_sticky_tamper <= 1'b1;
            if (sticky_illegal_core)
                sw_sticky_illegal <= 1'b1;
            // fsm_error is registered inside secure_boot_fsm – sample directly
            if (fsm_error_int)
                sw_sticky_fsm_error <= 1'b1;
            // security_breach is combinational in FSM – latch it here
            if (security_breach_int)
                sw_sticky_breach <= 1'b1;
            // group_error is registered inside group_fsm – sample directly
            if (group_error_int)
                sw_sticky_group_error <= 1'b1;

            // ── Clear via CONTROL write-one-to-clear ───────────────────────
            // Clear wins over set in the same cycle (intentional: SW ack)
            if (ctrl_clear_pulse[0]) sw_sticky_tamper      <= 1'b0;
            if (ctrl_clear_pulse[1]) sw_sticky_illegal     <= 1'b0;
            if (ctrl_clear_pulse[2]) sw_sticky_fsm_error   <= 1'b0;
            if (ctrl_clear_pulse[3]) sw_sticky_breach      <= 1'b0;
            if (ctrl_clear_pulse[4]) sw_sticky_group_error <= 1'b0;
        end
    end

    // =========================================================================
    // Wishbone slave – single-cycle ACK, classic mode
    //
    // Register select: wb_adr_i[3:2]
    //   2'b00  0x00  GLOBAL_STATE  R
    //   2'b01  0x04  STATUS_FLAGS  R
    //   2'b10  0x08  TIMEOUTS      R
    //   2'b11  0x0C  CONTROL       W (W1C, reads return 0)
    //
    // Ack behaviour:
    //   - wb_ack_o pulses HIGH for exactly one clock cycle per valid access
    //   - !wb_ack_o guard prevents double-ack on back-to-back transactions
    // =========================================================================
    wire [1:0] reg_sel = wb_adr_i[3:2];

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            wb_ack_o         <= 1'b0;
            wb_dat_o         <= 32'h0000_0000;
            ctrl_clear_pulse <= 5'b00000;
        end else begin
            // ── Defaults every cycle ───────────────────────────────────────
            wb_ack_o         <= 1'b0;
            wb_dat_o         <= 32'h0000_0000;
            ctrl_clear_pulse <= 5'b00000;

            // ── Valid access: cyc & stb asserted, not already acking ───────
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;   // single-cycle ack

                if (wb_we_i) begin
                    // ── WRITE path ─────────────────────────────────────────
                    // Only CONTROL (0x0C) accepts writes.
                    // All other addresses: ack but ignore data.
                    if (reg_sel == 2'b11) begin
                        // Byte-enable gate: only act if low byte is selected
                        if (wb_sel_i[0])
                            ctrl_clear_pulse <= wb_dat_i[4:0];
                        // bits [31:5] of CONTROL are reserved; hardware masks them
                    end
                    // Write data output is always 0
                    wb_dat_o <= 32'h0000_0000;

                end else begin
                    // ── READ path ──────────────────────────────────────────
                    case (reg_sel)

                        // ── 0x00  GLOBAL_STATE ────────────────────────────
                        // [4:0]   global_state_bits  (one-hot global FSM)
                        // [8:5]   group_state_bits   (one-hot group FSM)
                        // [9]     global_state_boot
                        // [10]    global_state_locked
                        // [11]    global_state_authorized
                        // [12]    global_state_safe_mode
                        // [13]    global_state_escalated
                        // [31:14] reserved (0)
                        2'b00: wb_dat_o <= {
                            18'h0,
                            global_state_escalated,
                            global_state_safe_mode,
                            global_state_authorized,
                            global_state_locked,
                            global_state_boot,
                            group_state_bits,       // [8:5]
                            global_state_bits       // [4:0]
                        };

                        // ── 0x04  STATUS_FLAGS ────────────────────────────
                        // [0]     sw_sticky_tamper      (SW shadow, clearable)
                        // [1]     sw_sticky_illegal     (SW shadow, clearable)
                        // [2]     sw_sticky_fsm_error   (SW shadow, clearable)
                        // [3]     sw_sticky_breach      (SW shadow, clearable)
                        // [4]     sw_sticky_group_error (SW shadow, clearable)
                        // [5]     sticky_tamper_core    (core-owned, reset-only)
                        // [6]     sticky_illegal_core   (core-owned, reset-only)
                        // [7]     fsm_error_int         (live)
                        // [8]     security_breach_int   (live)
                        // [9]     group_error_int       (live)
                        // [31:10] reserved (0)
                        2'b01: wb_dat_o <= {
                            22'h0,
                            group_error_int,        // [9]
                            security_breach_int,    // [8]
                            fsm_error_int,          // [7]
                            sticky_illegal_core,    // [6]
                            sticky_tamper_core,     // [5]
                            sw_sticky_group_error,  // [4]
                            sw_sticky_breach,       // [3]
                            sw_sticky_fsm_error,    // [2]
                            sw_sticky_illegal,      // [1]
                            sw_sticky_tamper        // [0]
                        };

                        // ── 0x08  TIMEOUTS ────────────────────────────────
                        // [15:0]  global_timeout_count
                        // [31:16] group_timeout_count
                        2'b10: wb_dat_o <= {
                            group_timeout_count,    // [31:16]
                            global_timeout_count    // [15:0]
                        };

                        // ── 0x0C  CONTROL (write-only) ────────────────────
                        // Reads always return 0
                        2'b11: wb_dat_o <= 32'h0000_0000;

                        default: wb_dat_o <= 32'h0000_0000;

                    endcase
                end
            end
        end
    end

    // =========================================================================
    // IRQ generation
    // user_irq[0] asserts when any shadow sticky flag is set.
    // Firmware deasserts by writing the corresponding CONTROL bits.
    // =========================================================================
    assign user_irq = sw_sticky_tamper      |
                      sw_sticky_illegal     |
                      sw_sticky_fsm_error   |
                      sw_sticky_breach      |
                      sw_sticky_group_error;

endmodule

`default_nettype wire
