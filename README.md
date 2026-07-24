# 32-bit Pipelined RISC-V Processor with Integrated Cache on FPGA

A 32-bit RV32I processor featuring a five-stage pipeline, hazard handling,
data forwarding, and integrated instruction and data caches. The processor
was designed in Verilog HDL and implemented for the Zybo Z7-10 FPGA.

## Key Features

- Five-stage pipeline: IF, ID, EX, MEM, and WB
- Supports RV32I R-, I-, S-, B-, U-, and J-type instructions
- Hazard detection with pipeline stall and flush
- EX/MEM and MEM/WB data forwarding
- 4-way set-associative instruction cache
- 2-way write-back data cache
- LRU cache replacement policy
- Critical-word-first refill with early restart
- Verilog HDL implementation

## FPGA Implementation Results

| Metric | Result |
|---|---:|
| FPGA board | Zybo Z7-10 |
| LUTs | 2,631 |
| Flip-flops | 4,441 |
| BRAMs | 1 |
| Timing-closed frequency | 50 MHz |
| Estimated maximum frequency | ~68 MHz |
| WNS at 50 MHz | 5.311 ns |
| Estimated on-chip power | 0.102 W |
| Failed routes | 0 |

> The maximum frequency and on-chip power are estimated from the Vivado post-implementation reports.

## Project Structure

```text
vivado/
├── rtl/          Verilog source files, constraints, and memory files
└── test_bench/   CPU simulation testbench
