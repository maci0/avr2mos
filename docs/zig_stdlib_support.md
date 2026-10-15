# Zig Standard Library (std) 6502 Translation Support Matrix

The `avr2mos` translator converts freestanding AVR (Atmega328p) object code into 6502 machine code. Because the target environment (a bare-metal 6502 or CHIP-8 equivalent) lacks an operating system, dynamic memory segment, or syscall interface, much of the Zig standard library is philosophically unsupported or mathematically impractical for an 8-bit CPU.

This table documents the state of the Zig Standard Library mapped to `avr2mos`.

| Zig `std` Module | Category | Tested? | Status/Reasoning |
| :--- | :--- | :--- | :--- |
| `std.mem` | Memory Manipulation (`sort`, `indexOf`, etc) | **YES** | **Supported**. Functions like `sortUnstable` and `indexOfScalar` compile seamlessly to inline loops and translate perfectly. |
| `std.hash` | Cryptographic/Non-Crypto Hashing | **YES** | **Supported**. Algorithms like `Wyhash` and `SHA256` work natively, but loop unrolling of 32-bit arithmetic can easily exceed the 6502's 64KB address space (e.g., `std.crypto.hash.sha2.Sha256` translates to >100KB). Handcrafted loops are required for large algorithms. |
| `std.math` | Mathematics & Bitwise Ops | **YES** | **Supported**. Basic 8/16/32-bit math translates fine. **Caveat**: Heavy division/modulo (`%`, `/`) triggers missing `compiler_rt` float/div routines (`__udivmodhi4`) on AVR. |
| `std.crypto` | Cryptography algorithms | **PARTIAL**| **Limited by ROM Size**. The algorithms technically translate flawlessly, but their generic implementations rely heavy on unrolled loops and `comptime` tables that cause `.text` segments to balloon past 64KB when broken down into 8-bit math. |
| `std.heap` | Memory Allocation | **YES** | **Supported (Static)**. We confirmed that `std.heap.FixedBufferAllocator` correctly dynamically segments an existing static byte-array safely without triggering float traps or MMU calls. However, `page_allocator`/`c_allocator` are fundamentally impossible on bare-metal. |
| `std.fmt` | String Formatting | **NO** | **Impossible**. String formatting requires pulling in `std.io.Writer`, generic type unwrapping, and floating-point conversion logic which completely breaks `compiler_rt` and balloons the binary size astronomically. |
| `std.io` | File/Stream IO | **NO** | **Impossible**. Relies on a host OS syscall layer (`write`, `read`) which doesn't exist on bare-metal 6502 without custom runtime hooks. |
| `std.fs` | Filesystem | **NO** | **Impossible**. Relies on POSIX/Windows kernel drivers. |
| `std.net` | Networking | **NO** | **Impossible**. Requires a host socket layer. |
| `std.os` / `std.posix` | Operating System Primitives | **NO** | **Impossible**. Bare-metal target. |
| `std.thread` / `std.Mutex`| Multithreading & Concurrency | **NO** | **Impossible**. 6502 is a single-core scalar processor. AVR lacks atomic primitives by default. |
| `std.time` | Timekeeping / Clocks | **NO** | **Impossible**. Requires OS-level RTC or hardware timers. |
| `std.base64` | Base64 En/Decoding | **NO** | **Impossible (Current Zig Bug)**. The Zig 0.15 implementation uses `u32` masks to index alphabet arrays. On an 8-bit AVR, `usize` is 16-bit (`u16`), triggering a hard compile error since 32-bit unsigned integers cannot safely coerce into 16-bit pointers. |
| `std.json` | JSON Parsing | **NO** | **Impossible**. JSON parsing heavily relies on dynamic allocation (`std.heap.page_allocator`) and floating-point numeric parsing (`f64`). |
| `std.Random` | Pseudo-Random Num Gen | **YES** | **Supported**. We verified that `std.Random.SplitMix64` 64-bit multi-register PRNG logic correctly cascades and evaluates over the 8-bit registers of the 6502 backend via `avr2mos`. |
| `std.simd` / `@Vector`| SIMD CPU Vectorization | **YES** | **Supported**. Basic vector operations map to chained scalar ALU instructions via LLVM lowering to AVR. |

## Collection & Data Structure Support
The standard generic collections provided by Zig have been explicitly tested in the `avr2mos` test gauntlet and **found to be fundamentally incompatible with the bare-metal 16-bit AVR/6502 backend** in Zig 0.15.

| Data Structure / Module | Status | Constraint |
| :--- | :--- | :--- |
| `ArrayList`, `ArrayListUnmanaged`, `ArrayHashMap`, `MultiArrayList` | **Impossible** | Capacity growth bounds Math inherently defaults to evaluating fractional floats via compiler-rt which balloons to unsupported 19-bit `f64` scale routines, panicking the ICE. |
| `AutoHashMap`, `HashMap`, `StringHashMap`, `StaticStringMap` | **Impossible** | Hardcodes `u32` for entry indices and array offsets. Overflows 16-bit (`usize = u16`) bare-metal targets instantly. |
| `DynamicBitSet`, `StaticBitSet`, `BitStack` | **Impossible** | 32-bit and 64-bit shifting/masking fallback logic hits unimplemented LLVM builtins on AVR freestanding targets, severely returning a SIGSEGV. |
| `Deque`, `PriorityQueue`, `DoublyLinkedList`, `SinglyLinkedList` | **Impossible** | Recursive optional pointer chains `?*Node` inside strictly aligned 8-byte padding boundary limits trigger ICE loop evaluations inside the generic LLVM backend. |
| `EnumArray`, `EnumMap`, `EnumSet` | **Supported** | Extremely primitive compile-time logic maps safely. |
| `BufMap`, `BufSet` | **Impractical** | Heavy dynamic string allocation risks blowing the 64KB ROM bounds. |

**Important Note**: To write any collection logic for bare-metal AVR traversing to MOS 6502, you **must** write handcrafted static arrays (`[N]T`) and handle bounds checking manually. Standard `std.heap.FixedBufferAllocator` can be used exclusively for raw memory reservations `slice(T, len)`. All high-level wrappers dynamically segfault the compiler.
