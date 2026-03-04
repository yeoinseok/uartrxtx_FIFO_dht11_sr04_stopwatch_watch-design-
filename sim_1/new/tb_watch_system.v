`timescale 1ns / 1ps
module tb_watch_system;

    reg iClk, iRst, iTick100Hz;
    reg iSw0, iSw1;
    reg iBtnCEdge, iBtnREdge, iBtnLEdge, iBtnUEdge, iBtnDEdge;
    wire [13:0] oDispData;
    wire [3:0]  oBlinkMask;
    wire [6:0] oCurrentHour, oCurrentMin, oCurrentSec, oCurrentCenti;

    watch_top dut (
        .iClk(iClk), .iRst(iRst), .iTick100Hz(iTick100Hz),
        .iSw0(iSw0), .iSw1(iSw1),
        .iBtnCEdge(iBtnCEdge), .iBtnREdge(iBtnREdge), .iBtnLEdge(iBtnLEdge),
        .iBtnUEdge(iBtnUEdge), .iBtnDEdge(iBtnDEdge),
        .oDispData(oDispData), .oBlinkMask(oBlinkMask),
        .oCurrentHour(oCurrentHour), .oCurrentMin(oCurrentMin),
        .oCurrentSec(oCurrentSec), .oCurrentCenti(oCurrentCenti)
    );

    initial iClk = 0;
    always #5 iClk = ~iClk;

    initial begin
        iTick100Hz = 0;
        forever begin
            #(10_000_000 - 10);
            @(posedge iClk); iTick100Hz = 1;
            @(posedge iClk); iTick100Hz = 0;
        end
    end

    task wait_abs;
        input integer t;
        begin
            if ($time < t) #(t - $time);
        end
    endtask

    initial begin
        $monitor("[%0t ns] SW_State=%0d CS=%0d S=%0d M=%0d H=%0d | ClkCS=%0d ClkS=%0d ClkM=%0d ClkH=%0d | iSw0=%b",
            $time,
            dut.u_stopwatch.rCurState,
            dut.u_stopwatch.rCentisec,
            dut.u_stopwatch.rSec,
            dut.u_stopwatch.rMin,
            dut.u_stopwatch.rHour,
            oCurrentCenti, oCurrentSec, oCurrentMin, oCurrentHour,
            iSw0
        );
    end

    initial begin
        iClk=0; iRst=1; iSw0=0; iSw1=0;
        {iBtnCEdge,iBtnREdge,iBtnLEdge,iBtnUEdge,iBtnDEdge} = 0;

        // ── [0.1ms] 리셋 해제
        wait_abs(100_000);
        iRst = 0;
        $display("[%0t ns] Reset 해제", $time);

        // ==========================================
        // STEP 1: 스탑워치 기능 검증 (iSw0=0)
        // ==========================================

        // ── [1ms] START (RUN)
        wait_abs(1_000_000);
        @(posedge iClk); iBtnCEdge = 1; @(posedge iClk); iBtnCEdge = 0;
        $display("[%0t ns] ★ Stopwatch START → State=%0d (1=RUN 기대)",
                 $time, dut.u_stopwatch.rCurState);

        // ── [22ms] STOP → 여기서 STOP 상태 충분히 확인
        wait_abs(22_000_000);
        @(posedge iClk); iBtnCEdge = 1; @(posedge iClk); iBtnCEdge = 0;
        $display("[%0t ns] ★ Stopwatch STOP → State=%0d CS=%0d (2=STOP 기대)",
                 $time, dut.u_stopwatch.rCurState, dut.u_stopwatch.rCentisec);

        // ── [32ms] CLEAR ← STOP에서 10ms 대기 후 CLEAR (STOP 상태 파형에서 확인 가능)
        wait_abs(32_000_000);
        @(posedge iClk); iBtnUEdge = 1; @(posedge iClk); iBtnUEdge = 0;
        $display("[%0t ns] ★ Stopwatch CLEAR 인가 → State=%0d (0=IDLE 기대)",
                 $time, dut.u_stopwatch.rCurState);

        // 다음 틱(40ms) 이후 카운터 0 확인
        wait_abs(40_500_000);
        $display("[%0t ns] 틱 후 CS=%0d S=%0d (0 기대)",
                 $time, dut.u_stopwatch.rCentisec, dut.u_stopwatch.rSec);

        // ==========================================
        // STEP 2: 시계 모드 (iSw0=1)
        // iSw0=1 이후 버튼은 시계로만 라우팅
        // ==========================================

        // ── [42ms] 시계 모드 전환
        wait_abs(42_000_000);
        iSw0 = 1; iSw1 = 0;
        $display("[%0t ns] ★ iSw0=1 Clock Mode 전환", $time);

        // 틱 3번 대기 → centisec 증가 확인
        wait_abs(52_000_000);
        $display("[%0t ns] 틱 1회 후 ClkCS=%0d (1 기대)", $time, oCurrentCenti);
        wait_abs(62_000_000);
        $display("[%0t ns] 틱 2회 후 ClkCS=%0d (2 기대)", $time, oCurrentCenti);
        wait_abs(72_000_000);
        $display("[%0t ns] 틱 3회 후 ClkCS=%0d (3 기대)", $time, oCurrentCenti);

        // ── [72ms] EDIT 진입 (BTNC)
        wait_abs(72_000_000);
        @(posedge iClk); iBtnCEdge = 1; @(posedge iClk); iBtnCEdge = 0;
        $display("[%0t ns] ★ Clock EDIT 진입 (Sec 편집)", $time);

        // ── Sec UP x2
        wait_abs(73_000_000);
        @(posedge iClk); iBtnUEdge = 1; @(posedge iClk); iBtnUEdge = 0;
        $display("[%0t ns] UP → Sec=%0d (1 기대)", $time, oCurrentSec);
        wait_abs(73_500_000);
        @(posedge iClk); iBtnUEdge = 1; @(posedge iClk); iBtnUEdge = 0;
        $display("[%0t ns] UP → Sec=%0d (2 기대)", $time, oCurrentSec);

        // ── Min 편집으로 이동 (BTNL)
        wait_abs(74_500_000);
        @(posedge iClk); iBtnLEdge = 1; @(posedge iClk); iBtnLEdge = 0;
        $display("[%0t ns] BTNL → Min 편집", $time);

        // ── Min UP x2
        wait_abs(75_500_000);
        @(posedge iClk); iBtnUEdge = 1; @(posedge iClk); iBtnUEdge = 0;
        $display("[%0t ns] UP → Min=%0d (1 기대)", $time, oCurrentMin);
        wait_abs(76_000_000);
        @(posedge iClk); iBtnUEdge = 1; @(posedge iClk); iBtnUEdge = 0;
        $display("[%0t ns] UP → Min=%0d (2 기대)", $time, oCurrentMin);

        // ── Hour 편집으로 이동 (BTNL)
        wait_abs(77_000_000);
        @(posedge iClk); iBtnLEdge = 1; @(posedge iClk); iBtnLEdge = 0;
        $display("[%0t ns] BTNL → Hour 편집", $time);

        // ── Hour UP x3 (12→1→2→3)
        wait_abs(78_000_000);
        @(posedge iClk); iBtnUEdge = 1; @(posedge iClk); iBtnUEdge = 0;
        $display("[%0t ns] UP → Hour=%0d (1 기대)", $time, oCurrentHour);
        wait_abs(78_500_000);
        @(posedge iClk); iBtnUEdge = 1; @(posedge iClk); iBtnUEdge = 0;
        $display("[%0t ns] UP → Hour=%0d (2 기대)", $time, oCurrentHour);
        wait_abs(79_000_000);
        @(posedge iClk); iBtnUEdge = 1; @(posedge iClk); iBtnUEdge = 0;
        $display("[%0t ns] UP → Hour=%0d (3 기대)", $time, oCurrentHour);

        // ── Hour DOWN x1 (3→2)
        wait_abs(79_500_000);
        @(posedge iClk); iBtnDEdge = 1; @(posedge iClk); iBtnDEdge = 0;
        $display("[%0t ns] DOWN → Hour=%0d (2 기대)", $time, oCurrentHour);

        // ── EDIT 종료 (BTNC)
        wait_abs(80_500_000);
        @(posedge iClk); iBtnCEdge = 1; @(posedge iClk); iBtnCEdge = 0;
        $display("[%0t ns] ★ EDIT 종료 → H=%0d M=%0d S=%0d 확정",
                 $time, oCurrentHour, oCurrentMin, oCurrentSec);

        wait_abs(82_000_000);
        $display("[%0t ns] === 시뮬레이션 완료 ===", $time);
        $finish;
    end
endmodule