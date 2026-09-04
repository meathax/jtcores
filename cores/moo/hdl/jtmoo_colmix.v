/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Author: Rafael Eduardo Paiva Feener. Copyright: Jose Tejada Gomez
 * Version: 1.0
 * Date: 17-6-2026 */

// K053251 priority mixer and K054338 colour combiner
// Plane 0 bypasses the K053251 and uses palette bank 0x700

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

    input      [ 1:0] shadow,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    // Debug
    input      [11:0] ioctl_addr,
    input             ioctl_ram,
    output reg [ 7:0] ioctl_din,
    output     [ 7:0] mmr_dump,

    input      [ 7:0] debug_bus
);

wire [23:0] k338_bg;
wire [15:0] k338_dout;
wire [10:0] col, pal_addr, cpu_pal_addr;
wire [ 8:0] ci0, ci1, ci2;
wire [ 7:0] ci3, ci4, alpha_level, bri1_lvl,
            pal_r, pal_g, pal_b, cpu_r, cpu_g, cpu_b,
            k338g_dump, k251g_dump;
wire [ 5:0] pri0;
wire [ 4:0] k338g_addr;
wire [ 3:0] k251g_addr;
wire [ 1:0] shd_out, mcol_shd;
wire        pcu_we, reg_we, col_n, k338_video_en, clipsl, alpha_add, pblend0,
            brit, wr_r, wr_g, wr_b, pal_word, p0_opaque, mcol_blank, mcol_bri,
            k338_dump_sel;
wire signed [9:0] shad_r, shad_g, shad_b;
reg  [23:0] bgr;
reg  [11:0] lyrf_l;
reg  [ 7:0] r8, g8, b8, fr8, fg8, fb8;
reg  [ 1:0] shd_l;
reg         blank_l, fixop_a, blend_a, bri_l, ph, ph_l;

// palette is xRGB_888, big endian: even word = R, odd word = {G,B}
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

