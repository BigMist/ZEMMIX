#include "VR800.h"
#include "VR800___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstring>
static unsigned char mem[65536];
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); size_t n = fread(mem, 1, 0x10000, f); fclose(f);
    static unsigned char hi[0x1000]; memcpy(hi, mem + 0xF000, n > 0xF000 ? n - 0xF000 : 0);
    memset(mem + 0x100, 0, 0xEF00);
    f = fopen(argv[2], "rb"); fread(mem + 0x100, 1, 0xEF00, f); fclose(f);
    memcpy(mem + 0xF000, hi, 0x1000);
    VR800 *cpu = new VR800; cpu->RESET = 1;
    for (unsigned long c = 0; c < 4000; c++) {
        cpu->CLK = 0; cpu->eval();
        cpu->DI = cpu->MREQ ? mem[cpu->ADDR] : 0xFF; cpu->eval();
        if (!cpu->RESET && cpu->MREQ && cpu->WR) mem[cpu->ADDR] = cpu->DO;
        auto *r = cpu->rootp;
        if (r->R800__DOT__MULW || r->R800__DOT__MULOP)
            printf("c=%lu FETCH=%03x STAGE=%d MULOP=%d MULW=%d WE=%02x WSEL=%x mul=%08x\n", c,
                   r->R800__DOT__FETCH, r->R800__DOT__STAGE, r->R800__DOT__MULOP, r->R800__DOT__MULW,
                   r->R800__DOT__WE, r->R800__DOT__REG_WSEL, r->R800__DOT__mul_r);
        cpu->CLK = 1; cpu->eval();
        if (c == 8) cpu->RESET = 0;
    }
    return 0;
}
