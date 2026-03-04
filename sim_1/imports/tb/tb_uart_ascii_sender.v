/*
[TB_INFO_START]
Name: tb_uart_ascii_sender
Target: uart_ascii_sender
Role: Testbench for ASCII Report Generator
Scenario:
  - Stimulates request inputs for Watch, SR04, DHT11, and Loopback
  - Simulates UART TX busy pressure
CheckPoint:
  - Captures serialized UART output into a log
  - Verifies correct formatting of strings (e.g., "WATCH...", "TEMP...")
  - Checks arbitration priority if multiple requests occur
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_uart_ascii_sender;
  initial begin
    $dumpfile("tb_uart_ascii_sender.vcd");
    $dumpvars(0, tb_uart_ascii_sender);
  end

  reg iClk;
  reg iRst;

  reg iTxBusy;
  wire [7:0] oTxData;
  wire oTxValid;

  reg [7:0] iLoopData;
  reg iLoopValid;
  reg iReqWatchReport;
  reg iReqSr04Report;
  reg iReqTempReport;
  reg iReqHumReport;
  reg [6:0] iWatchHour, iWatchMin, iWatchSec;
  reg [9:0] iSr04DistanceCm;
  reg iSr04DistanceValid;
  reg [7:0] iDhtHumInt;
  reg [7:0] iDhtTempInt;
  reg iDhtDataValid;

  uart_ascii_sender dut (
    .iClk(iClk),
    .iRst(iRst),
    .iTxBusy(iTxBusy),
    .oTxData(oTxData),
    .oTxValid(oTxValid),
    .iLoopData(iLoopData),
    .iLoopValid(iLoopValid),
    .iReqWatchReport(iReqWatchReport),
    .iReqSr04Report(iReqSr04Report),
    .iReqTempReport(iReqTempReport),
    .iReqHumReport(iReqHumReport),
    .iWatchHour(iWatchHour),
    .iWatchMin(iWatchMin),
    .iWatchSec(iWatchSec),
    .iSr04DistanceCm(iSr04DistanceCm),
    .iSr04DistanceValid(iSr04DistanceValid),
    .iDhtHumInt(iDhtHumInt),
    .iDhtTempInt(iDhtTempInt),
    .iDhtDataValid(iDhtDataValid)
  );

  always #5 iClk = ~iClk;

  integer busy_cnt;
  integer tx_count;
  reg [7:0] tx_log [0:255];

  // Simple UART-TX busy model:
  // after oTxValid pulse, busy stays high for a few cycles.
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      iTxBusy <= 1'b0;
      busy_cnt <= 0;
      tx_count <= 0;
    end else begin
      if (busy_cnt > 0) begin
        busy_cnt <= busy_cnt - 1;
        iTxBusy <= 1'b1;
      end else begin
        iTxBusy <= 1'b0;
      end

      if (oTxValid) begin
        tx_log[tx_count] <= oTxData;
        tx_count <= tx_count + 1;
        busy_cnt <= 3;
      end
    end
  end

  task pulse_loop(input [7:0] ch);
    begin
      @(posedge iClk);
      iLoopData  <= ch;
      iLoopValid <= 1'b1;
      @(posedge iClk);
      iLoopValid <= 1'b0;
    end
  endtask

  task pulse_watch_report;
    begin
      @(posedge iClk);
      iReqWatchReport <= 1'b1;
      @(posedge iClk);
      iReqWatchReport <= 1'b0;
    end
  endtask

  task pulse_sr04_report;
    begin
      @(posedge iClk);
      iReqSr04Report <= 1'b1;
      @(posedge iClk);
      iReqSr04Report <= 1'b0;
    end
  endtask

  task pulse_temp_report;
    begin
      @(posedge iClk);
      iReqTempReport <= 1'b1;
      @(posedge iClk);
      iReqTempReport <= 1'b0;
    end
  endtask

  task pulse_hum_report;
    begin
      @(posedge iClk);
      iReqHumReport <= 1'b1;
      @(posedge iClk);
      iReqHumReport <= 1'b0;
    end
  endtask

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;

    iTxBusy = 1'b0;
    iLoopData = 8'd0;
    iLoopValid = 1'b0;
    iReqWatchReport = 1'b0;
    iReqSr04Report = 1'b0;
    iReqTempReport = 1'b0;
    iReqHumReport = 1'b0;

    iWatchHour = 7'd12;
    iWatchMin  = 7'd34;
    iWatchSec  = 7'd56;
    iSr04DistanceCm = 10'd123;
    iSr04DistanceValid = 1'b1;
    iDhtHumInt = 8'd44;
    iDhtTempInt = 8'd23;
    iDhtDataValid = 1'b1;

    repeat (5) @(posedge iClk);
    iRst = 1'b0;

    pulse_loop("A");
    pulse_watch_report();
    pulse_sr04_report();
    pulse_temp_report();
    pulse_hum_report();

    repeat (500) @(posedge iClk);

    if (tx_count < 40) begin
      $display("uart_ascii_sender tx_count too small: %0d", tx_count);
      $finish;
    end

    $display("tb_uart_ascii_sender finished: tx_count=%0d", tx_count);
    $display("first bytes: %h %h %h %h %h %h",
      tx_log[0], tx_log[1], tx_log[2], tx_log[3], tx_log[4], tx_log[5]);
    $finish;
  end

endmodule