// K053251 inputs. CI1 is grounded on this board
assign pri0      = { lyro_pri, 1'b1 };
assign ci0       = lyro_pxl;
assign ci1       = 9'd0;
assign ci2       = lyra_pxl[8:0];
assign ci3       = { 1'b0, lyrb_pxl[7:5], lyrb_pxl[3:0] }; // only CI30..CI36 wired
assign ci4       = lyrc_pxl[7:0];

// MIX0 = COL8 & ~COL9 & ~COL10, MIX1 tied low
assign pblend0    = col[8] & ~col[9] & ~col[10];
// opaque plane 0 wins unless MIX0 selects blending with the K053251 winner
assign p0_opaque  = |lyrf_l[3:0];
assign mcol_blank = p0_opaque ? 1'b0 : col_n;
assign mcol_shd   = p0_opaque ? 2'b0 : shd_out;
assign mcol_bri   = p0_opaque ? 1'b0 : brit;
// plane 0 reads the palette on the odd clock cycles, bank 0x700-0x7FF
assign pal_addr   = ioctl_ram ? {1'b0,ioctl_addr[11:2]} :
                    ph        ? {3'b111,lyrf_l[7:0]}    : col;

// K054338/K053251 register dump: ioctl_addr[4] (or debug_bus[7]) selects the chip
assign k338_dump_sel = ioctl_ram ? ioctl_addr[4]   : debug_bus[7];
assign k338g_addr    = ioctl_ram ? ioctl_addr[9:5] : debug_bus[4:0];
assign k251g_addr    = ioctl_ram ? ioctl_addr[3:0] : debug_bus[3:0];
assign mmr_dump      = k338_dump_sel ? k338g_dump : k251g_dump;

// CLIPSL disables the clamp, the sum wraps instead
function [7:0] add_clip(input [7:0] cin, input signed [9:0] delta, input noclip);
    reg signed [10:0] sum;
begin
    // $signed keeps the addition signed so a negative delta is sign-extended
    sum = $signed({3'd0,cin}) + delta;
    add_clip = noclip          ? sum[7:0] :
               sum < 0         ? 8'd0  :
               sum > 11'sd255  ? 8'hff : sum[7:0];
end
endfunction

// mode 0: (front*level + back*(256-level))>>8
// mode 1: front + (back*(32-mixlv))>>5, mixlv is the top 5 bits of level
function [7:0] mix_blend(input [7:0] front, input [7:0] back, input [7:0] level, input additive);
    reg [ 8:0] inv9, asum;
    reg [ 5:0] inv5;
    reg [17:0] sum;
    reg [13:0] aprod;
begin
    inv9  = 9'd256 - {1'b0,level};
    inv5  = 6'd32 - {1'b0,level[7:3]};
    sum   = front*level + back*inv9; // <= 65280, no clamp needed
    aprod = back * inv5;
    asum  = {1'b0,front} + aprod[13:5];
    mix_blend = !additive ? sum[15:8] : asum[8] ? 8'hff : asum[7:0];
end
endfunction

// BRI1 is tied, so only brightness code 1 is selected
function [23:0] apply_bright(input [23:0] rgb, input en, input [7:0] lvl);
    reg [15:0] pb, pg, pr;
begin
    pb = 16'd0;
    pg = 16'd0;
    pr = 16'd0;
    if( en ) begin
        pb = rgb[23:16] * lvl;
        pg = rgb[15: 8] * lvl;
        pr = rgb[ 7: 0] * lvl;
        apply_bright = { pb[15:8], pg[15:8], pr[15:8] };
    end else apply_bright = rgb;
end
endfunction

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bgr     <= 0;
        shd_l   <= 0;
        blank_l <= 0;
        fixop_a <= 0;
        blend_a <= 0;
        bri_l   <= 0;
        lyrf_l  <= 0;
        {r8,g8,b8}    <= 0;
        {fr8,fg8,fb8} <= 0;
        ph      <= 0;
        ph_l    <= 0;
    end else begin
        ph   <= ~ph & ~pxl_cen;
        ph_l <= ph;
        if( ph_l )
            { fr8, fg8, fb8 } <= { pal_r, pal_g, pal_b };
        else
            { r8,  g8,  b8  } <= { pal_r, pal_g, pal_b };
        if( pxl_cen ) begin
            lyrf_l  <= lyrf_pxl;
            shd_l   <= mcol_shd;
            blank_l <= mcol_blank;
            bri_l   <= mcol_bri;
            fixop_a <= p0_opaque;
            blend_a <= p0_opaque & pblend0;
            bgr     <= apply_bright( !k338_video_en   ? 24'd0 :
                       blank_l          ? k338_bg :
                       fixop_a & ~blend_a ? { fb8, fg8, fr8 } :
                       fixop_a &  blend_a ? { mix_blend(fb8,b8,alpha_level,alpha_add),
                                               mix_blend(fg8,g8,alpha_level,alpha_add),
                                               mix_blend(fr8,r8,alpha_level,alpha_add) } :
                       ~|shd_l          ? { b8, g8, r8 } :
                                        { add_clip(b8,shad_b,clipsl),
                                          add_clip(g8,shad_g,clipsl),
                                          add_clip(r8,shad_r,clipsl) },
                       bri_l, bri1_lvl );
        end
    end
end

// palette dump: four bytes per entry, x/R/G/B
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
    // pin input-delay selects, not needed
    .mixpri      (                 ),
    .shdpri      (                 ),
    .brtpri      (                 ),
    .clipsl      ( clipsl          ),
    .dump_mmr    (                 ),
    .bri1_lvl    ( bri1_lvl        ),

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
    .shd_in     ( shadow    ),
    .shd_out    ( shd_out   ),
    // dump to SD card, done through u_k251g instead
    .ioctl_addr ( ioctl_ram ? ioctl_addr[3:0] : debug_bus[3:0] ),
    .ioctl_din  (           ),

    .cout       ( col       ),
    .brit       ( brit      ),
    .col_n      ( col_n     )
);

// read-only register mirrors for the SD-card dump, no effect on the chip models
jtk054338_mmr u_k338g(
    .rst        ( rst        ),
    .clk        ( clk        ),

    .cs         ( reg_cs     ),
    .addr       ( cpu_addr[4:1] ),
    .rnw        ( ~cpu_we    ),
    .din        ( cpu_dout   ),
    .dout       (            ),
    .dsn        ( cpu_dsn    ),

    .bgc_r      (), .bgc_g (), .bgc_b (),
    .shd1_r (), .shd1_g (), .shd1_b (),
    .shd2_r (), .shd2_g (), .shd2_b (),
    .shd3_r (), .shd3_g (), .shd3_b (),
    .bri1_lvl (), .bri2_lvl (), .bri3_lvl (),
    .mix1_lvl (), .mix1_mode (),
    .mix2_lvl (), .mix2_mode (),
    .mix3_lvl (), .mix3_mode (),
    .video_en (), .mixpri (), .shdpri (), .brtpri (), .clipsl (),

    .ioctl_addr ( k338g_addr ),
    .ioctl_din  ( k338g_dump ),
    .debug_bus  ( debug_bus  ),
    .st_dout    (            )
);

jtk053251_mmr u_k251g(
    .rst        ( rst        ),
    .clk        ( clk        ),

    .cs         ( pcu_we     ),
    .addr       ( cpu_addr[4:1] ),
    .rnw        ( ~cpu_we    ),
    .din        ( {2'd0,cpu_dout[5:0]} ),
    .dout       (            ),

    .pri0_ext (), .pri1_ext (), .pri2_ext (), .pri3 (), .pri4 (),
    .brit_thr (), .shd1_pri (), .shd2_pri (), .shd3_pri (),
    .colhi0 (), .colhi3 (), .full_en (), .exten (),

    .ioctl_addr ( k251g_addr ),
    .ioctl_din  ( k251g_dump ),
    .debug_bus  ( debug_bus  ),
    .st_dout    (            )
);

jtframe_dual_ram #(.AW(11),.SIMFILE("pal_g.bin")) u_pal_g(
    .clk0   ( clk           ),
    .data0  ( cpu_dout[15:8]),
    .addr0  ( cpu_pal_addr  ),
    .we0    ( wr_g          ),
    .q0     ( cpu_g         ),
    .clk1   ( clk           ),
    .data1  ( 8'd0          ),
    .addr1  ( pal_addr      ),
    .we1    ( 1'b0          ),
    .q1     ( pal_g         )
);

jtframe_dual_ram #(.AW(11),.SIMFILE("pal_r.bin")) u_pal_r(
    .clk0   ( clk           ),
    .data0  ( cpu_dout[7:0] ),
    .addr0  ( cpu_pal_addr  ),
    .we0    ( wr_r          ),
    .q0     ( cpu_r         ),
    .clk1   ( clk           ),
    .data1  ( 8'd0          ),
    .addr1  ( pal_addr      ),
    .we1    ( 1'b0          ),
    .q1     ( pal_r         )
);

jtframe_dual_ram #(.AW(11),.SIMFILE("pal_b.bin")) u_pal_b(
    .clk0   ( clk           ),
    .data0  ( cpu_dout[7:0] ),
    .addr0  ( cpu_pal_addr  ),
    .we0    ( wr_b          ),
    .q0     ( cpu_b         ),
    .clk1   ( clk           ),
    .data1  ( 8'd0          ),
    .addr1  ( pal_addr      ),
    .we1    ( 1'b0          ),
    .q1     ( pal_b         )
);

`ifdef SIMULATION
wire unused_colmix = &{ 1'b0, lyrb_pxl[4], lyrf_l[11:8],
                        lyra_pxl[11:9], lyrb_pxl[11:8], lyrc_pxl[11:8] };
`endif

endmodule
