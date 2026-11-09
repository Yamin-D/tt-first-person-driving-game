// Two pairs of seven-segment digits on the dashboard, rows 384-447: the score at
// columns 128-191 and the speed (v / 2, 0..96) at columns 32-95. One decoder
// serves all four digits, since only one is being scanned at a time. Each digit is a 32 x 64 cell of 4 x 8 pixel blocks, cx 0-7 and cy 0-7.
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
    // speed in BCD by shift-and-add-3, registered: v only changes once a frame
    reg [7:0] bcd, speed;
    integer i;
    always @(*) begin
        bcd = 8'd0;
        for (i = 7; i >= 1; i = i - 1) begin
            if (bcd[3:0] >= 4'd5) bcd[3:0] = bcd[3:0] + 4'd3;
            if (bcd[7:4] >= 4'd5) bcd[7:4] = bcd[7:4] + 4'd3;
            bcd = {bcd[6:0], v[i]};
        end
    end
    always @(posedge clk)
        speed <= bcd;

    wire       right = (x[9:6] == 4'b0010);
    wire       left  = (x[9:5] == 5'b00001) | (x[9:5] == 5'b00010);
    wire       panel = (right | left) & (y[8:6] == 3'b110);
    wire [2:0] cx    = x[4:2];
    wire [2:0] cy    = y[5:3];
    wire [3:0] digit = right ? (x[5] ? ones : tens) : (x[5] ? speed[7:4] : speed[3:0]);

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

    assign code = !panel ? 2'd0 : lit ? 2'd2 : 2'd1;
    wire _unused = &{v[0], 1'b0};
endmodule
