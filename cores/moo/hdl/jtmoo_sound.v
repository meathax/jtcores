/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Version: 1.0
 * Date: 2-9-2026 */

// Moo Mesa / Bucky O'Hare sound board (PWB353126)
//   C14  Z80          8 MHz (32MHz/4)
//   D13  YM2151       4 MHz (32MHz/8), its serial output feeds the K054539 SO pin
//   E4   K054539      18.432 MHz
//   U2   K054321      main/sound communication
//   E7   054744       PAL16L8 address decoder
//   F5   27C020       256 kB program ROM, banked by C7 (74LS157) from D7 (74LS174)
//   D5   MB8464       8 kB work RAM
// The Z80 NMI flip flop (G6B, 74LS74) is clocked by the inverted YM2151 IRQ
// and released by bit 4 of the bank latch.

module jtmoo_sound(
    input           rst,
    input           clk,
    input           cen_8,
    input           cen_4,
    input           cen_2,
    input           cen_pcm,

    input           pair_we,
    // communication with main CPU
    input   [ 7:0]  main_dout,
    output  [ 7:0]  pair_dout,
    input   [ 4:1]  main_addr,

    input           snd_irq,
    // ROM
    output  [17:0]  rom_addr,
    output  reg     rom_cs,
    input   [ 7:0]  rom_data,
    input           rom_ok,
    // PCM ROM. 22 bits: Moo Mesa only populates B6 (2 MB) but Bucky O'Hare also
    // populates A6, selected by the K054539's ROBS output -> 4 MB total. C8.
    output  [21:0]  pcm_addr,
    input   [ 7:0]  pcm_data,
    output          pcm_cs,
    input           pcm_ok,     // C5 (port): the K054539 must not read a sample byte
                                 // before the SDRAM data is valid -- see jt054539.v.
                                 // jtmoo_game_sdram.v already generates this signal
                                 // from cfg/mem.yaml's `pcm` bus; it just wasn't
                                 // threaded through this module until now.
    // Sound output. k539_l/r: K054321-attenuated K054539 PCM (unchanged name/
    // wiring). fm_l/r: YM2151 FM, STILL its own mixer channel (C5 FM-routing
    // decision: the real board sums FM into the K054539's AUX input before
    // that chip's own L/R pins, but the ported jt054539 has no AUX input --
    // see the jt054539 instantiation below) but now ALSO attenuated by the
    // same K054321 volume register as k539_l/r (C6b): fm_l/r no longer
    // bypass the CPU's volume fade. gain*(a+b) == gain*a + gain*b, so
    // independently scaling fm and pcm here and summing them later at the
    // jtframe mixer is numerically equivalent to the board's sum-then-
    // attenuate order inside the chip -- see jt054321.v and the u_54321
    // instantiation below for the mechanism.
    output     signed [15:0] k539_l, k539_r,
    output     signed [15:0] fm_l, fm_r,
    // Debug
    input    [ 7:0] debug_bus,
    output   [ 7:0] st_dout
);

