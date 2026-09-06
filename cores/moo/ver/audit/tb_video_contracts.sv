`timescale 1ns/1ps

// Diagnostic counterexamples for AUD-01/AUD-02 in doc/audit.md.
// Real core modules; synthetic bus/video inputs, no game ROM or display.
module tb_video_contracts;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg [2:0] phase = 0;
    always @(posedge clk) phase <= phase == 3'd5 ? 3'd0 : phase + 3'd1;
    wire pxl_cen = phase == 0;
    reg hs = 0;
    wire [8:0] hdump, vdump;
    wire [7:0] red, green, blue;
    reg reg_cs = 0;
    reg cpu_we = 0;
    reg [12:1] cpu_addr = 0;
    reg [15:0] cpu_data = 0;
    integer failures = 0;

    jtmoo_scroll u_scroll(
        .rst(rst), .clk(clk), .pxl_cen(pxl_cen),
        .lhbl(1'b1), .lvbl(1'b1), .hs(hs), .vs(1'b0),
        .hdump(hdump), .vdump(vdump),
        .reg_cs(1'b0), .gfx_cs(1'b0), .vram_cs(1'b0), .rmrd_cs(1'b0),
        .cpu_we(1'b0), .cpu_addr(12'd0), .cpu_dsn(2'b11), .cpu_dout(16'd0),
        .lyrf_data(32'd0), .lyra_data(32'd0), .lyrb_data(32'd0), .lyrc_data(32'd0),
        .lyrf_ok(1'b1), .lyra_ok(1'b1), .lyrb_ok(1'b1), .lyrc_ok(1'b1),
        .ioctl_addr(15'd0), .ioctl_ram(1'b0), .gfx_en(4'd0), .debug_bus(8'd0)
    );

    jtmoo_colmix u_colmix(
        .rst(rst), .clk(clk), .pxl_cen(pxl_cen), .lhbl(1'b1), .lvbl(1'b1),
        .pcu_cs(1'b0), .reg_cs(reg_cs), .pal_cs(1'b0),
        .cpu_we(cpu_we), .cpu_dout(cpu_data), .cpu_dsn(2'b00), .cpu_addr(cpu_addr),
        .lyrf_pxl(12'd0), .lyra_pxl(12'd0), .lyrb_pxl(12'd0), .lyrc_pxl(12'd0),
        .lyro_pxl(9'd0), .lyro_pri(5'd0), .shadow(2'd0),
        .red(red), .green(green), .blue(blue),
        .ioctl_addr(13'd0), .ioctl_ram(1'b0), .debug_bus(8'd0)
    );

    task write_k338(input [3:0] addr, input [15:0] data);
        @(negedge clk);
        cpu_addr = {8'd0, addr}; cpu_data = data; reg_cs = 1; cpu_we = 1;
        @(negedge clk);
        reg_cs = 0; cpu_we = 0;
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;
        hs = 1;
        repeat (48) @(negedge clk);
        hs = 0;
        if (vdump != 9'd1) begin
            $display("AUD-01 FAIL: one eight-pixel HS pulse advances vdump to %0d, expected 1", vdump);
            failures = failures + 1;
        end

        write_k338(4'd0, 16'h0012);
        write_k338(4'd1, 16'h3456);
        write_k338(4'd11, 16'h00ff);
        write_k338(4'd15, 16'h0001);
        repeat (96) @(negedge clk);
        // Existing brightness arithmetic: floor(channel * 255 / 256).
        if ({red,green,blue} != 24'h113355) begin
            $display("AUD-02 FAIL: background RGB=%06x, expected 113355", {red,green,blue});
            failures = failures + 1;
        end
        if (failures != 0) $fatal(1, "%0d video contract failures", failures);
        $display("PASS: video boundary contracts");
        $finish;
    end
endmodule
