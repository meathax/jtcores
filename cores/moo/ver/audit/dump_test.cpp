#include "Vjtmoo_dump.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

double sc_time_stamp() { return 0; }

int main(int argc, char** argv) {
    VerilatedContext context;
    context.commandArgs(argc, argv);
    Vjtmoo_dump dut{&context};
    struct Region { unsigned first, last, port; };
    const Region regions[] = {{0,0x6000,0},{0x6000,0x8000,1},{0x8000,0xc000,2},
                              {0xc000,0xc048,3},{0xc080,0xc08d,4},{0xc0a0,0xc0c0,4},
                              {0xc0c0,0xc0c8,5},{0xc0d0,0xc0e0,6}};
    const unsigned char signature[16] = {'M','O','O','S','C','E','N','E',1,0,0,0,0,0,0,0};
    for (unsigned addr=0; addr<65536; ++addr) {
        unsigned char values[7];
        for (unsigned port=0; port<7; ++port) values[port]=(addr*13+port*31)&255;
        dut.ioctl_addr=addr;
        dut.dump_scr=values[0]; dut.dump_pal=values[1]; dut.dump_obj=values[2];
        dut.scr_mmr=values[3]; dut.pal_mmr=values[4]; dut.obj_mmr=values[5];
        dut.ccu_mmr=values[6]; dut.debug_bus=addr&255; dut.st_scr=addr&255;
        unsigned expected=0;
        for (const auto& region: regions)
            if (addr>=region.first && addr<region.last) expected=values[region.port];
        if (addr>=0xc0e0 && addr<0xc0f0) expected=signature[addr-0xc0e0];
        dut.clk=0; dut.eval(); context.timeInc(1);
        dut.clk=1; dut.eval(); context.timeInc(1);
        if (dut.ioctl_din!=expected) {
            std::fprintf(stderr,"dump addr=%04x actual=%02x expected=%02x\n",
                         addr,dut.ioctl_din,expected);
            return 1;
        }
    }
    dut.final();
    std::puts("PASS: all 65536 serializer addresses, regions, padding and signature");
}
