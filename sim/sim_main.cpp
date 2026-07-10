#include <verilated.h>
#include "Vcore_top_sim.h"

vluint64_t main_time = 0;
const vluint64_t sim_limit = 30000000000; // 30Ãë·ÂÕæÊ±¼ä (ns)

double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vcore_top_sim* top = new Vcore_top_sim("top");

    top->clk_i = 0;
    top->rst_n_i = 0;

    while (!Verilated::gotFinish() && main_time < sim_limit) {
        top->clk_i = !top->clk_i;

        if (main_time < 100) top->rst_n_i = 0;
        else top->rst_n_i = 1;

        top->eval();

        if (main_time % 1000000 == 0) {
            printf("Time: %lu ns, score = %d\n", (unsigned long)main_time, top->perf_score);
        }

        if (top->perf_score != 0) {
            printf("\nCoreMark completed at time %lu ns\n", (unsigned long)main_time);
            printf("total_time(ms)   = %u\n", top->perf_total_time);
            printf("score            = %u\n", top->perf_score);
            printf("iterations       = %u\n", top->perf_iterations);
            printf("data_size(bytes) = %u\n", top->perf_data_size);
            printf("seedcrc(hex)     = 0x%x\n", top->perf_seedcrc);
            printf("total_errors     = %u\n", top->perf_total_errors);
            break;
        }

        main_time += 5;
    }

    if (main_time >= sim_limit) {
        printf("Simulation timeout reached without CoreMark score.\n");
    }

    delete top;
    return 0;
}