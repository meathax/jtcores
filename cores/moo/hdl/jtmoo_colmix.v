/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Author: Rafael Eduardo Paiva Feener. Copyright: Jose Tejada Gomez
 * Version: 1.0
 * Date: 17-6-2026 */

// Colour section of the Moo Mesa board
//   M9  K053251 priority mixer
//   J3  K054338 colour combiner, owns the palette RAM and the CPU window
//   G4/H4/J4  three HM6116 (2k x 8) holding R, G and B - the palette is
//             xRGB_888, matching MAME's palette_device::xRGB_888, 2048
//
// The board latches the K053251 outputs (COL0..10, NCOL, BRIT, SDO0/1) in
// L5/K5 (74LS273) before they reach the K054338. G8/G9/H8/H9 (74LS157) can
// replace them with the K054157's fourth pipeline, whose I1 inputs are tied
// so that COL8..10 read as 1 and every mix/shadow qualifier reads as 0. That
// is the 0x700 palette base MAME hardcodes as m_layer_colorbase[0] = 0x70 for
// the always-on-top plane 0.

module jtmoo_colmix(
    input             rst,
    input             clk,
    input             pxl_cen,

    // Base Video
    input             lhbl,
    input             lvbl,

    // CPU interface
    input             pcu_cs,   // K053251
    input             reg_cs,   // K054338 registers
    input             pal_cs,   // palette RAM
    input             cpu_we,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,
    input      [12:1] cpu_addr,
    output     [15:0] cpu_din,

    // Final pixels
    input      [11:0] lyrf_pxl, // plane 0, bypasses the K053251
    input      [11:0] lyra_pxl, // plane 1 -> CI2
    input      [11:0] lyrb_pxl, // plane 2 -> CI3
    input      [11:0] lyrc_pxl, // plane 3 -> CI4
    input      [ 8:0] lyro_pxl,
    input      [ 4:0] lyro_pri,
    input             blnk_sel,

    input      [ 1:0] shadow,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    // Debug
    input      [11:0] ioctl_addr,
    input             ioctl_ram,
    output reg [ 7:0] ioctl_din,
    output     [ 7:0] dump_mmr,

    input      [ 7:0] debug_bus
);

wire [15:0] k338_dout;
reg  [23:0] bgr;
reg  [ 7:0] r8, g8, b8;
wire [10:0] col;
wire        pcu_we, reg_we, col_n, k338_video_en;
wire signed [9:0] shad_r, shad_g, shad_b;
wire [23:0] k338_bg;
// K053251 inputs
wire [ 5:0] pri0;
wire [ 8:0] ci0, ci1, ci2;
wire [ 7:0] ci3, ci4;
wire [ 1:0] shd_out, shd_in;
wire        brit;
// palette RAM
wire [10:0] pal_addr, cpu_pal_addr;
wire [ 7:0] pal_r, pal_g, pal_b, cpu_r, cpu_g, cpu_b;
wire        wr_r, wr_g, wr_b, pal_word;
// plane 0 bypass
wire        p0_opaque;
wire [10:0] mcol;
wire        mcol_blank;
wire [ 1:0] mcol_shd;
reg  [ 1:0] shd_l;
reg         blank_l;

