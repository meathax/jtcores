#include "Vjtmoo_colmix.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>

static uint64_t simulation_time = 0;
double sc_time_stamp() { return static_cast<double>(simulation_time); }

int main(int argc, char** argv) {
    VerilatedContext context;
    context.commandArgs(argc, argv);
    Vjtmoo_colmix dut{&context};
    unsigned phase = 0;
    auto tick = [&]() {
        dut.pxl_cen = phase == 0;
        dut.clk = 0; dut.eval(); simulation_time += 5; context.timeInc(5);
        dut.clk = 1; dut.eval(); simulation_time += 5; context.timeInc(5);
        phase = (phase + 1) % 6;
    };
    auto settle = [&]() { for (unsigned i=0; i<96; ++i) tick(); };
    auto check = [&](uint32_t expected, const char* label) {
        settle();
        uint32_t actual = (dut.red << 16) | (dut.green << 8) | dut.blue;
        if (actual != expected) {
            std::fprintf(stderr, "%s: RGB=%06x expected=%06x\n", label, actual, expected);
            std::exit(1);
        }
    };
    dut.rst=1; dut.lhbl=1; dut.lvbl=1;
    dut.pcu_cs=0; dut.reg_cs=0; dut.pal_cs=0; dut.cpu_we=0;
    dut.cpu_addr=0; dut.cpu_dout=0; dut.cpu_dsn=3;
    dut.lyrf_pxl=0; dut.lyra_pxl=0; dut.lyrb_pxl=0; dut.lyrc_pxl=0;
    dut.lyro_pxl=0; dut.lyro_pri=0; dut.shadow=0;
    dut.ioctl_addr=0; dut.ioctl_ram=0; dut.debug_bus=0;
    settle(); dut.rst=0; settle();
    auto write = [&](bool palette, unsigned addr, unsigned value) {
        dut.reg_cs=!palette; dut.pal_cs=palette;
        dut.cpu_we=1; dut.cpu_dsn=0; dut.cpu_addr=addr; dut.cpu_dout=value;
        tick();
        dut.reg_cs=0; dut.pal_cs=0; dut.cpu_we=0; dut.cpu_dsn=3;
        tick();
    };
    write(false,11,255); write(false,15,1);
    for (uint32_t rgb : {0x123456u,0xff0000u,0x00ff00u,0x0000ffu,0xffffffu}) {
        write(false,0,rgb>>16); write(false,1,rgb&65535);
        auto dim=[](uint32_t c) { return c*255/256; };
        check((dim(rgb>>16)<<16)|(dim((rgb>>8)&255)<<8)|dim(rgb&255),"background");
    }
    write(true,0x702*2,0x23); write(true,0x702*2+1,0x6789);
    dut.lyrf_pxl=2;
    check(0x236789,"foreground palette bypass");
    dut.lhbl=0; check(0,"horizontal blanking");
    dut.lhbl=1; dut.lvbl=0; check(0,"vertical blanking");
    dut.lvbl=1; write(false,15,0); check(0,"video disable");
    for (unsigned i=0; i<2048; ++i) {
        unsigned r=(i*3+(i>>8)*19)&255;
        unsigned g=(i*7+(i>>8)*23)&255;
        unsigned b=(i*11+(i>>8)*29)&255;
        write(true,i*2,r); write(true,i*2+1,(g<<8)|b);
    }
    dut.ioctl_ram=1;
    for (unsigned i=0; i<2048; ++i) {
        unsigned expected[4]={0,(i*3+(i>>8)*19)&255,
                               (i*7+(i>>8)*23)&255,(i*11+(i>>8)*29)&255};
        for (unsigned lane=0; lane<4; ++lane) {
            dut.ioctl_addr=i*4+lane;
            for (unsigned delay=0; delay<4; ++delay) tick();
            if (dut.ioctl_din!=expected[lane]) {
                std::fprintf(stderr,"palette dump entry=%u lane=%u actual=%02x expected=%02x\n",
                             i,lane,dut.ioctl_din,expected[lane]);
                return 1;
            }
        }
    }
    for (unsigned reg=0; reg<16; ++reg) {
        unsigned value=0x1234u+reg*0x713u;
        write(false,reg,value);
        for (unsigned lane=0; lane<2; ++lane) {
            dut.ioctl_addr=0xa0+reg*2+lane;
            tick(); tick();
            unsigned expected=(value>>(lane*8))&255;
            if (dut.mmr_dump!=expected) {
                std::fprintf(stderr,"K338 dump reg=%u lane=%u actual=%02x expected=%02x\n",
                             reg,lane,dut.mmr_dump,expected);
                return 1;
            }
        }
    }
    for (unsigned reg=0; reg<13; ++reg) {
        unsigned value=(reg*7+3)&63;
        dut.pcu_cs=1; dut.cpu_we=1; dut.cpu_dsn=2;
        dut.cpu_addr=reg; dut.cpu_dout=value; tick();
        dut.pcu_cs=0; dut.cpu_we=0; dut.cpu_dsn=3;
        dut.ioctl_addr=0x80+reg; tick(); tick();
        if (dut.mmr_dump!=value) {
            std::fprintf(stderr,"K251 dump reg=%u actual=%02x expected=%02x\n",
                         reg,dut.mmr_dump,value);
            return 1;
        }
    }
    dut.final();
    std::puts("PASS: mixer colors, 8192 palette bytes and 45 live register bytes");
    return 0;
}
