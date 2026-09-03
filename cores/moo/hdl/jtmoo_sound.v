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
    // PCM ROM
    output  [20:0]  pcm_addr,
    input   [ 7:0]  pcm_data,
    output          pcm_cs,
    // Sound output
    output     signed [15:0] k539_l, k539_r,
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
wire signed [15:0] fm_l, fm_r;
wire [ 2:0] nc;

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
    // stream, not the internal full-resolution accumulator. C10.
    .sample     (           ),
    .left       ( fm_l      ),
    .right      ( fm_r      ),
    // Full resolution output (unused: not what the real board wires here)
    .xleft      (           ),
    .xright     (           )
);

/* verilator tracing_on */
jt539 #(.VOLSHIFT(1)) u_k54539(
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
    // YM2151 serial output mixed in by the K054539 (AUX1 on the schematics)
    .aux_l      ( fm_l      ),
    .aux_r      ( fm_r      ),
    // Sound output
    .left       ( k539_l    ),
    .right      ( k539_r    ),
    // debug
    .debug_bus  ( debug_bus ),
    .st_dout    ( st_dout   )
);

jt054321 u_54321(
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
    .int_n      ( int_n     )
);
`else
initial rom_cs   = 0;
assign  rom_addr = 0;
assign  pcm_addr = 0;
assign  pcm_cs   = 0;
assign  st_dout  = 0;
assign  { pair_dout, k539_l, k539_r } = 0;
`endif
endmodule