`ifndef NOSOUND
wire [ 7:0] cpu_dout, cpu_din, ram_dout, fm_dout, k39_dout, latch_dout;
wire [ 3:0] rom_hi;
reg  [ 3:0] bank;
wire [15:0] A;
wire        m1_n, mreq_n, rd_n, wr_n, iorq_n, rfsh_n, nmi_n,
            cpu_cen, fm_intn, latch_we, int_n;
reg         ram_cs, fm_cs, k39_cs, k21_cs, bank_we, mem_acc, nmi_clr;
// K054539 output before the K054321's global volume stage
wire signed [15:0] pcm_l, pcm_r;
// YM2151 output before the K054321's global volume stage (C6b). Previously
// fm_l/fm_r (the module's own output ports) were wired directly here,
// bypassing the K054321 entirely; now they are the u_54321 AUDIO=1 second
// pair's OUTPUT (out2_l/out2_r), and this pre-attenuation pair feeds its
// second INPUT (snd2_l/snd2_r) instead.
wire signed [15:0] fm_pre_l, fm_pre_r;
wire [ 1:0] nc;         // C8: pcm_addr is now 22 bits, rom_addr is 24. Harmless
                        // padding: jt054539's internal rom_addr accumulator
                        // never needs bits [23:22] for a real 2MB (Moo Mesa)
                        // or 4MB (Bucky, hypothetically) sample set, and only
                        // pcm_addr[21:0] reaches the physical SDRAM bus.
                        // C5 (port): the ported module has NO ROBS-equivalent
                        // second-ROM-bank select at all -- Bucky O'Hare's
                        // second sample ROM (A6, selected by the real
                        // K054539's ROBS pin) is NOT supported by this port.
                        // Moo Mesa itself only ever populates 2MB (B6) and is
                        // unaffected. Left undriven rather than inventing
                        // bank-select logic with no evidence for its timing.

// 054744 (PAL16L8) pin 12, SND~PAL8 -> J2 a39/b39 -> U2.24 on the 054986A
// daughterboard. Transcribed from the fusemap in doc/054744:
//   SND/PAL8 = !( A15 & A14 & A13 & !A12 & A11 & A10     ; EC00-EFFF (YM2151)
//               + /M1 & !A15 & A14                       ; 4000-7FFF
//               + /M1 & !A14 )                           ; 0000-3FFF, 8000-BFFF
// Documented only: what the K054321 does with this pin is unknown, and neither
// MAME's k054321 nor Furrtek's die trace models it. Class HYPOTHESIS, C7.
// Caveat: doc/054744 lists pin 1 as "/M1 (Z80 ~M1)" but annotates these terms
// "M1 fetch", which are opposite readings of the same literal. The M1-active
// reading is used here; it is not relied upon, since nothing consumes the pin.
wire snd_pal8_n = ~( ( A[15] &  A[14] & A[13] & ~A[12] & A[11] & A[10] ) |
                     ( ~m1_n & ~A[15] & A[14] )                          |
                     ( ~m1_n & ~A[14] ) );

assign latch_we = k21_cs && !wr_n;
// C7 (74LS157): A[15]=0 selects {GND,GND,GND,A14}, A[15]=1 selects the bank latch
assign rom_hi   = A[15] ? bank : {3'd0, A[14]};
assign rom_addr = {rom_hi, A[13:0]};
assign cpu_din  = rom_cs ? rom_data   :
                  ram_cs ? ram_dout   :
                  k39_cs ? k39_dout   :
                  k21_cs ? latch_dout :
                  fm_cs  ? fm_dout    : 8'hff;
// board has no Z80 wait states (C14 ~WAIT tied VCC); jtframe_sysz80 already
// handles rom_ok stalling internally

// 054744 (PAL16L8) at E7, decoded from its fusemap (see doc/054744):
// A10 is absent from the /PCM, /FM and /SLATCHES terms, so each window is 2 kB
always @(*) begin
    mem_acc = !mreq_n && rfsh_n;
    rom_cs  = mem_acc && !(A[15] && A[14]) && !rd_n; // /SROM     0000-BFFF
    ram_cs  = mem_acc && A[15:13]==3'b110;           // /SRAM     C000-DFFF
    k39_cs  = mem_acc && A[15:11]==5'b1110_0;        // /PCM      E000-E7FF
    fm_cs   = mem_acc && A[15:11]==5'b1110_1;        // /FM       E800-EFFF
    k21_cs  = mem_acc && A[15:11]==5'b1111_0;        // /SLATCHES F000-F7FF
    bank_we = mem_acc && A[15:10]==6'b1111_10;       // /SBANK_WR F800-FBFF
end

// D7 (74LS174): clocks on any F800-FBFF access, not gated by write.
reg bank_we_l;
always @(posedge clk) if(cpu_cen) bank_we_l <= bank_we;
wire bank_we_fall = bank_we_l & ~bank_we;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bank    <= 0;
        nmi_clr <= 1; // D7 Q4 cleared on reset -> NMI held masked
    end else if( bank_we_fall ) begin
        bank    <= cpu_dout[3:0];
        nmi_clr <= ~cpu_dout[4]; // Q4 -> 74LS74 active-low async SET
    end
end

// G6B (74LS74) latches on the YM2151 IRQ's assertion edge (G6.5 inverter
// on the schematic). MAME does not model this path.
jtframe_edge #(.QSET(0)) u_edge (
    .rst    ( rst       ),
    .clk    ( clk       ),
    .edgeof ( ~fm_intn  ),
    .clr    ( nmi_clr   ),
    .q      ( nmi_n     )
);

/* verilator tracing_off */
jtframe_sysz80 #(`ifdef SND_RAMW .RAM_AW(`SND_RAMW), `endif .CLR_INT(1)) u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen_8     ),
    .cpu_cen    ( cpu_cen   ),
    .int_n      ( int_n     ),
    .nmi_n      ( nmi_n     ),
    .busrq_n    ( 1'b1      ),
    .m1_n       ( m1_n      ),
    .mreq_n     ( mreq_n    ),
    .iorq_n     ( iorq_n    ),
    .rd_n       ( rd_n      ),
    .wr_n       ( wr_n      ),
    .rfsh_n     ( rfsh_n    ),
    .halt_n     (           ),
    .busak_n    (           ),
    .A          ( A         ),
    .cpu_din    ( cpu_din   ),
    .cpu_dout   ( cpu_dout  ),
    .ram_dout   ( ram_dout  ),
    // ROM access
    .ram_cs     ( ram_cs    ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    )
);

