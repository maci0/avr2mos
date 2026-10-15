# avr2mos: AVR to 6502 Static Binary Translator

`avr2mos` is a high-performance static binary translator that converts AVR8 machine code into equivalent 6502-family machine code. Unlike an emulator, `avr2mos` performs a full translation of the program's control flow and logic, resulting in standalone binaries that run natively on vintage and modern 6502 hardware.

---

## Features

- **Multi-CPU Target Support**:
  - **NMOS 6502**: Classic 6502 with safe jump handling (no CMOS opcodes).
  - **WDC 65C02**: Enhanced CMOS version with `BRA`, `STZ`, `PHX/PLX`, and `(zp)` indirect addressing.
  - **WDC 65816**: Full support for 8-bit emulation and 16-bit native modes with banked addressing.
- **Static Control Flow Analysis**: Builds a Control Flow Graph (CFG) to resolve complex jump patterns and conditional logic.
- **Peephole Optimization**: A label-aware optimizer that removes redundant loads, stores, and operations.
- **ELF Section Support**: Automatically parses `.text`, `.data`, and `.rodata` sections and maps them seamlessly to native 6502 addresses based on the ELF Virtual Memory Addresses (VMAs).
- **Indirect Control Flow**: Supports `IJMP` and `ICALL` instructions through trampolines.
- **Full Verification Harness**: A lock-step verification system comparing translated binaries against original AVR simulations.

---

## Technical Specification

### Architectural Profiles

| Profile | Description | Constraints/Capabilities |
| :--- | :--- | :--- |
| **NMOS 6502** | Original NMOS silicon | No CMOS opcodes, safe `JMP (abs)` handling. |
| **65C02** | Modern CMOS version | Adds `BRA`, `STZ`, `PHX`, `PLX`, `PHY`, `PLY`, `TRB`, `TSB`. |
| **65816 (E)** | 65816 Emulation Mode | 8-bit registers, 65C02-compatible instruction set. |
| **65816 (N)** | 65816 Native Mode | 16-bit A/X/Y (via `REP`/`SEP`), 24-bit banked addressing. |

### Memory Model

- **Registers**: AVR `r0`–`r31` → 6502 Zero Page **$00–$1F**.
- **I/O Space**: AVR `$00`–`$3F` → 6502 Zero Page **$20–$5F**.
- **Scratch Space**: 6502 Zero Page **$80–$81** is reserved for internal temporary calculations (e.g., during `SWAP` or multiplication) to prevent unintentional I/O register corruption.
- **SRAM (Data/BSS)**: Data memory segments translate to 6502 based natively on the VMA addresses defined in the Zig target/linker script (e.g. mapping `.data` to `$5000`).
- **Stack**: Maintained explicitly in memory if used, starting from AVR's initialized `SP` down through the standard 6502 stack bounds or SRAM.

### Supported Addressing Modes

`avr2mos` successfully translates the following AVR memory addressing modes:
- **Register Direct** (1 or 2 registers)
- **I/O Direct** (`in`, `out`, `cbi`, `sbi`, `sbic`, `sbis`)
- **Data Direct** (`lds`, `sts`)
- **Data Indirect** via X, Y, Z registers (mapped to 6502 ZP pairs)
- **Data Indirect with Post-Increment** (`ld X+`, `st Y+`)
- **Data Indirect with Pre-Decrement** (`ld -X`, `st -Z`)
- **Data Indirect with Displacement** (`ldd Y+q`, `std Z+q`)
- **Program Memory Indirect** (`lpm Z`, `lpm Z+`) 

*(Note: Extended memory addressing via `elpm` and `RAMPZ` is currently unhandled or treats RAMPZ as 0).*

### Supported Instructions

100+ AVR instructions are fully translated with exact condition code replication (unless operating under relaxed flags):
- **ALU / Logic**: `add`, `adc`, `sub`, `subi`, `sbc`, `sbci`, `and`, `andi`, `or`, `ori`, `eor`, `com`, `neg`, `inc`, `dec`, `tst`, `clr`, `ser`, `cp`, `cpc`, `cpi`
- **Multiplication**: `mul`, `muls`, `mulsu`, `fmul`, `fmuls`, `fmulsu` (Caveat: Emitted via a subroutine call that clobbers the resulting registers `r0`($00)/`r1`($01) and scratch space `$80`/`$81`).
- **Bit & Bit-Test**: `lsr`, `ror`, `asr`, `swap`, `bset`, `bclr`, `bst`, `bld`, `sbr`, `cbr`, `sbi`, `cbi`
- **Data Transfer**: `mov`, `movw`, `ldi`, `ld`, `ldd`, `st`, `std`, `lds`, `sts`, `lpm`, `in`, `out`, `push`, `pop`
- **Control Flow**: `rjmp`, `jmp`, `ijmp`, `rcall`, `call`, `icall`, `ret`, `reti`, `cpse`, `sbrc`, `sbrs`, `sbic`, `sbis`, `brbc`, `brbs` (and all branch aliases: `breq`, `brne`, `brcc`, `brcs`, etc.)
- **System**: `nop`, `break`, `cli`, `sei`, `sleep`, `wdr`

