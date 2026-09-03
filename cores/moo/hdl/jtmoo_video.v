/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Author: Rafael Eduardo Paiva Feener. Copyright: Jose Tejada Gomez
 * Version: 1.0
 * Date: 17-6-2026 */

module jtmoo_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,

    // Base Video
    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,

    // Object DMA
    input      [ 1:0] oram_we,
    // CPU interface
    input      [16:1] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,

    input             pcu_cs,
    input             k338_cs,
    input             pal_cs,
    output     [15:0] pal_dout,
    output     [15:0] tilesys_dout,

    input             cco_cs,
    input             rw,
    input      [ 3:0] vtimer_addr,
    output     [ 7:0] vtimer_mmr,

    output            dma_bsy,
    output     [15:0] objsys_dout,
    input             objsys_cs,
    input             objreg_cs,
    input             objcha_n,

    input             scrreg_cs,
    input             scr_cs,
    input             blnk_sel,

    output            vdtac,
    input             tilesys_cs,
    input             rmrd_cs,  // graphics ROM read-back window
    output            rst8,     // reset signal at 8th frame

    // control
    output            flip,
    output            int1,
    // Tile ROMs
    output     [20:2] lyrf_addr,
    output     [20:2] lyra_addr,
    output     [20:2] lyrb_addr,
    output     [20:2] lyrc_addr,
    output     [22:2] lyro_addr,

    output            lyrf_cs,
    output            lyra_cs,
    output            lyrb_cs,
    output            lyrc_cs,
    output            lyro_cs,

    input             lyrf_ok,
    input             lyra_ok,
    input             lyrb_ok,
    input             lyrc_ok,
    input             lyro_ok,

    input      [31:0] lyrf_data,
    input      [31:0] lyra_data,
    input      [31:0] lyrb_data,
    input      [31:0] lyrc_data,
    input      [31:0] lyro_data,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    // Debug
    input      [15:0] ioctl_addr,
    input             ioctl_ram,
    output     [ 7:0] ioctl_din,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus,
    output     [ 7:0] st_dout
);