// The K054338 sees the palette as xRGB_888, big endian: the even word holds
// the red byte in D[7:0], the odd word holds green in D[15:8] and blue in
// D[7:0]
assign pal_word     = cpu_addr[1];
assign cpu_pal_addr = cpu_addr[12:2];
assign wr_r         = pal_cs & cpu_we & ~pal_word & ~cpu_dsn[0];
assign wr_g         = pal_cs & cpu_we &  pal_word & ~cpu_dsn[1];
assign wr_b         = pal_cs & cpu_we &  pal_word & ~cpu_dsn[0];
assign pcu_we       = pcu_cs & ~cpu_dsn[0] & cpu_we;
assign reg_we       = reg_cs & cpu_we & (cpu_dsn!=2'b11);
assign cpu_din      = reg_cs   ? k338_dout :
                      pal_word ? { cpu_g, cpu_b } : { 8'd0, cpu_r };
assign {blue,green,red} = (lvbl & lhbl) ? bgr : 24'd0;

// K053251 wiring. CI1 is grounded on this board
assign pri0      = { lyro_pri, 1'b1 };
assign ci0       = lyro_pxl;
assign ci1       = 9'd0;
// CI2 is nine bits wide. With four palette bits per layer FPAL4 is always
// low, so the N6/H6 gate that would blank FCOLR under blnk_sel never fires
assign ci2       = { 1'b0, lyra_pxl[7:4], lyra_pxl[3:0] };
assign ci3       = { 1'b0, lyrb_pxl[6:4], lyrb_pxl[3:0] }; // only CI30..CI36 wired
assign ci4       = { lyrc_pxl[7:4], lyrc_pxl[3:0] };
assign shd_in    = shadow;

// Plane 0 wins over everything when it is opaque and brings its own
// palette bank, with no shadow, blank or blend qualifier
assign p0_opaque  = |lyrf_pxl[3:0];
assign mcol       = p0_opaque ? { 3'b111, lyrf_pxl[7:0] } : col;
assign mcol_blank = p0_opaque ? 1'b0 : col_n;
assign mcol_shd   = p0_opaque ? 2'b0 : shd_out;
assign pal_addr   = mcol;

function [7:0] add_clip(input [7:0] cin, input signed [9:0] delta);
    reg signed [10:0] sum;
begin
    sum = {3'd0,cin} + delta;
    add_clip = sum < 0        ? 8'd0  :
               sum > 11'sd255 ? 8'hff : sum[7:0];
end
endfunction

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bgr     <= 0;
        shd_l   <= 0;
        blank_l <= 0;
        {r8,g8,b8} <= 0;
    end else begin
        { r8, g8, b8 } <= { pal_r, pal_g, pal_b };
        if( pxl_cen ) begin
            shd_l   <= mcol_shd;
            blank_l <= mcol_blank;
            bgr     <= !k338_video_en ? 24'd0 :
                       blank_l        ? k338_bg :
                       ~|shd_l        ? { b8, g8, r8 } :
                                        { add_clip(b8,shad_b), add_clip(g8,shad_g), add_clip(r8,shad_r) };
        end
    end
end

// Palette dump: four bytes per entry, x/R/G/B, covering the low 1024 entries
always @(posedge clk) begin
    case( ioctl_addr[1:0] )
        2'd0: ioctl_din <= 8'd0;
        2'd1: ioctl_din <= pal_r;
        2'd2: ioctl_din <= pal_g;
        default: ioctl_din <= pal_b;
    endcase
end

jt054338 u_k338(
    .rst         ( rst             ),
    .clk         ( clk             ),

    .cs          ( reg_cs          ),
    .we          ( reg_we          ),
    .addr        ( cpu_addr[4:1]   ),
    .din         ( cpu_dout        ),
    .dsn         ( cpu_dsn         ),
    .dout        ( k338_dout       ),

    // MIX0 on the board is COL8 & ~COL9 & ~COL10 out of the K053251
    .pblend      ( { 1'b0, mcol[8] & ~mcol[9] & ~mcol[10] } ),
    .shadow      ( shd_l           ),

    .bg_rgb      ( k338_bg         ),
    .alpha_level (                 ),
    .alpha_add   (                 ),
    .video_en    ( k338_video_en   ),
    .mixpri      (                 ),
    .shdpri      (                 ),
    .brtpri      (                 ),
    .clipsl      (                 ),
    .dump_mmr    (                 ),

    .shadow_r    ( shad_r          ),
    .shadow_g    ( shad_g          ),
    .shadow_b    ( shad_b          )
);

jtcolmix_053251 u_k251(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    // CPU interface
    .cs         ( pcu_we    ),
    .addr       (cpu_addr[4:1]),
    .din        (cpu_dout[5:0]),
    // explicit priorities
    .sel        ( 1'b0      ),
    .pri0       ( pri0      ),
    .pri1       ( 6'h0      ),
    .pri2       ( 6'h0      ),
    // color inputs
    .ci0        ( ci0       ),
    .ci1        ( ci1       ),
    .ci2        ( ci2       ),
    .ci3        ( ci3       ),
    .ci4        ( ci4       ),
    // shadow
    .shd_in     ( shd_in    ),
    .shd_out    ( shd_out   ),
    // dump to SD card
    .ioctl_addr ( ioctl_ram ? ioctl_addr[3:0] : debug_bus[3:0] ),
    .ioctl_din  ( dump_mmr  ),

    .cout       ( col       ),
    .brit       ( brit      ),
    .col_n      ( col_n     )
);

// G4: green plane
jtframe_dual_ram #(.AW(11),.SIMFILE("pal_g.bin")) u_pal_g(
    .clk0   ( clk           ),
    .data0  ( cpu_dout[15:8]),
    .addr0  ( cpu_pal_addr  ),
    .we0    ( wr_g          ),
    .q0     ( cpu_g         ),
    .clk1   ( clk           ),
    .data1  ( 8'd0          ),
    .addr1  ( ioctl_ram ? {1'b0,ioctl_addr[11:2]} : pal_addr ),
    .we1    ( 1'b0          ),
    .q1     ( pal_g         )
);

// H4: red plane
jtframe_dual_ram #(.AW(11),.SIMFILE("pal_r.bin")) u_pal_r(
    .clk0   ( clk           ),
    .data0  ( cpu_dout[7:0] ),
    .addr0  ( cpu_pal_addr  ),
    .we0    ( wr_r          ),
    .q0     ( cpu_r         ),
    .clk1   ( clk           ),
    .data1  ( 8'd0          ),
    .addr1  ( ioctl_ram ? {1'b0,ioctl_addr[11:2]} : pal_addr ),
    .we1    ( 1'b0          ),
    .q1     ( pal_r         )
);

// J4: blue plane
jtframe_dual_ram #(.AW(11),.SIMFILE("pal_b.bin")) u_pal_b(
    .clk0   ( clk           ),
    .data0  ( cpu_dout[7:0] ),
    .addr0  ( cpu_pal_addr  ),
    .we0    ( wr_b          ),
    .q0     ( cpu_b         ),
    .clk1   ( clk           ),
    .data1  ( 8'd0          ),
    .addr1  ( ioctl_ram ? {1'b0,ioctl_addr[11:2]} : pal_addr ),
    .we1    ( 1'b0          ),
    .q1     ( pal_b         )
);

`ifdef SIMULATION
wire unused_colmix = &{ 1'b0, brit, blnk_sel, lyrb_pxl[7], lyrf_pxl[11:8],
                        lyra_pxl[11:8], lyrb_pxl[11:8], lyrc_pxl[11:8] };
`endif

endmodule
