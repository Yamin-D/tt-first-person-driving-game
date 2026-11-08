// Per-line values for the road.
//   z  = 2**14 / s_y, from a restoring divider producing one quotient bit per
//        clock. It starts at x = 640 (after the visible pixels) and works out z
//        for the NEXT line in 15 clocks; the quotient register then holds that z
//        for the whole of the next line.
//   A  = ((h - 320) << 6) + p * s_y, within 17 bits. Loaded at the end of the
//        last sky row and then built by adding p once per road row.
//   Ae = (A >>> 6) plus the curve offset kappa * z / 64, for the next line. Built
//        in horizontal blanking with up to three shifted adds, after the divider
//        has finished, so the pixel stage still needs one adder: x - centre = x + Ae.
`default_nettype none

module line_setup #(
    parameter Z_BITS = 11         // quotient bits kept (11..15); curves use the low 11
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire        [9:0]  x,
    input  wire        [9:0]  y,
    input  wire signed [7:0]  h,
    input  wire signed [7:0]  p,
    input  wire signed [3:0]  kappa,
    output wire [Z_BITS-1:0]  z,
    output reg  signed [10:0] Ae
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
    reg a_load;                   // high at x = 640 on row 127
    reg a_add;                    // high at x = 640 on rows 128..383
    reg e_load;                   // high at x = 656, once z is ready
    reg e_step;                   // high at x = 657..659
    reg [1:0] e_bit;              // 0, 1, 2 while e_step is high
    always @(posedge clk) begin
        start  <= (x == 10'd639) && (y >= HORIZON) && (y < DASH_TOP - 10'd1);
        a_load <= (x == 10'd639) && (y == HORIZON - 10'd1);
        a_add  <= (x == 10'd639) && (y >= HORIZON) && (y < DASH_TOP);
        e_load <= (x == 10'd655);
        e_step <= (x >= 10'd656) && (x < 10'd659);
        e_bit  <= x[1:0];
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
    // no reset: A is always loaded on row 127, before any road row
    reg signed [16:0] A;
    always @(posedge clk) begin
        if (a_load)
            A <= {h_off, 6'b000000};
        else if (a_add)
            A <= A + {{9{p[7]}}, p};
    end

    // ---- curve: Ae = (A >>> 6) -/+ (kappa * z >> 6), one shifted add per clock.
    // Negative kappa's magnitude is its bit inversion; subtraction is one's
    // complement, so no carry in. z is clamped very near the horizon (s_y < 9).
    wire        sat  = (d[7:4] == 4'd0) & (~d[3] | (d[2:0] == 3'd0));
    wire [10:0] zs   = sat ? 11'd2047 : q[10:0];
    wire [2:0]  mag  = kappa[2:0] ^ {3{kappa[3]}};
    wire [10:0] term = (e_bit == 2'd0) ? {6'd0, zs[10:6]} :
                       (e_bit == 2'd1) ? {5'd0, zs[10:5]} : {4'd0, zs[10:4]};
    wire        use_bit = (e_bit == 2'd0) ? mag[0] :
                          (e_bit == 2'd1) ? mag[1] : mag[2];
    // no reset: loaded on every line
    always @(posedge clk) begin
        if (e_load)
            Ae <= A[16:6];
        else if (e_step & use_bit)
            Ae <= Ae + (term ^ {11{~kappa[3]}});
    end
    wire _unused = &{diff[8], A[5:0], 1'b0};
endmodule
