`timescale 1ns / 1ps

// 1. Interface: RTL 포트 이름(iPush, iPop, oPopData)에 맞춰 수정 
interface fifo_interface (input logic clk);
    logic       rst;
    logic [7:0] iPushData;
    logic       iPush;
    logic       iPop;
    logic [7:0] oPopData;
    logic       oFull;
    logic       oEmpty;
endinterface

// 2. Transaction: 시나리오(NORMAL, FULL, EMPTY, PUSH_POP) 정의
class transaction;
    rand bit [7:0] wdata;
    rand bit       push;
    rand bit       pop;
    
    typedef enum {NORMAL, FULL_STRESS, EMPTY_STRESS, PUSH_POP_STRESS} scenario_t;
    scenario_t scenario;
    
    logic [7:0] rdata;
    logic       full;
    logic       empty;

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
        $display("%t : [%s] scenario=%s | push=%b data=%h full=%b | pop=%b rdata=%h empty=%b", 
                 $time, name, scenario.name(), push, wdata, full, pop, rdata, empty);
    endfunction
endclass

// 3. Generator: 시나리오별 트랜잭션 생성 및 피드백 루프
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
            tr.randomize() with { scenario == sc_type; };
            gen2drv_mbox.put(tr);
            @(gen_next_ev); 
        end
    endtask
endclass

// 4. Driver: 인터페이스를 통해 RTL에 데이터 주입 (Left side of U)
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
            #1; // Hold time
            fifo_if.iPush     = tr.push;
            fifo_if.iPushData = tr.wdata;
            fifo_if.iPop      = tr.pop;
        end
    endtask
endclass

// 5. Monitor: RTL 출력 샘플링 (Right side of U)
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
            @(negedge fifo_if.clk); // 안정적인 데이터 샘플링 시점
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

// 6. Scoreboard: Queue 기반 정답지 비교
class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_ev;
    logic [7:0] fifo_queue[$:15]; // 모델링용 큐 (Depth 16)
    logic [7:0] exp_data;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_ev);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_ev  = gen_next_ev;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            
            // Write 검증 (Overflow 방지 로직 포함)
            if (tr.push && !tr.full) begin
                fifo_queue.push_front(tr.wdata);
            end

            // Read 검증 (Underflow 방지 및 데이터 비교)
            if (tr.pop && !tr.empty) begin
                exp_data = fifo_queue.pop_back();
                if (exp_data === tr.rdata)
                    $display("[PASS] %t | Exp: %h, Got: %h", $time, exp_data, tr.rdata);
                else
                    $error("[FAIL] %t | Exp: %h, Got: %h", $time, exp_data, tr.rdata);
            end
            
            ->gen_next_ev;
        end
    endtask
endclass

// 7. Environment & Top: 시나리오 순차 실행
module tb_fifo_sv;
    logic clk = 0;
    always #5 clk = ~clk;

    fifo_interface if_inst(clk);
    
    // 사용자의 최신 Fifo.v 인스턴스화 및 연결 
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

    // 실행 로직
    initial begin
        automatic environment env = new(if_inst);
        env.run_all();
    end
endmodule

// (환경 클래스는 위 코드의 run() 로직을 포함하여 별도 정의하거나 통합 가능)
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

    task run_all();
        fork drv.run(); mon.run(); scb.run(); join_none
        drv.preset();
        $display("\n>>> START SCENARIOS <<<");
        gen.run(20, transaction::NORMAL);       // 일반
        gen.run(20, transaction::FULL_STRESS);  // Overflow
        gen.run(20, transaction::EMPTY_STRESS); // Underflow
        gen.run(20, transaction::PUSH_POP_STRESS); // 동시 동작
        $display("\n>>> ALL SCENARIOS DONE <<<");
        #100 $finish;
    endtask
endclass