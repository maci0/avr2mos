const std = @import("std");

// --- From test_zig.zig ---
export fn process_simple(a: u8, b: u8) u8 {
    var c = a +% b;
    c = c ^ 0x55;
    return c;
}

// --- From test_zig_complex.zig ---
const Point = packed struct {
    x: u8,
    y: u8,
    flags: u8,
};

pub fn processPoints(points: [*]Point, len: usize) u8 {
    var checksum: u8 = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const pt = points[i];
        if (pt.flags & 0x01 != 0) {
            checksum +%= pt.x;
            checksum ^= pt.y;
        }
    }
    return checksum;
}

// --- From test_zig_extreme.zig ---
// 1. Complex Datastructures: Doubly Linked List Node featuring optionals
const Node = struct {
    value: u32,
    prev: ?*Node,
    next: ?*Node,
};

// Simulated allocations
var node_pool: [10]Node = undefined;
var pool_idx: usize = 0;

fn allocNode(val: u32) *Node {
    const node = &node_pool[pool_idx];
    pool_idx += 1;
    node.* = .{ .value = val, .prev = null, .next = null };
    return node;
}

// 2. Heavy 32-bit Mathematics: ChaCha20 Quarter Round
fn rotl32(x: u32, n: u5) u32 {
    return std.math.rotl(u32, x, n);
}

fn quarterRound(state: *[16]u32, a: usize, b: usize, c: usize, d: usize) void {
    state[a] +%= state[b];
    state[d] ^= state[a];
    state[d] = rotl32(state[d], 16);
    state[c] +%= state[d];
    state[b] ^= state[c];
    state[b] = rotl32(state[b], 12);
    state[a] +%= state[b];
    state[d] ^= state[a];
    state[d] = rotl32(state[d], 8);
    state[c] +%= state[d];
    state[b] ^= state[c];
    state[b] = rotl32(state[b], 7);
}

fn chacha20Block(state: *[16]u32) void {
    var working_state: [16]u32 = undefined;
    for (0..16) |idx| {
        working_state[idx] = state[idx];
    }

    // 10 internal iterations (20 rounds)
    var i: u8 = 0;
    while (i < 10) : (i += 1) {
        quarterRound(&working_state, 0, 4, 8, 12);
        quarterRound(&working_state, 1, 5, 9, 13);
        quarterRound(&working_state, 2, 6, 10, 14);
        quarterRound(&working_state, 3, 7, 11, 15);
        quarterRound(&working_state, 0, 5, 10, 15);
        quarterRound(&working_state, 1, 6, 11, 12);
        quarterRound(&working_state, 2, 7, 8, 13);
        quarterRound(&working_state, 3, 4, 9, 14);
    }

    var j: usize = 0;
    while (j < 16) : (j += 1) {
        state[j] +%= working_state[j];
    }
}

