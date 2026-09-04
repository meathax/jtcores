/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 4-8-2024 */

// AUDIO=1 applies the volume register to the audio pair
module jt054321 #(parameter AUDIO=0)(
    input            rst,
    input            clk,
    input      [3:0] maddr,
    input      [7:0] mdout,
    output reg [7:0] mdin,
    input            mwe,

    input      [1:0] saddr,
    input      [7:0] sdout,
    output reg [7:0] sdin,
    input            swe,

    // Z80 bus control
    input            snd_on,
    input            siorq_n,
    output reg       int_n,

    input signed [15:0] snd_l,
    input signed [15:0] snd_r,
    output signed [15:0] out_l,
    output signed [15:0] out_r
);

reg [7:0] snd_latch[0:2];
// reg [7:0] active;
reg [5:0] vol;
reg       sndon_l;

always @(posedge clk) begin
    if( rst ) begin
        int_n   <= 1;
        sndon_l <= 0;
    end else begin
        sndon_l <= snd_on;
        if( snd_on && !sndon_l ) int_n<=0;
        if( !siorq_n ) int_n <= 1;
    end
end

always @(posedge clk) begin
    if(rst) begin
        vol          <= 0;
        // active    <= 0;
        snd_latch[0] <= 0;
        snd_latch[1] <= 0;
        snd_latch[2] <= 0;
    end else begin
        // Main CPU
        if(mwe) case(maddr)
            // 0: active <= mdout;
            2: vol <= 0;
            3: if( ~&vol ) vol <= vol+6'd1;
            6: snd_latch[0] <= mdout;
            7: snd_latch[1] <= mdout;
        endcase
        mdin <= maddr==4'd10 ? snd_latch[2] : 8'd0;
        // Sound CPU
        if(swe && saddr==0 ) snd_latch[2] <= sdout;
        sdin <= saddr[0] ? snd_latch[1] : snd_latch[0];
    end
end

// gain = 2^((vol-40)/10), MAME k054321.cpp, clamped at unity
reg [8:0] gain;

always @(*) begin
    case(vol)
        6'd0 : gain = 9'd16;   6'd1 : gain = 9'd17;   6'd2 : gain = 9'd18;
        6'd3 : gain = 9'd20;   6'd4 : gain = 9'd21;   6'd5 : gain = 9'd23;
        6'd6 : gain = 9'd24;   6'd7 : gain = 9'd26;   6'd8 : gain = 9'd28;
        6'd9 : gain = 9'd30;   6'd10: gain = 9'd32;   6'd11: gain = 9'd34;
        6'd12: gain = 9'd37;   6'd13: gain = 9'd39;   6'd14: gain = 9'd42;
        6'd15: gain = 9'd45;   6'd16: gain = 9'd49;   6'd17: gain = 9'd52;
        6'd18: gain = 9'd56;   6'd19: gain = 9'd60;   6'd20: gain = 9'd64;
        6'd21: gain = 9'd69;   6'd22: gain = 9'd74;   6'd23: gain = 9'd79;
        6'd24: gain = 9'd84;   6'd25: gain = 9'd91;   6'd26: gain = 9'd97;
        6'd27: gain = 9'd104;  6'd28: gain = 9'd111;  6'd29: gain = 9'd119;
        6'd30: gain = 9'd128;  6'd31: gain = 9'd137;  6'd32: gain = 9'd147;
        6'd33: gain = 9'd158;  6'd34: gain = 9'd169;  6'd35: gain = 9'd181;
        6'd36: gain = 9'd194;  6'd37: gain = 9'd208;  6'd38: gain = 9'd223;
        6'd39: gain = 9'd239;
        default: gain = 9'd256;
    endcase
end

generate
    if( AUDIO==1 ) begin : g_audio
        reg signed [25:0] mul_l, mul_r;
        always @(posedge clk) begin
            if( rst ) begin
                mul_l <= 26'd0;
                mul_r <= 26'd0;
            end else begin
                mul_l <= snd_l * $signed({1'b0,gain});
                mul_r <= snd_r * $signed({1'b0,gain});
            end
        end
        assign out_l = mul_l[23:8];
        assign out_r = mul_r[23:8];
    end else begin : g_bypass
        assign out_l = snd_l;
        assign out_r = snd_r;
    end
endgenerate

endmodule
