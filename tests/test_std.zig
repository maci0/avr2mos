const std = @import("std");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    while (true) {}
}

const Point = extern struct {
    x: u8,
    y: u8,
};

fn lessThan(context: void, a: Point, b: Point) bool {
    _ = context;
    if (a.x == b.x) return a.y < b.y;
    return a.x < b.x;
}

export var result_sorted: [5]Point = undefined;
export var result_rand: u64 = 0;
export var index_found: i16 = -1;
export var bounded_len: u8 = 0;

export fn main() void {
    // 1. Test std.sort
    var arr = [_]Point{
        .{ .x = 5, .y = 10 },
        .{ .x = 1, .y = 2 },
        .{ .x = 5, .y = 1 },
        .{ .x = 3, .y = 4 },
        .{ .x = 2, .y = 2 },
    };
    std.mem.sortUnstable(Point, &arr, {}, lessThan);
    for (arr, 0..) |p, i| {
        result_sorted[i] = p;
    }

    // 2. Test std.hash (Wyhash 64-bit hashing algorithm)
    result_rand = std.hash.Wyhash.hash(0, "avr2mos_stdlib_test");

    // 3. Test std.mem.indexOf
    const search_data = "avr2mos_hello_world";
    if (std.mem.indexOfScalar(u8, search_data, 'w')) |idx| {
        index_found = @intCast(idx);
    }
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
