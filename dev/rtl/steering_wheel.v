// Steering wheel in the foreground, centred on column 320, row 448 (the screen
// cuts off its lower part). Purely combinational: its result is registered as
// part of stage 1 of pixel_colour.
//
// The wheel angle w has five values, so there is no trigonometry:
//   rim    two octagons, inside when a < R, b < R and a + b < sqrt(2) R,
//          where a = |dx| and b = |dy| use bit inversion, not negation
//   spoke  sheared by slope w/4 (a shift): the top bits of dy - w dx / 4 agree
//
// The centre and radius make dx and dy bit slices of the counters.
// FULL = 0: for a 1x1 tile. Radius 64, 8 px rim, one spoke, one colour.
// FULL = 1: for a 1x2 tile. Radius 128, 16 px rim, T of spokes, marker, hub.
// code: 0 no wheel here, 1 black, 2 yellow, 3 grey.
`default_nettype none

module steering_wheel #(parameter FULL = 0) (
    input  wire       clk,
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire signed [2:0] w,
    output wire [1:0] code
);
    wire tilted   = (w[1:0] != 2'b00);
    wire positive = ~w[2] & tilted;
    wire negative =  w[2];

    generate if (FULL) begin : g_full
        // Two clocks: the adders here, the compares after the registers. Its
        // result is one clock later than the other per-pixel logic, which moves
        // the wheel one pixel to the right.
        wire on = (x >= 10'd192) & (x < 10'd448) & y[8] & (y[7] | y[6]);
        wire [7:0] dx = {~(x[7] ^ x[6]), ~x[6], x[5:0]};    // -128..127
        wire [7:0] dy = {y[7] ^ y[6],    ~y[6], y[5:0]};    // -128..31
        wire [6:0] a  = dx[6:0] ^ {7{dx[7]}};
        wire [6:0] b  = dy[6:0] ^ {7{dy[7]}};
        wire [7:0] s  = a + b;

        // marker on the top of the rim, 16 px wide, centred on dx = 16 w
        wire [4:0] m       = dx[7:3] - {w[2], w, 1'b0};
        wire       mark_at = dy[7] & ((m == 5'd0) | (m == 5'b11111));

        // shifts: |w| = 1 is >> 2, |w| = 2 is >> 1
        wire [7:0] tx = !tilted ? 8'd0 : w[0] ? {{2{dx[7]}}, dx[7:2]} : {dx[7], dx[7:1]};
        wire [7:0] ty = !tilted ? 8'd0 : w[0] ? {{2{dy[7]}}, dy[7:2]} : {dy[7], dy[7:1]};
        wire [7:0] sh = dy + (tx ^ {8{positive}});          // across spoke
        wire [7:0] sv = dx + (ty ^ {8{negative}});          // lower spoke

        reg [6:0] a_q;
        reg [7:0] s_q;
        reg [4:0] sh_q, sv_q;
        reg       on_q, mark_q;
        always @(posedge clk) begin
            a_q     <= a;
            s_q     <= s;
            on_q    <= on;
            mark_q  <= mark_at;
            sh_q    <= sh[7:3];
            sv_q    <= sv[7:3];
        end

        wire sp_h = (sh_q == 5'd0) | (sh_q == 5'b11111);
        wire sp_v = ((sv_q == 5'd0) | (sv_q == 5'b11111)) & ~dy[7];
        wire spoke_q = sp_h | sp_v;

        // a, b < 128 from their widths
        wire in_out = (s_q < 8'd181);
        wire in_in  = (a_q < 7'd112) & (b < 7'd112) & (s_q < 8'd158);
        wire rim    = in_out & ~in_in;
        wire hub    = (a_q < 7'd20) & (b < 7'd20) & (s_q < 8'd28);

        assign code = !on_q        ? 2'd0 :
                      rim & mark_q ? 2'd2 :
                      rim          ? 2'd1 :
                      hub          ? 2'd2 :
                      in_in & spoke_q ? 2'd3 : 2'd0;
    end else begin : g_small
        wire on = (x[9:7] == 3'b010) & y[8] & y[7];
        wire [6:0] dx = {~x[6], x[5:0]};                    // -64..63
        wire [6:0] dy = {~y[6], y[5:0]};
        wire [5:0] a  = dx[5:0] ^ {6{dx[6]}};
        wire [5:0] b  = dy[5:0] ^ {6{dy[6]}};
        wire [6:0] s  = a + b;

        wire in_in = (a < 6'd56) & (b < 6'd56) & (s < 7'd80);
        wire rim   = (s < 7'd92) & ~in_in;                  // a, b < 64 from `on`

        wire [6:0] t  = !tilted ? 7'd0 : w[0] ? {{2{dx[6]}}, dx[6:2]} : {dx[6], dx[6:1]};
        wire [6:0] sh = dy + (t ^ {7{positive}});
        wire spoke = in_in & ((sh[6:2] == 5'd0) | (sh[6:2] == 5'b11111));

        assign code = {1'b0, on & (rim | spoke)};
    end endgenerate

    wire _unused = &{negative, 1'b0};
endmodule
