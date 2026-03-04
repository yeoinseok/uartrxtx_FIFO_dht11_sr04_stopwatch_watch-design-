`timescale 1ns / 1ps

// 1. Interface: RTL 포트와 1:1 매칭
interface fifo_interface (input logic clk);
    logic       rst;
    logic [7:0] iPushData;
    logic       iPush;
    logic       iPop;
    logic [7:0] oPopData;
    logic       oFull;
    logic       oEmpty;
endinterface

// 2. Transaction: 데이터 및 시나리오 정의
class transaction;
    rand bit [7:0] wdata;
    rand bit       push;
    rand bit       pop;
    
    typedef enum {NORMAL, FULL_STRESS, EMPTY_STRESS, PUSH_POP_STRESS} scenario_t;
    // [핵심 수정] rand 추가: 이 변수가 랜덤하게 변해야 제약 조건이 동작함
    rand scenario_t scenario; 
    
    logic [7:0] rdata;
    logic       full;
    logic       empty;

    // 시나리오 유도 제약 조건
    constraint c_scenario {
        if (scenario == FULL_STRESS) {
            push dist {1 := 90, 0 := 10}; pop == 0;
        } else if (scenario == EMPTY_STRESS) {
            push == 0; pop dist {1 := 90, 0 := 10};
        } else if (scenario == PUSH_POP_STRESS) {
            push == 1; pop == 1;
        } else {
            push dist {1 := 50, 0 := 50}; pop dist {1 := 50, 0 := 50};
        }
    }

    function void display(string name);
        $display("%t : [%s] %s | push=%b data=%h full=%b | pop=%b rdata=%h empty=%b", 
                  $time, name, scenario.name(), push, wdata, full, pop, rdata, empty);
    endfunction
endclass

// 3. Generator: 트랜잭션 생성 및 시나리오 주입
class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event gen_next_ev;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_ev);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_ev  = gen_next_ev;
    endfunction

    task run(int count, transaction::scenario_t sc_type);
        repeat (count) begin
            tr = new();
            // scenario 변수가 rand이므로 이제 randomize()가 실패하지 않습니다.
            if (!tr.randomize() with { scenario == sc_type; }) begin
                $error("Randomization failed at %t", $time);
            end
            gen2drv_mbox.put(tr);
            @(gen_next_ev); 
        end
    endtask
endclass

// 4. Driver: 신호 주입
class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual fifo_interface fifo_if;

    function new(mailbox#(transaction) gen2drv_mbox, virtual fifo_interface fifo_if);
        this.gen2drv_mbox = gen2drv_mbox;
        this.fifo_if = fifo_if;
    endfunction

    task preset();
        fifo_if.rst = 1;
        fifo_if.iPush = 0; fifo_if.iPop = 0; fifo_if.iPushData = 0;
        repeat(3) @(negedge fifo_if.clk);
        fifo_if.rst = 0;
    endtask

    task run();
        forever begin
            gen2drv_mbox.get(tr);
            @(posedge fifo_if.clk);
            #1; // Hold time 고려
            fifo_if.iPush     = tr.push;
            fifo_if.iPushData = tr.wdata;
            fifo_if.iPop      = tr.pop;
        end
    endtask
endclass

// 5. Monitor: 신호 관찰
class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    virtual fifo_interface fifo_if;

    function new(mailbox#(transaction) mon2scb_mbox, virtual fifo_interface fifo_if);
        this.mon2scb_mbox = mon2scb_mbox;
        this.fifo_if = fifo_if;
    endfunction

    task run();
        forever begin
            tr = new();
            @(negedge fifo_if.clk); 
            tr.push  = fifo_if.iPush;
            tr.wdata = fifo_if.iPushData;
            tr.pop   = fifo_if.iPop;
            tr.rdata = fifo_if.oPopData;
            tr.full  = fifo_if.oFull;
            tr.empty = fifo_if.oEmpty;
            mon2scb_mbox.put(tr);
        end
    endtask
endclass

// 6. Scoreboard: 큐 기반 검증
class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_ev;
    logic [7:0] fifo_queue[$:15]; 
    logic [7:0] exp_data;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_ev);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_ev  = gen_next_ev;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            
            if (tr.push && !tr.full) begin
                fifo_queue.push_front(tr.wdata);
            end

            if (tr.pop && !tr.empty) begin
                exp_data = fifo_queue.pop_back();
                if (exp_data === tr.rdata)
                    $display("[PASS] %t | Data Match: %h", $time, tr.rdata);
                else
                    $error("[FAIL] %t | Expected: %h, Got: %h", $time, exp_data, tr.rdata);
            end
            
            ->gen_next_ev;
        end
    endtask
endclass

// 7. Environment: 계층 통합
class environment;
    generator gen; driver drv; monitor mon; scoreboard scb;
    mailbox #(transaction) g2d, m2s;
    event next;
    virtual fifo_interface v_if;

    function new(virtual fifo_interface v_if);
        this.v_if = v_if;
        g2d = new(); m2s = new();
        gen = new(g2d, next); drv = new(g2d, v_if);
        mon = new(m2s, v_if); scb = new(m2s, next);
    endfunction

    task run();
        fork
            drv.run();
            mon.run();
            scb.run();
        join_none

        drv.preset();
        
        $display("\n>>> STARTING SCENARIOS <<<");
        gen.run(15, transaction::NORMAL);
        gen.run(20, transaction::FULL_STRESS);  
        gen.run(20, transaction::EMPTY_STRESS); 
        gen.run(20, transaction::PUSH_POP_STRESS); 
        
        #100 $display(">>> ALL TESTS COMPLETED <<<");
        $finish;
    endtask
endclass

// 8. Top Module
module tb_fifo_sv;
    logic clk = 0; // 요청하신 대로 clk 이름 유지
    always #5 clk = ~clk;

    fifo_interface if_inst(clk);
    
    Fifo #(
        .P_DATA_WIDTH(8),
        .P_FIFO_DEPTH(16)
    ) dut (
        .iClk(clk),
        .iRst(if_inst.rst),
        .iPush(if_inst.iPush),
        .iPushData(if_inst.iPushData),
        .oFull(if_inst.oFull),
        .iPop(if_inst.iPop),
        .oPopData(if_inst.oPopData),
        .oEmpty(if_inst.oEmpty)
    );

    environment env;
    initial begin
        env = new(if_inst);
        env.run();
    end
endmodule