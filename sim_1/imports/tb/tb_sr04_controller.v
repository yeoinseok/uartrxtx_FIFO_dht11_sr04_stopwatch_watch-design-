// /*
// [TB_INFO_START]
// Name: tb_sr04_controller
// Target: sr04_controller
// Role: Testbench for SR04 Ultrasonic Controller
// Scenario:
//   - Generates 1us tick pulse from system clock
//   - Simulates Echo return signal with variable duration in microseconds
// CheckPoint:
//   - Verifies Trigger pulse generation (10us)
//   - Verifies Distance calculation based on echo width
//   - Checks flag assertions for valid measurement
// [TB_INFO_END]
// */

 `timescale 1ns / 1ps

module tb_sr04_controller;
  initial begin
    $dumpfile("tb_sr04_controller.vcd");
    $dumpvars(0, tb_sr04_controller);
  end

  localparam integer CLK_PERIOD_NS = 10;   // 100MHz
  localparam integer CLK_PER_US    = 100;  // 1us = 100 cycles @100MHz

  reg iClk;
  reg iRst;
  reg iEcho;
  reg iStart;
  reg iTickUs;
  reg [7:0] rTickDiv;

  wire oTrig;
  wire [9:0] oDistanceCm;
  wire oDistanceValid;

  // 1MHz test clock model:
  // 1 cycle = 1us (easy to reason about pulse widths).
  sr04_controller #(
    .TRIG_US(10)
  ) dut (
    .iClk(iClk),
    .iRst(iRst),
    .iTickUs(iTickUs),
    .iEcho(iEcho),
    .iStart(iStart),
    .oTrig(oTrig),
    .oDistanceCm(oDistanceCm),
    .oDistanceValid(oDistanceValid)
  );

  // 100MHz system clock
  always #(CLK_PERIOD_NS/2) iClk = ~iClk;

  // 1us tick pulse: high for one iClk cycle.
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rTickDiv <= 8'd0;
      iTickUs  <= 1'b0;
    end else begin
      if (rTickDiv == CLK_PER_US - 1) begin
        rTickDiv <= 8'd0;
        iTickUs  <= 1'b1;
      end else begin
        rTickDiv <= rTickDiv + 1'b1;
        iTickUs  <= 1'b0;
      end
    end
  end

  task wait_us(input integer n_us);
    integer k;
    begin
      for (k = 0; k < n_us; k = k + 1) begin
        @(posedge iClk);
        while (iTickUs !== 1'b1) @(posedge iClk);
      end
    end
  endtask

  task pulse_start_req;
    begin
      @(posedge iClk);
      iStart <= 1'b1;
      @(posedge iClk);
      iStart <= 1'b0;
    end
  endtask

  task send_echo_high_us(input integer n_us);
    begin
      @(negedge iClk);
      iEcho = 1'b1;
      wait_us(n_us);
      @(negedge iClk);
      iEcho = 1'b0;
    end
  endtask

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;
    iEcho = 1'b0;
    iStart = 1'b0;
    iTickUs = 1'b0;
    rTickDiv = 8'd0;

    repeat (5) @(posedge iClk);
    iRst = 1'b0;

    // Start one measurement manually.
    pulse_start_req();

    // Wait until oTrig phase finishes and controller waits for iEcho.
    wait (oTrig == 1'b1);
    wait (oTrig == 1'b0);
    wait_us(20);

    // Echo high width = 580us -> around 10cm (580/58).
    send_echo_high_us(580);

    wait (oDistanceValid == 1'b1);
    if ((oDistanceCm < 9) || (oDistanceCm > 11)) begin
      $display("sr04 distance out of expected range: %0d", oDistanceCm);
      $finish;
    end

    wait_us(20);
    $display("tb_sr04_controller finished: oDistanceCm=%0d", oDistanceCm);
    $finish;
  end

endmodule


















//글리치 3번 5ns 10ns 15ns 발생
//거리가 너무 멀거나 너무가깝거나 

// `timescale 1ns / 1ps

// module tb_sr04_controller;
//     initial begin
//         $dumpfile("tb_sr04_controller.vcd");
//         $dumpvars(0, tb_sr04_controller);
//     end

//     localparam integer CLK_PERIOD_NS = 10;   // 100MHz
//     localparam integer CLK_PER_US    = 100;  // 1us = 100 cycles @100MHz

//     reg iClk;
//     reg iRst;
//     reg iEcho;
//     reg iStart;
//     reg iTickUs;
//     reg [7:0] rTickDiv;

