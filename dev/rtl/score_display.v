// The dashboard readouts, rows 384-447: the score as two seven-segment digits at
// columns 128-191, and a speed bar in the panel at columns 32-95. Each digit is a 32 x 64 cell of 4 x 8 pixel blocks, cx 0-7 and cy 0-7.
// code: 0 none, 1 panel, 2 lit segment.
`default_nettype none

module score_display (
    input  wire       clk,
    input  wire [7:0] v,
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire [3:0] tens,
    input  wire [3:0] ones,
    output wire [1:0] code
);
    wire       right = (x[9:6] == 4'b0010);
    wire       left  = (x[9:5] == 5'b00001) | (x[9:5] == 5'b00010);
    wire       panel = (right | left) & (y[8:6] == 3'b110);
    wire [2:0] cx    = x[4:2];
    wire [2:0] cy    = y[5:3];
    // the speed bar: v / 4 rows up from the panel's bottom row, in columns 48-79
    wire       bar   = left & ((x[9:4] == 6'd3) | (x[9:4] == 6'd4)) & (~y[5:0] < v[7:2]);
    // Which digit is next is worked out one column ahead and registered, which
    // takes the digit choice off the path from x through the segment decoder.
    wire       next5 = x[5] ^ (&x[4:0]);
    reg  [3:0] digit;
    always @(posedge clk)
        digit <= next5 ? ones : tens;

    reg [6:0] seg;                                          // gfedcba
    always @(*) begin
        case (digit)
            4'd0:    seg = 7'b0111111;
            4'd1:    seg = 7'b0000110;
            4'd2:    seg = 7'b1011011;
            4'd3:    seg = 7'b1001111;
            4'd4:    seg = 7'b1100110;
            4'd5:    seg = 7'b1101101;
            4'd6:    seg = 7'b1111101;
            4'd7:    seg = 7'b0000111;
            4'd8:    seg = 7'b1111111;
            default: seg = 7'b1101111;
        endcase
    end

    wire mid   = (cx >= 3'd1) & (cx <= 3'd5);
    wire upper = (cy >= 3'd1) & (cy <= 3'd3);
    wire lower = (cy >= 3'd5) & (cy <= 3'd6);
    wire lit = (seg[0] & mid & (cy == 3'd0)) | (seg[1] & (cx == 3'd6) & upper) |
               (seg[2] & (cx == 3'd6) & lower) | (seg[3] & mid & (cy == 3'd7)) |
               (seg[4] & (cx == 3'd0) & lower) | (seg[5] & (cx == 3'd0) & upper) |
               (seg[6] & mid & (cy == 3'd4));

    assign code = !panel ? 2'd0 : ((right & lit) | bar) ? 2'd2 : 2'd1;
    wire _unused = &{v[1:0], 1'b0};
endmodule
