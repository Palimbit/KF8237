# KF8237 - 8237/8237A-like programmable DMA controller written in SystemVerilog 

## Palimbit fork

Reusable core based on kitune-san/KF8237, with independent register-contract
tests and scoped fixes. See [scope, reproduction and limitations](docs/register-contract.md).
Run `bash scripts/test-registers.sh`. This first suite does not certify full
8237 compatibility; the upstream limitations below remain applicable.

## About
KF8237 is programmable DMA controller like 8237/8237A.

## Differences from original
- AEN timing
- Memory-to-Memory transfer is not supported (TODO)
- I/O ports is separated into input and output port

## Features
- Single transfer mode
- Block transfer mode
- Demand transfer mode
- Cascade mode
- 3 Transfer types (Read/Write/Verify)
- Autoinitialize
- Rotating priority
- Compressed timing

## Block
![KF8237_block](DOC/img/KF8237_block.png)