// Added complexity: Recursive Fibonacci
fn fibonacci(n: u32) u32 {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

// Added complexity: Sorting algorithm on fixed array
fn bubbleSort(arr: []u8) void {
    var n = arr.len;
    var swapped = true;
    while (swapped) {
        swapped = false;
        var i: usize = 1;
        while (i < n) : (i += 1) {
            if (arr[i - 1] > arr[i]) {
                const temp = arr[i - 1];
                arr[i - 1] = arr[i];
                arr[i] = temp;
                swapped = true;
            }
        }
        n -= 1;
    }
}

// Added complexity: Tagged Unions and Switches
const Instruction = union(enum) {
    add: struct { a: u8, b: u8 },
    sub: struct { a: u8, b: u8 },
    halt: void,
};

fn executeInstruction(inst: Instruction) u8 {
    return switch (inst) {
        .add => |data| data.a +% data.b,
        .sub => |data| data.a -% data.b,
        .halt => 0,
    };
}

// Added complexity: Errors, defer, errdefer
const MyError = error{
    TooLarge,
    IsZero,
};

fn performCalculation(val: u8) MyError!u8 {
    if (val == 0) return MyError.IsZero;
    if (val > 100) return MyError.TooLarge;

    var temp: u8 = val;
    defer temp +%= 1;
    errdefer temp = 0xFF;

    return temp *% 2;
}

// Added complexity: Comptime evaluation
fn computeComptimeValue() u8 {
    comptime var res: u8 = 0;
    comptime {
        for (0..5) |i| {
            res += @as(u8, @intCast(i));
        }
    }
    return res; // 0+1+2+3+4 = 10
}

// Removed arbitrary sized integers as they crash the Zig AVR compiler-rt linker

// Added complexity: Vectors, Generics, Tuples, Function Pointers, Inline Loops
fn genericOp(comptime T: type, a: T, b: T) T {
    return a +% b;
}

// Global function pointer target
fn multiplyByTwo(x: u8) u8 {
    return x *% 2;
}

fn testExtremeFeatures() u8 {
    // 1. Vector Math
    const v1: @Vector(4, u16) = .{ 10, 20, 30, 40 };
    const v2: @Vector(4, u16) = .{ 1, 2, 3, 4 };
    const v3 = v1 + v2; // {11, 22, 33, 44}

    // 2. Tuples / Anonymous Structs
    const my_tuple = .{ @as(u8, 100), @as(u16, 200), @as(u32, 300) };

    // 3. Generics (anytype / comptime type)
    const gen_res = genericOp(u8, 55, 45); // 100

    // 4. Function Pointers
    const func_ptr: *const fn (u8) u8 = multiplyByTwo;
    const fp_res = func_ptr(10); // 20

    // 5. Inline For loops
    var inline_sum: u8 = 0;
    inline for (.{ 1, 2, 3, 4, 5 }) |val| {
        inline_sum += val;
    } // 15

    // Mix them all up
    var mixed: u8 = 0;
    mixed ^= @as(u8, @truncate(v3[0])) ^ @as(u8, @truncate(v3[3]));
    mixed ^= my_tuple[0] ^ @as(u8, @truncate(my_tuple[1]));
    mixed ^= gen_res;
    mixed ^= fp_res;
    mixed ^= inline_sum;

    return mixed;
}

// Removed Wyhash as 64-bit math currently triggers a Zig AVR compiler-rt bug.
export fn main() void {
    // ---- Test Simple Process ----
    const p1 = @as(*volatile u8, @ptrFromInt(0x21));
    const p2 = @as(*volatile u8, @ptrFromInt(0x22));
    const out_simple = process_simple(p1.*, p2.*);

    // ---- Test Complex Points ----
    const p1_c = @as(*volatile u8, @ptrFromInt(0x0110));
    const p2_c = @as(*volatile u8, @ptrFromInt(0x0113));
    p1_c.* = 10;
    p2_c.* = 20;
    const points_buf = @as([*]Point, @ptrCast(@as(*anyopaque, @ptrFromInt(0x0110))));
    const out_complex = processPoints(points_buf, 2);

    // ---- Test Extreme List/ChaCha ----
    const root = allocNode(0x11111111);
    const n1 = allocNode(0x22222222);
    const n2 = allocNode(0x33333333);
    root.next = n1;
    n1.prev = root;
    n1.next = n2;
    n2.prev = n1;

    var curr: ?*Node = root;
    var sum: u32 = 0;
    while (curr) |c| {
        sum +%= c.value;
        curr = c.next;
    }

    var state: [16]u32 = undefined;
    state[0] = 0x61707865;
    state[1] = 0x3320646e;
    state[2] = 0x79622d32;
    state[3] = 0x6b206574;

    var k: usize = 4;
    while (k < 12) : (k += 1) {
        state[k] = sum +% @as(u32, @intCast(k));
    }
    state[12] = 1;
    state[13] = 0;
    state[14] = 0x4A000000;
    state[15] = 0x00000000;

    chacha20Block(&state);
    const out_extreme: u8 = @truncate(state[0] ^ state[15]);

    // ---- Added Complexity Tests ----
    const fib_val = fibonacci(6);

    var sort_arr = [_]u8{ 5, 2, 9, 1, 5, 6 };
    bubbleSort(&sort_arr);

    // ---- More Added Complexity Tests ----
    const union_val = executeInstruction(Instruction{ .add = .{ .a = 15, .b = 25 } });

    var err_val: u8 = 0;
    if (performCalculation(50)) |v| {
        err_val = v; // Should be 100
    } else |err| {
        if (err == MyError.IsZero) {
            err_val = 1;
        } else {
            err_val = 255;
        }
    }

    const comptime_val = computeComptimeValue(); // 10

    const extreme_val = testExtremeFeatures();

    // Output final results
    const out_ptr = @as(*volatile u8, @ptrFromInt(0x20));
    out_ptr.* = out_simple ^ out_complex ^ out_extreme ^ @as(u8, @truncate(fib_val)) ^ sort_arr[0] ^ union_val ^ err_val ^ comptime_val ^ extreme_val;
}
