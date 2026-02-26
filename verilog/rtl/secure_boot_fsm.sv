`timescale 1ns/1ps

//==============================================================================
// Module: secure_boot_fsm
//==============================================================================

module secure_boot_fsm (
    // Clock and Reset
    input  logic        clk,
    input  logic        reset,

    // Boot and Firmware Verification Events
    input  logic        fw_ok,
    input  logic        fw_fail,
    input  logic        size_mismatch,
    input  logic        hdr_parse_fail,
    input  logic        global_pin_ok,

    // Authorization and Access Control Events
    input  logic        group_unlocked,
    input  logic        group_autolock,

    // Access Denial Tracking
    input  logic        file_denied,

    // Fault and Tamper Detection
    input  logic        power_glitch,
    input  logic        clock_glitch,
    input  logic        fatal_tamper,
    input  logic        illegal_state,

    // Reset Control Inputs
    input  logic        warm_reset_req,
    input  logic        cold_reset_req,

    // State Outputs
    output logic [4:0]  state_bits,
    output logic        state_boot,
    output logic        state_locked,
    output logic        state_authorized,
    output logic        state_safe_mode,
    output logic        state_escalated,

    // Functional Outputs
    output logic        unlock_enable,
    output logic        debug_enable,
    output logic        safe_led,

    // Status and Diagnostic Outputs
    output logic        fsm_error,
    output logic        security_breach,
    output logic [15:0] timeout_count
);

    //==========================================================================
    // State Encoding (One-Hot)
    //==========================================================================
    typedef enum logic [4:0] {
        GLOBAL_BOOT       = 5'b00001,
        GLOBAL_LOCKED     = 5'b00010,
        GLOBAL_AUTHORIZED = 5'b00100,
        GLOBAL_SAFE_MODE  = 5'b01000,
        GLOBAL_ESCALATED  = 5'b10000
    } state_t;

    state_t state, next_state, prev_state;

    //==========================================================================
    // Timeout Configuration
    //==========================================================================
    localparam logic [15:0] BOOT_TIMEOUT      = 16'd1000;
    localparam logic [15:0] LOCKED_TIMEOUT    = 16'd2000;
    localparam logic [15:0] AUTH_TIMEOUT      = 16'd3000;
    localparam logic [15:0] SAFE_MODE_TIMEOUT = 16'd5000; // reserved, unused

    logic [15:0] timeout_counter;
    logic        timeout_boot, timeout_locked, timeout_auth;

    //==========================================================================
    // Access Denial Counter
    //==========================================================================
    logic [1:0] denial_counter;
    logic       file_denied_1, file_denied_2;

    //==========================================================================
    // Event Grouping
    //==========================================================================
    logic boot_failure_event;
    logic fault_event;
    logic state_onehot_error;

    assign boot_failure_event = fw_fail | size_mismatch | hdr_parse_fail;
    assign fault_event        = power_glitch | clock_glitch;

    // One-hot error disabled during reset
    assign state_onehot_error = (!reset) && (state != 5'b00001 && state != 5'b00010 && state != 5'b00100 && state != 5'b01000 && state != 5'b10000);

    //==========================================================================
    // Out-of-order input detection
    //
    // Each signal is "unexpected" if asserted in a state where it has no
    // defined role.  Unexpected assertion -> SAFE_MODE.
    //==========================================================================
    logic unexpected_input;

    always_comb begin
        unexpected_input = 1'b0;

        case (state)
            GLOBAL_BOOT: begin
                if (global_pin_ok || group_unlocked || file_denied ||
                    warm_reset_req || cold_reset_req || group_autolock)
                    unexpected_input = 1'b1;
            end
            GLOBAL_LOCKED: begin
                if (fw_ok || warm_reset_req || group_autolock)
                    unexpected_input = 1'b1;
            end
            GLOBAL_AUTHORIZED: begin
                if (fw_ok || global_pin_ok || group_unlocked)
                    unexpected_input = 1'b1;
            end
            GLOBAL_SAFE_MODE: begin
                if (fw_ok || global_pin_ok || group_unlocked || file_denied ||
                    group_autolock || boot_failure_event)
                    unexpected_input = 1'b1;
            end
            GLOBAL_ESCALATED: begin
                unexpected_input = 1'b0;
            end
            default: begin
                unexpected_input = 1'b0;
            end
        endcase
    end

    //==========================================================================
    // Sequential Logic - State Register and Counters
    //==========================================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            state           <= GLOBAL_BOOT;
            prev_state      <= GLOBAL_BOOT;
            timeout_counter <= 16'd0;
            denial_counter  <= 2'd0;
        end else begin
            prev_state <= state;
            state      <= next_state;

            // Timeout counter: reset on state change, otherwise increment
            if (state != prev_state)
                timeout_counter <= 16'd0;
            else if (timeout_counter < 16'hFFFF)
                timeout_counter <= timeout_counter + 16'd1;

            // Denial counter
            if (state == GLOBAL_AUTHORIZED || state == GLOBAL_LOCKED) begin
                if (file_denied && denial_counter < 2'd3)
                    denial_counter <= denial_counter + 2'd1;
                else if (group_unlocked)
                    denial_counter <= 2'd0;
            end else begin
                denial_counter <= 2'd0;
            end
        end
    end

    //==========================================================================
    // Timeout Event Generation
    //==========================================================================
    always_comb begin
        timeout_boot   = (!reset) && (state == GLOBAL_BOOT       && timeout_counter >= BOOT_TIMEOUT);
        timeout_locked = (!reset) && (state == GLOBAL_LOCKED     && timeout_counter >= LOCKED_TIMEOUT);
        timeout_auth   = (!reset) && (state == GLOBAL_AUTHORIZED && timeout_counter >= AUTH_TIMEOUT);
        // SAFE_MODE_TIMEOUT reserved; no timeout_safe used
    end

    assign file_denied_1 = (denial_counter == 2'd1);
    assign file_denied_2 = (denial_counter >= 2'd2);

    //==========================================================================
    // Next State Combinational Logic
    //==========================================================================
    always_comb begin
        // Reset dominates everything
        if (reset) begin
            next_state = GLOBAL_BOOT;
        end else begin
            next_state = state;

            // Priority 0: One-hot violation
            if (state_onehot_error) begin
                next_state = GLOBAL_ESCALATED;
            end

            // Priority 1: Fatal tamper / illegal
            else if (fatal_tamper || illegal_state) begin
                next_state = GLOBAL_ESCALATED;
            end

            // Priority 2: Fault event from ANY state -> ESCALATED
            else if (fault_event) begin
                next_state = GLOBAL_ESCALATED;
            end

            // Priority 3: Out-of-order input -> SAFE_MODE
            else if (unexpected_input) begin
                next_state = GLOBAL_SAFE_MODE;
            end

            // Priority 4: State-specific transitions
            else begin
                case (state)

                    GLOBAL_BOOT: begin
                        if (fw_ok)
                            next_state = GLOBAL_LOCKED;
                        else if (boot_failure_event || timeout_boot)
                            next_state = GLOBAL_SAFE_MODE;
                    end

                    GLOBAL_LOCKED: begin
                        // Primary unlock path: PIN validation
                        if (global_pin_ok)
                            next_state = GLOBAL_AUTHORIZED;

                        // Secondary unlock path: group FSM
                        else if (group_unlocked)
                            next_state = GLOBAL_AUTHORIZED;

                        // Fail-secure transitions
                        else if (file_denied_2 || timeout_locked)
                            next_state = GLOBAL_SAFE_MODE;

                        // Reset path
                        else if (cold_reset_req)
                            next_state = GLOBAL_BOOT;
                    end

                    GLOBAL_AUTHORIZED: begin
                        if (group_autolock || timeout_auth)
                            next_state = GLOBAL_LOCKED;
                        else if (file_denied_2)
                            next_state = GLOBAL_SAFE_MODE;
                        else if (file_denied_1)
                            next_state = GLOBAL_LOCKED;
                        else if (warm_reset_req)
                            next_state = GLOBAL_LOCKED;
                        else if (cold_reset_req)
                            next_state = GLOBAL_BOOT;
                    end

                    GLOBAL_SAFE_MODE: begin
                        if (warm_reset_req)
                            next_state = GLOBAL_BOOT;
                        else if (cold_reset_req)
                            next_state = GLOBAL_BOOT;
                    end

                    GLOBAL_ESCALATED: begin
                        next_state = GLOBAL_ESCALATED; // Absorbing state
                    end

                    default: begin
                        next_state = GLOBAL_ESCALATED;
                    end

                endcase
            end
        end
    end

    //==========================================================================
    // Output Logic
    //==========================================================================
    always_comb begin
        unlock_enable = 1'b0;
        debug_enable  = 1'b0;
        safe_led      = 1'b0;

        case (state)
            GLOBAL_AUTHORIZED: begin
                unlock_enable = 1'b1;
                debug_enable  = 1'b1;
            end
            GLOBAL_SAFE_MODE,
            GLOBAL_ESCALATED: begin
                safe_led = 1'b1;
            end
            default: begin
                // no-op
            end
        endcase
    end

    //==========================================================================
    // State Decode Outputs
    //==========================================================================
    assign state_boot       = (state == GLOBAL_BOOT);
    assign state_locked     = (state == GLOBAL_LOCKED);
    assign state_authorized = (state == GLOBAL_AUTHORIZED);
    assign state_safe_mode  = (state == GLOBAL_SAFE_MODE);
    assign state_escalated  = (state == GLOBAL_ESCALATED);
    assign state_bits       = state;

    //==========================================================================
    // Status Outputs
    //==========================================================================
    logic fsm_error_r;

    always_ff @(posedge clk) begin
        if (reset)
            fsm_error_r <= 1'b0;
        else if (state_onehot_error || illegal_state)
            fsm_error_r <= 1'b1;
    end

    assign fsm_error      = fsm_error_r;
    assign security_breach = state_safe_mode | state_escalated;
    assign timeout_count   = timeout_counter;

endmodule
