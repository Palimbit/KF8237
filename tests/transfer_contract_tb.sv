// SPDX-License-Identifier: MIT
// Public-interface tests: Intel 8237A 231466-005, active cycles and registers.
`timescale 1ns/1ps
module transfer_contract_tb;
    reg clock=0; always #100 clock=~clock;
    reg reset=0,chip_select_n=1,ready=1,hold_acknowledge=0;
    reg [3:0] dma_request=0,address_in=0;
    reg [7:0] data_bus_in=0;
    reg io_read_n_in=1,io_write_n_in=1,end_of_process_n_in=1;
    wire [7:0] data_bus_out;
    wire [15:0] address_out;
    wire [3:0] dma_acknowledge;
    wire io_read_n_out,io_read_n_io,io_write_n_out,io_write_n_io;
    wire end_of_process_n_out,output_highst_address,hold_request;
    wire address_enable,address_strobe,memory_read_n,memory_write_n;
    KF8237 dut(.*);
    reg [7:0] memory[65536];
    integer checks=0,failures=0,cases=0,completed=0,tc_pulses=0;
    integer active_ch=0,active_type=1,active_mode=2,drop_after=0,eop_after=0;
    reg decrement=0,monitor=0;
    reg [15:0] expected_address=0,pulse_address=0;
    reg [7:0] pulse_data=0;
    reg prev_write=1,prev_io_write=1,prev_eop=1;
    reg write_pending=0,io_write_pending=0;
    reg [7:0] value; reg [15:0] word_value;

    function automatic [7:0] pattern(input integer n);
        pattern=8'(n*37+8'h5b);
    endfunction
    task check(input bit ok,input string label);
        checks++; if(!ok) begin failures++; $display("FAIL case %0d: %s",cases,label); end
    endtask
    task tick(input integer n);
        repeat(n) begin @(posedge clock); #10; end
    endtask
    task fresh;
        monitor=0; reset=1; chip_select_n=1; dma_request=0;
        hold_acknowledge=0; ready=1; end_of_process_n_in=1;
        io_read_n_in=1; io_write_n_in=1; tick(4); reset=0; tick(4);
        completed=0;tc_pulses=0;drop_after=0;eop_after=0;write_pending=0;io_write_pending=0;
        prev_write=1;prev_io_write=1;prev_eop=1;
    endtask
    task wr(input reg[3:0] p,input reg[7:0] d);
        address_in=p;data_bus_in=d;chip_select_n=0;tick(1);
        io_write_n_in=0;tick(3);io_write_n_in=1;tick(2);chip_select_n=1;tick(2);
    endtask
    task rd(input reg[3:0] p,output reg[7:0] d);
        address_in=p;chip_select_n=0;tick(1);io_read_n_in=0;tick(3);
        d=data_bus_out;io_read_n_in=1;tick(2);chip_select_n=1;tick(2);
    endtask
    task word_wr(input reg[3:0] p,input reg[15:0] d);
        wr(12,0);wr(p,d[7:0]);wr(p,d[15:8]);
    endtask
    task word_rd(input reg[3:0] p,output reg[15:0] d);
        reg[7:0] lo,hi;
        wr(12,0);rd(p,lo);rd(p,hi);d={hi,lo};
    endtask
    task setup(input integer ch,input integer kind,input integer mode,
               input reg[15:0] start,input integer length,input bit dec,input bit auto_init);
        reg[15:0] a;
        cases++;fresh();active_ch=ch;active_type=kind;active_mode=mode;
        decrement=dec;expected_address=start;
        word_wr(4'(ch*2),start);word_wr(4'(ch*2+1),16'(length-1));
        wr(11,8'((mode<<6)|(dec<<5)|(auto_init<<4)|(kind<<2)|ch));
        wr(10,8'(ch));
        a=start;
        for(integer n=0;n<length;n++) begin
            memory[a]=(kind==2)?pattern(n):8'hce;
            a=dec?a-16'd1:a+16'd1;
        end
        monitor=1;
    endtask
    task start_service;
        dma_request=4'(1<<active_ch);
        for(integer n=0;n<20 && !hold_request;n++)tick(1);
        check(hold_request,"HRQ after DREQ");tick(3);
        check(memory_read_n && memory_write_n && io_read_n_out && io_write_n_out,
              "no strobes before HLDA");
        hold_acknowledge=1;
    endtask
    task await_release;
        for(integer n=0;n<200 && hold_request;n++)tick(1);
        check(!hold_request,"service releases HRQ");
        hold_acknowledge=0;dma_request=0;tick(6);
    endtask
    task verify_end(input reg[15:0] addr,input reg[15:0] count,input bit tc);
        word_rd(4'(active_ch*2),word_value);check(word_value===addr,"final address");
        word_rd(4'(active_ch*2+1),word_value);check(word_value===count,"final count");
        rd(8,value);check(value[active_ch]===tc,"channel EOP status");
        rd(8,value);check(value[3:0]===0,"status read clears TC bits");
    endtask
    // Observe each write pulse once. READY stretches a pulse; it must not
    // create repeated memory or peripheral commits. Memory isn't DUT state.
    always @(posedge clock) begin
        #2;
        if(monitor && !reset) begin
            if(!memory_write_n && prev_write) begin
                write_pending=1;pulse_address=address_out;pulse_data=pattern(completed);
                check(!io_read_n_out && memory_read_n && io_write_n_out,"I/O to memory strobes");
                check(address_out===expected_address,"write sequence address");
                check(dma_acknowledge==~4'(1<<active_ch),"write DACK channel");
                if(drop_after==completed+1)dma_request=0;
                if(eop_after==completed+1)end_of_process_n_in=0;
            end
            if(write_pending && !memory_write_n)
                check(address_out===pulse_address,"address stable during memory write");
            if(memory_write_n && !prev_write && write_pending) begin
                memory[pulse_address]=pulse_data;write_pending=0;completed++;
                expected_address=decrement?expected_address-16'd1:expected_address+16'd1;
            end
            if(!io_write_n_out && prev_io_write) begin
                io_write_pending=1;pulse_address=address_out;pulse_data=memory[address_out];
                check(!memory_read_n && memory_write_n && io_read_n_out,"memory to I/O strobes");
                check(address_out===expected_address,"read sequence address");
                check(pulse_data===pattern(completed),"peripheral receives memory data");
                check(dma_acknowledge==~4'(1<<active_ch),"read DACK channel");
                if(drop_after==completed+1)dma_request=0;
                if(eop_after==completed+1)end_of_process_n_in=0;
            end
            if(io_write_pending && !io_write_n_out)
                check(address_out===pulse_address,"address stable during peripheral write");
            if(io_write_n_out && !prev_io_write && io_write_pending) begin
                io_write_pending=0;completed++;
                expected_address=decrement?expected_address-16'd1:expected_address+16'd1;
            end
            if(!end_of_process_n_out && prev_eop)tc_pulses++;
            if(active_type==0)
                check(memory_read_n && memory_write_n && io_read_n_out && io_write_n_out,
                      "verify leaves all data strobes inactive");
        end
        prev_write=memory_write_n;prev_io_write=io_write_n_out;prev_eop=end_of_process_n_out;
    end

    initial begin
        // Four channels, both byte directions, carry/borrow and 16-bit wrap.
        for(integer ch=0;ch<4;ch++)for(integer kind=1;kind<=2;kind++)
        for(integer dec=0;dec<2;dec++)begin
            setup(ch,kind,2,dec?16'h0001:16'hfffe,4,1'(dec),0);
            drop_after=1;start_service();await_release();
            check(completed==4,"block continues after DREQ withdrawal");
            check(tc_pulses==1,"one terminal count output pulse");
            verify_end(dec?16'hfffd:16'h0002,16'hffff,1);
            if(kind==1)begin
                for(integer n=0;n<4;n++)
                    check(memory[16'(dec?1-n:65534+n)]===pattern(n),"memory byte payload");
            end
            // EOP without autoinit sets the channel mask. A fresh DREQ must wait.
            dma_request=4'(1<<ch);tick(20);
            check(!hold_request,"TC automatically masks non-autoinit channel");
        end
        // Count zero is exactly one byte, not zero or 65536.
        setup(2,1,2,16'h1234,1,0,0);drop_after=1;start_service();await_release();
        check(completed==1 && tc_pulses==1,"count zero gives one transfer");
        verify_end(16'h1235,16'hffff,1);
        // READY must stretch the active write, retaining its address and count.
        setup(1,1,2,16'h12fe,3,0,0);ready=0;drop_after=1;start_service();
        for(integer n=0;n<20 && memory_write_n;n++)tick(1);
        check(!memory_write_n,"write starts before READY");tick(10);
        check(completed==0 && !memory_write_n,"READY prevents completion");
        ready=1;await_release();check(completed==3,"exact commits after READY");
        verify_end(16'h1301,16'hffff,1);
        // Autoinit reloads base and leaves channel enabled for another service.
        setup(3,1,2,16'h2040,2,0,1);drop_after=1;start_service();await_release();
        check(completed==2,"first autoinit block");verify_end(16'h2040,1,1);
        completed=0;tc_pulses=0;expected_address=16'h2040;
        start_service();await_release();check(completed==2,"second autoinit block without programming");
        verify_end(16'h2040,1,1);
        // Verify ignores READY and performs no payload transfer.
        setup(0,0,2,16'h3210,3,0,0);ready=0;start_service();
        for(integer n=0;n<30 && dma_acknowledge==4'hf;n++)tick(1);
        dma_request=0;await_release();
        check(completed==0 && tc_pulses==1,"verify ignores READY and reaches TC");
        verify_end(16'h3213,16'hffff,1);
        // Demand pauses on DREQ withdrawal, retaining progress for resume.
        for(integer kind=1;kind<=2;kind++) begin
            setup(1,kind,0,16'h45fe,5,0,0);drop_after=1;start_service();await_release();
            check(completed==1 && tc_pulses==0,"demand pauses after one byte");
            verify_end(16'h45ff,3,0);drop_after=0;
            start_service();await_release();check(completed==5,"demand resumes remaining bytes");
            verify_end(16'h4603,16'hffff,1);
        end
        // A held DREQ in single mode needs a new grant for every byte.
        setup(2,1,1,16'h50fe,3,0,0);drop_after=3;
        dma_request=4'(1<<active_ch);
        for(integer n=0;n<3;n++)begin
            for(integer w=0;w<20 && !hold_request;w++)tick(1);
            check(hold_request,"single mode repeated DREQ");hold_acknowledge=1;
            for(integer w=0;w<30 && hold_request;w++)tick(1);
            check(!hold_request,"single mode releases after byte");
            check(completed==n+1,"single mode exactly one byte per grant");
            tick(8);check(!hold_request,"wait for HLDA low before new HRQ");
            hold_acknowledge=0;tick(2);
        end
        dma_request=0;tick(6);verify_end(16'h5101,16'hffff,1);
        // External EOP during a byte ends the block after that byte, even
        // with remaining count. Autoinit decides whether to restore the base.
        for(integer ai=0;ai<2;ai++)begin
            setup(3,1,2,16'h6000,8,0,1'(ai));drop_after=1;eop_after=2;
            start_service();await_release();end_of_process_n_in=1;
            check(completed==2,"external EOP ends current byte");
            check(tc_pulses==0,"external EOP isn't internal terminal count");
            verify_end(ai?16'h6000:16'h6002,ai?16'd7:16'd5,1);
        end
        $display("TRANSFER CONTRACT: cases=%0d checks=%0d failures=%0d",cases,checks,failures);
        if(failures)$fatal(1,"transfer contract failed");
        $display("PASS transfer contract");$finish;
    end
    initial begin #100000000;$fatal(1,"watchdog");end
endmodule