/* verilator tracing_off */
jt51 u_jt51(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_4     ),
    .cen_p1     ( cen_2     ),
    .cs_n       ( !fm_cs    ),
    .wr_n       ( wr_n      ),
    .a0         ( A[0]      ),
    .din        ( cpu_dout  ),
    .dout       ( fm_dout   ),
    .ct1        (           ),
    .ct2        (           ),
    .irq_n      ( fm_intn   ),
    // The board feeds the K054539's AUX1 input from the YM2151's serial DAC
    // output (SO, pin 21 -> AXDA), which is the quantised low-resolution
    // stream, not the internal full-resolution accumulator. C10. C5 (port):
    // jt054539.v has no AUX input (see the FM-routing note below), so this
    // low-resolution `left`/`right` output now feeds its own mixer channel
    // via u_54321's second pair (C6b: `fm_pre_l`/`fm_pre_r` -> attenuated ->
    // `fm_l`/`fm_r`, module output) instead of the K054539's AUX pin -- still
    // the low-resolution pair called for by C10, just summed a stage later
    // and now sharing the same CPU volume register as PCM.
    .sample     (           ),
    .left       ( fm_pre_l  ),
    .right      ( fm_pre_r  ),
    // Full resolution output (unused: not what the real board wires here)
    .xleft      (           ),
    .xright     (           )
);

