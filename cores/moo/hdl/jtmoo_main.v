/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Author: Rafael Eduardo Paiva Feener. Copyright: Jose Tejada Gomez
 * Version: 1.0
 * Date: 17-6-2026 */

module jtmoo_main(
    input                rst,
    input                clk, // 48 MHz
    input                cen_16,
    input                LVBL,
    input                bucky,
    input                int1,

    output        [20:1] main_addr,
    output        [ 1:0] ram_dsn,
    output        [15:0] cpu_dout,
    // 8-bit interface
    output               cpu_we,
    output reg           pal_cs,   // palette RAM, seen through the K054338
    output reg           pcu_cs,   // K053251
    output reg           k338_cs,  // K054338 registers
    // Sound interface
    output               pair_we,   // K054321 PAIR~{CS} write
    input         [ 7:0] pair_dout, // K054321 PAIR~{CS} read
    output reg           sndon,     // K054321 SDON irq trigger

    output reg           rom_cs,
    output reg           ram_cs,
    output reg           vram_cs,
    output                oram_cs,  // object RAM CPU window, 0x190000-0x19FFFF
    output reg           scr_cs,

    input         [15:0] oram_dout,
    input         [15:0] vram_dout,
    input         [15:0] pal_dout,
    input         [15:0] ram_dout,
    input         [15:0] rom_data,
    input                ram_ok,
    input                rom_ok,
    input                vdtac,
    output               ram_we,

    output reg           cco_cs,
    output               rw,
    input         [ 7:0] vtimer_mmr,

    // video configuration
    output        [ 1:0] oram_we,
    output reg           objreg_cs,
    output reg           scrreg_cs,
    output reg           objcha_n,
    output reg           rmrd_cs,  // graphics ROM read-back window
    output reg           blnk_sel,
    input                dma_bsy,
    // EEPROM
    output      [ 6:0]   nv_addr,
    input       [ 7:0]   nv_dout,
    output      [ 7:0]   nv_din,
    output               nv_we,
    // Cabinet
    input         [ 6:0] joystick1,
    input         [ 6:0] joystick2,
    input         [ 6:0] joystick3,
    input         [ 6:0] joystick4,
    input         [ 3:0] cab_1p,
    input         [ 3:0] coin,
    input         [ 3:0] service,
    input         [ 3:0] dipsw,
    input                dip_pause,
    input                dip_test,
    output        [ 7:0] st_dout,
    input         [ 7:0] debug_bus
);
`ifndef NOMAIN
wire [23:1] A;
wire        cpu_cen, cpu_cenb;
wire        UDSn, LDSn, RnW, ASn, VPAn, DTACKn;
wire [ 2:0] FC;
reg  [ 2:0] IPLn;
reg         cab_cs, HALTn,
            eep_di, eep_clk, eep_cs, intdma_enb,
            pair_cs, reg_cs;
reg  [15:0] cpu_din, cab_dout, cur_ctrl2;
reg  [ 7:0] io_dout;
wire [ 7:0] hip_dout;
wire        eep_rdy, eep_do, bus_cs, bus_busy, BUSn;
wire        dtac_mux, intdma;
wire [15:0] cpu_dout_68k;
wire [23:1] a_mx;
wire        asn_mx;
wire [ 1:0] dsn_mx;

/* verilator tracing_on */
// 053990 (N4) takes the bus for its DMA (BRn/BGACKn on main.kicad_sch),
// same pattern as jtriders_main. Exact 053990 cycle timing unverified.
assign a_mx     = prot_bgackn ? A            : prot_addr;
assign asn_mx   = prot_bgackn ? ASn          : prot_asn;
assign dsn_mx   = prot_bgackn ? {UDSn, LDSn} : prot_dsn;
assign rw       = prot_bgackn ? RnW          : prot_wrn;

assign main_addr= a_mx[20:1];
assign ram_dsn  = dsn_mx;
assign ram_we   = ram_cs & ~rw & ~&ram_dsn;
// rmrd_cs/vdtac is folded into bus_busy so the dtack recovery accounting
// sees it (cal50 does the same; riders/xmen instead OR ~vdtac onto DTACKn
// outside the recovery math -- either works, this just states the choice).
assign bus_cs   = rom_cs | ram_cs | rmrd_cs;
assign bus_busy = (rom_cs & ~rom_ok) | (ram_cs & ~ram_ok) | (rmrd_cs & ~vdtac);
assign BUSn     = asn_mx | (dsn_mx[1] & dsn_mx[0]);
assign VPAn     = ~vpa;

assign cpu_we   = prot_bgackn ? ~RnW : ~prot_wrn;
assign cpu_dout = prot_bgackn ? cpu_dout_68k : prot_din;
// 0x190000-0x19FFFF sprite RAM, 055373 ORAMWE term: write cycles only
assign oram_we  = ~ram_dsn & {2{~rw & oram_wr}};
assign oram_cs  =  oram_wr & ~BUSn;

assign st_dout  = 0; // status byte permanently zero; debug-only, no consumer wires it up
assign dtac_mux = DTACKn;
assign pair_we  = pair_cs && !RnW && !LDSn;

reg none_cs, hip_cs, io_cs, obj_cs;
reg vpa, oram_wr, dec_en;
always @* begin
    rom_cs   = 0;
    ram_cs   = 0;
    rmrd_cs  = 0;
    vpa      = 0;
    oram_wr  = 0;
    scr_cs   = 0;
    dec_en   = 0;
    scrreg_cs= 0;
    k338_cs  = 0;
    obj_cs   = 0;
    objreg_cs= 0;
    reg_cs   = 0;
    pcu_cs   = 0;
    prot_cs  = 0;
    cco_cs   = 0;
    hip_cs   = 0;
    sndon    = 0;
    pair_cs  = 0;
    vram_cs  = 0; // tilesys_cs
    cab_cs   = 0;
    io_cs    = 0;
    pal_cs   = 0;
    // Address decode runs off the muxed bus (a_mx/asn_mx) so it correctly
    // serves both the 68000's own cycles and the 053990's DMA cycles when
    // it holds the bus (prot_bgackn low) -- see the a_mx/asn_mx/dsn_mx mux
    // above (A7). VPA/autovector stays tied to the CPU's own ASn/A: the
    // 053990 never generates an interrupt-acknowledge cycle.
    if(!ASn && A[23]) vpa = 1;
    if(!asn_mx && a_mx[22:21]==0) begin
        // 055373 - PAL20L10 (from PAL equations)
        casez( a_mx[20:14] )
            7'b110_01??: oram_wr  = 1;     // ORAMWE
            7'b110_1100: rmrd_cs  = ~BUSn; // PRE_DTACK: tile ROM read-back
            7'b110_1000: scr_cs   = ~BUSn; // LYR_PRIO: tile RAM window
            7'b110_00??: ram_cs   = ~BUSn;
            7'b011_0???: dec_en   = 1;     // PALE
            7'b00?_????: rom_cs   = 1;     // ~OE1 in sch
            7'b10?_????: rom_cs   = 1;     // ~OE2 in sch
            7'b111_0000: pal_cs   =~BUSn;  // RAMCS: palette RAM through the K054338
            default:;
        endcase
    end
    if(dec_en) begin
        case (a_mx[16:13])
            4'h0: scrreg_cs = ~BUSn; // ROMCS in sch // to scroll
            4'h1: objreg_cs = ~BUSn; // REG
            4'h2: obj_cs    = ~BUSn; // CRCS: 053246 ROM read-back register
            4'h5: k338_cs   = 1;     // REGCS: K054338 registers
            4'h6: pcu_cs    = 1;     // PCUCS // to colmix 053251
            4'h7: prot_cs   = ~BUSn; // OBJ_REG_SEL

            // CCU (053252) is 8-bit only (real board wires DB0-7 alone),
            // so gate on the low data strobe -- an upper-byte-only write
            // must not touch the CCU register file. D7.
            4'h8: cco_cs  = ~BUSn & ~dsn_mx[0]; // /CCO
            4'h9: hip_cs  = ~BUSn & bucky; // COLCS
            4'hA: sndon   = ~BUSn; // SDON
            4'hB: pair_cs = ~BUSn; // PAIRCS
            4'hC: vram_cs = ~BUSn; // BNKSCR
            4'hD: cab_cs  = ~BUSn; // IOCS
            4'hE: io_cs   = ~BUSn; // IOCSB
            4'hF: reg_cs  = ~BUSn; // REG_WRITE
            default:;
        endcase
    end
`ifdef SIMULATION
    none_cs = ~BUSn & ~|{rom_cs, ram_cs, pal_cs, io_cs, prot_cs, k338_cs, hip_cs, rmrd_cs,
        cab_cs, vram_cs, scr_cs, scrreg_cs, obj_cs, objreg_cs, sndon, pcu_cs, reg_cs, cco_cs};
