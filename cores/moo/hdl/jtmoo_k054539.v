/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

    Author: meathax
    Date: 4-9-2026 */

/*  Konami K054539 (TOP) PCM sound chip, Moo Mesa local model.

    LOCAL VERIFICATION ONLY. This is not, and does not claim to be, the shared
    `jt539` module. It is an independent implementation written from MAME's
    k054539.cpp and Furrtek's SiliconRE 054539 die reconstruction, kept inside
    cores/moo so that Moo's sound self-test and boot path can be exercised
    while the shared-module question is settled upstream. Do not promote this
    file to modules/ and do not use it from another core.

    Board facts honoured (sch/moomesa/sound.kicad_sch, E4 and C5):
      - no A8 pin: the register file is addressed as {A9,A[7:0]}, so
        0xE100-0xE1FF mirrors 0xE000-0xE0FF.
      - AXDA/AXXA/ALRA/AXWA (pins 36-39) carry the YM2151 serial DAC stream and
        YMD (pin 73) is strapped to VCC, so the aux stream is mixed digitally
        inside this chip; the 054539 output is the board's only analogue
        source. That is why `aux_l`/`aux_r` exist here at all.
      - reverb SRAM C5 is an HM62256 driven on R_A0..13 plus R_A16; RABS is NC.
      - straps: DTS1=1, DTS2=0, USE2=0, RRMD=0, DLY=0, ADDA=0. TIM and ROBS NC.

    Register read-back is real chip behaviour and a boot requirement: the sound
    Z80 POST writes and re-reads 0xE000-0xE1FF, and a chip that returns zero
    fails the test and drives the 68000 into its device-error screen.

    Implemented: register file with read-back, 8-channel serial sequencer at one
    sample every 384 `cen` (48 kHz), the three sample formats Moo uses (8-bit,
    16-bit LE and 4-bit DPCM with their 0x80/0x8000/0x88 terminators), Q16 mix
    with the voltab/pantab tables, key on/off, UPDATE_AT_KEYON position latches,
    live position mirroring, forward and reverse playback, the 0x227
    programmable timer, the reverb delay line, and the 0x22d/0x22e data port
    over both the reverb RAM and the shared PCM ROM.
*/

module jtmoo_k054539 #(parameter
    VOLSHIFT = 0,                   // aux (YM2151) attenuation, in right shifts
    VOLTAB   = "voltab.hex",
    PANTAB   = "pantab.hex",
    REVTAB   = "rram_zero.hex"
)(
    input               rst,
    input               clk,
    input               cen,     // 18.432 MHz. 384 cen = one 48 kHz sample
    output              timeout, // TIM pin, NC on Moo
    // CPU interface. addr = {A[9],A[7:0]}; the chip has no A8 pin
    input      [ 8:0]   addr,
    input               we,
    input               rd,
    input               cs,
    input      [ 7:0]   din,
    output     [ 7:0]   dout,
    output reg          busy,    // hold the sound CPU while a data-port read is in flight
    // PCM ROM, shared SDRAM: the data is not zero latency, so rom_ok must be
    // honoured. Reading without waiting yields false terminators and dropouts.
    output              rom_cs,
    output     [23:0]   rom_addr,
    input      [ 7:0]   rom_data,
    input               rom_ok,
    // YM2151 serial DAC stream, mixed in by the chip (see header)
    input signed [15:0] aux_l,
    input signed [15:0] aux_r,
    // Sound output
    output signed [15:0] left,
    output signed [15:0] right,
    // debug
    input      [ 7:0]   debug_bus,
    output     [ 7:0]   st_dout
);

// ---------------------------------------------------------------------------
// Register file, addressed with the board bus {A9,A7:0}.
// MAME offset -> module offset: channels 0x0xx unchanged; control 0x2xx->0x1xx
//   active=0x22c->0x12c  ctrl=0x22f->0x12f  keyon=0x214->0x114 keyoff=0x215->0x115
//   channel base1=0x20*ch (unchanged)   base2=0x200+2*ch -> 0x100+2*ch
// The CPU and the sequencer share this single write process so that Quartus
// infers one register block instead of a multiply driven array.
// ---------------------------------------------------------------------------
reg  [7:0] regs [0:511];
reg  [7:0] active;
reg  [7:0] rr_cpu_data;
reg  [7:0] rb_data;
// UPDATE_AT_KEYON holds position writes outside the visible register file
// until the next key-on. Kept flat for Quartus inference.
reg  [7:0] pos_latch [0:23];
// The chip captures CPU writes when the active low write strobe is released.
// The Z80 holds one bus transaction across several 48 MHz clocks, so keep its
// stable bus value and emit exactly one release commit.
reg        cpu_write_pending;
reg  [8:0] cpu_write_addr;
reg  [7:0] cpu_write_data;
wire       cpu_write_active = cs && we;
wire       cpu_write_commit = cpu_write_pending && !cpu_write_active;
integer    gi;
initial for (gi=0; gi<512; gi=gi+1) regs[gi] = 8'd0;

