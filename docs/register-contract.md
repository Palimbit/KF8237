# Register contract and fork scope

This MIT-licensed fork starts at kitune-san/KF8237 commit
`229aa0903784777af4746e39fa9ca9f1254bd630`. Keep the upstream LICENSE and
attribution. Generic corrections and tests belong here; machine address maps,
page registers, CPU bridges, SDRAM arbitration and board pin constraints do not.

The independent black-box test uses only the public KF8237 interface. It checks
address/count byte ordering and channel isolation, the shared first/last byte
pointer, unselected writes, every mask vector against each DREQ, individual
mask commands, software requests, controller disable, Master Clear and the
absence of memory transfers before HLDA. It drives a 5 MHz test clock; that is
a simulation fixture, not a measured FPGA frequency or timing certificate.

The contract comes from Intel's [8237A datasheet, order 231466-005](https://www.pcjs.org/documents/datasheets/intel/INTEL_8237A_DMA.pdf),
printed pages 7-10: register descriptions, software commands and programming
table. Clear Mask Register enables all four hardware requests and must not
reset the independent software Request register. Software requests are
non-maskable and are tested in block mode. Master Clear resets requests and
sets all masks. The patch also removes Clear Mask's unrelated reset of the
request lock; active-transfer behavior remains outside this first suite.

On upstream HDL, the new suite reports 202 checks and eight failures: Clear
Mask leaves each channel masked and destroys each software request. The fork
corrects those side effects in Priority Encoder. Re-run the same test after
any change:

```sh
bash scripts/test-registers.sh
```

Requires Bash, Verilator with `--binary --timing` support, make and a C++
toolchain. An optional first argument selects the output directory. Logs and
generated executable stay in build/. The explicit C++ optimization setting
also works around an observed local MSYS2 GCC 16.2 link failure with the
default -Os setting. Compiler warnings remain visible in compile.log;
upstream width warnings are not a clean-lint result.

This is an initial register regression, not a complete 8237 conformance claim.
It does not validate actual DMA data movement, count exhaustion/TC, EOP,
autoinitialization, rotating priorities, READY waits, cascade, electrical
timing, reset retention of address/count, or masked-request status semantics.
Upstream's AEN timing difference and unsupported memory-to-memory mode remain.
No BIOS, proprietary media or board dependencies are required.

## Reuse policy

Consumers pin a tested commit as a Git submodule. A new commit here does not
silently update consumers. Each machine updates its gitlink, runs its own
integration regressions and records the selected revision. Keep upstream
available as a remote for reviewed merges; do not follow main automatically
in release builds. PIC/PIT can adopt this layout separately after their
existing snapshots and tests are preserved.
