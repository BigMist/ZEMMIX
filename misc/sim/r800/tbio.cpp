// zexdoc / zexall on the R800 core (misc/r800): 64 KB RAM read in the same clock,
// the program at 0100h, mini CP/M (cpm.asm) at 0000h, output to stdout.
#include "VR800.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

static unsigned char mem[65536];

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "tb cpm.bin prog.com [max_clocks]\n"); return 1; }
    FILE *f = fopen(argv[1], "rb"); size_t n = fread(mem, 1, 0x10000, f); fclose(f);
    // cpm.bin is 0000h-F0xxh: keep 0000h-00FFh and F000h-
    static unsigned char hi[0x1000]; memcpy(hi, mem + 0xF000, n > 0xF000 ? n - 0xF000 : 0);
    memset(mem + 0x100, 0, 0xEF00);
    f = fopen(argv[2], "rb"); fread(mem + 0x100, 1, 0xEF00, f); fclose(f);
    memcpy(mem + 0xF000, hi, 0x1000);
    unsigned long long maxc = argc > 3 ? strtoull(argv[3], 0, 0) : 20000000000ULL;
    VR800 *cpu = new VR800;
    cpu->RESET = 1; cpu->INT = 0; cpu->NMI = 0; cpu->WAIT_I = 0; cpu->CLK = 0;
    unsigned long long c;
    for (c = 0; c < maxc; c++) {
        // the access shown in this clock: data in, write and I/O at the rising edge
        cpu->CLK = 0; cpu->eval();
        cpu->DI = cpu->MREQ ? mem[cpu->ADDR] : (cpu->IORQ && !cpu->M1 ? ((cpu->ADDR & 0xFF) ^ 0x5A) : 0xFF);
        cpu->eval();
        if (!cpu->RESET) {
            if (cpu->MREQ && cpu->WR) mem[cpu->ADDR] = cpu->DO;
            if (cpu->IORQ && !cpu->M1 && (cpu->ADDR & 0xFF) >= 0x10)
                printf("[%s %04X %02X]", cpu->WR ? "OUT" : "IN", cpu->ADDR, cpu->WR ? cpu->DO : cpu->DI);
            if (cpu->IORQ && cpu->WR && !cpu->M1) {
                int p = cpu->ADDR & 0xFF;
                if (p == 1) { putchar(cpu->DO); fflush(stdout); }
                if (p == 2) { printf("\n[exit at clock %llu]\n", c); break; }
            }
        }
        cpu->CLK = 1; cpu->eval();
        if (c == 8) cpu->RESET = 0;
    }
    if (c >= maxc) printf("\n[stopped at %llu clocks]\n", c);
    delete cpu;
    return 0;
}
