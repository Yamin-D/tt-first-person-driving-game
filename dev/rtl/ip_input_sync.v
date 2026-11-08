// Two-flop synchroniser for the buttons. There is no debounce counter:
// car_state only reads the buttons on the frame pulse, every 16.7 ms, which is
// longer than a switch bounces, so each read sees either the old or new state.
`default_nettype none

module ip_input_sync #(
    parameter N = 4
) (
    input  wire         clk,
    input  wire [N-1:0] in,
    output wire [N-1:0] out
);
    reg [N-1:0] s1, s2;
    always @(posedge clk) begin
        s1 <= in;
        s2 <= s1;
    end
    assign out = s2;
endmodule
