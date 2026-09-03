/* SPDX-FileCopyrightText: 2026 jlrh (github.com/jlrh/konami-fpga)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Konami K054539 PCM sound chip -- adapted from the "Cowboys of Moo Mesa"
 * core in github.com/jlrh/konami-fpga (GPL-3.0, built on the same JTFRAME
 * framework as this repo), commit 1a6838f75d613234a1f57c5e053df1d8b63a3876,
 * file cores/moomesa/hdl/k054539.v, dated 2026-08-31. Imported into jtcores
 * 2026-09-04. Renamed module/file (k054539 -> jt054539) to match this
 * repo's module-naming convention; comments translated Spanish->English for
 * repo consistency. The synthesizable logic below is otherwise UNCHANGED
 * from the source -- do not "fix" anything here without also checking
 * against the original file, since its author's own bit-exactness claim
 * (see provenance note below) only covers the untouched logic.
 *
 * This is NOT Jotego's private `jt539` module (sponsor-gated, unavailable
 * to this project -- see D:\evidence\moo\log_pcm.md "C5" for the full
 * account of why that module could not be used and why Furrtek's raw
 * SiliconRE gate-level netlist was not hand-ported either). This is an
 * independent, from-scratch implementation written against MAME's
 * k054539.cpp and Furrtek's SiliconRE die trace
 * (github.com/furrtek/SiliconRE/Konami/054539).
 *
 * Provenance / verification claim (from the upstream author, not verified
 * by this project beyond the MAME differential noted in
 * D:\evidence\moo\log_pcmport.md): "validated bit-exact against a
 * MAME-derived C++ model" and "playable on MiSTer -- audio ... runs on
 * hardware" for this exact game. The reference C++ model and upstream
 * testbench are not shipped in the upstream repo (gitignored) and are not
 * present here -- this project cannot independently reproduce that
 * validation and instead added its own MAME differential check, see the
 * import log.
 *
 * ============================== STATUS: Phase 3 (as imported) ============
 * Implemented:
 *   - Register file with the real bus mapping {A[9],A[7:0]} (A[8] is lost
 *     on the real board) + read-back (needed for POST on this board family:
 *     the upstream author's own note says the Z80 POST writes/rereads
 *     0xE000-0xE1FF, and with dout stuck at 0 the boot hangs. Our own board
 *     is a sibling of theirs on the same PWB353126-family sound board).
 *   - Serial 8-channel FSM, one sample every 384 `cen` (48 kHz), pos/frac
 *     accumulator.
 *   - The THREE sample formats Moo Mesa uses (measured by the upstream
 *     author with a live tap: 8-bit 240 / 16-bit 187 / DPCM 43 uses):
 *       * 8-bit PCM  (type 0x0): 1 byte, val=byte<<8, terminator 0x80.
 *       * 16-bit PCM (type 0x4): 2 bytes LE, terminator 0x8000.
 *       * 4-bit DPCM (type 0x8): nibble + step table, accumulate, term 0x88.
 *   - Fixed-point Q16 mixing via voltab/pantab ($readmemh) + L/R pan
 *     (including the 0x8x range), key on/off. Output = PURE PCM (its own
 *     channel into jtframe's rcmix). FM (jt51) is a SEPARATE CHANNEL
 *     (mem.yaml: fm + pcm) so jtframe mixes at wide precision without
 *     eating into headroom -- see the FM-routing note in jtmoo_sound.v for
 *     why this project follows that choice instead of the real board's
 *     internal-AUX-mixing topology. Live PCM trim via debug_bus[7:4]
 *     (default = unity) to calibrate balance without recompiling.
 * TODO (left exactly as the upstream author left it, not attempted here):
 *   - Reverb "reverse" mode (unused on Moo Mesa: measured 0/470 uses).
 *   - Exact UPDATE_AT_KEYON latch behaviour (here: restart on a key-on edge
 *     reads registers 0x0c-0e directly instead).
 *
 * The register-file read-back is REAL, REQUIRED-FOR-BOOT behaviour on the
 * upstream author's board, not a nicety -- see the paragraph above.
 */