wire update_at_keyon = regs[9'h12f][0];
wire reg_updates     = ~regs[9'h12f][7];
wire [7:0] keyon_retrigger = (cpu_write_commit &&
                              (cpu_write_addr == 9'h114) && reg_updates) ?
                              cpu_write_data : 8'h00;

assign dout    = (addr == 9'h12c) ? active :
                 (addr == 9'h12d) ? ((rd && regs[9'h12f][4]) ?
                                      (regs[9'h12e] == 8'h80 ? rr_cpu_data : rb_data) : 8'h00) :
                 regs[addr];

// 0x227 (module 0x127) programs a real periodic timer:
//   period = (38+data) * (clock/384/14400), halved, per MAME k054539.cpp:421-429
//   and call_timer_handler at k054539.cpp:309-313. The timer free runs once
//   armed, toggling timer_state every period, but only while 0x22f bit 5 is
//   set. `timeout` mirrors that square wave, not the sample tick.
reg  [12:0] timer_cnt;
reg         timer_state;
reg         timer_armed;
wire [12:0] timer_add   = 13'd38 + {5'b0, regs[9'h127]};
localparam  [12:0] TIMER_THRESH = 13'd7200;
wire [13:0] timer_sum   = {1'b0, timer_cnt} + {1'b0, timer_add};

wire [8:0] b1 = {1'b0, ch, 5'b0};
wire [8:0] b2 = 9'h100 + {5'b0, ch, 1'b0};
assign timeout = timer_state;

// ---------------------------------------------------------------------------
// Volume and pan tables, Q16, same values as MAME's fixed mode.
// Bare file names follow the jtframe convention (see jtriders_tmnt2.v's
// log2.hex): the master copies live in cores/moo/hdl and are staged into the
// simulation directory.
// ---------------------------------------------------------------------------
reg [15:0] voltab [0:255];   // <= 0x4000
reg [16:0] pantab [0:15];    // <= 0x10000
initial begin
    $readmemh(VOLTAB, voltab);
    $readmemh(PANTAB, pantab);
end

// ---------------------------------------------------------------------------
// Per channel state, authoritative, in BYTE units between samples
// ---------------------------------------------------------------------------
reg [23:0] cpos   [0:7];
reg [15:0] cpfrac [0:7];
reg signed [15:0] cval  [0:7];
reg signed [15:0] cpval [0:7];

reg  [7:0] restart;   // key-on edge restart

// ---------------------------------------------------------------------------
// Sequencer
// ---------------------------------------------------------------------------
localparam [3:0]
    S_IDLE = 4'd0, S_LOAD = 4'd1, S_ACC = 4'd2,
    S_R8   = 4'd3, S_R16L = 4'd4, S_R16H = 4'd5, S_RD = 4'd6,
    S_MIX  = 4'd7, S_NEXT = 4'd8, S_DONE = 4'd9,
    S_REVRD= 4'd10, S_RVWR = 4'd11;   // reverb: read feedback @revpos, RMW @widx

reg [3:0]  state;
reg [8:0]  sample_cnt;
reg [2:0]  ch;

// current channel working registers
reg [24:0] w_pos;              // 25b: DPCM works in NIBBLE units (pos<<1)
reg signed [31:0] w_pfrac;
reg signed [15:0] w_val, w_pval;
reg [23:0] w_loop;
reg [7:0]  w_lo;              // low byte of a 16 bit sample
reg [7:0]  w_vol;
reg [3:0]  w_pan;
reg [1:0]  w_type;            // 0=8bit, 1=16bit(0x4), 2=DPCM(0x8), 3=no-op(0xc)
reg        w_loopen;
reg        w_reverse;

// Playback ROM request registers. The external port is arbitrated with the
// data-port readback below; only one request is presented at a time.
reg         sample_rom_cs;
reg  [23:0] sample_rom_addr;

reg         rb_pending, rb_active, rb_read_seen, rb_data_valid;
reg         rr_cpu_read_seen, rr_cpu_data_valid;
reg  [23:0] rb_addr_l;
reg  [14:0] rr_cpu_addr_l;
wire        rb_rom_bank = regs[9'h12e] != 8'h80;
wire        rb_cpu_read = cs && rd && (addr == 9'h12d) && regs[9'h12f][4] && rb_rom_bank;
wire        rr_cpu_read = cs && rd && (addr == 9'h12d) &&
                          (regs[9'h12e] == 8'h80) && regs[9'h12f][4];

assign rom_cs   = sample_rom_cs | rb_active;
assign rom_addr = rb_active ? rb_addr_l : sample_rom_addr;

// The board leaves the Z80 WAIT pin unconnected, so the real chip answers the
// data port without stalling the CPU; it owns a private PCM ROM bus. Here the
// samples come from shared SDRAM, so the read cannot always be answered inside
// one Z80 bus cycle. `busy` is registered and fed back to the sound CPU clock
// enable, which reproduces the data (correct bytes, no false terminators) at
// the cost of a stall the board does not have. INFERRED, fidelity only.
wire        rb_wait  = rb_pending | rb_active |
                       (rb_cpu_read && !rb_data_valid) |
                       (rr_cpu_read && !rr_cpu_data_valid);

// Q16 accumulators, as MAME: sum at full precision and shift >>16 once
reg signed [39:0] accL, accR;

// ---------------------------------------------------------------------------
// Reverb, mono delay line (MAME k054539.cpp). The audio delay uses
// int16[0x2000] words; the CPU data port exposes the whole 0x8000 byte store,
// with pointer bit 16 selecting the upper 0x4000 byte half.
// Per sample: read+clear rram[reverb_pos] (feedback, added to L and R alike);
// every channel accumulates its attenuated sample in rram[(rdelta+reverb_pos)
// &0x1fff]; then reverb_pos++. The read is registered so that BRAM is inferred.
// Init through $readmemh rather than an `initial for` loop: Quartus caps the
// unroll at 5000 iterations and 8192 would raise Error 10106.
// ---------------------------------------------------------------------------
reg  [16:0] read_ptr;             // 0x22d pointer, wraps at 0x1ffff
reg  [12:0] reverb_pos;
reg  [12:0] rr_addr;              // write address: clear @revpos, RMW @widx
reg         rr_we;
reg  signed [15:0] rr_din;
wire [14:0] rr_port_addr = {read_ptr[16], read_ptr[13:0]};
wire [12:0] rd_addr;

// The reverb store has two independent 0x4000 byte banks. The CPU data port
// stays on RAM port 0 and the audio read/modify/write path on port 1, so
// Quartus infers two dual port M10K memories instead of 262,144 flops.
wire        rr_cpu_write = cpu_write_commit && (cpu_write_addr == 9'h12d) &&
                            (regs[9'h12e] == 8'h80);
wire [1:0]  rr_cpu_we = rr_cpu_write ?
                        (rr_port_addr[0] ? 2'b10 : 2'b01) : 2'b00;
wire [15:0] rr_cpu_din = rr_port_addr[0] ? {cpu_write_data,8'h00} :
                                           {8'h00,cpu_write_data};
wire [15:0] rr_lo_cpu_q, rr_hi_cpu_q, rr_audio_q;
/* The upper CPU visible bank has no audio port consumer in the 0x2000 word
   MAME delay path; keep its parked dual port output explicit. */
/* verilator lint_off UNUSEDSIGNAL */
wire [15:0] rr_hi_audio_q;
/* verilator lint_on UNUSEDSIGNAL */
wire [12:0] rr_cpu_word_addr = rr_cpu_read_seen ? rr_cpu_addr_l[13:1] :
                                                  rr_port_addr[13:1];
wire [15:0] rr_cpu_q = rr_cpu_addr_l[14] ? rr_hi_cpu_q : rr_lo_cpu_q;
wire signed [15:0] rr_dout = rr_audio_q;

jtframe_dual_ram16 #(
    .AW           ( 13     ),
    .SIMHEXFILE_LO( REVTAB ),
    .SIMHEXFILE_HI( REVTAB ),
    .SYNFILE_LO   ( REVTAB ),
    .SYNFILE_HI   ( REVTAB )
) u_rram_lo (
    .clk0  ( clk           ),
    .data0 ( rr_cpu_din    ),
    .addr0 ( rr_cpu_word_addr ),
    .we0   ( rr_port_addr[14] ? 2'b00 : rr_cpu_we ),
    .q0    ( rr_lo_cpu_q   ),
    .clk1  ( clk           ),
    .data1 ( rr_din        ),
    .addr1 ( rr_we ? rr_addr : rd_addr ),
    .we1   ( rr_we ? 2'b11 : 2'b00 ),
    .q1    ( rr_audio_q    )
);

jtframe_dual_ram16 #(
    .AW           ( 13     ),
    .SIMHEXFILE_LO( REVTAB ),
    .SIMHEXFILE_HI( REVTAB ),
    .SYNFILE_LO   ( REVTAB ),
    .SYNFILE_HI   ( REVTAB )
) u_rram_hi (
    .clk0  ( clk           ),
    .data0 ( rr_cpu_din    ),
    .addr0 ( rr_cpu_word_addr ),
    .we0   ( rr_port_addr[14] ? rr_cpu_we : 2'b00 ),
    .q0    ( rr_hi_cpu_q   ),
    .clk1  ( clk           ),
    .data1 ( 16'h0000      ),
    .addr1 ( 13'd0         ),
    .we1   ( 2'b00         ),
    .q1    ( rr_hi_audio_q )
);

wire [15:0] rram_port_word = rr_cpu_q;
wire [7:0] rram_port_dout = rr_cpu_addr_l[0] ?
                              rram_port_word[15:8] :
                              rram_port_word[7:0];

// --- current channel L/R volume, Q16 ---
wire [16:0] vt   = {1'b0, voltab[w_vol]};
wire [16:0] pl   = pantab[w_pan];
wire [16:0] pr   = pantab[4'd14 - w_pan];
wire [33:0] lfull= vt * pl;
wire [33:0] rfull= vt * pr;
/* verilator lint_off UNUSEDSIGNAL */
wire [16:0] lfull_discarded_diag = {lfull[33], lfull[15:0]};
wire [16:0] rfull_discarded_diag = {rfull[33], rfull[15:0]};
/* verilator lint_on UNUSEDSIGNAL */
wire [16:0] lvol = lful_clamp(lfull[32:16]);
wire [16:0] rvol = lful_clamp(rfull[32:16]);
function [16:0] lful_clamp(input [16:0] v);
    lful_clamp = (v > 17'h1CCCC) ? 17'h1CCCC : v;   // VOL_CAP=1.8 in Q16
endfunction

// channel contribution in Q16, not truncated: w_val * vol. Rounded at the end.
wire signed [33:0] cprodL = $signed(w_val) * $signed({1'b0, lvol});
wire signed [33:0] cprodR = $signed(w_val) * $signed({1'b0, rvol});
wire signed [39:0] contribL = {{6{cprodL[33]}}, cprodL};
wire signed [39:0] contribR = {{6{cprodR[33]}}, cprodR};

// --- Reverb parameters of the current channel (MAME, fixed mode) ---
//   rdelta = ({base1[7],base1[6]} >> 3);  rdelta = (rdelta+revpos)&0x3fff;
//   widx   = (rdelta + revpos) & 0x1fff;  (revpos added TWICE: exact MAME quirk)
//   bval   = min(vol + base1[4], 255);    rbvol = (voltab[bval]*32768)>>16
//   rev_contrib = (int16)((cur_val * rbvol) >> 16), accumulated in rram[widx]
wire [15:0] rdelta_word = {regs[b1+9'd7], regs[b1+9'd6]};
/* verilator lint_off UNUSEDSIGNAL */
wire [2:0]  rdelta_discarded_diag = rdelta_word[2:0];
/* verilator lint_on UNUSEDSIGNAL */
wire [12:0] rrd  = rdelta_word[15:3];                            // 16b >>3 = 13b
wire [13:0] rd14 = ({1'b0,rrd} + {1'b0,reverb_pos}) & 14'h3fff;
wire [14:0] wsum = {1'b0,rd14} + {2'b0,reverb_pos};
/* verilator lint_off UNUSEDSIGNAL */
wire [1:0]  wsum_discarded_diag = wsum[14:13];
/* verilator lint_on UNUSEDSIGNAL */
wire [12:0] widx = wsum[12:0];                                    // &0x1fff
assign rd_addr = ((state == S_MIX) || (state == S_RVWR)) ?
                 widx : reverb_pos;
wire [8:0]  bsum = {1'b0,w_vol} + {1'b0, regs[b1+9'd4]};
wire [7:0]  bval = bsum[8] ? 8'd255 : bsum[7:0];                  // clamp 255
wire [15:0] rbvol = {1'b0, voltab[bval][15:1]};                   // voltab>>1
wire signed [32:0] rprod = $signed(w_val) * $signed({1'b0, rbvol});
/* verilator lint_off UNUSEDSIGNAL */
wire [16:0] rprod_discarded_diag = {rprod[32], rprod[15:0]};
/* verilator lint_on UNUSEDSIGNAL */
wire signed [15:0] rev_contrib = rprod[31:16];                    // (>>16) to int16

// channel base addresses
wire [23:0] delta_now = {regs[b1+9'd2], regs[b1+9'd1], regs[b1+9'd0]};
wire signed [31:0] delta_signed = regs[b2][5] ?
                                   -$signed({8'b0,delta_now}) :
                                    $signed({8'b0,delta_now});
// MAME k054539.cpp:195 switches on base2[0]&0xc: 0x0/0x4/0x8 are the three
// known formats; 0xc falls to `default:` at k054539.cpp:281-283, which performs
// no ROM read and no position advance, so the channel idles. type_now==2'd3
// encodes that no-op case; see S_LOAD/S_MIX below.
wire [1:0]  type_now  = (regs[b2] & 8'h0c)==8'h00 ? 2'd0 :
                        (regs[b2] & 8'h0c)==8'h04 ? 2'd1 :
                        (regs[b2] & 8'h0c)==8'h08 ? 2'd2 : 2'd3;

// UPDATE_AT_KEYON latch index: 3*ch + (addr[4:0]-0x0c). addr[4:2] is 3'b011 in
// that window, so the offset is simply addr[1:0].
wire [4:0] pl_idx = {2'b0,addr[7:5]} + {1'b0,addr[7:5],1'b0} + {3'b0,addr[1:0]};

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
function [3:0] pan_idx(input [7:0] p);
    if      (p >= 8'h81 && p <= 8'h8f) pan_idx = p[3:0] - 4'd1;
    else if (p >= 8'h11 && p <= 8'h1f) pan_idx = p[3:0] - 4'd1;
    else                               pan_idx = 4'd7;
endfunction

// current DPCM nibble, by position parity (nibble units)
wire [3:0] dnib = w_pos[0] ? rom_data[7:4] : rom_data[3:0];
wire signed [15:0] ds = dpcm_step(dnib);

// position advance, in w_pos units
wire [24:0] npos1 = w_reverse ? w_pos - 25'd1 : w_pos + 25'd1;
wire [24:0] npos2 = w_reverse ? w_pos - 25'd2 : w_pos + 25'd2;

// ---------------------------------------------------------------------------
// Output. The YM2151 aux stream is summed here because the board mixes it
// inside this chip (see the header). VOLSHIFT attenuates the aux leg only.
// ---------------------------------------------------------------------------
reg signed [15:0] pcm_l, pcm_r;
wire signed [15:0] aux_l_att = aux_l >>> VOLSHIFT;
wire signed [15:0] aux_r_att = aux_r >>> VOLSHIFT;
wire signed [16:0] sum_l = {pcm_l[15],pcm_l} + {aux_l_att[15],aux_l_att};
wire signed [16:0] sum_r = {pcm_r[15],pcm_r} + {aux_r_att[15],aux_r_att};

function signed [15:0] sat17(input signed [16:0] v);
    sat17 = (v >  17'sd32767) ?  16'sd32767 :
            (v < -17'sd32768) ? -16'sd32768 : v[15:0];
endfunction

assign left    = sat17(sum_l);
assign right   = sat17(sum_r);
assign st_dout = debug_bus[0] ? {4'd0, state} : active;

integer ci;
always @(posedge clk) begin
    if (rst) begin
        state <= S_IDLE; sample_cnt <= 0; ch <= 0;
        sample_rom_cs <= 0; sample_rom_addr <= 0;
        pcm_l <= 0; pcm_r <= 0; accL <= 0; accR <= 0;
        busy <= 1'b0;
        active <= 0; restart <= 0;
        cpu_write_pending <= 1'b0;
        cpu_write_addr <= 9'd0;
        cpu_write_data <= 8'd0;
        read_ptr <= 0;
        rb_pending <= 1'b0;
        rb_active <= 1'b0;
        rb_read_seen <= 1'b0;
        rb_data_valid <= 1'b0;
        rr_cpu_read_seen <= 1'b0;
        rr_cpu_data_valid <= 1'b0;
        rr_cpu_data <= 8'd0;
        rr_cpu_addr_l <= 15'd0;
        rb_addr_l <= 24'd0;
        rb_data <= 8'd0;
        reverb_pos <= 0; rr_we <= 0; rr_addr <= 0; rr_din <= 0;
        timer_cnt <= 13'd0; timer_state <= 1'b0; timer_armed <= 1'b0;
        for (ci=0; ci<8; ci=ci+1) begin
            cpos[ci] <= 0; cpfrac[ci] <= 0; cval[ci] <= 0; cpval[ci] <= 0;
        end
        for (ci=0; ci<24; ci=ci+1) pos_latch[ci] <= 0;
    end else begin
        busy <= rb_wait;
        if (cpu_write_active) begin
            cpu_write_pending <= 1'b1;
            cpu_write_addr <= addr;
            cpu_write_data <= din;
        end else begin
            cpu_write_pending <= 1'b0;
        end

        // ROM bank data port reads are serialized behind the playback
        // sequencer. The Z80 is held through `busy` while the shared SDRAM byte
        // is fetched; sample timing is paused only for this transaction.
        if (!rb_cpu_read) begin
            rb_read_seen <= 1'b0;
            rb_data_valid <= 1'b0;
            if (rb_pending && !rb_active)
                rb_pending <= 1'b0;
        end else if (!rb_read_seen) begin
            rb_read_seen <= 1'b1;
            if (!rb_pending && !rb_active) begin
                // Capture the byte address at the start of the CPU
                // transaction. The serial pointer is incremented on the same
                // clock edge below, so deriving the address later would skip
                // the byte being read.
                rb_pending <= 1'b1;
                rb_addr_l  <= {regs[9'h12e][6:0], read_ptr};
            end
        end

        // The dual port RAM presents the reverb data port byte one clock after
        // the CPU read begins. Hold the Z80 until that output is valid, just as
        // for a serialized ROM bank read.
        if (!rr_cpu_read) begin
            rr_cpu_read_seen <= 1'b0;
            rr_cpu_data_valid <= 1'b0;
        end else if (!rr_cpu_read_seen) begin
            rr_cpu_read_seen <= 1'b1;
            rr_cpu_data_valid <= 1'b0;
            rr_cpu_addr_l <= rr_port_addr;
        end else begin
            // Capture the registered RAM result before the live serial pointer
            // selects the following byte.
            rr_cpu_data <= rram_port_dout;
            rr_cpu_data_valid <= 1'b1;
        end
        // Use only idle slack for the CPU data port. The chip keeps its 48 kHz
        // stream running while this port is accessed, so a data port read must
        // never freeze the sample counter.
        if (rb_pending && !rb_active && (state == S_IDLE) &&
            (sample_cnt != 9'd0) && (sample_cnt < 9'd320)) begin
            rb_pending <= 1'b0;
            rb_active  <= 1'b1;
        end
        if (rb_active && rom_ok) begin
            rb_data       <= rom_data;
            rb_active     <= 1'b0;
            rb_data_valid <= 1'b1;
        end

        // Ordinary register storage is transparent for the duration of the
        // active low write enable. Position bytes are diverted to the
        // UPDATE_AT_KEYON latches until key-on release.
        if (cpu_write_active) begin
            if (addr == 9'h12f) begin
                // 0x22f D7 is transparent; D0/D1/D4/D5 commit below.
                regs[9'h12f][7] <= din[7];
            end else if (update_at_keyon && !addr[8] &&
                         (addr[4:0] >= 5'h0c) && (addr[4:0] <= 5'h0e)) begin
                pos_latch[pl_idx] <= din;
            end else if (addr[8] && (addr[7:4] == 4'h0) && addr[0]) begin
                // Odd channel control D0 is release latched; its D2/D4/D5
                // fields are transparent while the strobe is active.
                regs[addr] <= {din[7:1], regs[addr][0]};
            end else begin
                regs[addr] <= din;
            end
        end

        // The decapped start/stop block captures key-on at nKONWR release.
        if (cpu_write_commit) begin
            case (cpu_write_addr)
                9'h114: begin
                    // MAME suppresses all register updates while bit 7 of the
                    // global control is set. With UPDATE_AT_KEYON, copy the
                    // three latched position bytes atomically.
                    if (reg_updates) begin
                        active  <= active | cpu_write_data;
                        // Key-on restarts every selected voice, including one
                        // whose active bit is already set: voices are reused
                        // rapidly for event effects, and suppressing an
                        // active-to-active retrigger would leave the new
                        // position latch unconsumed and silence later SFX.
                        restart <= restart | cpu_write_data;
                    end
                    if (update_at_keyon) begin
                        for (ci=0; ci<8; ci=ci+1) begin
                            if (cpu_write_data[ci]) begin
                                regs[(ci*32)+32'd12] <= pos_latch[(ci*3)+0];
                                regs[(ci*32)+32'd13] <= pos_latch[(ci*3)+1];
                                regs[(ci*32)+32'd14] <= pos_latch[(ci*3)+2];
                            end
                        end
                    end
                end
                // SiliconRE shows 0x22f bits 0/1/4/5 captured on the rising
                // edge of its decoded active low write strobe. D7 stays
                // transparent above and D2/D3/D6 are unimplemented.
                9'h12f: begin
                    regs[9'h12f][0] <= cpu_write_data[0];
                    regs[9'h12f][1] <= cpu_write_data[1];
                    regs[9'h12f][4] <= cpu_write_data[4];
                    regs[9'h12f][5] <= cpu_write_data[5];
                    // MAME k054539.cpp:444-448: disabling the timer output
                    // (bit 5 low) forces m_timer_state back to 0 immediately.
                    if (!cpu_write_data[5]) timer_state <= 1'b0;
                end
                // MAME k054539.cpp:421-429 (0x227): every write reprograms the
                // period and resets the toggle state, regardless of bit 5.
                9'h127: begin
                    timer_cnt   <= 13'd0;
                    timer_state <= 1'b0;
                    timer_armed <= 1'b1;
                end
                default: begin
                    if (cpu_write_addr[8] &&
                        (cpu_write_addr[7:4] == 4'h0) && cpu_write_addr[0])
                        regs[cpu_write_addr][0] <= cpu_write_data[0];
                end
            endcase
        end
        // Key-off is level visible for the full decoded write strobe in the
        // decapped start/stop block; release must not apply it a second time.
        if (cpu_write_active) begin
            case (addr)
                9'h115: if (reg_updates) active <= active & ~din;
                9'h12c: if (reg_updates) active <= din;
                default: ;
            endcase
        end

        // 0x22d advances the serial pointer for both writes and reads; 0x22e
        // selects a bank and resets the pointer. ROM bank reads go through the
        // streaming ROM path; the reverb bank answers from the RAM above.
        if (cpu_write_commit && (cpu_write_addr == 9'h12d))
            read_ptr <= read_ptr + 17'd1;
        else if ((rb_cpu_read && !rb_read_seen) ||
                 (rr_cpu_read && !rr_cpu_read_seen))
            read_ptr <= read_ptr + 17'd1;
        else if (cpu_write_active && (addr == 9'h12e))
            read_ptr <= 17'd0;

        if (cen) begin
            sample_cnt <= (sample_cnt == 9'd383) ? 9'd0 : sample_cnt + 9'd1;
            // Hold the SDRAM request until rom_ok. `cen` runs at 18.432 MHz
            // against a 48 MHz clock, so an unconditional clear here would
            // drop the request several clocks before the shared SDRAM could
            // answer it, and the *_ok handshake would never complete. The
            // capture states re-assert it explicitly for the next byte.
            sample_rom_cs <= (state==S_R8 || state==S_R16L ||
                              state==S_R16H || state==S_RD) && !rom_ok;
            rr_we  <= 1'b0;   // no reverb write by default (rom_cs pattern)

            // Programmable timer divider: advances once per audio sample tick,
            // independent of the PCM sequencer below.
            if (timer_armed && (sample_cnt == 9'd0)) begin
                if (timer_sum >= {1'b0, TIMER_THRESH}) begin
                    timer_cnt <= timer_sum[12:0] - TIMER_THRESH;
                    if (regs[9'h12f][5]) timer_state <= ~timer_state;
                end else begin
                    timer_cnt <= timer_sum[12:0];
                end
            end

            case (state)
            S_IDLE: if ((sample_cnt == 9'd0) && !rb_active) begin
                        ch <= 0;
                        if (regs[9'h12f][0]) begin
                            state <= S_REVRD;   // rd_addr=reverb_pos, data ready in S_REVRD
                        end else begin
                            accL <= 0; accR <= 0; state <= S_LOAD;   // chip off: no reverb
                        end
                    end

            // ---------- reverb: feedback @reverb_pos seeds accL/accR, clears the slot ----------
            S_REVRD: begin
                accL <= { {8{rr_dout[15]}}, rr_dout, 16'b0 };   // rbase[revpos]<<16 (Q40, sext)
                accR <= { {8{rr_dout[15]}}, rr_dout, 16'b0 };
                rr_addr <= reverb_pos; rr_din <= 16'sd0; rr_we <= 1'b1;   // rram[reverb_pos] <= 0
                state <= S_LOAD;
            end

            // ---------- load channel parameters and set the accumulator up ----------
            S_LOAD: begin
                if (!active[ch] || !regs[9'h12f][0]) begin
                    state <= S_NEXT;
                end else begin
                    w_vol    <=  regs[b1+9'd3];
                    w_loop   <= {regs[b1+9'ha], regs[b1+9'h9], regs[b1+9'h8]};
                    w_loopen <=  regs[b2+9'd1][0];
                    w_pan    <=  pan_idx(regs[b1+9'd5]);
                    w_type   <=  type_now;
                    w_reverse<=  regs[b2][5];
                    // pos/frac base in byte units. DPCM is scaled to nibbles.
                    if (type_now == 2'd2) begin
                        // DPCM: pos<<1, frac<<1, carry fix, then += delta
                        if (restart[ch]) begin
                            w_pos   <= {regs[b1+9'he], regs[b1+9'hd], regs[b1+9'hc]} << 1;
                            w_pfrac <= delta_signed;                     // (0<<1)=0, +/-delta
                            w_val   <= 0; w_pval <= 0;
                            // Do not lose a same-clock CPU retrigger while the
                            // sequencer consumes the old request.
                            restart[ch] <= keyon_retrigger[ch];
                        end else begin
                            // frac<<1; if bit16 -> pos|1, frac&0xffff; then +delta
                            w_pos   <= ({cpos[ch],1'b0}) | (cpfrac[ch][15] ? 25'd1 : 25'd0);
                            w_pfrac <= $signed({15'b0, cpfrac[ch], 1'b0}) + delta_signed
                                       - (cpfrac[ch][15] ? 32'h0001_0000 : 32'd0);
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end
                    end else begin
                        if (restart[ch]) begin
                            w_pos   <= {1'b0, regs[b1+9'he], regs[b1+9'hd], regs[b1+9'hc]};
                            w_pfrac <= delta_signed;
                            w_val   <= 0; w_pval <= 0;
                            restart[ch] <= keyon_retrigger[ch];
                        end else if (type_now == 2'd3) begin
                            // MAME default branch (sample type 0xc): the switch
                            // body never runs, so `cur_pfrac += delta` never
                            // executes and cur_pos/cur_val stay untouched.
                            w_pos   <= {1'b0, cpos[ch]};
                            w_pfrac <= $signed({16'b0, cpfrac[ch]});
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end else begin
                            w_pos   <= {1'b0, cpos[ch]};
                            w_pfrac <= $signed({16'b0, cpfrac[ch]}) + delta_signed;
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end
                    end
                    // type 0xc (2'd3) never fetches ROM data nor advances the
                    // position: go straight to the mix/writeback step.
                    state <= (type_now == 2'd3) ? S_MIX : S_ACC;
                end
            end

            // ---------- while(cur_pfrac & ~0xffff): advance and read ----------
            S_ACC: begin
                if (|w_pfrac[31:16]) begin
                    // Forward playback subtracts one whole fraction; reverse
                    // playback adds it back while the signed fraction is
                    // negative, matching MAME's fdelta/pdelta pair.
                    w_pfrac <= w_pfrac +
                               (w_reverse ? 32'sh0001_0000 : -32'sh0001_0000);
                    case (w_type)
                    2'd0: begin // 8 bit: +1 byte
                        w_pos    <= npos1;
                        sample_rom_addr <= npos1[23:0];
                        sample_rom_cs   <= 1'b1; state <= S_R8;
                    end
                    2'd1: begin // 16 bit: +2 bytes (low then high)
                        w_pos    <= npos2;
                        sample_rom_addr <= npos2[23:0];
                        sample_rom_cs   <= 1'b1; state <= S_R16L;
                    end
                    default: begin // DPCM: +1 nibble; read byte pos>>1
                        w_pos    <= npos1;
                        sample_rom_addr <= npos1[24:1];
                        sample_rom_cs   <= 1'b1; state <= S_RD;
                    end
                    endcase
                end else begin
                    state <= S_MIX;
                end
            end

            // ---------- 8 bit capture (waits for rom_ok: SDRAM data ready) ----------
            S_R8: if (rom_ok) begin
                w_pval <= w_val;
                if (rom_data == 8'h80) begin
                    if (w_loopen) begin
                        w_pos <= {1'b0, w_loop}; sample_rom_addr <= w_loop; sample_rom_cs <= 1'b1; state <= S_R8;
                    end else begin
                        // A key-on queued after this channel's S_LOAD belongs to
                        // the replacement voice. Do not let the old in-flight
                        // sample's terminator retire it before the next S_LOAD
                        // consumes the pending restart.
                        if (reg_updates && !restart[ch] && !keyon_retrigger[ch]) active[ch] <= 1'b0;
                        w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_val <= $signed({rom_data, 8'h00}); state <= S_ACC;
                end
            end

            // ---------- 16 bit capture (low byte then high), rom_ok on each ----------
            S_R16L: if (rom_ok) begin
                w_lo     <= rom_data;
                sample_rom_addr <= w_pos[23:0] + 24'd1;   // high byte
                sample_rom_cs   <= 1'b1; state <= S_R16H;
            end
            S_R16H: if (rom_ok) begin
                w_pval <= w_val;
                if ({rom_data, w_lo} == 16'h8000) begin
                    if (w_loopen) begin
                        w_pos <= {1'b0, w_loop}; sample_rom_addr <= w_loop; sample_rom_cs <= 1'b1; state <= S_R16L;
                    end else begin
                        if (reg_updates && !restart[ch] && !keyon_retrigger[ch]) active[ch] <= 1'b0;
                        w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_val <= $signed({rom_data, w_lo}); state <= S_ACC;
                end
            end

            // ---------- DPCM capture (waits for rom_ok) ----------
            S_RD: if (rom_ok) begin
                if (rom_data == 8'h88) begin
                    if (w_loopen) begin
                        w_pos <= {w_loop, 1'b0}; sample_rom_addr <= w_loop; sample_rom_cs <= 1'b1; state <= S_RD;
                    end else begin
                        if (reg_updates && !restart[ch] && !keyon_retrigger[ch]) active[ch] <= 1'b0;
                        w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_pval <= w_val;
                    w_val  <= clip16( {{8{w_val[15]}}, w_val} + {{8{ds[15]}}, ds} );
                    state  <= S_ACC;
                end
            end

            // ---------- mix and writeback (DPCM is scaled back down) ----------
            S_MIX: begin
                accL <= accL + contribL;
                accR <= accR + contribR;
                if (w_type == 2'd2) begin
                    cpos[ch]   <= w_pos[24:1];                             // pos>>1
                    cpfrac[ch] <= w_pfrac[16:1] | (w_pos[0] ? 16'h8000 : 16'h0000);
                end else begin
                    cpos[ch]   <= w_pos[23:0];
                    cpfrac[ch] <= w_pfrac[15:0];
                end
                // The silicon mirrors the current sample position into the
                // channel's 0x0c..0x0e bytes while register updates are
                // enabled. This is observable through the Z80 readback path and
                // is required by diagnostics.
                // A CPU key-on may commit a new latched start on this exact
                // clock edge. Give that command priority over the retiring
                // voice's live position mirror; otherwise S_LOAD consumes
                // restart from the just overwritten end address and the
                // replacement effect is silent or malformed.
                if (reg_updates && !restart[ch] && !keyon_retrigger[ch]) begin
                    regs[b1+9'h0c] <= (w_type == 2'd2) ? w_pos[8:1]  : w_pos[7:0];
                    regs[b1+9'h0d] <= (w_type == 2'd2) ? w_pos[16:9] : w_pos[15:8];
                    regs[b1+9'h0e] <= (w_type == 2'd2) ? w_pos[24:17] : w_pos[23:16];
                end
                cval[ch]  <= w_val;
                cpval[ch] <= w_pval;
                state <= S_RVWR;        // rd_addr=widx issued in S_MIX, ready in S_RVWR
            end

            // ---------- reverb RMW: rram[widx] += rev_contrib (int16, wraps) ----------
            S_RVWR: begin
                rr_addr <= widx;                   // write address (ch not yet advanced)
                rr_din  <= rr_dout + rev_contrib;  // rr_dout = old rram[widx]
                rr_we   <= 1'b1;                   // commits during S_NEXT
                state   <= S_NEXT;
            end

            S_NEXT: begin
                if (ch == 3'd7) state <= S_DONE;
                else begin ch <= ch + 3'd1; state <= S_LOAD; end
            end

            S_DONE: begin  // Q16 -> integer (>>16) and clamp, as MAME
                pcm_l <= clip16($signed(accL[39:16]));
                pcm_r <= clip16($signed(accR[39:16]));
                if (regs[9'h12f][0]) reverb_pos <= reverb_pos + 13'd1;  // frozen if chip off
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end
end

endmodule
