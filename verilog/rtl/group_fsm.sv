`timescale 1ns/1ps

module group_fsm #(
    // One-hot state encoding
    parameter logic [3:0] GROUP_DISABLED  = 4'b0001,
    parameter logic [3:0] GROUP_LOCKED    = 4'b0010,
    parameter logic [3:0] GROUP_UNLOCKED  = 4'b0100,
    parameter logic [3:0] GROUP_SUSPENDED = 4'b1000,

    // Per-state timeout thresholds (in cycles)
    parameter logic [15:0] DISABLED_TIMEOUT  = 16'd500,
    parameter logic [15:0] LOCKED_TIMEOUT    = 16'd1000,
    parameter logic [15:0] UNLOCKED_TIMEOUT  = 16'd2000,
    parameter logic [15:0] SUSPENDED_TIMEOUT = 16'hFFFF   // usually ignored / absorbing
) (
    input  logic        clk,
    input  logic        reset,

    // Global gating
    input  logic        global_authorized,   // from global FSM

    // Local control / events
    input  logic        unlock_req,          // request to unlock this group
    input  logic        autolock,            // explicit autolock event
    input  logic        file_denied,         // access denied on this group
    input  logic        tamper,              // local tamper
    input  logic        illegal_state,       // detected illegal state

    // State outputs
    output logic [3:0]  state_bits,
    output logic        state_disabled,
    output logic        state_locked,
    output logic        state_unlocked,
    output logic        state_suspended,

    // Status / events
    output logic        group_unlocked,      // to global FSM
    output logic        group_locked,
    output logic        group_suspended,
    output logic        group_error,         // sticky error flag

    // Timeout visibility
    output logic [15:0] timeout_count
);

    //==========================================================================
    // State Registers
    //==========================================================================
    logic [3:0] state, next_state;

    // One-hot check
    logic state_onehot_error;
    assign state_onehot_error =
        (state != GROUP_DISABLED)  &&
        (state != GROUP_LOCKED)    &&
        (state != GROUP_UNLOCKED)  &&
        (state != GROUP_SUSPENDED);

    // State register
    always_ff @(posedge clk) begin
        if (reset)
            state <= GROUP_DISABLED;
        else
            state <= next_state;
    end

    //==========================================================================
    // Timeout Counter
    //==========================================================================
    logic [15:0] timeout_counter;
    assign timeout_count = timeout_counter;

    // Reset counter on state change, increment otherwise
    always_ff @(posedge clk) begin
        if (reset) begin
            timeout_counter <= 16'd0;
        end else if (next_state != state) begin
            timeout_counter <= 16'd0;
        end else begin
            timeout_counter <= timeout_counter + 16'd1;
        end
    end

    // Per-state timeout events
    logic timeout_disabled;
    logic timeout_locked;
    logic timeout_unlocked;
    logic timeout_suspended;

    assign timeout_disabled  = (timeout_counter >= DISABLED_TIMEOUT);
    assign timeout_locked    = (timeout_counter >= LOCKED_TIMEOUT);
    assign timeout_unlocked  = (timeout_counter >= UNLOCKED_TIMEOUT);
    assign timeout_suspended = (timeout_counter >= SUSPENDED_TIMEOUT);

    //==========================================================================
    // Next State Logic
    //==========================================================================
    always_comb begin
        next_state = state;

        // Top priority: tamper / illegal / one-hot → SUSPENDED
        if (state_onehot_error || illegal_state || tamper) begin
            next_state = GROUP_SUSPENDED;
        end else begin
            unique case (state)

                GROUP_DISABLED: begin
                    // No idle residency: timeout forces progress
                    if (timeout_disabled)
                        next_state = GROUP_LOCKED;
                    else if (unlock_req && global_authorized)
                        next_state = GROUP_UNLOCKED;
                    else
                        next_state = GROUP_DISABLED;
                end

                GROUP_LOCKED: begin
                    if (timeout_locked)
                        next_state = GROUP_SUSPENDED;
                    else if (unlock_req && global_authorized)
                        next_state = GROUP_UNLOCKED;
                    else
                        next_state = GROUP_LOCKED;
                end

                GROUP_UNLOCKED: begin
                    if (timeout_unlocked || autolock || file_denied)
                        next_state = GROUP_LOCKED;
                    else
                        next_state = GROUP_UNLOCKED;
                end

                GROUP_SUSPENDED: begin
                    // Absorbing; optional timeout escalation if desired
                    if (SUSPENDED_TIMEOUT != 16'd0 && timeout_suspended)
                        next_state = GROUP_SUSPENDED; // placeholder for escalation
                    else
                        next_state = GROUP_SUSPENDED;
                end

                default: next_state = GROUP_SUSPENDED;

            endcase
        end
    end

    //==========================================================================
    // State Decode
    //==========================================================================
    assign state_bits      = state;
    assign state_disabled  = (state == GROUP_DISABLED);
    assign state_locked    = (state == GROUP_LOCKED);
    assign state_unlocked  = (state == GROUP_UNLOCKED);
    assign state_suspended = (state == GROUP_SUSPENDED);

    //==========================================================================
    // Status / Events
    //==========================================================================
    assign group_unlocked  = state_unlocked;
    assign group_locked    = state_locked;
    assign group_suspended = state_suspended;

    // Sticky error: any illegal/one-hot/tamper latches error
    logic group_error_r;
    always_ff @(posedge clk) begin
        if (reset)
            group_error_r <= 1'b0;
        else if (state_onehot_error || illegal_state || tamper)
            group_error_r <= 1'b1;
    end

    assign group_error = group_error_r;

endmodule
