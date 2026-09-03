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
wire        pcu_we, reg_we, col_n, k338_video_en, clipsl;
wire signed [9:0] shad_r, shad_g, shad_b;
wire [23:0] k338_bg;
wire [ 7:0] alpha_level;
wire        alpha_add, pblend0;
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
// plane 0 (layer F) bypass + its own blend-only palette lookup. The real
// 054338 (J3) owns RAB0-12 to G4/H4/J4 and reads the palette bank twice per
// pixel (SiliconRE: "alternating pixel color codes for the two layers");
// here that is modelled as a second, independent 256-entry mirror of the
// fixed 0x700-0x7FF plane-0 bank instead of doubling the shared port's
// read rate, so the existing mcol/pal_addr timing is untouched.
wire        p0_opaque;
wire        mcol_blank;
wire [ 1:0] mcol_shd;
reg  [ 1:0] shd_l;
reg         blank_l;
reg         fixop_a, blend_a;
wire        f_wr_r, f_wr_g, f_wr_b;
wire [ 7:0] f_pal_r, f_pal_g, f_pal_b;
reg  [ 7:0] fr8, fg8, fb8;

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
// CI2 bit 8 is FPAL4 on the schematic: the K054157's DFI8 output (the tile
// attribute's colpre[0] bit MAME's tile_callback discards), routed straight
// through to the K053251's CI28 pin. On the board this is the per-tile
// blend-enable flag for layer a -- see jt05415x.v tcolor[0]/a_pal[4].
assign ci2       = { lyra_pxl[8], lyra_pxl[7:4], lyra_pxl[3:0] };
assign ci3       = { 1'b0, lyrb_pxl[6:4], lyrb_pxl[3:0] }; // only CI30..CI36 wired
assign ci4       = { lyrc_pxl[7:4], lyrc_pxl[3:0] };
assign shd_in    = shadow;

// MIX0 on the board is COL8 & ~COL9 & ~COL10 sampled on the K053251's own
// output slot (H8/H9 mux I0 = M9), never on plane 0's slot -- see EVIDENCE.md.
assign pblend0    = col[8] & ~col[9] & ~col[10];
// Plane 0 (layer F) is the board's other alternating slot (H8/H9 mux I1 =
// L7, the K054157 CO bus): when opaque and pblend0 is clear it still wins
// outright with its own fixed palette bank, unchanged from before. When
// pblend0 is set the K054338 blends it with the K053251 winner instead of
// overriding it -- see the fr8/fg8/fb8 mirror lookup and the bgr mux below.
assign p0_opaque  = |lyrf_pxl[3:0];
assign mcol_blank = p0_opaque ? 1'b0 : col_n;
assign mcol_shd   = p0_opaque ? 2'b0 : shd_out;
assign pal_addr   = col;

// Plane 0's own 256-entry bank (0x700-0x7FF), mirrored from the CPU's
// writes to the main palette RAM so it can be read in parallel with the
// K053251 winner instead of stealing the shared video port.
assign f_wr_r = wr_r & (cpu_pal_addr[10:8]==3'b111);
assign f_wr_g = wr_g & (cpu_pal_addr[10:8]==3'b111);
assign f_wr_b = wr_b & (cpu_pal_addr[10:8]==3'b111);

function [7:0] add_clip(input [7:0] cin, input signed [9:0] delta, input noclip);
    reg signed [10:0] sum;
begin
    sum = {3'd0,cin} + delta;
    // CONTROL[5] (CLIPSL) disables the min/max clamp on real silicon
    // (Konami 054338, SiliconRE gate-level trace) -- the sum wraps instead
    // of saturating when set.
    add_clip = noclip          ? sum[7:0] :
               sum < 0         ? 8'd0  :
               sum > 11'sd255  ? 8'hff : sum[7:0];
end
endfunction

// K054338 mode 0 (interpolation, front*level + back*(256-level), top 8 of
// the sum) and mode 1 (additive, front + back*(32-mixlv)>>5) -- SiliconRE
// Konami/054338 README. mixlv (5b) is recovered from alpha_level (8b) as
// its top 5 bits: jt054338 expands mixlv to alpha_level={mixlv,mixlv[4:2]}.
// Only mode 0 is exercised by this ROM (see EVIDENCE.md register trace);
// mode 1 is implemented from the same evidence but unverified in practice.
function [7:0] mix_blend(input [7:0] front, input [7:0] back, input [7:0] level, input additive);
    reg [ 8:0] inv9;
    reg [ 5:0] inv5;
    reg [17:0] sum;
    reg [13:0] aprod;
    reg [ 8:0] asum;
begin
    inv9 = 9'd256 - {1'b0,level};
    if( additive ) begin
        inv5  = 6'd32 - {1'b0,level[7:3]};
        aprod = back * inv5;
        asum  = {1'b0,front} + aprod[13:5];
        mix_blend = asum[8] ? 8'hff : asum[7:0];
    end else begin
        // front,back<=255 and level+inv9==256 exactly, so this sum is
        // provably <=255*256=65280 and the >>8 below never needs a clamp.
        sum = front*level + back*inv9;
        mix_blend = sum[15:8];
    end
end
endfunction

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bgr     <= 0;
        shd_l   <= 0;
        blank_l <= 0;
        fixop_a <= 0;
        blend_a <= 0;
        {r8,g8,b8}    <= 0;
        {fr8,fg8,fb8} <= 0;
    end else begin
        { r8,  g8,  b8  } <= { pal_r,   pal_g,   pal_b   };
        { fr8, fg8, fb8 } <= { f_pal_r, f_pal_g, f_pal_b };
        if( pxl_cen ) begin
            shd_l   <= mcol_shd;
            blank_l <= mcol_blank;
            fixop_a <= p0_opaque;
            blend_a <= p0_opaque & pblend0;
            bgr     <= !k338_video_en   ? 24'd0 :
                       blank_l          ? k338_bg :
                       fixop_a & ~blend_a ? { fb8, fg8, fr8 } :
                       fixop_a &  blend_a ? { mix_blend(fb8,b8,alpha_level,alpha_add),
                                               mix_blend(fg8,g8,alpha_level,alpha_add),
                                               mix_blend(fr8,r8,alpha_level,alpha_add) } :
                       ~|shd_l          ? { b8, g8, r8 } :
                                          { add_clip(b8,shad_b,clipsl), add_clip(g8,shad_g,clipsl), add_clip(r8,shad_r,clipsl) };
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

    .pblend      ( { 1'b0, pblend0 } ),
    .shadow      ( shd_l           ),

    .bg_rgb      ( k338_bg         ),
    .alpha_level ( alpha_level     ),
    .alpha_add   ( alpha_add       ),
    .video_en    ( k338_video_en   ),
    // mixpri/shdpri/brtpri: on real silicon (Konami 054338, SiliconRE
    // gate-level trace) these select pipeline delay for the external
    // MIX/SHD/BRI pin busses, compensating for board wire skew between the
    // 053251 and this chip. A synchronous FPGA model has no such skew to
    // compensate for, so they are left open.
    .mixpri      (                 ),
    .shdpri      (                 ),
    .brtpri      (                 ),
    .clipsl      ( clipsl          ),
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

// Plane 0's own 256-entry mirror (0x700-0x7FF), read at lyrf_pxl[7:0] in
// parallel with the K053251 winner above -- see the f_wr_r/g/b comment and
// the bgr mux. No SIMFILE: it is populated by the same CPU writes as the
// main palette RAM well before any blend is exercised.
jtframe_dual_ram #(.AW(8)) u_fpal_g(
    .clk0   ( clk               ),
    .data0  ( cpu_dout[15:8]    ),
    .addr0  ( cpu_pal_addr[7:0] ),
    .we0    ( f_wr_g            ),
    .q0     (                   ),
    .clk1   ( clk               ),
    .data1  ( 8'd0              ),
    .addr1  ( lyrf_pxl[7:0]     ),
    .we1    ( 1'b0              ),
    .q1     ( f_pal_g           )
);

jtframe_dual_ram #(.AW(8)) u_fpal_r(
    .clk0   ( clk               ),
    .data0  ( cpu_dout[7:0]     ),
    .addr0  ( cpu_pal_addr[7:0] ),
    .we0    ( f_wr_r            ),
    .q0     (                   ),
    .clk1   ( clk               ),
    .data1  ( 8'd0              ),
    .addr1  ( lyrf_pxl[7:0]     ),
    .we1    ( 1'b0              ),
    .q1     ( f_pal_r           )
);

jtframe_dual_ram #(.AW(8)) u_fpal_b(
    .clk0   ( clk               ),
    .data0  ( cpu_dout[7:0]     ),
    .addr0  ( cpu_pal_addr[7:0] ),
    .we0    ( f_wr_b            ),
    .q0     (                   ),
    .clk1   ( clk               ),
    .data1  ( 8'd0              ),
    .addr1  ( lyrf_pxl[7:0]     ),
    .we1    ( 1'b0              ),
    .q1     ( f_pal_b           )
);

`ifdef SIMULATION
wire unused_colmix = &{ 1'b0, brit, blnk_sel, lyrb_pxl[7], lyrf_pxl[11:8],
                        lyra_pxl[11:9], lyrb_pxl[11:8], lyrc_pxl[11:8] };
`endif

endmodule
