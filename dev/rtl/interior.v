// The static inside of the car, tested per pixel from the screen counters.
// We sit on the left, so only the left has a pillar. The pillar's edge moves
// away from the centre going up: t = y/4 + ~x is -48..-1 on the pillar and
// >= 0 on the side window beyond it, which needs one adder and no carry in.
// code: 0 none, 1 roof or pillar, 2 mirror, 3 top of the dashboard,
//       5 vent slat, 6 side window.
`default_nettype none

module interior (
    input  wire [9:0] x,
    input  wire [9:0] y,
    output wire [2:0] code
);
    wire [10:0] t = {4'b0000, y[8:2]} + ~{1'b0, x};
    wire dash   = y[8] & (y[7] | (y[6] & y[5]));            // y >= 352
    wire roof   = (y[9:4] == 6'd0);                         // y < 16
    wire pillar = ~dash & (t[10:6] == 5'b11111) & (t[5:4] != 2'b00);
    wire window = ~dash & ~roof & ~t[10];
    wire mirror = (x[9:7] == 3'b010) & (y[9:4] == 6'd1);    // rows 16-31
    wire pad    = (y[8:4] == 5'b10110);                     // rows 352-367
    wire vent   = (y[8:5] == 4'b1101) & (x[9:6] == 4'b1001) & (x[5:4] != 2'b11) & y[2];

    assign code = mirror        ? 3'd2 :
                  roof | pillar ? 3'd1 :
                  pad           ? 3'd3 :
                  vent          ? 3'd5 :
                  window        ? 3'd6 : 3'd0;
endmodule
