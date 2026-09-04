/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 2-9-2026 */

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
    output  [21:0]  pcm_addr,
    input   [ 7:0]  pcm_data,
    output          pcm_cs,
    input           pcm_ok,
    // Sound output
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
            cpu_cen, fm_intn, latch_we, int_n, snd_pal8_n, bank_we_fall;
reg         ram_cs, fm_cs, k39_cs, k21_cs, bank_we, mem_acc, nmi_clr, bank_we_l;
wire signed [15:0] pcm_l, pcm_r, fm_pre_l, fm_pre_r;
wire [ 1:0] nc;

// 054744 SND~PAL8
assign snd_pal8_n = ~( ( A[15] &  A[14] & A[13] & ~A[12] & A[11] & A[10] ) |
                       ( ~m1_n & ~A[15] & A[14] )                          |
                       ( ~m1_n & ~A[14] ) );
assign latch_we = k21_cs && !wr_n;
assign rom_hi   = A[15] ? bank : {3'd0, A[14]};
assign rom_addr = {rom_hi, A[13:0]};
assign cpu_din  = rom_cs ? rom_data   :
                  ram_cs ? ram_dout   :
                  k39_cs ? k39_dout   :
                  k21_cs ? latch_dout :
                  fm_cs  ? fm_dout    : 8'hff;
assign bank_we_fall = bank_we_l & ~bank_we;

// 054744 PAL: no A10 term, so each window is 2 kB
always @(*) begin
    mem_acc = !mreq_n && rfsh_n;
    rom_cs  = mem_acc && !(A[15] && A[14]) && !rd_n; // /SROM     0000-BFFF
    ram_cs  = mem_acc && A[15:13]==3'b110;           // /SRAM     C000-DFFF
    k39_cs  = mem_acc && A[15:11]==5'b1110_0;        // /PCM      E000-E7FF
    fm_cs   = mem_acc && A[15:11]==5'b1110_1;        // /FM       E800-EFFF
    k21_cs  = mem_acc && A[15:11]==5'b1111_0;        // /SLATCHES F000-F7FF
    bank_we = mem_acc && A[15:10]==6'b1111_10;       // /SBANK_WR F800-FBFF
end

// bank latch clocks on any F800-FBFF access, not gated by write
always @(posedge clk) if(cpu_cen) bank_we_l <= bank_we;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bank    <= 0;
        nmi_clr <= 1;
    end else if( bank_we_fall ) begin
        bank    <= cpu_dout[3:0];
        nmi_clr <= ~cpu_dout[4];
    end
end

// NMI latches on the YM2151 IRQ assertion edge
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
    .sample     (           ),
    .left       ( fm_pre_l  ),
    .right      ( fm_pre_r  ),
    // Full resolution output
    .xleft      (           ),
    .xright     (           )
);

/* verilator tracing_on */
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
    // Sound output
    .left       ( pcm_l     ),
    .right      ( pcm_r     ),
    // debug
    .debug_bus  ( debug_bus ),
    .st_dout    ( st_dout   )
);

// one volume register applies to both PCM and FM
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
    .pal8_n     ( snd_pal8_n),
    // PCM volume
    .snd_l      ( pcm_l     ),
    .snd_r      ( pcm_r     ),
    .out_l      ( k539_l    ),
    .out_r      ( k539_r    ),
    // FM volume
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
