// Whole-chip test: runs tt_um_road_racer through a button script and reads
// frames back from the VGA pins only, exactly as a monitor would.
// The pins show pixel (x, y) two clocks after the counters were at (x, y):
// one clock in pixel_colour's pipeline and one in the output register.
//   tb_chip <script.txt> <out_dir> <frame> [<frame> ...]
// Writes <out_dir>/frame_<n>.bin (640x480 bytes of RGB222) for each requested
// frame and reports any sync pulse in the wrong place.
#include "Vtt_um_road_racer.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <set>
#include <string>
#include <vector>

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: tb_chip script out_dir frames...\n"); return 2; }
    std::vector<int> keys;
    FILE *f = fopen(argv[1], "r");
    char line[16];
    while (fgets(line, sizeof line, f))
        if (line[0] == '0' || line[0] == '1')
            keys.push_back(strtol(line, nullptr, 2));   // bits: L R A B
    fclose(f);
    std::string out_dir = argv[2];
    std::set<int> want;
    int last = 0;
    for (int i = 3; i < argc; i++) { want.insert(atoi(argv[i])); last = std::max(last, atoi(argv[i])); }

    Verilated::commandArgs(argc, argv);
    auto *top = new Vtt_um_road_racer;
    top->ena = 1; top->uio_in = 0; top->ui_in = 0; top->rst_n = 0; top->clk = 0;
    for (int i = 0; i < 10; i++) { top->clk = 1; top->eval(); top->clk = 0; top->eval(); }
    top->rst_n = 1;
    top->clk = 1; top->eval(); top->clk = 0; top->eval();   // registered reset releases

    std::vector<unsigned char> buf(640 * 480);
    long sync_errors = 0, oe_errors = 0;
    int cx = 0, cy = 0, frame = 0;
    int px = -1, py = -1, pf = -1;          // counters one clock earlier
    while (frame <= last + 1) {
        if (cx == 0 && cy == 0) {
            int k = frame < (int)keys.size() ? keys[frame] : 0;
            // ui_in[0]=left [1]=right [2]=accel [3]=brake; script bits are L R A B
            top->ui_in = ((k >> 3) & 1) | (((k >> 2) & 1) << 1) |
                         (((k >> 1) & 1) << 2) | ((k & 1) << 3);
        }
        top->clk = 1; top->eval();
        // after this edge the pins show the pixel the counters were at one
        // clock earlier, (px, py) in frame pf
        unsigned uo = top->uo_out;
        if (pf >= 0) {
            int hs = (uo >> 7) & 1, vs = (uo >> 3) & 1;
            if (hs != !(px >= 656 && px < 752)) sync_errors++;
            if (vs != !(py >= 490 && py < 492)) sync_errors++;
            if (top->uio_oe != 0x01) oe_errors++;
            if (px < 640 && py < 480 && want.count(pf)) {
                int r = ((uo >> 0) & 1) << 1 | ((uo >> 4) & 1);
                int g = ((uo >> 1) & 1) << 1 | ((uo >> 5) & 1);
                int b = ((uo >> 2) & 1) << 1 | ((uo >> 6) & 1);
                buf[py * 640 + px] = (r << 4) | (g << 2) | b;
                if (px == 639 && py == 479) {
                    std::string path = out_dir + "/frame_" + std::to_string(pf) + ".bin";
                    FILE *o = fopen(path.c_str(), "wb");
                    fwrite(buf.data(), 1, buf.size(), o);
                    fclose(o);
                }
            }
        }
        top->clk = 0; top->eval();
        px = cx; py = cy; pf = frame;
        if (++cx == 800) {
            cx = 0;
            if (++cy == 525) {
                cy = 0;
                frame++;
            }
        }
    }
    printf("frames simulated: %d\nsync errors: %ld\nuio_oe errors: %ld\n",
           frame, sync_errors, oe_errors);
    delete top;
    return 0;
}