module jt054539 #(parameter VOLSHIFT=0) (
    input               rst,
    input               clk,
    input               cen,     // 18.432 MHz gated (pcm). 384 cen = 1 sample (48 kHz)
    output              timeout,

    // CPU interface (addr = {A[9],A[7:0]}, 9 bits; A[8] is lost on the real bus)
    input      [ 8:0]   addr,
    input               we,
    input               rd,
    input               cs,
    input      [ 7:0]   din,
    output     [ 7:0]   dout,

    // ROM (PCM samples) in SHARED SDRAM -> rom_ok MUST be honoured (the data is
    // NOT zero-latency -- under video+cpu+sound contention it arrives late; reading
    // without waiting reads a false terminator = missing/cut-off sound).
    output reg          rom_cs,
    output reg [23:0]   rom_addr,
    input      [ 7:0]   rom_data,
    input               rom_ok,

    // Sound output (PURE PCM -- FM goes through its own channel in jtframe's rcmix)
    output reg signed [15:0] left,
    output reg signed [15:0] right,

    input      [ 7:0]   debug_bus,
    output     [ 7:0]   st_dout
);

// ---------------------------------------------------------------------------
// Register file (addressed by the module's {A9,A7:0} address).
// MAME offset -> module offset mapping: channel block 0x0xx unchanged;
// control 0x2xx -> 0x1xx: active=0x22c->0x12c ctrl=0x22f->0x12f
// keyon=0x214->0x114 keyoff=0x215->0x115
// channel ch base1=0x20*ch (unchanged), base2=0x200+2*ch -> 0x100+2*ch
// CPU is the ONLY writer of regs[] (single driver). keyon/keyoff/terminator
// touch `active`.
// ---------------------------------------------------------------------------
reg  [7:0] regs [0:511];
integer    gi;
initial for (gi=0; gi<512; gi=gi+1) regs[gi] = 8'd0;

always @(posedge clk) begin
    if (cs && we) regs[addr] <= din;
end

assign dout    = regs[addr];
assign timeout = 1'b0;
assign st_dout = 8'd0;

// ---------------------------------------------------------------------------
// Volume/pan tables (Q16) -- same as the upstream author's k054539_ref.cpp
// FIXED mode reference model.
// ---------------------------------------------------------------------------
reg [15:0] voltab [0:255];   // <= 0x4000
reg [16:0] pantab [0:14];    // <= 0x10000
initial begin
    $readmemh("voltab.hex", voltab);
    $readmemh("pantab.hex", pantab);
end

// ---------------------------------------------------------------------------
// Per-channel state (authoritative; in BYTE units between samples)
// ---------------------------------------------------------------------------
reg [23:0] cpos   [0:7];
reg [15:0] cpfrac [0:7];
reg signed [15:0] cval  [0:7];
reg signed [15:0] cpval [0:7];

reg  [7:0] active;    // channels sounding (MAME 0x22c)
reg  [7:0] restart;   // restart on a key-on edge

// ---------------------------------------------------------------------------
// Sequencer
// ---------------------------------------------------------------------------
localparam [3:0]
    S_IDLE = 4'd0, S_LOAD = 4'd1, S_ACC = 4'd2,
    S_R8   = 4'd3, S_R16L = 4'd4, S_R16H = 4'd5, S_RD = 4'd6,
    S_MIX  = 4'd7, S_NEXT = 4'd8, S_DONE = 4'd9,
    S_REVRD= 4'd10, S_RVWR = 4'd11;   // reverb: read feedback @revpos ; channel RMW @widx

reg [3:0]  state;
reg [8:0]  sample_cnt;
reg [2:0]  ch;

// working registers for the channel in flight
reg [24:0] w_pos;              // 25b: DPCM works in NIBBLE units (pos<<1)
reg [31:0] w_pfrac;
reg signed [15:0] w_val, w_pval;
reg [23:0] w_loop;
reg [7:0]  w_lo;              // low byte of a 16-bit sample
reg [7:0]  w_vol;
reg [3:0]  w_pan;
reg [1:0]  w_type;           // 0=8bit, 1=16bit(0x4), 2=DPCM(0x8)
reg        w_loopen;

// Q16 accumulators (as MAME does: sum at full precision, >>16 ONCE at the end)
reg signed [39:0] accL, accR;