`endif
end

jtframe_edge #(.QSET(0)) u_ff(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .edgeof     ( dma_bsy   ),
    .clr        (~intdma_enb),
    .q          ( intdma    ) // IRQ in schematics
);

always @(posedge clk) begin
    IPLn <= 3'b111;
    if(!intdma)
        IPLn <= 3'b010;
    // int1 comes from jtk053252's jtframe_edge with the default QSET=1, so
    // it is active high (1 = INT1 pending until the CPU acks it). The real
    // PCB's INT1 pin is active low into the LS148, but the RTL module has
    // already inverted that. Testing !int1 here left level 4 asserted only
    // while idle and never once INT1 was pending, so the ISR never ran,
    // never acked, and int1 stuck high forever (boot waits on the ISR
    // clearing a RAM flag at 0x18004A, verified by MAME disassembly).
    else if (int1)
        IPLn <= 3'b011;
    else if (!prot_irqn)
        IPLn <= 3'b100;

    HALTn   <= dip_pause & ~rst;
    cpu_din <= rom_cs  ? rom_data        :
               ram_cs  ? ram_dout        :
               (obj_cs|oram_cs) ? oram_dout : // 0x0C4000 ROM read-back reg
                                               // and 0x190000 sprite RAM (A2)
               (vram_cs | scr_cs | scrreg_cs | rmrd_cs) ? vram_dout :
               (pal_cs|k338_cs) ? pal_dout :
               reg_cs  ? cur_ctrl2       :
               cco_cs  ? {8'd0,vtimer_mmr}: // 053252 CCU read-back (A6)
               prot_cs ? prot_din        :
               pair_cs ? {8'd0,pair_dout}:
               io_cs   ? {8'd0,io_dout  }:
               cab_cs  ? cab_dout        : 16'hffff;
end

always @(posedge clk) begin
    // PSACA1 = MAIN_A1 through two series inverters (io_cabinet.kicad_sch
    // G6.1/M6.1); the 74LS257 select is A1 itself, low = P1/P3, high =
    // P2/P4 -- matches doc/moo.cpp:569-570 (0x0DA000=P1_P3, 0x0DA002=
    // P2_P4). Previously inverted (A5), which sent every 1P/3P/2P/4P
    // input, including start and coin, to the wrong address.
    cab_dout <= A[1] ? { cab_1p[3], joystick4, cab_1p[1], joystick2 }:
                       { cab_1p[2], joystick3, cab_1p[0], joystick1 };
    io_dout  <= A[1] ? { dipsw, dip_test, 1'b1, eep_rdy, eep_do }:
                       { service , coin };
end


always @(posedge clk, posedge rst) begin
    if( rst ) begin
        eep_di  <= 0;
        eep_cs  <= 0;
        eep_clk <= 0;
        intdma_enb <= 1;
        objcha_n   <= 1;
        blnk_sel   <= 0;
        cur_ctrl2  <= 0;
    end else begin
        // 0x0DE000 control2: Q4 (74LS174) low byte, N6 (74LS175) high byte.
        // Qualified on the muxed rw/dsn_mx so a (never expected) 053990
        // DMA access here would be handled consistently; normal operation
        // is bit-identical to using RnW/LDSn/UDSn directly.
        if( reg_cs & ~rw ) begin
            if( !dsn_mx[0] ) begin
                cur_ctrl2[ 7:0] <= cpu_dout[7:0];
                { intdma_enb, eep_clk, eep_cs, eep_di } <= {cpu_dout[5],cpu_dout[2:0]};
            end
            if( !dsn_mx[1] ) begin
                cur_ctrl2[15:8] <= cpu_dout[15:8];
                objcha_n <= ~cpu_dout[8];
                blnk_sel <=  cpu_dout[9];
            end
        end
    end
end

/* verilator tracing_on */
wire [23:1] prot_addr;
wire [15:0] prot_dout, prot_din;
wire [ 1:0] prot_dsn;
wire        prot_asn, prot_wrn, prot_irqn,
            prot_brn, prot_bgackn, BGn;
reg         prot_cs;
assign prot_dout  = cpu_din;
assign prot_irqn = 1;
jtriders_tmnt2 u_prot(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( cen_16        ),

    .cs         ( prot_cs       ),
    .addr       ( main_addr[4:1]),
    .dsn        ( ram_dsn       ),
    .din        ( cpu_dout      ), // = cpu_dout
    .cpu_we     ( cpu_we        ),
    .dtack_n    ( dtac_mux /*DTACKn*/        ),

    // DMA
    .bus_asn    ( prot_asn      ),
    .bus_addr   ( prot_addr     ),
    .bus_din    ( prot_din      ),
    .bus_dout   ( prot_dout     ),
    .bus_dsn    ( prot_dsn      ),
    .bus_wrn    ( prot_wrn      ),

    .BRn        ( prot_brn      ),
    .BGn        ( BGn           ),
    .BGACKn     ( prot_bgackn   )
);

// only used in Bucky O'Hare
jtk054000 u_hip(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .cs     ( hip_cs    ),
    .addr   ( A[5:1]    ),
    .we     ( cpu_we    ),
    .din    ( cpu_dout[7:0] ),
    .dout   ( hip_dout  )
);

/* verilator tracing_on */
jt5911 #(.SIMFILE("nvram.bin")) u_eeprom(
    .rst        ( rst       ),
    .clk        ( clk       ),
    // chip interface
    .sclk       ( eep_clk   ),         // serial clock
    .sdi        ( eep_di    ),         // serial data in
    .sdo        ( eep_do    ),         // serial data out
    .rdy        ( eep_rdy   ),
    .scs        ( eep_cs    ),         // chip select, active high. Goes low in between instructions
    // Dump access
    .mem_addr   ( nv_addr   ),
    .mem_din    ( nv_din    ),
    .mem_we     ( nv_we     ),
    .mem_dout   ( nv_dout   ),
    // NVRAM contents changed
    .dump_clr   ( 1'b0      ),
    .dump_flag  (           )
);

// The board seems to control DTACKn with combinational logic
// DTACKn follows ASn with a delay of ~15.6ns
wire slow_mem = rom_cs | ram_cs;
jtframe_68kdtack_cen #(.W(6),.RECOVERY(1)) u_dtack(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cpu_cen    ( cpu_cen   ),
    .cpu_cenb   ( cpu_cenb  ),
    .bus_cs     ( bus_cs    ),
    .bus_busy   ( bus_busy  ),
    .bus_legit  ( 1'b0      ),
    // bus_ack tied low like riders/xmen (same 053990 DMA chip): 053990 bus timing
    // is not independently verified as exempt from recovery accounting.
    .bus_ack    ( 1'b0      ),
    .ASn        ( ASn       ),
    .DSn        ({UDSn,LDSn}),
    .num        ( 5'd1      ),  // numerator
    .den        ( 6'd3      ),  // denominator, 3 (16MHz)
    .DTACKn     ( DTACKn    ),
    .wait2      ( slow_mem  ),  // RAM of that age didn't operate at 16MHz
    .wait3      ( 1'b0      ),
    // Frequency report
    .fave       (           ),
    .fworst     (           )
);

jtframe_m68k u_cpu(
    .clk        ( clk         ),
    .rst        ( rst         ),
    .RESETn     (             ),
    .cpu_cen    ( cpu_cen     ),
    .cpu_cenb   ( cpu_cenb    ),

    // Buses
    .eab        ( A           ),
    .iEdb       ( cpu_din     ),
    .oEdb       ( cpu_dout_68k),


    .eRWn       ( RnW         ),
    .LDSn       ( LDSn        ),
    .UDSn       ( UDSn        ),
    .ASn        ( ASn         ),
    .VPAn       ( VPAn        ),
    .FC         ( FC          ),

    .BERRn      ( 1'b1        ),
    // Bus arbitrion
    .HALTn      ( HALTn       ),
    .BRn        ( prot_brn    /*1'b1*/),
    .BGACKn     ( prot_bgackn /*1'b1*/),
    .BGn        ( BGn         ),

    .DTACKn     ( dtac_mux    ),
    .IPLn       ( IPLn        ) // VBLANK
);
`else
    reg [7:0] saved[0:0];
    integer f,fcnt=0;

    // initial begin
    //     f=$fopen("other.bin","rb");
    //     if( f!=0 ) begin
    //         fcnt=$fread(saved,f);
    //         $fclose(f);
    //         $display("Read %1d bytes for dimming configuration", fcnt);
    //         {dimmod,dimpol,dim} = {saved[0][5:4],saved[0][2:0]};
    //     end else begin
    //         {dimmod,dimpol,dim} = 0;
    //     end
    // end
    initial begin
        objcha_n  = 1;
        objreg_cs = 0;
        pal_cs    = 0;
        pcu_cs    = 0;
        k338_cs   = 0;
        rmrd_cs   = 0;
        reg_cs    = 0;
        ram_cs    = 0;
        rom_cs    = 0;
        sndon     = 0;
        vram_cs   = 0;
    end
    assign
        cpu_dout  = 0,
        cpu_we    = 0,
        main_addr = 0,
        ram_dsn   = 0,
        st_dout   = 0,
        nv_addr   = 0,
        nv_din    = 0,
        pair_we   = 0,
        oram_cs   = 0,
        nv_we     = 0;
`endif
endmodule