//     wire oTrig;
//     wire [9:0] oDistanceCm;
//     wire oDistanceValid;

//     // DUT Instance: 파라미터를 명시하지 않으면 코드의 기본값(30,000us)이 사용됩니다.
//     sr04_controller #(
//         .TRIG_US(10)
//         // .WAIT_ECHO_TIMEOUT_US(30000) <- 기본값이 30ms라면 생략 가능
//     ) dut (
//         .iClk(iClk),
//         .iRst(iRst),
//         .iTickUs(iTickUs),
//         .iEcho(iEcho),
//         .iStart(iStart),
//         .oTrig(oTrig),
//         .oDistanceCm(oDistanceCm),
//         .oDistanceValid(oDistanceValid)
//     );

//     // 100MHz Clock Generation
//     always #(CLK_PERIOD_NS / 2) iClk = ~iClk;

//     // 1us Tick Generation
//     always @(posedge iClk or posedge iRst) begin
//         if (iRst) begin
//             rTickDiv <= 8'd0;
//             iTickUs  <= 1'b0;
//         end else begin
//             if (rTickDiv == CLK_PER_US - 1) begin
//                 rTickDiv <= 8'd0;
//                 iTickUs  <= 1'b1;
//             end else begin
//                 rTickDiv <= rTickDiv + 1'b1;
//                 iTickUs  <= 1'b0;
//             end
//         end
//     end

//     // Task: n_us만큼 대기
//     task wait_us(input integer n_us);
//         integer k;
//         begin
//             for (k = 0; k < n_us; k = k + 1) begin
//                 @(posedge iClk);
//                 while (iTickUs !== 1'b1) @(posedge iClk);
//             end
//         end
//     endtask

//     // Task: 시작 신호 펄스
//     task pulse_start_req;
//         begin
//             @(posedge iClk);
//             iStart <= 1'b1;
//             @(posedge iClk);
//             iStart <= 1'b0;
//         end
//     endtask

//     // Main Simulation
//     initial begin
//         // 초기화
//         iClk   = 1'b0;
//         iRst   = 1'b1;
//         iEcho  = 1'b0;
//         iStart = 1'b0;
//         repeat (10) @(posedge iClk);
//         iRst = 1'b0;
//         repeat (10) @(posedge iClk);

//         // --- [CASE 1: 노이즈/글리치 정밀 테스트] ---
//         $display("CASE 1: Glitch Test (5ns, 10ns, 15ns) starting...");
        
//         @(negedge iClk);
//         iEcho = 1'b1; #5; iEcho = 1'b0;  // 5ns
//         $display("  Sent 5ns Glitch");
//         wait_us(5);

//         @(negedge iClk);
//         iEcho = 1'b1; #10; iEcho = 1'b0; // 10ns
//         $display("  Sent 10ns Glitch");
//         wait_us(5);

//         @(negedge iClk);
//         iEcho = 1'b1; #15; iEcho = 1'b0; // 15ns
//         $display("  Sent 15ns Glitch");
//         wait_us(10);

//         // --- [CASE 2: 극한의 근접 거리 (10us)] ---
//         // 1cm(58us)보다 훨씬 짧은 신호가 들어올 때
//         $display("CASE 2: Extreme Close-range test (10us)...");
//         pulse_start_req();
//         wait (oTrig == 1'b1);
//         wait (oTrig == 1'b0);

//         @(negedge iClk);
//         iEcho = 1'b1; 
//         wait_us(10); 
//         iEcho = 1'b0;

//         wait (oDistanceValid == 1'b1);
//         $display("CASE 2 Result: Distance = %0d cm", oDistanceCm);
//         wait_us(20);

//         // --- [CASE 3: 오리지널 타임아웃 테스트 (30ms)] ---
//         // 물체가 없어서 에코가 영원히 안 올 때를 가정
//         $display("CASE 3: Original Timeout test (30ms) starting...");
//         $display("  This will take some time in simulation...");
//         pulse_start_req();
//         wait (oTrig == 1'b0);

//         // 실제 30,000us 이상을 기다려야 합니다.
//         // 안전하게 31,000us를 대기하여 타임아웃 복귀를 확인합니다.
//         wait_us(31000);

//         if (dut.rCurState == 3'd0)
//             $display("CASE 3 Success: Returned to IDLE after 30ms timeout.");
//         else 
//             $display("CASE 3 Fail: Stuck in State %0d", dut.rCurState);

//         wait_us(100);
//         $display("All original time scenarios finished.");
//         $finish;
//     end

// endmodule

















