// The Tiny Tapeout Gamepad Pmod on ui[4] latch, ui[5] clock, ui[6] data,
// following TinyTapeout/vga-playground's gamepad_pmod.v (Pat Deegan, Apache-2.0).
// The Pmod shifts out 12 bits per controller on rising clock edges and pulses
// latch when done; the last 12 bits are controller 1, in the order
// B, Y, Select, Start, Up, Down, Left, Right, A, X, L, R, active high. All ones
// means no controller. Only the four game controls are kept:
//   left = Left, right = Right, accelerate = B or Up, brake = Y or Down.
`default_nettype none

module gamepad (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       pmod_latch,
    input  wire       pmod_clk,
    input  wire       pmod_data,
    output reg  [3:0] keys          // {brake, accelerate, right, left}
);
    // two-flop synchronisers, plus the previous value for edge detection
    reg [1:0] data_s, clk_s, latch_s;
    reg       clk_prev, latch_prev;
    always @(posedge clk) begin
        if (!rst_n) begin
            data_s     <= 2'b00;
            clk_s      <= 2'b00;
            latch_s    <= 2'b00;
            clk_prev   <= 1'b0;
            latch_prev <= 1'b0;
        end else begin
            data_s     <= {data_s[0],  pmod_data};
            clk_s      <= {clk_s[0],   pmod_clk};
            latch_s    <= {latch_s[0], pmod_latch};
            clk_prev   <= clk_s[1];
            latch_prev <= latch_s[1];
        end
    end

    // no reset: only read at a latch, after a full packet has shifted in
    reg [11:0] shift;
    always @(posedge clk)
        if (clk_s[1] & ~clk_prev)
            shift <= {shift[10:0], data_s[1]};

    wire absent = &shift;
    always @(posedge clk) begin
        if (!rst_n)
            keys <= 4'b0000;
        else if (latch_s[1] & ~latch_prev)
            keys <= absent ? 4'b0000 :
                    {shift[10] | shift[6], shift[11] | shift[7], shift[4], shift[5]};
    end
endmodule