// ---------------------------------------------------------------------------
// Reverb -- mono delay line (MAME k054539.cpp). rbase = int16[0x2000] in BRAM.
// Per sample: rram[reverb_pos] is READ+CLEARED (feedback, added to L and R
// equally); each channel ACCUMULATES its attenuated sample into
// rram[(rdelta+reverb_pos)&0x1fff]; then reverb_pos++.
// REGISTERED (synchronous) read -> infers BRAM (a lesson from the upstream
// project: async read/write here previously synthesized as plain logic).
// Zero-init via $readmemh (not an `initial for` loop: Quartus limits loop
// unrolling to 5000 iterations -> Error 10106 at 8192 entries; Verilator/
// lint accept the loop, which would have hidden the same class of bug this
// project already hit once with a different generated file --
// rram_zero.hex = 8192 x "0000".
// ---------------------------------------------------------------------------
reg  signed [15:0] rram [0:8191];
initial $readmemh("rram_zero.hex", rram);
reg  [12:0] reverb_pos;
reg  [12:0] rr_addr;             // WRITE address (clear @revpos / RMW @widx)
reg         rr_we;
reg  signed [15:0] rr_din;
reg  signed [15:0] rr_dout;      // registered read of rram[rd_addr] (1 cycle latency)
// combinational READ address: in S_MIX reads @widx (for the channel's RMW in
// S_RVWR); in every other state reads @reverb_pos (feedback, used in
// S_REVRD after being emitted in S_IDLE).
wire [12:0] rd_addr = (state==S_MIX) ? widx : reverb_pos;
always @(posedge clk) begin
    rr_dout <= rram[rd_addr];
    if (rr_we) rram[rr_addr] <= rr_din;
end

