// Per-line values for the road.
//   z  = 2**14 / s_y, from a restoring divider producing one quotient bit per
//        clock. It starts at x = 640 (after the visible pixels) and works out z
//        for the NEXT line in 15 clocks; the quotient register then holds that z
//        for the whole of the next line.
//   A  = ((h - 320) << 6) + p * s_y, within 17 bits. Loaded at the end of the
//        last sky row and then built by adding p at the end of every road row. Folding h - 320 in
//        means the pixel stage needs one adder: x - centre = x + (A >>> 6).
`default_nettype none

module line_setup #(
    parameter Z_BITS = 4          // quotient bits kept (2..15): 4 for stage 1, 15 for curves
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire        [9:0]  x,
    input  wire        [9:0]  y,
    input  wire signed [7:0]  h,
    input  wire signed [8:0]  p,           // position, counted double: P >>> 5
    output wire [Z_BITS-1:0]  z,
    output reg  signed [16:0] A
);
    localparam [9:0] HORIZON  = 10'd128;
    localparam [9:0] DASH_TOP = 10'd384;

    // ---- divider: s_y of the next line is y + 1 - 128 = y - 127 (1..255)
    // divisor for the next line, registered: y is steady for 640 clocks first
    reg  [7:0] d;
    always @(posedge clk)
        d <= y[7:0] - 8'd127;                           // same as (y - 127) mod 256

    // Strobes are decoded one clock early and registered, so each comes
    // straight from a flip-flop on the same cycle as before. This keeps the
    // decode logic off the paths into the many registers they control.
    reg start;                    // high at x = 640 on rows 128..382
    reg a_load;                   // high at x = 799 on row 127
    reg a_add;                    // high at x = 799 on rows 128..383
    always @(posedge clk) begin
        start  <= (x == 10'd639) && (y >= HORIZON) && (y < DASH_TOP - 10'd1);
        a_load <= (x == 10'd798) && (y == HORIZON - 10'd1);
        a_add  <= (x == 10'd798) && (y >= HORIZON) && (y < DASH_TOP);
    end

    reg [7:0]  r;                 // remainder, always < d after a step
    reg [Z_BITS-1:0] q;           // the last Z_BITS quotient bits are the low bits
    reg [3:0]  i;                 // 14..0 while dividing, 15 when idle

    wire       busy = (i != 4'd15);
    wire [8:0] r_sh = {r, (i == 4'd14)};               // bring down the next bit of 2**14
    wire [9:0] diff = {1'b0, r_sh} - {2'b00, d};       // one subtractor ...
    wire       ge   = ~diff[9];                        // ... whose borrow is the compare
    wire [7:0] r_new = ge ? diff[7:0] : r_sh[7:0];

    always @(posedge clk) begin
        if (!rst_n)      i <= 4'd15;
        else if (start)  i <= 4'd14;
        else if (busy)   i <= i - 4'd1;                 // 0 -> 15 ends the run
    end

    // r and q need no reset: r is cleared at start and q is fully shifted over
    always @(posedge clk) begin
        if (start) begin
            r <= 8'd0;
        end else if (busy) begin
            r <= r_new;
            q <= {q[Z_BITS-2:0], ge};
        end
    end

    assign z = q;

    // ---- centre offset and steering accumulator
    wire signed [10:0] h_off = {{3{h[7]}}, h} - 11'sd320;
    // no reset: A is always loaded at the end of row 127, before any road row
    always @(posedge clk) begin
        if (a_load)
            A <= {h_off, 6'b000000};
        else if (a_add)
            A <= A + {{8{p[8]}}, p};
    end
    wire _unused = &{diff[8], 1'b0};
endmodule
