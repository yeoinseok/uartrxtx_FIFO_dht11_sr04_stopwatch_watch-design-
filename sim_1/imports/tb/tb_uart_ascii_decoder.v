/*
[TB_INFO_START]
Name: tb_uart_ascii_decoder
Target: uart_ascii_decoder
Role: Testbench for ASCII Command Decoder
Scenario:
  - Sends various ASCII characters via `send_byte_expect` task
CheckPoint:
  - Verifies mapping of characters to control pulses (e.g., 'c' -> BtnC)
  - Checks latching/clearing of toggle signals
  - Verifies pass-through for loopback data
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_uart_ascii_decoder;
  initial begin
    $dumpfile("tb_uart_ascii_decoder.vcd");
    $dumpvars(0, tb_uart_ascii_decoder);
  end

  reg        iClk;
  reg        iRst;
  reg  [7:0] iRxData;
  reg        iRxValid;

  wire oBtnC, oBtnU, oBtnD, oBtnL, oBtnR;
  wire oTglSw0, oTglSw1, oTglSw2, oTglSw3, oClrSwTgl;
  wire oReqWatchRpt, oReqSr04Rpt, oReqTempRpt, oReqHumRpt;
  wire [7:0] oLoopData;
  wire oLoopValid;

  uart_ascii_decoder dut (
    .iClk(iClk),
    .iRst(iRst),
    .iRxData(iRxData),
    .iRxValid(iRxValid),
    .oBtnC(oBtnC),
    .oBtnU(oBtnU),
    .oBtnD(oBtnD),
    .oBtnL(oBtnL),
    .oBtnR(oBtnR),
    .oTglSw0(oTglSw0),
    .oTglSw1(oTglSw1),
    .oTglSw2(oTglSw2),
    .oTglSw3(oTglSw3),
    .oClrSwTgl(oClrSwTgl),
    .oReqWatchRpt(oReqWatchRpt),
    .oReqSr04Rpt(oReqSr04Rpt),
    .oReqTempRpt(oReqTempRpt),
    .oReqHumRpt(oReqHumRpt),
    .oLoopData(oLoopData),
    .oLoopValid(oLoopValid)
  );

  always #5 iClk = ~iClk;

  task send_byte_expect(
    input [7:0] ch,
    input exp_btn_c,
    input exp_btn_u,
    input exp_btn_d,
    input exp_btn_l,
    input exp_btn_r,
    input exp_tgl_sw0,
    input exp_tgl_sw1,
    input exp_tgl_sw2,
    input exp_tgl_sw3,
    input exp_clr_sw_tgl,
    input exp_watch_report,
    input exp_sr04_report,
    input exp_temp_report,
    input exp_hum_report
  );
    begin
      @(posedge iClk);
      iRxData  <= ch;
      iRxValid <= 1'b1;
      @(posedge iClk);
      #1;

      if (oBtnC !== exp_btn_c) begin
        $display("oBtnC mismatch for '%c'", ch);
        $finish;
      end
      if (oBtnU !== exp_btn_u) begin
        $display("oBtnU mismatch for '%c'", ch);
        $finish;
      end
      if (oBtnD !== exp_btn_d) begin
        $display("oBtnD mismatch for '%c'", ch);
        $finish;
      end
      if (oBtnL !== exp_btn_l) begin
        $display("oBtnL mismatch for '%c'", ch);
        $finish;
      end
      if (oBtnR !== exp_btn_r) begin
        $display("oBtnR mismatch for '%c'", ch);
        $finish;
      end

      if (oTglSw0 !== exp_tgl_sw0) begin
        $display("oTglSw0 mismatch for '%c'", ch);
        $finish;
      end
      if (oTglSw1 !== exp_tgl_sw1) begin
        $display("oTglSw1 mismatch for '%c'", ch);
        $finish;
      end
      if (oTglSw2 !== exp_tgl_sw2) begin
        $display("oTglSw2 mismatch for '%c'", ch);
        $finish;
      end
      if (oTglSw3 !== exp_tgl_sw3) begin
        $display("oTglSw3 mismatch for '%c'", ch);
        $finish;
      end
      if (oClrSwTgl !== exp_clr_sw_tgl) begin
        $display("oClrSwTgl mismatch for '%c'", ch);
        $finish;
      end

      if (oReqWatchRpt !== exp_watch_report) begin
        $display("watch report pulse mismatch for '%c'", ch);
        $finish;
      end
      if (oReqSr04Rpt !== exp_sr04_report) begin
        $display("sr04 report pulse mismatch for '%c'", ch);
        $finish;
      end
      if (oReqTempRpt !== exp_temp_report) begin
        $display("temp report pulse mismatch for '%c'", ch);
        $finish;
      end
      if (oReqHumRpt !== exp_hum_report) begin
        $display("hum report pulse mismatch for '%c'", ch);
        $finish;
      end

      if (oLoopValid !== 1'b1) begin
        $display("oLoopValid mismatch for '%c'", ch);
        $finish;
      end
      if (oLoopData !== ch) begin
        $display("oLoopData mismatch for '%c'", ch);
        $finish;
      end

      @(posedge iClk);
      iRxValid <= 1'b0;
      iRxData  <= 8'd0;

      // Pulse outputs must clear on the next cycle.
      @(posedge iClk);
      #1;
      if (oBtnC || oBtnU || oBtnD || oBtnL || oBtnR) begin
        $display("button pulse not cleared after '%c'", ch);
        $finish;
      end
      if (oTglSw0 || oTglSw1 || oTglSw2 || oTglSw3 || oClrSwTgl) begin
        $display("toggle pulse not cleared after '%c'", ch);
        $finish;
      end
      if (oReqWatchRpt || oReqSr04Rpt || oReqTempRpt || oReqHumRpt) begin
        $display("report pulse not cleared after '%c'", ch);
        $finish;
      end
    end
  endtask

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;
    iRxData = 8'd0;
    iRxValid = 1'b0;

    repeat (4) @(posedge iClk);
    iRst = 1'b0;

    send_byte_expect("u", 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    send_byte_expect("1", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    send_byte_expect("3", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    send_byte_expect("5", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    send_byte_expect("6", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    send_byte_expect("w", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
    send_byte_expect("s", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
    send_byte_expect("t", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
    send_byte_expect("h", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
    send_byte_expect("c", 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    send_byte_expect("x", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);

    repeat (10) @(posedge iClk);
    $display("tb_uart_ascii_decoder finished");
    $finish;
  end

endmodule
