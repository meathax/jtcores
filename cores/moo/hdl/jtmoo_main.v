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

// E5: debug-only status byte, no functional consumer on real hardware.
// Was permanently tied to 0 (previous session found the original intended
// expression referenced signals -- rmrd/div8/game_id -- that no longer
// exist in this design and could not be honestly reconstructed). Wired
// instead to the interrupt/DMA/bus-arbitration state the D1/D2 work in
// this session most needed to observe: bus master handshake, the level-5
// (DMA-end) and level-4 (INT1) request latches, the raw DMA-busy strobe,
// and the current IPL encoding -- useful for a future ioctl/debug_bus
// differential check of the D2 fix without adding a new debug port.
assign st_dout  = { 1'b0, prot_bgackn, intdma, int1, dma_bsy, IPLn };
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

// D2 (KNOWN, main.md sec.6/9 GAP-5 note + sec.7): the level-5 flip-flop
// (G6B.1) clocks on "C = NOT OBJDMA" (K8.3), i.e. on the falling edge of
// OBJDMA -- when sprite DMA *ends*, not when it starts. dma_bsy is OBJDMA's
// RTL equivalent (active high while DMA is in progress), so the rising edge
// of ~dma_bsy is the falling edge of dma_bsy/OBJDMA. Previously edgeof was
// dma_bsy itself (DMA start) -- fixed here to ~dma_bsy (DMA end).
jtframe_edge #(.QSET(0)) u_ff(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .edgeof     (~dma_bsy   ),
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
    // D8 (KNOWN, io_cabinet.kicad_sch S16 / crtc_io_snd_latch.md G9): the
    // real board has four independent SERVICE1-4 inputs on D4-D7 of IOCSB
    // (MAME moo.cpp:668-671 keeps them separate). JTFRAME's MiSTer wrapper
    // exposes a single service-coin key, so all four board inputs stay
    // tied to that one bit ({4{service}}); this is a framework limitation,
    // not a schematic-vs-RTL mismatch, and is not worth spending unused
    // buttons on. See README for the deliberate-deviation list.
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
                // D4 (HYPOTHESIS, crtc_io_snd_latch.md G8 / scroll.md sec.4
                // item 3 / main.md D4): bit 9 -> N6.Q1 -> J8.1 XOR ~MCLK2 ->
                // H6.4 AND FPAL4 -> net N$26, confirmed a dead end in the
                // capture by three independent sheet audits (053252, scroll
                // and io_cabinet net lists all show H6.4 pin 11 unconnected).
                // Its real destination in the colour path (jtmoo_colmix.v,
                // out of this file's scope) cannot be resolved from the
                // available capture. Left wired here exactly as before;
                // do not "fix" the colmix consumer on a guess.
                blnk_sel <=  cpu_dout[9];
                // D3 (KNOWN, crtc_io_snd_latch.md sec.5 item "D11 -> Q3/~Q3
                // -> both NC"): the real board latches control2 bit 11 but
                // never connects it anywhere, so MAME's "bit 11 enables
                // IRQ4 (unconfirmed)" is not supported by the schematic.
                // Level 4 (IPLn<=3'b011 above, gated only on int1) stays
                // ungated on purpose -- this matches the board, not a
                // shortcut. Do not gate it on cur_ctrl2[11] without new
                // hardware evidence contradicting the capture.
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
// D1 (KNOWN, main.md GAP-4 / sec.7, MAME_SYSTEM=moomesa mame_read_memory
// evidence): level-3 autovector (0x00006C) reads 0x00001000, the same
// address shared by levels 1, 2, 6 and 7. The code at 0x1000 is
// `move.w d0,$1000; nop; bra.s *-4` -- an infinite dead loop, not an rte or
// real handler. Levels 4 (0x24B0) and 5 (0x2482) instead hold distinct
// handlers that clear real RAM flags. So the ROM never expects level 3 to
// fire; asserting it would hang the CPU forever. prot_irqn stays hard-tied
// to 1 (never asserted) rather than wiring a 053990 IRQ output -- confirmed
// closed, not merely deferred.
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

// D9 (main.md sec.6/GAP-5, KNOWN for rmrd_cs / HYPOTHESIS for vram_cs):
// ~DTACK = o23(PAL) & DTACK(054338) & N$27 & N$23. o23 is combinational
// and gives zero-wait DTACK straight off /AS for everything EXCEPT
// 0x1A0000-0x1BFFFF -- that includes rom_cs and ram_cs, so the old
// `wait2 = slow_mem` on them was a JTFRAME SDRAM-latency guess, not a
// board fact; real SDRAM latency is already covered by the *_ok terms in
// bus_busy above, so wait2 is removed entirely (tied 0).
//   - rmrd_cs (0x1B0000 tile-ROM read-back, KNOWN wiring / INFERRED exact
//     count): N$23 = NOT M7.Q2, a 74LS174 4-stage shift chain (D5-Q5-D4-Q4-
//     D3-Q3-D2-Q2) clocked at 16 MHz (M16B) and reset by ~AS -- 4 x 16 MHz
//     wait cycles. jtframe_68kdtack_cen's own header comment documents
//     wait3=1 as "3 wait states" (vs. the default mandatory 1), the closest
//     built-in match to a fixed multi-cycle chain, so wait3 is wired to
//     rmrd_cs here rather than adding a bespoke counter. Whether this
//     module's wait3 path reproduces exactly 4 (vs. 3) 16 MHz cycles
//     depends on fx68k's AS/DS timing relative to this counter's ASn_l
//     load edge, which needs a cycle trace to confirm, not hand tracing --
//     left INFERRED pending a differential run once simulation is
//     available again (see log). rmrd_cs also keeps its existing SDRAM-
//     latency stall via vdtac in bus_busy above (lyrf_ok, the tile-ROM
//     burst-ready signal) -- that term models real SDRAM access time,
//     which the board's fixed
//     4-stage chain does not have to wait for (Furrtek ROM read-back is a
//     latched byte, not a burst), so this RTL is stricter than the board
//     on this path but not known to violate it (both delay assertion by
//     at least 4 cycles, this one may delay it longer while SDRAM answers).
//   - vram_cs/scr_cs (0x1A0000 054157/056832 VRAM, HYPOTHESIS): N$27 is a
//     3-stage 74LS74 chain (J6.2->K7.1->J6.1) clocked by `~M6`/`M3`/`~M6`.
//     Neither ~M6 nor M3 has a captured driver anywhere in this project
//     (main.md Q-2, scroll.md sec.4 item 5, crtc_io_snd_latch.md sec.5
//     item 4 all independently confirm this -- the 053252 CLK1/CLK2
//     outputs that are the leading candidate have no captured consumer
//     either). Without a measured or documented ~M6/M3 period there is no
//     evidence-backed cycle count to encode, so vram_cs/scr_cs is left
//     running the framework's normal one-wait-state DTACK cycle (no wait2/
//     wait3, no counter) rather than inventing one. Do not "fix" this
//     without a board logic-analyser trace or the paper schematic.
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
    .wait2      ( 1'b0      ),  // o23 is zero-wait for rom_cs/ram_cs (D9); real
                                 // SDRAM latency is covered by rom_ok/ram_ok
                                 // in bus_busy instead of a guessed wait2.
    .wait3      ( rmrd_cs   ),  // 0x1B0000 tile-ROM read-back 4-stage/16MHz
                                 // chain (D9, main.md sec.6, KNOWN).
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
