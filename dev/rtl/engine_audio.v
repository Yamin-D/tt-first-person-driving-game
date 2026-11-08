// Engine sound. A phase accumulator steps once per line (31.25 kHz) with a step
// that rises with speed: inc = 128 + 2v gives about 61 Hz idling, 244 Hz at top
// speed. 128 + 2v = (v + 64) << 1, so it needs only a 2-bit increment. The sample is a sawtooth plus a square an octave below. Off the road,
// LFSR noise is mixed in for a gravel rumble. The output pin is PWM: high
// while the low 8 bits of the VGA x counter are below the sample, which gives
// a 98 kHz carrier with no counter of its own.
`default_nettype none

module engine_audio (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick,       // once per line
    input  wire [7:0] v,
    input  wire       offroad,
    input  wire [7:0] pwm_count,  // x[7:0] from the VGA timing
    output wire [7:0] sample,
    output reg        out
);
    reg [16:0] phase;
    reg [14:0] lfsr;

    wire [8:0] v64 = {1'b0, v} + 9'd64;
    wire [9:0] inc = {v64, 1'b0};

    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= 17'd0;
            lfsr  <= 15'h7FFF;
        end else if (tick) begin
            phase <= phase + {7'd0, inc};
            lfsr  <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};
        end
    end

    wire [7:0] base = {1'b0, phase[15:9]} + (phase[16] ? 8'd64 : 8'd0);
    assign sample = offroad ? (base ^ {2'b00, lfsr[5:0]}) : base;

    // registered, so the pin is driven straight from a flip-flop
    always @(posedge clk)
        out <= (pwm_count < sample);
endmodule
