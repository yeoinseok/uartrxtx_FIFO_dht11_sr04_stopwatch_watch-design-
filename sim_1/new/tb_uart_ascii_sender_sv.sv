`timescale 1ns / 1ps

// 1. Interface
interface ascii_if (input logic clk);
    logic       rst;
    logic       iTxBusy;
    logic [7:0] oTxData;
    logic       oTxValid;
    logic       iReqWatchReport, iReqSr04Report, iReqTempReport, iReqHumReport;
    logic [6:0] iWatchHour, iWatchMin, iWatchSec;
    logic [9:0] iSr04DistanceCm;
    logic       iSr04DistanceValid;
    logic [7:0] iDhtHumInt, iDhtTempInt;
    logic       iDhtDataValid;
endinterface

// 2. Transaction (온습도 범위 0~99 제한 추가)
class transaction;
    typedef enum {WATCH, SR04, TEMP, HUM} scenario_t; 
    rand scenario_t scenario;
    rand bit [6:0] hour, min, sec;
    rand bit [9:0] distance;
    rand bit [7:0] temp_val, hum_val;

    constraint c_limit { 
        hour inside {[0:23]}; min inside {[0:59]}; sec inside {[0:59]}; 
        distance inside {[0:999]};
        temp_val inside {[0:99]}; hum_val inside {[0:99]}; // 두 자리 숫자
    }
endclass

// 3. Generator
class generator;
    transaction tr;
    mailbox #(transaction) g2d, g2s;
    event next;
    function new(mailbox#(transaction) g2d, mailbox#(transaction) g2s, event next);
        this.g2d = g2d; this.g2s = g2s; this.next = next;
    endfunction
    task run(int count, transaction::scenario_t sc_type);
        repeat (count) begin
            tr = new();
            tr.randomize() with { scenario == sc_type; };
            g2d.put(tr); g2s.put(tr);
            @(next);
        end
    endtask
endclass

// 4. Driver: 4가지 요청 모두 핸들링
class driver;
    transaction tr;
    mailbox #(transaction) g2d;
    virtual ascii_if vif;
    function new(mailbox#(transaction) g2d, virtual ascii_if vif);
        this.g2d = g2d; this.vif = vif;
    endfunction
    task preset();
        vif.rst = 1; vif.iTxBusy = 0;
        vif.iReqWatchReport = 0; vif.iReqSr04Report = 0;
        vif.iReqTempReport = 0;  vif.iReqHumReport = 0;
        repeat(10) @(posedge vif.clk);
        vif.rst = 0;
    endtask
    task run();
        fork
            forever begin
                g2d.get(tr);
                @(posedge vif.clk); #1;
                
                if (tr.scenario == transaction::WATCH)      vif.iReqWatchReport = 1;
                else if (tr.scenario == transaction::SR04)  vif.iReqSr04Report  = 1;
                else if (tr.scenario == transaction::TEMP)  vif.iReqTempReport  = 1;
                else                                        vif.iReqHumReport   = 1;

                vif.iWatchHour = tr.hour; vif.iWatchMin = tr.min; vif.iWatchSec = tr.sec;
                vif.iSr04DistanceCm = tr.distance; vif.iSr04DistanceValid = 1;
                vif.iDhtTempInt = tr.temp_val; vif.iDhtHumInt = tr.hum_val; vif.iDhtDataValid = 1;
                
                repeat(2) @(posedge vif.clk); #1;
                vif.iReqWatchReport = 0; vif.iReqSr04Report = 0;
                vif.iReqTempReport = 0;  vif.iReqHumReport = 0;
            end
            forever begin
                @(posedge vif.clk);
                if (vif.oTxValid) begin
                    #1; vif.iTxBusy = 1;
                    repeat(3) @(posedge vif.clk);
                    #1; vif.iTxBusy = 0;
                end
            end
        join_none
    endtask
endclass

// 5. Monitor
class monitor;
    mailbox #(byte) m2s;
    virtual ascii_if vif;
    function new(mailbox#(byte) m2s, virtual ascii_if vif);
        this.m2s = m2s; this.vif = vif;
    endfunction
    task run();
        forever begin
            @(posedge vif.clk);
            if (vif.oTxValid) m2s.put(vif.oTxData);
        end
    endtask
endclass

// 6. Scoreboard: TEMP와 HUM 정답지 완벽 추가
class scoreboard;
    mailbox #(transaction) g2s;
    mailbox #(byte) m2s;
    event next;
    transaction tr;
    byte act_char;
    string golden_str;
    string act_str;
    int errors;

    function new(mailbox#(transaction) g2s, mailbox#(byte) m2s, event next);
        this.g2s = g2s; this.m2s = m2s; this.next = next;
    endfunction

    task run();
        forever begin
            g2s.get(tr);
            errors = 0; act_str = "";
            
            // RTL 로직에 맞춘 4가지 시나리오 정답지 생성
            if (tr.scenario == transaction::WATCH)
                golden_str = $sformatf("%c%cWATCH %02d:%02d:%02d%c%c", 8'h0D, 8'h0A, tr.hour, tr.min, tr.sec, 8'h0D, 8'h0A);
            else if (tr.scenario == transaction::SR04)
                golden_str = $sformatf("%c%cSR04 %03dcm%c%c", 8'h0D, 8'h0A, tr.distance, 8'h0D, 8'h0A);
            else if (tr.scenario == transaction::TEMP)
                golden_str = $sformatf("%c%cTEMP %02dC%c%c", 8'h0D, 8'h0A, tr.temp_val, 8'h0D, 8'h0A);
            else // HUM (%%를 써야 문자 '%'로 출력됨)
                golden_str = $sformatf("%c%cHUM %02d%%%c%c", 8'h0D, 8'h0A, tr.hum_val, 8'h0D, 8'h0A);

            $display("\n[Scoreboard] Expected: %p", golden_str);

            for (int i = 0; i < golden_str.len(); i++) begin
                fork
                    begin
                        m2s.get(act_char);
                        act_str = $sformatf("%s%c", act_str, act_char); 
                        if (golden_str[i] != act_char) errors++;
                    end
                    begin
                        #100000; disable fork;
                    end
                join_any
            end

            $display("[Scoreboard] Actual  : %p", act_str);
            if (act_str == "") $display("[FAIL] Timeout!");
            else if (errors == 0 && act_str.len() == golden_str.len()) $display("[PASS] Message Match!");
            else $display("[FAIL] Message Mismatch! Errors: %0d", errors);
            ->next;
        end
    endtask
endclass

// 7. Environment & 8. Top Module
class environment;
    generator gen; driver drv; monitor mon; scoreboard scb;
    mailbox #(transaction) g2d, g2s;
    mailbox #(byte) m2s;
    event next;
    virtual ascii_if vif;

    function new(virtual ascii_if vif);
        this.vif = vif;
        g2d = new(); g2s = new(); m2s = new();
        gen = new(g2d, g2s, next); drv = new(g2d, vif);
        mon = new(m2s, vif); scb = new(g2s, m2s, next);
    endfunction

    task run();
        fork drv.run(); mon.run(); scb.run(); join_none
        drv.preset();
        $display("\n>>> STARTING VALIDATION <<<");
        // 4가지 시나리오 모두 실행!
        gen.run(1, transaction::WATCH);
        gen.run(1, transaction::SR04); 
        gen.run(1, transaction::TEMP); 
        gen.run(1, transaction::HUM); 
        #10000;
        $display("\n>>> ALL TESTS FINISHED <<<");
        $finish;
    endtask
endclass

module tb_uart_ascii_sender_sv();
    logic clk = 0;
    always #5 clk = ~clk;
    ascii_if if_inst(clk);
    
    uart_ascii_sender dut (
        .iClk(clk), .iRst(if_inst.rst), .iTxBusy(if_inst.iTxBusy),
        .oTxData(if_inst.oTxData), .oTxValid(if_inst.oTxValid),
        .iLoopData(8'h00), .iLoopValid(1'b0),
        .iReqWatchReport(if_inst.iReqWatchReport), .iReqSr04Report(if_inst.iReqSr04Report),
        .iReqTempReport(if_inst.iReqTempReport), .iReqHumReport(if_inst.iReqHumReport),
        .iWatchHour(if_inst.iWatchHour), .iWatchMin(if_inst.iWatchMin), .iWatchSec(if_inst.iWatchSec),
        .iSr04DistanceCm(if_inst.iSr04DistanceCm), .iSr04DistanceValid(if_inst.iSr04DistanceValid),
        .iDhtHumInt(if_inst.iDhtHumInt), .iDhtTempInt(if_inst.iDhtTempInt), .iDhtDataValid(if_inst.iDhtDataValid)
    );
    
    environment env;
    initial begin env = new(if_inst); env.run(); end
endmodule