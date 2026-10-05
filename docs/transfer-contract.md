# Transfer contract

Run `bash scripts/test-transfers.sh` with the same Verilator/C++ prerequisites
as the register suite. The regression uses only the public KF8237 ports and
a synthetic 64 KiB memory/peripheral environment, clocked at 5 MHz. It requires
no machine ROM, SDRAM model or proprietary media. The unchanged top-level port
interface remains reusable by machine-specific adapters.

## Coverage

28 scenarios exercise four channels, both byte directions, ascending and
descending addressing, 8-bit carries and 16-bit wrap, count zero, a full 65536
operation Verify block, READY stalls in both data directions, autoinit across
successive blocks, Demand pause/resume, Single mode with held DREQ, external
EOP with and without autoinit, TC/status clearing and channel masking after
EOP. Fast HLDA and delayed grant release are explicit handshake cases.

Every destination write pulse commits once; pulse stretching must not duplicate
data. Distinct source bytes, independent address predictions, memory content,
count/address readback and observed terminal-count pulses are checked. Verify
has no data strobes. Payload travels directly between the model endpoints;
the 8237 controls their strobes and addresses rather than carrying those bytes
through an internal data register.

The specification reference is Intel [8237A 231466-005](https://www.pcjs.org/documents/datasheets/intel/INTEL_8237A_DMA.pdf),
printed pages 5-9, active modes, transfer types, autoinitialization and EOP.
The initial 25-scenario suite reproduced 32 failures on the preceding register
revision. A subsequent held-autoinit-block test reproduced another defect.
The fork now masks a non-autoinit channel at EOP, ignores READY in Verify,
samples external EOP through active transfer phases, and treats DREQ as a level.
The next service waits for HLDA release without cancelling a fast grant already
requested by HRQ. These changes apply to controller behavior, not a PCS86 map.

## Limits

Simulation checks transfer control and a synthetic bus. It does not establish
electrical timing, AEN compatibility, synthesis, SDRAM/CPU arbitration or board
operation. Memory-to-memory remains unsupported. Cascade, concurrent channel
priorities, compressed/extended timing, configurable DREQ/DACK polarity,
masked-request status and reset retention require further tests. Asynchronous
input sampling is represented by the RTL clocked interface, not an analog
metastability or setup/hold model. Compiler width warnings remain visible.

The earlier register suite must continue to pass alongside this suite. GitHub
Actions is configured for both but was disabled by organization policy during
the local FpgaMach validation; that local result is separate from remote CI.
