// as tb.cpp, but every access is held by WAIT_I for 0..3 clocks with garbage on DI
// (the bus of the ZEMMIX); reports when the access shown changes while held.
#include "VR800.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

static unsigned char mem[65536];

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "tbw cpm.bin prog.com [max_clocks]\n"); return 1; }
    FILE *f = fopen(argv[1], "rb"); size_t n = fread(mem, 1, 0x10000, f); fclose(f);
    static unsigned char hi[0x1000]; memcpy(hi, mem + 0xF000, n > 0xF000 ? n - 0xF000 : 0);
    memset(mem + 0x100, 0, 0xEF00);
    f = fopen(argv[2], "rb"); fread(mem + 0x100, 1, 0xEF00, f); fclose(f);
    memcpy(mem + 0xF000, hi, 0x1000);
    unsigned long long maxc = argc > 3 ? strtoull(argv[3], 0, 0) : 20000000000ULL;
    VR800 *cpu = new VR800;
    cpu->RESET = 1; cpu->INT = 0; cpu->NMI = 0; cpu->WAIT_I = 0; cpu->CLK = 0;
    unsigned long long c; int hold = -1, bad = 0;
    unsigned key = 0, rnd = 12345; int intl = 0; unsigned long long nint = 0;
    for (c = 0; c < maxc; c++) {
        if (c > 100 && c % 3001 == 0) { intl = 1; nint++; }
        cpu->INT = intl;
        cpu->CLK = 0; cpu->eval();
        bool acc = !cpu->RESET && (cpu->MREQ || cpu->IORQ);
        unsigned k = (cpu->ADDR << 8) | (cpu->MREQ << 4) | (cpu->IORQ << 3) | (cpu->WR << 2) | (cpu->M1 << 1);
        if (acc && hold < 0) { rnd = rnd * 1103515245 + 12345; hold = (rnd >> 16) & 3; key = k; }
        if (hold > 0 && k != key && bad < 20) {
            printf("\n[clock %llu: access %06X changed to %06X while held]\n", c, key, k); bad++;
        }
        if (hold > 0) { cpu->WAIT_I = 1; cpu->DI = rnd >> 24; }
        else { cpu->WAIT_I = 0; cpu->DI = cpu->MREQ ? mem[cpu->ADDR] : 0xFF; }
        cpu->eval();
        {
            unsigned k2 = (cpu->ADDR << 8) | (cpu->MREQ << 4) | (cpu->IORQ << 3) | (cpu->WR << 2) | (cpu->M1 << 1);
            if (hold >= 0 && k2 != key && bad < 20) {
                printf("\n[clock %llu: access %06X follows DI %02X: %06X]\n", c, key, cpu->DI, k2); bad++;
            }
        }
        if (acc && hold == 0) {
            if (cpu->MREQ && cpu->WR) mem[cpu->ADDR] = cpu->DO;
            if (cpu->IORQ && cpu->WR && !cpu->M1) {
                int p = cpu->ADDR & 0xFF;
                if (p == 1) { putchar(cpu->DO); fflush(stdout); }
                if (p == 3) intl = 0;
                if (p == 2) { printf("\n[exit at clock %llu, %llu INT]\n", c, nint); break; }
            }
        }
        cpu->CLK = 1; cpu->eval();
        if (hold > 0) hold--; else if (hold == 0) hold = -1;
        if (c == 8) cpu->RESET = 0;
    }
    if (c >= maxc) printf("\n[stopped at %llu clocks]\n", c);
    delete cpu;
    return 0;
}
