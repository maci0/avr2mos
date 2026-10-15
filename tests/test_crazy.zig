const std = @import("std");

var accumulator: u16 = 0;

// Test standard array bounds and index manipulation
fn testArrayLogic() u16 {
    const arr: [8]u16 = [_]u16{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var sum: u16 = 0;
    var i: u16 = 0;
    while (i < 8) : (i += 1) {
        if (i % 2 == 0) {
            sum += arr[i] * 2;
        } else {
            sum += arr[i];
        }
    }
    return sum;
}

// Test multi-level nested function calls simulating recursion depth bounds
fn depth3(v: u16) u16 {
    return v ^ 0x0F0F;
}
fn depth2(v: u16) u16 {
    return depth3(v) + 10;
}
fn depth1(v: u16) u16 {
    return depth2(v) - 5;
}

export fn _start() void {
    const arr_sum = testArrayLogic();
    const depth_val = depth1(0x1234);

    accumulator = arr_sum + depth_val;

    while (true) {}
}
