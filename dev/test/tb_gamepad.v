// Sends Gamepad Pmod packets from gamepad_vectors.txt, one per line:
//   <number of bits> <half period in clocks> <bits, first sent first>
// and prints the decoded keys after each latch.
`timescale 1ns/1ps
`default_nettype none

module tb_gamepad;
    reg clk = 0, rst_n = 0;
    reg pmod_latch = 0, pmod_clk = 0, pmod_data = 0;
    wire [3:0] keys;
    integer fd, code, n, half, i, k;
    reg [23:0] bits;

    gamepad dut (.clk(clk), .rst_n(rst_n), .pmod_latch(pmod_latch),
                 .pmod_clk(pmod_clk), .pmod_data(pmod_data), .keys(keys));

    always #20 clk = ~clk;

    task wait_clocks(input integer c);
        for (k = 0; k < c; k = k + 1) @(posedge clk);
    endtask

    initial begin
        fd = $fopen("gamepad_vectors.txt", "r");
        wait_clocks(3);
        rst_n = 1;
        while (!$feof(fd)) begin
            code = $fscanf(fd, "%d %d %b\n", n, half, bits);
            for (i = n - 1; i >= 0; i = i - 1) begin
                #1 pmod_data = bits[i];
                wait_clocks(half);
                #1 pmod_clk = 1;
                wait_clocks(half);
                #1 pmod_clk = 0;
            end
            wait_clocks(half);
            #1 pmod_latch = 1;
            wait_clocks(half);
            #1 pmod_latch = 0;
            wait_clocks(8);
            $display("%0d", keys);
        end
        $finish;
    end
endmodule
