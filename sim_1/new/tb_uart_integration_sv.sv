`timescale 1ns / 1ps

// 1. Interface: 하드웨어 포트 정의
interface uart_if (input logic clk);
    logic       rst;
    logic       iReqWatchReport, iReqSr04Report, iReqTempReport, iReqHumReport;
    logic [6:0] iWatchHour, iWatchMin, iWatchSec;
    logic [9:0] iSr04DistanceCm; logic iSr04DistanceValid;
    logic [7:0] iDhtHumInt, iDhtTempInt; logic iDhtDataValid;
    logic       oTx; 
endinterface

// 2. Transaction: 물리적 한계치 반영
class transaction;
    typedef enum {WATCH, SR04, TEMP, HUM} scenario_t; 
    rand scenario_t scenario;
    rand bit [6:0] hour, min, sec;
    rand bit [9:0] distance; // [수정] SR04 실제 측정 범위 반영
    rand bit [7:0] temp_val, hum_val;

    constraint c_limit { 
        hour inside {[0:23]}; min inside {[0:59]}; sec inside {[0:59]}; 
        // [수정] HC-SR04의 유효 측정 거리인 2~400cm로 제한하여 현실성 부여
        distance inside {[2:400]}; 
        temp_val inside {[0:99]}; hum_val inside {[0:99]}; 
    }
endclass

// 3. Generator: 시나리오별 트랜잭션 생성 및 전달
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
            if (!tr.randomize() with { scenario == sc_type; }) 
                $error("[Gen] Randomization Failed!");
            g2d.put(tr); g2s.put(tr);
            @(next); // 스코어보드 채점 완료 대기
        end
    endtask
endclass

// 4. Driver: DUT에 물리 신호 인가
class driver;
    transaction tr;
    mailbox #(transaction) g2d;
    virtual uart_if vif;

    function new(mailbox#(transaction) g2d, virtual uart_if vif);
        this.g2d = g2d; this.vif = vif;
    endfunction

    task preset();
        vif.rst = 1;
        vif.iReqWatchReport = 0; vif.iReqSr04Report = 0;
        vif.iReqTempReport = 0;  vif.iReqHumReport = 0;
        vif.iSr04DistanceValid = 0; vif.iDhtDataValid = 0;
        repeat(10) @(posedge vif.clk);
        vif.rst = 0;
    endtask

    task run();
        forever begin
            g2d.get(tr);
            @(posedge vif.clk); #1;
            
            // 시나리오별 요청 신호 활성화
            case(tr.scenario)
                transaction::WATCH: vif.iReqWatchReport = 1;
                transaction::SR04 : vif.iReqSr04Report  = 1;
                transaction::TEMP : vif.iReqTempReport  = 1;
                transaction::HUM  : vif.iReqHumReport   = 1;
            endcase

            vif.iWatchHour = tr.hour; vif.iWatchMin = tr.min; vif.iWatchSec = tr.sec;
            vif.iSr04DistanceCm = tr.distance; vif.iSr04DistanceValid = 1;
            vif.iDhtTempInt = tr.temp_val; vif.iDhtHumInt = tr.hum_val; vif.iDhtDataValid = 1;
            
            repeat(2) @(posedge vif.clk); #1;
            {vif.iReqWatchReport, vif.iReqSr04Report, vif.iReqTempReport, vif.iReqHumReport} = 4'b0000;
        end
    endtask
endclass

// 5. Monitor: oTx 비트스트림 디코딩 (9600 Baud)
class monitor;
    mailbox #(byte) m2s;
    virtual uart_if vif;

    function new(mailbox#(byte) m2s, virtual uart_if vif);
        this.m2s = m2s; this.vif = vif;
    endfunction

    task run();
        byte rcv_char;
        forever begin
            @(negedge vif.oTx); // Start Bit 감지
            #52083; // 0.5 bit 지점 (Center Sampling)
            if (vif.oTx == 0) begin
                for (int i=0; i<8; i++) begin
                    #104166; // 1 bit 간격 이동
                    rcv_char[i] = vif.oTx; 
                end
                #104166; // Stop bit 확인을 위한 이동
                m2s.put(rcv_char);
            end
        end
    endtask
endclass

// 6. Scoreboard: 기대값(Golden) 생성 및 비교
class scoreboard;
    mailbox #(transaction) g2s;
    mailbox #(byte) m2s;
    event next;
    transaction tr;
    byte act_char;
    string golden_str, act_str;
    int errors;

    function new(mailbox#(transaction) g2s, mailbox#(byte) m2s, event next);
        this.g2s = g2s; this.m2s = m2s; this.next = next;
    endfunction

    task run();
        forever begin
            g2s.get(tr);
            errors = 0; act_str = "";
            
            // 기대 문자열 포맷팅 (\r\n 포함)
            case(tr.scenario)
                transaction::WATCH: golden_str = $sformatf("%c%cWATCH %02d:%02d:%02d%c%c", 8'h0D, 8'h0A, tr.hour, tr.min, tr.sec, 8'h0D, 8'h0A);
                transaction::SR04 : golden_str = $sformatf("%c%cSR04 %03dcm%c%c", 8'h0D, 8'h0A, tr.distance, 8'h0D, 8'h0A);
                transaction::TEMP : golden_str = $sformatf("%c%cTEMP %02dC%c%c", 8'h0D, 8'h0A, tr.temp_val, 8'h0D, 8'h0A);
                transaction::HUM  : golden_str = $sformatf("%c%cHUM %02d%%%c%c", 8'h0D, 8'h0A, tr.hum_val, 8'h0D, 8'h0A);
            endcase

            $display("\n[Scoreboard] Expected: %p", golden_str);

            for (int i = 0; i < golden_str.len(); i++) begin
                fork
                    begin
                        m2s.get(act_char);
                        act_str = $sformatf("%s%c", act_str, act_char); 
                        if (golden_str[i] != act_char) errors++;
                    end
                    begin
                        #10000000; // 타임아웃 10ms (UART 전송 시간 고려)
                        disable fork;
                    end
                join_any
            end

            $display("[Scoreboard] Actual  : %p", act_str);
            if (act_str == "") $display("[FAIL] Timeout! No Data.");
            else if (errors == 0 && act_str.len() == golden_str.len()) $display("[PASS] Perfect Match!");
            else $display("[FAIL] Mismatch! Errors: %0d", errors);
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
    virtual uart_if vif;

    function new(virtual uart_if vif);
        this.vif = vif;
        g2d = new(); g2s = new(); m2s = new();
        gen = new(g2d, g2s, next); drv = new(g2d, vif);
        mon = new(m2s, vif); scb = new(g2s, m2s, next);
    endfunction

    task run();
        fork drv.run(); mon.run(); scb.run(); join_none
        drv.preset();
        $display("\n>>> STARTING VERIFICATION (Distance Limited 2-400cm) <<<");
        gen.run(1, transaction::WATCH);
        gen.run(1, transaction::SR04); 
        gen.run(1, transaction::TEMP); 
        gen.run(1, transaction::HUM); 
        #50_000_000; 
        $display("\n>>> ALL TESTS FINISHED <<<");
        $finish;
    endtask
endclass

module tb_uart_integration_sv();
    logic clk = 0;
    always #5 clk = ~clk;
    uart_if if_inst(clk);

    // RTL 컴포넌트들 간의 내부 신호
    logic wTick16x;
    logic [7:0] wTxData, wTxFifoData;
    logic wTxValid, wTxFifoPop, wTxFifoEmpty, wTxFifoFull, wTxBusy;
    logic wTxPathBusy;

    assign wTxFifoPop = (!wTxFifoEmpty) && (!wTxBusy);
    assign wTxPathBusy = wTxBusy || wTxFifoFull;

    baud_rate_gen #(.CLK_FREQ(100_000_000), .BAUD_RATE(9600)) u_baud (
        .iClk(clk), .iRst(if_inst.rst), .oTick16x(wTick16x)
    );

    uart_ascii_sender u_sender (
        .iClk(clk), .iRst(if_inst.rst), .iTxBusy(wTxPathBusy),
        .oTxData(wTxData), .oTxValid(wTxValid),
        .iLoopData(8'h00), .iLoopValid(1'b0),
        .iReqWatchReport(if_inst.iReqWatchReport), .iReqSr04Report(if_inst.iReqSr04Report),
        .iReqTempReport(if_inst.iReqTempReport), .iReqHumReport(if_inst.iReqHumReport),
        .iWatchHour(if_inst.iWatchHour), .iWatchMin(if_inst.iWatchMin), .iWatchSec(if_inst.iWatchSec),
        .iSr04DistanceCm(if_inst.iSr04DistanceCm), .iSr04DistanceValid(if_inst.iSr04DistanceValid),
        .iDhtHumInt(if_inst.iDhtHumInt), .iDhtTempInt(if_inst.iDhtTempInt), .iDhtDataValid(if_inst.iDhtDataValid)
    );

    Fifo #(.P_DATA_WIDTH(8), .P_FIFO_DEPTH(16)) u_fifo (
        .iClk(clk), .iRst(if_inst.rst),
        .iPush(wTxValid && !wTxFifoFull), .iPushData(wTxData), .oFull(wTxFifoFull),
        .iPop(wTxFifoPop), .oPopData(wTxFifoData), .oEmpty(wTxFifoEmpty)
    );

    uart_tx u_tx (
        .iClk(clk), .iRst(if_inst.rst), .iTick16x(wTick16x),
        .iData(wTxFifoData), .iValid(wTxFifoPop),
        .oTx(if_inst.oTx), .oBusy(wTxBusy) 
    );

    environment env;
    initial begin env = new(if_inst); env.run(); end
endmodule