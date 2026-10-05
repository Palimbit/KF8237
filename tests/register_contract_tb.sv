// SPDX-License-Identifier: MIT
// Black-box register checks against Intel 8237A 231466-005, pp. 7-10.
`timescale 1ns/1ps
module register_contract_tb;
    reg clock = 0;
    always #100 clock = ~clock;
    reg reset = 0, chip_select_n = 1, ready = 1, hold_acknowledge = 0;
    reg [3:0] dma_request = 0, address_in = 0;
    reg [7:0] data_bus_in = 0;
    reg io_read_n_in = 1, io_write_n_in = 1, end_of_process_n_in = 1;
    wire [7:0] data_bus_out;
    wire [15:0] address_out;
    wire [3:0] dma_acknowledge;
    wire io_read_n_out, io_read_n_io, io_write_n_out, io_write_n_io;
    wire end_of_process_n_out, output_highst_address, hold_request;
    wire address_enable, address_strobe, memory_read_n, memory_write_n;
    KF8237 dut(.*);
    integer checks = 0, failures = 0;
    reg [7:0] value;
    reg [15:0] word_value, expected[8];

    task tick(input integer n);
        repeat(n) begin @(posedge clock); #1; end
    endtask
    task check(input bit ok, input string label);
        checks++;
        if (!ok) begin failures++; $display("FAIL: %s", label); end
    endtask
    task fresh;
        chip_select_n=1; io_read_n_in=1; io_write_n_in=1; dma_request=0;
        reset=1; tick(4); reset=0; tick(4);
    endtask
    // Hold the address through the trailing write edge. No internal DUT probes.
    task wr(input reg [3:0] port, input reg [7:0] data);
        address_in=port; data_bus_in=data; chip_select_n=0;
        tick(1); io_write_n_in=0; tick(3); io_write_n_in=1;
        tick(2); chip_select_n=1; tick(2);
    endtask
    task rd(input reg [3:0] port, output reg [7:0] data);
        address_in=port; chip_select_n=0;
        tick(1); io_read_n_in=0; tick(3); data=data_bus_out;
        io_read_n_in=1; tick(2); chip_select_n=1; tick(2);
    endtask
    task word_wr(input reg [3:0] port, input reg [15:0] data);
        wr(12,0); wr(port,data[7:0]); wr(port,data[15:8]);
    endtask
    task word_rd(input reg [3:0] port, output reg [15:0] data);
        reg [7:0] lo, hi;
        wr(12,0); rd(port,lo); rd(port,hi); data={hi,lo};
    endtask
    task no_transfer;
        check(dma_acknowledge===4'hf && memory_read_n===1'b1 &&
              memory_write_n===1'b1, "no transfer without HLDA");
    endtask

    initial begin
        fresh(); rd(8,value); check(value===0,"reset status");
        rd(13,value); check(value===0,"reset temporary register");
        // Distinct bytes and channels detect byte-order and register alias errors.
        for(integer round=0;round<4;round++) begin
            for(integer p=0;p<8;p++) begin
                expected[p]=16'h91e3 ^ (16'(p)*16'h1327) ^ (16'(round)*16'h55aa);
                word_wr(4'(p),expected[p]);
            end
            for(integer p=0;p<8;p++) begin
                word_rd(4'(p),word_value);
                check(word_value===expected[p],$sformatf("round %0d register %0d",round,p));
            end
        end
        // The first/last flip-flop is shared across registers, reads and writes.
        word_wr(0,16'h1234); word_wr(7,16'habcd);
        wr(12,0); rd(0,value); check(value===8'h34,"shared pointer low");
        rd(7,value); check(value===8'hab,"shared pointer high across channels");
        wr(12,0); rd(0,value); wr(7,8'h56);
        word_rd(7,word_value); check(word_value===16'h56cd,"shared read/write pointer");
        wr(12,0); rd(0,value); wr(12,8'hff); rd(0,value);
        check(value===8'h34,"clear pointer ignores data");
        // Unselected writes must not alter a register or advance the pointer.
        wr(12,0); address_in=0; data_bus_in=8'hff;
        io_write_n_in=0; tick(3); io_write_n_in=1; tick(3);
        rd(0,value); check(value===8'h34,"unselected write isolation");

        // Every mask vector against every individual hardware request.
        for(integer mask=0;mask<16;mask++) begin
            for(integer ch=0;ch<4;ch++) begin
                fresh(); wr(15,8'(mask)); dma_request=4'(1<<ch); tick(12);
                check(hold_request===((mask & (1<<ch))==0),
                      $sformatf("mask=%0h DREQ=%0d",mask,ch));
                no_transfer();
            end
        end
        for(integer ch=0;ch<4;ch++) begin
            fresh(); wr(10,8'(ch)); dma_request=4'(1<<ch); tick(12);
            check(hold_request===1'b1,"single-channel unmask"); no_transfer();
            fresh(); wr(15,0); wr(10,8'(ch+4)); dma_request=4'(1<<ch); tick(12);
            check(hold_request===1'b0,"single-channel mask");
            fresh(); wr(14,8'ha5); dma_request=4'(1<<ch); tick(12);
            check(hold_request===1'b1,"clear all masks enables DREQ");
            fresh(); wr(11,8'(8'h80+ch)); wr(9,8'(ch+4)); tick(12);
            check(hold_request===1'b1,"software block request is non-maskable");
            wr(14,0); rd(8,value);
            check(value[4+ch]===1'b1,"clear masks preserves software request");
            wr(13,8'hff); dma_request=0; tick(8); rd(8,value);
            check(value===0 && hold_request===0,"master clear removes requests");
            dma_request=4'(1<<ch); tick(12);
            check(hold_request===0,"master clear masks all channels");
        end
        fresh(); wr(8,4); wr(15,0); dma_request=1; tick(12);
        check(hold_request===0,"command disables controller");
        wr(8,0); tick(12); check(hold_request===1,"command re-enables controller");
        no_transfer();
        $display("REGISTER CONTRACT: checks=%0d failures=%0d",checks,failures);
        if(failures!=0) $fatal(1,"register contract failed");
        $display("PASS register contract"); $finish;
    end
    initial begin #10000000; $fatal(1,"watchdog"); end
endmodule
