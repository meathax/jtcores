`timescale 1ns/1ps
module tb_nomain;
    logic clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    logic rst = 1;
    wire [20:1] main_addr;
    wire [1:0] ram_dsn, oram_we;
    wire [15:0] cpu_dout;
    wire [6:0] nv_addr;
    wire [7:0] nv_din, st_dout;
    wire cpu_we, pal_cs, pcu_cs, k338_cs, pair_we, sndon, rom_cs, ram_cs;
    wire vram_cs, oram_cs, scr_cs, ram_we, cco_cs, rw, objreg_cs, scrreg_cs;
    wire objcha_n, rmrd_cs, nv_we;
    jtmoo_main dut(
        .clk(clk), .rst(rst), .cen_16(clk), .int1(clk),
        .main_addr(main_addr), .ram_dsn(ram_dsn), .cpu_dout(cpu_dout),
        .cpu_we(cpu_we), .pal_cs(pal_cs), .pcu_cs(pcu_cs), .k338_cs(k338_cs),
        .pair_we(pair_we), .pair_dout(8'hff), .sndon(sndon),
        .rom_cs(rom_cs), .ram_cs(ram_cs), .vram_cs(vram_cs), .oram_cs(oram_cs),
        .scr_cs(scr_cs), .oram_dout(16'hffff), .vram_dout(16'hffff),
        .pal_dout(16'hffff), .ram_dout(16'hffff), .rom_data(16'hffff),
        .ram_ok(clk), .rom_ok(clk), .vdtac(clk), .ram_we(ram_we),
        .cco_cs(cco_cs), .rw(rw), .vtimer_mmr(8'hff), .oram_we(oram_we),
        .objreg_cs(objreg_cs), .scrreg_cs(scrreg_cs), .objcha_n(objcha_n),
        .rmrd_cs(rmrd_cs), .dma_bsy(clk), .nv_addr(nv_addr), .nv_dout(8'hff),
        .nv_din(nv_din), .nv_we(nv_we), .joystick1(7'h7f), .joystick2(7'h7f),
        .joystick3(7'h7f), .joystick4(7'h7f), .cab_1p(4'hf), .coin(4'hf),
        .service(4'hf), .dipsw(4'hf), .dip_pause(clk), .dip_test(clk),
        .st_dout(st_dout), .debug_bus(8'hff)
    );
    initial begin
        repeat (3) begin
            repeat (16) begin
                @(negedge clk);
                assert ({cpu_we,pal_cs,pcu_cs,k338_cs,pair_we,sndon,rom_cs,ram_cs,
                         vram_cs,oram_cs,scr_cs,ram_we,cco_cs,objreg_cs,scrreg_cs,
                         rmrd_cs,nv_we,oram_we} == '0)
                    else $fatal(1, "NOMAIN issued a bus transaction");
                assert (ram_dsn == 2'b11 && rw && objcha_n)
                    else $fatal(1, "NOMAIN active-low bus controls are not idle");
                assert ({main_addr,cpu_dout,nv_addr,nv_din,st_dout} == '0)
                    else $fatal(1, "NOMAIN undriven bus payload");
            end
            rst = ~rst;
        end
        $display("PASS: NOMAIN idle bus, reset and all output contracts");
        $finish;
    end
endmodule
