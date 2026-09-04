/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
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
    output     [ 7:0] dump_mmr,

    input      [ 7:0] debug_bus
);

wire [23:0] k338_bg, k338_dump;
wire [15:0] k338_dout;
wire [10:0] col, pal_addr, cpu_pal_addr;
wire [ 8:0] ci0, ci1, ci2;
wire [ 7:0] ci3, ci4, k251_dump, alpha_level, bri1_lvl,
            pal_r, pal_g, pal_b, cpu_r, cpu_g, cpu_b, f_pal_r, f_pal_g, f_pal_b,
            k338_byte;
wire [ 5:0] pri0;
wire [ 1:0] shd_out, shd_in, mcol_shd, k338_byte_sel;
wire        pcu_we, reg_we, col_n, k338_video_en, clipsl, alpha_add, pblend0,
            brit, wr_r, wr_g, wr_b, pal_word, p0_opaque, mcol_blank, mcol_bri,
            f_wr_r, f_wr_g, f_wr_b, k338_dump_sel;
wire signed [9:0] shad_r, shad_g, shad_b;
reg  [23:0] bgr;
reg  [11:0] lyrf_l;
reg  [ 7:0] r8, g8, b8, fr8, fg8, fb8;
reg  [ 1:0] shd_l;
reg         blank_l, fixop_a, blend_a, bri_l;

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
assign ci2       = { lyra_pxl[8], lyra_pxl[7:4], lyra_pxl[3:0] };
assign ci3       = { 1'b0, lyrb_pxl[7:5], lyrb_pxl[3:0] }; // only CI30..CI36 wired
assign ci4       = { lyrc_pxl[7:4], lyrc_pxl[3:0] };
assign shd_in    = shadow;

// MIX0 = COL8 & ~COL9 & ~COL10, MIX1 tied low
assign pblend0    = col[8] & ~col[9] & ~col[10];
// opaque plane 0 wins unless MIX0 selects blending with the K053251 winner
assign p0_opaque  = |lyrf_l[3:0];
assign mcol_blank = p0_opaque ? 1'b0 : col_n;
assign mcol_shd   = p0_opaque ? 2'b0 : shd_out;
assign mcol_bri   = p0_opaque ? 1'b0 : brit;
assign pal_addr   = col;

// plane 0 palette mirror, bank 0x700-0x7FF
assign f_wr_r = wr_r & (cpu_pal_addr[10:8]==3'b111);
assign f_wr_g = wr_g & (cpu_pal_addr[10:8]==3'b111);
assign f_wr_b = wr_b & (cpu_pal_addr[10:8]==3'b111);

// K054338 dump: CONTROL/brightness/PBLEND on ioctl_addr[4] or debug_bus[7]
assign k338_dump_sel = ioctl_ram ? ioctl_addr[4]   : debug_bus[7];
assign k338_byte_sel = ioctl_ram ? ioctl_addr[1:0] : debug_bus[1:0];
assign k338_byte     = k338_byte_sel==2'd0 ? k338_dump[23:16] :
                       k338_byte_sel==2'd1 ? k338_dump[15:8]  : k338_dump[7:0];
assign dump_mmr      = k338_dump_sel ? k338_byte : k251_dump;

// CLIPSL disables the clamp, the sum wraps instead
function [7:0] add_clip(input [7:0] cin, input signed [9:0] delta, input noclip);
    reg signed [10:0] sum;
begin
    sum = {3'd0,cin} + delta;
    add_clip = noclip          ? sum[7:0] :
               sum < 0         ? 8'd0  :
               sum > 11'sd255  ? 8'hff : sum[7:0];
end
endfunction

// mode 0: (front*level + back*(256-level))>>8
// mode 1: front + (back*(32-mixlv))>>5, mixlv is the top 5 bits of level
function [7:0] mix_blend(input [7:0] front, input [7:0] back, input [7:0] level, input additive);
    reg [ 8:0] inv9;
    reg [ 5:0] inv5;
    reg [17:0] sum;
    reg [13:0] aprod;
    reg [ 8:0] asum;
begin
    inv9 = 9'd256 - {1'b0,level};
    // defaults only satisfy Quartus all-paths-assigned check (10776)
    inv5  = 6'd0;
    sum   = 18'd0;
    aprod = 14'd0;
    asum  = 9'd0;
    if( additive ) begin
        inv5  = 6'd32 - {1'b0,level[7:3]};
        aprod = back * inv5;
        asum  = {1'b0,front} + aprod[13:5];
        mix_blend = asum[8] ? 8'hff : asum[7:0];
    end else begin
        sum = front*level + back*inv9; // <= 65280, no clamp needed
        mix_blend = sum[15:8];
    end
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
    end else begin
        { r8,  g8,  b8  } <= { pal_r,   pal_g,   pal_b   };
        { fr8, fg8, fb8 } <= { f_pal_r, f_pal_g, f_pal_b };
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
    .dump_mmr    ( k338_dump       ),
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
    .shd_in     ( shd_in    ),
    .shd_out    ( shd_out   ),
    // dump to SD card
    .ioctl_addr ( ioctl_ram ? ioctl_addr[3:0] : debug_bus[3:0] ),
    .ioctl_din  ( k251_dump ),

    .cout       ( col       ),
    .brit       ( brit      ),
    .col_n      ( col_n     )
);

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

// plane 0 palette mirror
jtframe_dual_ram #(.AW(8)) u_fpal_g(
    .clk0   ( clk               ),
    .data0  ( cpu_dout[15:8]    ),
    .addr0  ( cpu_pal_addr[7:0] ),
    .we0    ( f_wr_g            ),
    .q0     (                   ),
    .clk1   ( clk               ),
    .data1  ( 8'd0              ),
    .addr1  ( lyrf_l[7:0]       ),
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
    .addr1  ( lyrf_l[7:0]       ),
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
    .addr1  ( lyrf_l[7:0]       ),
    .we1    ( 1'b0              ),
    .q1     ( f_pal_b           )
);

`ifdef SIMULATION
wire unused_colmix = &{ 1'b0, lyrb_pxl[4], lyrf_l[11:8],
                        lyra_pxl[11:9], lyrb_pxl[11:8], lyrc_pxl[11:8] };
`endif

endmodule
