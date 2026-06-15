# Multifunctional RTL Design: SR04·DHT11 Sensor & UART/FIFO Based Clock·Stopwatch

> SR04·DHT11 센서 인터페이스, UART/FIFO 통신, 실시간 시계·스톱워치를 하나의 동기식 시스템으로 통합 설계한 RTL 프로젝트

## 🎬 동작 영상

[![동작 영상](https://img.youtube.com/vi/kMOGe5HuzZg/0.jpg)](https://youtu.be/kMOGe5HuzZg)

## 📌 프로젝트 개요

SR04 초음파 센서, DHT11 온습도 센서, UART 통신, FIFO 버퍼, 실시간 시계, 스톱워치를 하나의 통합 시스템으로 설계한 RTL 프로젝트입니다. Single Clock/Reset 동기식 설계를 기반으로 외부 비동기 신호를 안정적으로 처리하기 위해 Synchronizer와 x16 샘플링 로직을 구현했고, FSM 기반 제어로 다중 모드 전환 시 글리치를 방지했습니다. Timeout 카운터를 설계하여 센서 무응답 시에도 시스템이 안정적으로 복구되는 방어적 설계를 완성했습니다.

**개발 기간:** 2026.01.20 ~ 2026.02.23  
**팀 구성:** 3인 팀 프로젝트  
**담당 업무:** SR04, DHT11, STOPWATCH, WATCH Design

## 🛠 기술 스택

- **HDL:** Verilog
- **FPGA 툴:** Xilinx Vivado

## 🏗 시스템 아키텍처

### 동기식 설계 아키텍처
- **Single Clock/Reset:** 전체 시스템을 하나의 클럭으로 동기화
- **Synchronizer:** 외부 비동기 신호(UART Rx) 안정화를 위한 2-stage FF
- **x16 샘플링:** Baud Rate Generator 기반 정확한 데이터 수신

### 센서 인터페이스 설계
- **SR04 초음파 센서:** 거리 측정 및 타이밍 제어
- **DHT11 온습도 센서:** 온도/습도 데이터 읽기 및 파싱
- **Timeout 메커니즘:** 센서 무응답 시 FSM 강제 복귀

### 통신 및 버퍼링
- **UART Rx/Tx:** 9600 baud rate 기반 직렬 통신
- **FIFO 버퍼:** 데이터 흐름 제어 및 유실 방지
- **양방향 제어:** PC 가상 스위치 + 보드 물리 스위치 통합

### 시계 및 스톱워치 모듈
- **실시간 시계:** 시/분/초 카운터 및 설정 모드
- **스톱워치:** 시작/정지/리셋 기능 구현
- **FSM 기반 모드 전환:** 글리치 방지 상태 제어

## 🔧 Troubleshooting

### FSM Hang-up 문제

**문제:**  
외부 센서(SR04 Echo 등)의 단선이나 측정 범위 이탈로 응답 신호가 오지 않을 경우, FSM이 특정 상태에서 무한 대기에 빠져 전체 FPGA 시스템이 정지(Hang-up)되는 취약점 발견

**원인:**  
외부 I/O 모듈의 응답을 100% 신뢰하도록 설계된 기본 FSM 구조의 한계

**해결:**  
하드웨어적 Timeout 카운터를 설계에 반영하여 응답 대기 상태에서 설정된 임계 시간(30ms) 초과 시 FSM을 강제로 IDLE 상태로 복구시키는 예외 처리 메커니즘 구현

**결과:** ✅ 외부 센서 무응답 시에도 시스템 안정적 복구 (Defensive Design 완성)

## 📚 배운 점

- **Single Clock/Reset 동기식 설계:** 회로의 예측 가능성과 동작 안정성 확보
- **CDC 대응 설계:** Synchronizer(2-stage FF)로 Metastability 문제 방지
- **방어적 설계의 중요성:** 외부 환경 변화에도 Hang-up 없는 강인한 시스템 설계