wire [11:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl;
wire [ 8:0] hdump, vdump, lyro_pxl;
wire [ 7:0] dump_scr, st_scr, dump_obj, scr_mmr, obj_mmr, dump_pal, pal_mmr;
wire [ 4:0] lyro_pri;
wire [ 1:0] shadow;
wire [ 3:0] obj_amsb, ommra;
wire [13:1] orama;
wire        cpu_weg;

assign cpu_weg = cpu_we && cpu_dsn!=2'b11;
// The read-back steals the first tile ROM port, so the CPU waits for it
assign vdtac   = lyrf_ok;

jtriders_dump #(.FULLRAM(1)) u_dump(
    .clk            ( clk             ),
    .dump_scr       ( dump_scr        ),
    .dump_obj       ( dump_obj        ),
    .dump_pal       ( dump_pal        ),
    .pal_mmr        ( pal_mmr         ),
    .scr_mmr        ( scr_mmr         ),
    .obj_mmr        ( obj_mmr         ),
    .psac_mmr       ( 8'b0            ),
    .other          ( 8'd0            ),

    .ioctl_addr     ( ioctl_addr      ),
    .ioctl_din      ( ioctl_din       ),
    .obj_amsb       ( obj_amsb        ),
    .part_addr      (                 ),

    .debug_bus      ( debug_bus       ),
    .st_scr         ( st_scr          ),
    .st_dout        ( st_dout         )
);

// video timer, L4 on the schematics. INIT holds the values the game programs
// at 0D0000-0D001F: HC=512 HFP=33 HBP=55 VC=264 VFP=17 VBP=15 VSW=8 HSW=5.
// Without it the CCU never cycles and the boot ROM hangs before attract.
jtk053252 #(.INIT(128'h00_00_00_74_0E_11_07_01_00_00_37_00_21_00_FF_01)) u_k053252(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),

    .cs         ( cco_cs        ), // /CC0
    .addr       ( vtimer_addr   ),
    .rnw        ( rw            ),
    .din        ( cpu_dout[7:0] ),
    .dout       ( vtimer_mmr    ),

    .hs         ( hs            ),
    .vs         ( vs            ),
    .lhbl       ( lhbl          ),
    .lhbs       (               ),
    .lvbl       ( lvbl          ),
    .hld        (               ),
    .vld        (               ),
    // unused
    .vldi       ( 1'b1          ),
    .hldi       ( 1'b1          ),
    .sel        ( 3'd0          ),
    .int1       ( int1          ),
    .int2       (               ),
    // IOCTL dump
    .ioctl_addr ( ioctl_addr[3:0]),
    .ioctl_din  (               )
);

/* verilator tracing_on */
jtmoo_scroll u_scroll(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),
    .vs         ( vs        ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),

    // CPU interface
    .cpu_addr   (cpu_addr[12:1]),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .cpu_we     ( cpu_weg   ),
    .reg_cs     ( scrreg_cs ),
    .gfx_cs     ( tilesys_cs),
    .vram_cs    ( scr_cs    ),
    .rmrd_cs    ( rmrd_cs   ),
    .rst8       ( rst8      ),
    .tile_dout  ( tilesys_dout ),
    .flip       ( flip      ),

    // Tile ROMs
    .lyrf_addr  ( lyrf_addr ),
    .lyra_addr  ( lyra_addr ),
    .lyrb_addr  ( lyrb_addr ),
    .lyrc_addr  ( lyrc_addr ),
    .lyrf_cs    ( lyrf_cs   ),
    .lyra_cs    ( lyra_cs   ),
    .lyrb_cs    ( lyrb_cs   ),
    .lyrc_cs    ( lyrc_cs   ),
    .lyrf_data  ( lyrf_data ),
    .lyra_data  ( lyra_data ),
    .lyrb_data  ( lyrb_data ),
    .lyrc_data  ( lyrc_data ),
    .lyrf_ok    ( lyrf_ok   ),
    .lyra_ok    ( lyra_ok   ),
    .lyrb_ok    ( lyrb_ok   ),
    .lyrc_ok    ( lyrc_ok   ),

    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),
    .lyrc_pxl   ( lyrc_pxl  ),

    // Debug
    .ioctl_addr ( ioctl_addr[14:0]),
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_din  ( dump_scr  ),
    .mmr_dump   ( scr_mmr   ),

    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus ),
    .st_dout    ( st_scr    )
);

/* verilator tracing_on */
assign ommra = {cpu_addr[3:1],cpu_dsn[1]};
// Object RAM word address: F6/F7 (74LS245) on the schematic give
// {EN7..EN0,EA5..EA1} = {MAIN_A15..A8, MAIN_A5..A1}; A6/A7 are not wired to
// the RAM at all (each entry's 32 words alias four times across them).
// Entry stride is therefore 32 words. The DMA-side read address
// (ESTRIDE_LOG2(5)/ENTRY_LOG2(8) below) uses the same geometry, so the
// CPU-write and DMA-read views of this RAM agree.
assign orama = {cpu_addr[15:8], cpu_addr[5:1]};

localparam [9:0] OVOFFSET=0;

jtsimson_obj #(.RAMW(13),.SHADOW(1),.ESTRIDE_LOG2(5),.ENTRY_LOG2(8)) u_obj(    // sprite logic
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),
    .simson     ( 1'b0      ),
    .ln_done    (           ),

    .voffset    ( OVOFFSET  ),
    // Base Video (inputs)
    .hs         ( hs        ),
    .lvbl       ( lvbl      ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    // CPU interface
    .ram_cs     ( objsys_cs ),
    .ram_addr   ( orama     ),
    .ram_din    ( cpu_dout  ),
    .ram_we     ( oram_we   ),
    .cpu_din    (objsys_dout),

    .reg_cs     ( objreg_cs ),
    .mmr_addr   ( ommra     ),
    .mmr_din    ( cpu_dout  ),
    .mmr_we     ( cpu_we    ),
    .mmr_dsn    ( cpu_dsn   ),

    .dma_bsy    ( dma_bsy   ),
    // ROM
    .rom_addr   ( lyro_addr ),
    .rom_data   ( lyro_data ),
    .rom_ok     ( lyro_ok   ),
    .rom_cs     ( lyro_cs   ),
    .objcha_n   ( objcha_n  ),
    // pixel output
    .pxl        ( lyro_pxl  ),
    .shd        ( shadow    ),
    .prio       ( lyro_pri  ),
    // Debug
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_addr ( {obj_amsb[1:0],ioctl_addr[11:0]} ),
    .dump_ram   ( dump_obj  ),
    .dump_reg   ( obj_mmr   ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus )
);

/* verilator tracing_on */
jtmoo_colmix u_colmix(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),

    // CPU interface
    .cpu_addr   (cpu_addr[12:1]),
    .cpu_we     ( cpu_weg   ),
    .cpu_din    ( pal_dout  ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .pal_cs     ( pal_cs    ),
    .pcu_cs     ( pcu_cs    ),
    .reg_cs     ( k338_cs   ),

    // Final pixels
    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),
    .lyrc_pxl   ( lyrc_pxl  ),
    .lyro_pxl   ( lyro_pxl  ),
    .lyro_pri   ( lyro_pri  ),
    .blnk_sel   ( blnk_sel  ),

    .shadow     ( shadow    ),

    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      ),

    // Debug
    .ioctl_addr ( ioctl_addr[11:0]),
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_din  ( dump_pal  ),
    .dump_mmr   ( pal_mmr   ),

    .debug_bus  ( debug_bus )
);

endmodule
