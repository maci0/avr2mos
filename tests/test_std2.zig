const std = @import("std");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    while (true) {}
}

export var rand_result: u64 = 0;
export var base64_out: [32]u8 = [_]u8{0} ** 32;
export var alloc_val_1: u16 = 0;
export var alloc_val_2: u16 = 0;

export fn main() void {
    // 1. Test SplitMix64 PRNG
    var prng = std.Random.SplitMix64.init(0x1234567890ABCDEF);
    rand_result = prng.next();

    // 2. Base64 is unsupported on AVR due to Zig 0.15 stdlib `usize` bugs.

    // 3. Test FixedBufferAllocator
    var buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    if (allocator.create(u16)) |ptr| {
        ptr.* = 0xBEEF;
        alloc_val_1 = ptr.*;
    } else |_| {}

    if (allocator.alloc(u16, 4)) |slice| {
        slice[3] = 0xCAFE;
        alloc_val_2 = slice[3];
    } else |_| {}
}

export fn _start() void {
    main();
    while (true) {}
}

export fn memcpy(dest: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dest[i] = src[i];
    }
    return dest;
}

export fn memset(dest: [*]u8, val: u8, n: usize) [*]u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dest[i] = val;
    }
    return dest;
}