// --- L/R volume of the channel in flight (Q16) ---
wire [16:0] vt   = {1'b0, voltab[w_vol]};
wire [16:0] pl   = pantab[w_pan];
wire [16:0] pr   = pantab[4'd14 - w_pan];
wire [33:0] lfull= vt * pl;
wire [33:0] rfull= vt * pr;
wire [16:0] lvol = lful_clamp(lfull[32:16]);
wire [16:0] rvol = lful_clamp(rfull[32:16]);
function [16:0] lful_clamp(input [16:0] v);
    lful_clamp = (v > 17'h1CCCC) ? 17'h1CCCC : v;   // VOL_CAP=1.8 in Q16
endfunction

// channel contribution in Q16 (UNtruncated): w_val * vol. Accumulated like
// this and rounded only once, at the end.
wire signed [33:0] cprodL = $signed(w_val) * $signed({1'b0, lvol});
wire signed [33:0] cprodR = $signed(w_val) * $signed({1'b0, rvol});
wire signed [39:0] contribL = {{6{cprodL[33]}}, cprodL};
wire signed [39:0] contribR = {{6{cprodR[33]}}, cprodR};

// --- Reverb: parameters of the channel in flight (MAME, FIXED mode) ---
//   rdelta = ({base1[7],base1[6]} >> 3);  rdelta = (rdelta+revpos)&0x3fff;
//   widx   = (rdelta + revpos) & 0x1fff;  (revpos added TWICE: exact MAME quirk)
//   bval   = min(vol + base1[4], 255);    rbvol = (voltab[bval]*32768)>>16 = voltab[bval]>>1
//   rev_contrib = (int16)((cur_val * rbvol) >> 16)  -> ACCUMULATED (int16, wraps) into rram[widx]
// A 16-bit concatenation shifted right by 3 has its top 3 bits always zero
// by construction (unsigned shift), so assigning the result to a 13-bit
// wire below is lossless -- the width checker doesn't narrow a shift
// expression's declared width to match its actual significant bits, hence
// the otherwise-spurious truncation warning. Confirmed during import,
// 2026-09-04 (D:\evidence\moo\log_pcmport.md); the source's own comment
// already states "16b >>3 = 13b". Logic below unchanged from upstream.
// verilator lint_off WIDTHTRUNC
wire [12:0] rrd  = {regs[b1+9'd7], regs[b1+9'd6]} >> 3;          // 16b >>3 = 13b
// verilator lint_on WIDTHTRUNC
wire [13:0] rd14 = ({1'b0,rrd} + {1'b0,reverb_pos}) & 14'h3fff;
wire [14:0] wsum = {1'b0,rd14} + {2'b0,reverb_pos};
wire [12:0] widx = wsum[12:0];                                    // &0x1fff
wire [8:0]  bsum = {1'b0,w_vol} + {1'b0, regs[b1+9'd4]};
wire [7:0]  bval = bsum[8] ? 8'd255 : bsum[7:0];                  // clamp to 255
wire [15:0] rbvol = {1'b0, voltab[bval][15:1]};                   // voltab>>1 (always < VOL_CAP)
wire signed [32:0] rprod = $signed(w_val) * $signed({1'b0, rbvol});
wire signed [15:0] rev_contrib = rprod[31:16];                   // (>>16) truncated to int16

// channel base addresses
wire [8:0] b1 = {1'b0, ch, 5'b0};            // 0x20*ch
wire [8:0] b2 = 9'h100 + {5'b0, ch, 1'b0};   // 0x100 + 2*ch
wire [23:0] delta_now = {regs[b1+9'd2], regs[b1+9'd1], regs[b1+9'd0]};
wire [1:0]  type_now  = (regs[b2] & 8'h0c)==8'h00 ? 2'd0 :
                        (regs[b2] & 8'h0c)==8'h04 ? 2'd1 : 2'd2;

// DPCM step table (x0x100)
function signed [15:0] dpcm_step(input [3:0] n);
    case (n)
        4'd0:  dpcm_step =  16'sd0;      4'd1:  dpcm_step =  16'sd256;
        4'd2:  dpcm_step =  16'sd512;    4'd3:  dpcm_step =  16'sd1024;
        4'd4:  dpcm_step =  16'sd2048;   4'd5:  dpcm_step =  16'sd4096;
        4'd6:  dpcm_step =  16'sd8192;   4'd7:  dpcm_step =  16'sd16384;
        4'd8:  dpcm_step =  16'sd0;      4'd9:  dpcm_step = -16'sd16384;
        4'd10: dpcm_step = -16'sd8192;   4'd11: dpcm_step = -16'sd4096;
        4'd12: dpcm_step = -16'sd2048;   4'd13: dpcm_step = -16'sd1024;
        4'd14: dpcm_step = -16'sd512;    4'd15: dpcm_step = -16'sd256;
    endcase
endfunction

// clamp to int16
function signed [15:0] clip16(input signed [23:0] v);
    clip16 = (v >  24'sd32767) ? 16'sd32767 :
             (v < -24'sd32768) ? -16'sd32768 : v[15:0];
endfunction
// live PCM trim: (PCM*pg) >> 3, clamped. pg comes from debug_bus[7:4] (below).
function signed [15:0] trimg(input signed [15:0] pcm16, input [4:0] pg);
    trimg = clip16( (pcm16*$signed({1'b0,pg})) >>> 3 );
endfunction
function [3:0] pan_idx(input [7:0] p);
    if      (p >= 8'h81 && p <= 8'h8f) pan_idx = p[3:0] - 4'd1;
    else if (p >= 8'h11 && p <= 8'h1f) pan_idx = p[3:0] - 4'd1;
    else                               pan_idx = 4'd7;
endfunction

// current DPCM nibble, by parity of the position (nibble units)
wire [3:0] dnib = w_pos[0] ? rom_data[7:4] : rom_data[3:0];
wire signed [15:0] ds = dpcm_step(dnib);

// --- Live-adjustable PCM trim via debug_bus (calibrate balance without recompiling) ---
//   debug_bus[7:4] = PCM trim (/8; 0 -> default 8 = UNITY). The base FM/PCM
//   balance is set by jtframe's rcmix (mem.yaml: fm + pcm channels); this
//   trim is only for live fine-tuning. (FM is trimmed on its own channel,
//   in jtmoo_sound.v with debug_bus[3:0].)
wire [4:0] pcm_g = (debug_bus[7:4]==4'd0) ? 5'd8 : {1'b0, debug_bus[7:4]};
// position advance (w_pos units)
wire [24:0] npos1 = w_pos + 25'd1;
wire [24:0] npos2 = w_pos + 25'd2;

integer ci;
always @(posedge clk) begin
    if (rst) begin
        state <= S_IDLE; sample_cnt <= 0; ch <= 0;
        rom_cs <= 0; rom_addr <= 0;
        left <= 0; right <= 0; accL <= 0; accR <= 0;
        active <= 0; restart <= 0;
        reverb_pos <= 0; rr_we <= 0; rr_addr <= 0; rr_din <= 0;   // reverb (rram init via `initial`)
        for (ci=0; ci<8; ci=ci+1) begin
            cpos[ci] <= 0; cpfrac[ci] <= 0; cval[ci] <= 0; cpval[ci] <= 0;
        end
    end else begin
        // key on/off from the CPU (runs at clk, not cen)
        if (cs && we) begin
            case (addr)
                9'h114: begin restart <= restart | (din & ~active); active <= active | din; end
                9'h115: active <= active & ~din;
                default: ;
            endcase
        end

        if (cen) begin
            sample_cnt <= (sample_cnt == 9'd383) ? 9'd0 : sample_cnt + 9'd1;
            rom_cs <= 1'b0;
            rr_we  <= 1'b0;   // no reverb write by default (same pattern as rom_cs)

            case (state)
            S_IDLE: if (sample_cnt == 9'd0) begin
                        ch <= 0;
                        if (regs[9'h12f][0]) begin
                            state <= S_REVRD;   // rd_addr=reverb_pos (emitted); rr_dout ready in S_REVRD
                        end else begin
                            accL <= 0; accR <= 0; state <= S_LOAD;     // chip off: no reverb
                        end
                    end

            // ---------- reverb: feedback @reverb_pos -> init accL/accR, and CLEAR the slot ----------
            S_REVRD: begin
                accL <= { {8{rr_dout[15]}}, rr_dout, 16'b0 };   // rbase[revpos]<<16 (Q40, sign-extended)
                accR <= { {8{rr_dout[15]}}, rr_dout, 16'b0 };
                rr_addr <= reverb_pos; rr_din <= 16'sd0; rr_we <= 1'b1;   // rram[reverb_pos] <= 0
                state <= S_LOAD;
            end

            // ---------- load parameters + set up the accumulator ----------
            S_LOAD: begin
                if (!active[ch] || !regs[9'h12f][0]) begin
                    state <= S_NEXT;
                end else begin
                    w_vol    <=  regs[b1+3];
                    w_loop   <= {regs[b1+9'ha], regs[b1+9'h9], regs[b1+9'h8]};
                    w_loopen <=  regs[b2+1][0];
                    w_pan    <=  pan_idx(regs[b1+5]);
                    w_type   <=  type_now;
                    // base pos/frac (byte units). For DPCM this is scaled to nibbles below.
                    if (type_now == 2'd2) begin
                        // DPCM: pos<<1, frac<<1, carry adjust, +=delta
                        if (restart[ch]) begin
                            w_pos   <= {regs[b1+9'he], regs[b1+9'hd], regs[b1+9'hc]} << 1;
                            w_pfrac <= {8'b0, delta_now};                 // (0<<1)=0, +delta
                            w_val   <= 0; w_pval <= 0;
                            restart[ch] <= 1'b0;
                        end else begin
                            // frac<<1; if bit16 set -> pos|1, frac&0xffff; then +=delta
                            w_pos   <= ({cpos[ch],1'b0}) | (cpfrac[ch][15] ? 25'd1 : 25'd0);
                            w_pfrac <= {15'b0, cpfrac[ch], 1'b0} + {8'b0, delta_now}
                                       - (cpfrac[ch][15] ? 32'h0001_0000 : 32'd0);
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end
                    end else begin
                        if (restart[ch]) begin
                            w_pos   <= {1'b0, regs[b1+9'he], regs[b1+9'hd], regs[b1+9'hc]};
                            w_pfrac <= {8'b0, delta_now};
                            w_val   <= 0; w_pval <= 0;
                            restart[ch] <= 1'b0;
                        end else begin
                            w_pos   <= {1'b0, cpos[ch]};
                            w_pfrac <= {16'b0, cpfrac[ch]} + {8'b0, delta_now};
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end
                    end
                    state <= S_ACC;
                end
            end

            // ---------- while(cur_pfrac & ~0xffff): advance and read ----------
            S_ACC: begin
                if (|w_pfrac[31:16]) begin
                    w_pfrac <= w_pfrac - 32'h0001_0000;
                    case (w_type)
                    2'd0: begin // 8-bit: +1 byte
                        w_pos    <= npos1;
                        rom_addr <= npos1[23:0];
                        rom_cs   <= 1'b1; state <= S_R8;
                    end
                    2'd1: begin // 16-bit: +2 bytes (reads low, then high)
                        w_pos    <= npos2;
                        rom_addr <= npos2[23:0];
                        rom_cs   <= 1'b1; state <= S_R16L;
                    end
                    default: begin // DPCM: +1 nibble; reads byte at pos>>1
                        w_pos    <= npos1;
                        rom_addr <= npos1[24:1];
                        rom_cs   <= 1'b1; state <= S_RD;
                    end
                    endcase
                end else begin
                    state <= S_MIX;
                end
            end

            // ---------- capture 8-bit (wait for rom_ok: SDRAM data ready) ----------
            S_R8: if (rom_ok) begin
                w_pval <= w_val;
                if (rom_data == 8'h80) begin
                    if (w_loopen) begin
                        w_pos <= {1'b0, w_loop}; rom_addr <= w_loop; rom_cs <= 1'b1; state <= S_R8;
                    end else begin
                        active[ch] <= 1'b0; w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_val <= $signed({rom_data, 8'h00}); state <= S_ACC;
                end
            end

            // ---------- capture 16-bit (low byte, then high) -- wait for rom_ok on each byte ----------
            S_R16L: if (rom_ok) begin
                w_lo     <= rom_data;
                rom_addr <= w_pos[23:0] + 24'd1;   // high byte
                rom_cs   <= 1'b1; state <= S_R16H;
            end
            S_R16H: if (rom_ok) begin
                w_pval <= w_val;
                if ({rom_data, w_lo} == 16'h8000) begin
                    if (w_loopen) begin
                        w_pos <= {1'b0, w_loop}; rom_addr <= w_loop; rom_cs <= 1'b1; state <= S_R16L;
                    end else begin
                        active[ch] <= 1'b0; w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_val <= $signed({rom_data, w_lo}); state <= S_ACC;
                end
            end

            // ---------- capture DPCM (wait for rom_ok) ----------
            S_RD: if (rom_ok) begin
                if (rom_data == 8'h88) begin
                    if (w_loopen) begin
                        w_pos <= {w_loop, 1'b0}; rom_addr <= w_loop; rom_cs <= 1'b1; state <= S_RD;
                    end else begin
                        active[ch] <= 1'b0; w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_pval <= w_val;
                    w_val  <= clip16( {{8{w_val[15]}}, w_val} + {{8{ds[15]}}, ds} );
                    state  <= S_ACC;
                end
            end

            // ---------- mix + writeback (de-scale DPCM) ----------
            S_MIX: begin
                accL <= accL + contribL;
                accR <= accR + contribR;
                if (w_type == 2'd2) begin
                    cpos[ch]   <= w_pos[24:1];                             // pos>>1
                    cpfrac[ch] <= {1'b0, w_pfrac[15:1]} | (w_pos[0] ? 16'h8000 : 16'h0);
                end else begin
                    cpos[ch]   <= w_pos[23:0];
                    cpfrac[ch] <= w_pfrac[15:0];
                end
                cval[ch]  <= w_val;
                cpval[ch] <= w_pval;
                state <= S_RVWR;        // rd_addr=widx (emitted in S_MIX); rr_dout ready in S_RVWR
            end

            // ---------- reverb RMW: rram[widx] += rev_contrib (int16, wraps) ----------
            S_RVWR: begin
                rr_addr <= widx;                   // write address (ch not yet incremented)
                rr_din  <= rr_dout + rev_contrib;  // rr_dout = rram[widx] (old, read via rd_addr in S_MIX)
                rr_we   <= 1'b1;                    // commits during S_NEXT
                state   <= S_NEXT;
            end

            S_NEXT: begin
                if (ch == 3'd7) state <= S_DONE;
                else begin ch <= ch + 3'd1; state <= S_LOAD; end
            end

            S_DONE: begin  // Q16 -> integer (>>16), clamp the PCM (as MAME does), and live PCM trim
                left  <= trimg( clip16($signed(accL[39:16])), pcm_g );
                right <= trimg( clip16($signed(accR[39:16])), pcm_g );
                if (regs[9'h12f][0]) reverb_pos <= reverb_pos + 13'd1;  // freezes if chip is OFF (ref: early return)
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end
end

endmodule
