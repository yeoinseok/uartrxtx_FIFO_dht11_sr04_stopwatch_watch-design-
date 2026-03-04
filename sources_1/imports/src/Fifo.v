/*
[MODULE_INFO_START]
Name: Fifo
Role: First-In First-Out Data Buffer
Summary:
  - Parameterized FIFO for UART data buffering (RX and TX).
  - Implements circular buffer with Read/Write pointers.
  - Provides Full/Empty status flags.
  - Used to decouple UART timing from the main control loop.
StateDescription:
  - IDLE: No operation.
  - PUSH_ONLY: Only write occurring.
  - POP_ONLY: Only read occurring.
  - PUSH_POP: Simultaneous read and write.
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module Fifo #(
  parameter integer P_DATA_WIDTH = 8,
  parameter integer P_FIFO_DEPTH = 16
)(
  input  wire                    iClk,
  input  wire                    iRst,

  // Write Interface
  input  wire                    iPush,
  input  wire [P_DATA_WIDTH-1:0] iPushData,
  output wire                    oFull,

  // Read Interface
  input  wire                    iPop,
  output wire [P_DATA_WIDTH-1:0] oPopData,
  output wire                    oEmpty
);

  localparam integer LP_ADDR_WIDTH = (P_FIFO_DEPTH <= 2) ? 1 : $clog2(P_FIFO_DEPTH);
  localparam integer LP_CNT_WIDTH  = $clog2(P_FIFO_DEPTH + 1);

  localparam [1:0] IDLE     = 2'd0;
  localparam [1:0] PUSH_ONLY = 2'd1;
  localparam [1:0] POP_ONLY  = 2'd2;
  localparam [1:0] PUSH_POP  = 2'd3;

  reg [1:0] rCurState;
  reg [1:0] rNxtState;

  reg [P_DATA_WIDTH-1:0] rMem [0:P_FIFO_DEPTH-1];
  reg [LP_ADDR_WIDTH-1:0] rWrPtr;
  reg [LP_ADDR_WIDTH-1:0] rRdPtr;
  reg [LP_CNT_WIDTH-1:0]  rCount;

  wire wPushReq;
  wire wPopReq;

  function [LP_ADDR_WIDTH-1:0] f_inc_ptr;
    input [LP_ADDR_WIDTH-1:0] ptr;
    begin
      if (ptr == (P_FIFO_DEPTH - 1)) f_inc_ptr = {LP_ADDR_WIDTH{1'b0}};
      else                           f_inc_ptr = ptr + 1'b1;
    end
  endfunction

  assign oEmpty   = (rCount == {LP_CNT_WIDTH{1'b0}});
  assign oFull    = (rCount == P_FIFO_DEPTH[LP_CNT_WIDTH-1:0]);
  assign wPushReq = iPush && !oFull;
  assign wPopReq  = iPop && !oEmpty;

  // Read data is current read pointer location.
  assign oPopData = rMem[rRdPtr];

  always @(*) begin
    rNxtState = IDLE;

    case (rCurState)
      IDLE, PUSH_ONLY, POP_ONLY, PUSH_POP: begin
        case ({wPushReq, wPopReq})
          2'b10: rNxtState = PUSH_ONLY;
          2'b01: rNxtState = POP_ONLY;
          2'b11: rNxtState = PUSH_POP;
          default: rNxtState = IDLE;
        endcase
      end

      default: rNxtState = IDLE;
    endcase
  end

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin  //리셋시 모든 레지스터 초기화
      rCurState <= IDLE; //
      rWrPtr    <= {LP_ADDR_WIDTH{1'b0}}; //쓰기포인터 0으로 초기화
      rRdPtr    <= {LP_ADDR_WIDTH{1'b0}}; //일기 포인터 0으로 초기화
      rCount    <= {LP_CNT_WIDTH{1'b0}}; // 데이터개수 0으로 초기화
    end else begin
      rCurState <= rNxtState;  //아이들 일때 다음

      case (rNxtState) 
        PUSH_ONLY: begin //푸시, 데이터저장 동작만 수행 
          rMem[rWrPtr] <= iPushData;  //데이터를 현재 위치에일단저장
          rWrPtr       <= f_inc_ptr(rWrPtr); // 쓰기포인터 다음저장소 가르켜
          rCount       <= rCount + 1'b1; //데이터 개수 1개 증가시며 이모든데 푸시일떄
        end

        POP_ONLY: begin  //팝 데이터 읽어와 가져오는거지
          rRdPtr <= f_inc_ptr(rRdPtr); // 팝은 어사인을 으로 tx로 밀어넣었고 다음팝을 포인터로가르켜
          rCount <= rCount - 1'b1; //팝? 가져갓네 데이터하나빼
        end

        PUSH_POP: begin
          rMem[rWrPtr] <= iPushData; // 푸시들어왔을때 푸시데이터를 포인터위치에 저장함 풀떴을때는 assign으로 선언한거고
          rWrPtr       <= f_inc_ptr(rWrPtr); //푸시했을때 포인터를 다음위치로 옮겨
          rRdPtr       <= f_inc_ptr(rRdPtr); //풀했을때 포인터를 다음위치로 옮겨
        end

        default: begin
          // IDLE
        end
      endcase
    end
  end

endmodule