### Translation Invariants & Caveats

- **Skip Instructions**: Normalized into conditional branches around the target instruction. 32-bit skip targets (`lds`, `sts`, `jmp`, `call`) are accurately measured and bypassed.
- **Indirect Calls/Jumps**: Translated via a static jump-table based trampoline system for deterministic behavior across the limited 6502 addressing space.
- **Flag Semantics**: 
  - **Relaxed (Default)**: Maps Carry, Zero, Negative, and Overflow. Ignores Half-Carry (H), Transfer (T), and Sign (S) flags for massive performance gains.
  - **Strict**: Optional software-based emulation of all AVR flags.
- **Multiplication**: 16-bit products are calculated through a shared runtime assembly subroutine rather than being inlined.

### NESDev Macro Synthesis
`avr2mos` natively synthesizes highly optimized 6502 assembly macros from the **NESDev** competitive coding community to replace naive AVR execution patterns:
- **`ASR` (Arithmetic Shift Right)**: Implemented using an ingenious `ASL A` (pushing sign to carry), followed by `ROR zp` replacing a 15-cycle multi-instruction jump sequence.
- **`SWAP` (Nybble Swap)**: Translated using a rapid double `ASL A | ADC #$80 | ROL A` accumulator trick, executing in 18 cycles instead of a brutal 31-cycle memory loop.
- **`MUL` (16-bit Multiplication)**: Extended AVR 16-bit multiplication utilizes the NESDev math right-shifting sequence natively within the translation path, increasing throughput by >40% over recursive subroutines.

### Optimization Levels

`avr2mos` includes a multi-tiered peephole optimizer designed to eliminate redundant 6502 instructions and reduce code footprint:
- **`-O0`**: Disabled. Performs a strictly raw, unoptimized 1:1 translation.
- **`-O1` (Default)**: Eliminates redundant immediate loads (`LDA #imm`) and redundant zero-page operations, preventing unnecessary ALU usage.
- **`-O2`**: Dead Code Elimination (DCE). Safely removes orphaned, unreachable instructions following unconditional jumps (`JMP`) and returns (`RTS`, `RTI`).
- **`-O3`**: Aggressive peephole and macro fusion. Removes redundant `LDX`/`LDY` immediate loads to drastically reduce register thrashing and fusions redundant flag mutations (e.g., contiguous `SEC`/`CLC` pairs).
- **`-Os`**: Size aggregation. Folds 3-byte Absolute Address manipulations into 2-byte Zero-Page targets (e.g., `LDA $004A` becomes `LDA $4A`) where mathematically safe, yielding significant (up to 40%) size reductions without speed penalties.

**Architecture**: The optimizer utilizes an $O(1)$ jump-label lookup matrix pre-computed per iteration, and a declarative rule engine. This ensures highly efficient linear scanning without $O(N)$ nested iteration overheads, running stable transformations until the binary mathematically converges.

---

## Installation & Usage

### Build
`avr2mos` is written in Zig (requires Zig 0.13.0+).

```bash
zig build -Doptimize=ReleaseSafe
```

### Translate
```bash
./zig-out/bin/avr2mos --input program.elf --output program.bin --cpu 65c02 --report report.txt
```

### Options
| Option | Description |
| :--- | :--- |
| `--input <file>` | Input AVR ELF or binary. |
| `--output <file>` | Translated 6502 binary. This is the destination path, not a format switch. |
| `--format <FMT>` | `auto`, `text`, or `json`. `auto` stays text on a pipe. JSON prints one object with `input`, `output`, `bytes`, and `changed`. |
| `schema [command]` | Print the CLI Spec 0.3 document. Needs no input file. |
| `version` | Print the version. |
| `--cpu <profile>` | `nmos6502`, `65c02`, `65816` (default: `nmos6502`). |
| `--mode <mode>` | `emulation`, `native` (for 65816). |
| `--strict-flags` | Software implementation of H, T, S flags. |
| `-O0` to `-Os` | Optimization levels. `-O0`: None, `-O1`: Basic, `-O2`: DCE, `-O3`: Aggressive, `-Os`: Size (default: `-O1`). |

---

## Verification & Testing

Verify functional equivalence using the integrated lock-step simulator (requires `avr-gdb` and `py65`):

```bash
uv run scripts/verify.py tests/test_alu.asm
```

The verify tool automatically assembles the AVR source, translates it, and compares the register/memory states of both processors in real-time.

### Stress Testing

The `tests/sha256.zig` cryptographic test and `tests/test_crazy.zig` bounds test validate the translator under extreme load. The `sha256` test successfully hashes strings over ~110,000 continuous 6502 cycles without failure, demonstrating absolute memory and state equivalence. Extensive Zig Standard Library Torture Tests have also mapped out exact compiler bounds and `.rodata` limitations across the AVR-freestanding ecosystem.

---
*Developed by the avr2mos team. For deeper architectural details, see the inline comments in the source.*