/* verilator tracing_on */
// C5 (port): jt054539.v is a from-scratch, real-hardware-validated K054539
// implementation adapted from github.com/jlrh/konami-fpga (GPL-3.0, same
// game/board family) -- see modules/jt054539/hdl/jt054539.v for full
// provenance and D:\evidence\moo\log_pcmport.md for the import record.
// It replaces the modules/jt539 stub (that submodule's upstream, Jotego's
// private jt539, was never reachable -- see log_pcm.md "C5"; Furrtek's raw
// SiliconRE netlist was independently judged unportable in one session,
// same log).
//
// FM-routing deviation from the schematic (documented, not silent): the
// real board feeds the YM2151's serial output into the K054539's AUX1 pin,
// which mixes FM+PCM inside the chip before its own L/R pins (tier-1
// schematic evidence, sound.kicad_sch chip E4). The ported module has no
// AUX input at all -- its upstream author removed it after finding that
// summing FM+PCM inside the chip's Q16 accumulator railed the final clip16
// during their own hardware bring-up. This project follows their
// hardware-validated choice (FM and PCM as separate jtframe rcmix channels,
// summed at wide precision downstream instead of inside the chip) rather
// than re-adding an aux-mixing path this project has not itself validated.
// Evidence class: KNOWN (schematic wiring) vs INFERRED (that the separate-
// channel approach is audibly equivalent) -- a real accuracy/practicality
// tradeoff, not an oversight.
//
// C6b (this change): the chip-summing deviation above is about WHERE FM and
// PCM are added together (inside the K054539 vs downstream at the jtframe
// mixer) -- it says nothing about volume. Before this change, fm_l/fm_r
// were wired straight from u_jt51 to this module's output ports, so the
// K054321's global volume register (u_54321 below) never touched FM at
// all: the CPU's volume fade (moo.cpp frames 959-1022) would fade PCM to
// silence while FM stayed at full volume, which does not match ANY
// plausible reading of the schematic (every reading has FM reach the
// K054321 one way or another, either inside the K054539's sum or, on this
// port, downstream of it). Fixed by routing fm_pre_l/fm_pre_r through
// u_54321's new second pair (snd2_l/snd2_r -> out2_l/out2_r, jt054321.v)
// so the SAME `gain` register scales both FM and PCM, while still keeping
// fm_l/fm_r as this module's own separate output channel (no re-summing
// inside a shared accumulator, so the upstream author's clip16 rail
// problem does not return). Class INFERRED (same tier as the FM-routing
// decision above: the attenuation-law equivalence is a arithmetic argument,
// not an independent hardware measurement of this board).
jt054539 #(.VOLSHIFT(1)) u_k054539(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_pcm   ),
    .timeout    (           ),
    // CPU interface
    .addr       ({A[9],A[7:0]}),
    .we         ( ~wr_n     ),
    .rd         ( ~rd_n     ),
    .cs         ( k39_cs    ),
    .din        ( cpu_dout  ),
    .dout       ( k39_dout  ),
    // ROM
    .rom_cs     ( pcm_cs    ),
    .rom_addr   ({nc,pcm_addr}),
    .rom_data   ( pcm_data  ),
    .rom_ok     ( pcm_ok    ),
    // Sound output, before the K054321 volume stage
    .left       ( pcm_l     ),
    .right      ( pcm_r     ),
    // debug
    .debug_bus  ( debug_bus ),
    .st_dout    ( st_dout   )
);

// The K054321 sits in series with the only audio path on the board:
// E4 FRDT/WDCK/LRCK -> U2.1/2/3, U2.9/10/11 -> U1 AD1868 -> 1B1 LA4705.
// AUDIO(1) makes its global volume register act on the K054539 pair. C6.
// C6b: the SAME register also now attenuates FM through the second pair
// (snd2_l/snd2_r -> out2_l/out2_r), since the CPU volume fade must reach
// both on real hardware (see the jt054539 instantiation comment above).
jt054321 #(.AUDIO(1)) u_54321(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .maddr      ( main_addr ),
    .mdout      ( main_dout ),
    .mdin       ( pair_dout ),
    .mwe        ( pair_we   ),

    .saddr      ( A[1:0]    ),
    .sdout      ( cpu_dout  ),
    .sdin       ( latch_dout),
    .swe        ( latch_we  ),

    // Z80 bus control
    .snd_on     ( snd_irq   ),
    .siorq_n    ( iorq_n    ),
    .int_n      ( int_n     ),

    // C7: accepted, unused inside the module
    .pal8_n     ( snd_pal8_n),
    // C6: global volume applied to the K054539 pair
    .snd_l      ( pcm_l     ),
    .snd_r      ( pcm_r     ),
    .out_l      ( k539_l    ),
    .out_r      ( k539_r    ),
    // C6b: same global volume applied to FM, kept as a separate output pair
    .snd2_l     ( fm_pre_l  ),
    .snd2_r     ( fm_pre_r  ),
    .out2_l     ( fm_l      ),
    .out2_r     ( fm_r      )
);
`else
initial rom_cs   = 0;
assign  rom_addr = 0;
assign  pcm_addr = 0;
assign  pcm_cs   = 0;
assign  st_dout  = 0;
assign  { pair_dout, k539_l, k539_r, fm_l, fm_r } = 0;
`endif
endmodule
