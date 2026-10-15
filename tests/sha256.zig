// Standalone SHA256 in Zig to avoid compiler_rt float dependencies from std lib.

const K = [_]u32{ 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 };

fn rightRotate(val: u32, shift: u5) u32 {
    const inv_shift = @as(u5, @truncate(32 - @as(u32, shift)));
    return (val >> shift) | (val << inv_shift);
}

fn sha256_hash(msg: []const u8, out: *[32]u8) void {
    var h0: u32 = 0x6a09e667;
    var h1: u32 = 0xbb67ae85;
    var h2: u32 = 0x3c6ef372;
    var h3: u32 = 0xa54ff53a;
    var h4: u32 = 0x510e527f;
    var h5: u32 = 0x9b05688c;
    var h6: u32 = 0x1f83d9ab;
    var h7: u32 = 0x5be0cd19;

    var padded: [64]u8 = [_]u8{0} ** 64;
    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        padded[i] = msg[i];
    }
    padded[msg.len] = 0x80;

    // Length in bits (msg.len * 8). Assuming msg.len < 56
    const bit_len: u32 = @as(u32, @intCast(msg.len)) * 8;
    padded[60] = @as(u8, @truncate(bit_len >> 24));
    padded[61] = @as(u8, @truncate(bit_len >> 16));
    padded[62] = @as(u8, @truncate(bit_len >> 8));
    padded[63] = @as(u8, @truncate(bit_len));

    var w: [64]u32 = undefined;
    var j: usize = 0;
    while (j < 16) : (j += 1) {
        w[j] = (@as(u32, padded[j * 4]) << 24) |
            (@as(u32, padded[j * 4 + 1]) << 16) |
            (@as(u32, padded[j * 4 + 2]) << 8) |
            (@as(u32, padded[j * 4 + 3]));
    }

    while (j < 64) : (j += 1) {
        const s0 = rightRotate(w[j - 15], 7) ^ rightRotate(w[j - 15], 18) ^ (w[j - 15] >> 3);
        const s1 = rightRotate(w[j - 2], 17) ^ rightRotate(w[j - 2], 19) ^ (w[j - 2] >> 10);
        w[j] = w[j - 16] +% s0 +% w[j - 7] +% s1;
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var hh = h7;

    j = 0;
    while (j < 64) : (j += 1) {
        const s1 = rightRotate(e, 6) ^ rightRotate(e, 11) ^ rightRotate(e, 25);
        const ch = (e & f) ^ (~e & g);
        const temp1 = hh +% s1 +% ch +% K[j] +% w[j];
        const s0 = rightRotate(a, 2) ^ rightRotate(a, 13) ^ rightRotate(a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const temp2 = s0 +% maj;

        hh = g;
        g = f;
        f = e;
        e = d +% temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 +% temp2;
    }

    h0 +%= a;
    h1 +%= b;
    h2 +%= c;
    h3 +%= d;
    h4 +%= e;
    h5 +%= f;
    h6 +%= g;
    h7 +%= hh;

    out[0] = @as(u8, @truncate(h0 >> 24));
    out[1] = @as(u8, @truncate(h0 >> 16));
    out[2] = @as(u8, @truncate(h0 >> 8));
    out[3] = @as(u8, @truncate(h0));
    out[4] = @as(u8, @truncate(h1 >> 24));
    out[5] = @as(u8, @truncate(h1 >> 16));
    out[6] = @as(u8, @truncate(h1 >> 8));
    out[7] = @as(u8, @truncate(h1));
    out[8] = @as(u8, @truncate(h2 >> 24));
    out[9] = @as(u8, @truncate(h2 >> 16));
    out[10] = @as(u8, @truncate(h2 >> 8));
    out[11] = @as(u8, @truncate(h2));
    out[12] = @as(u8, @truncate(h3 >> 24));
    out[13] = @as(u8, @truncate(h3 >> 16));
    out[14] = @as(u8, @truncate(h3 >> 8));
    out[15] = @as(u8, @truncate(h3));
    out[16] = @as(u8, @truncate(h4 >> 24));
    out[17] = @as(u8, @truncate(h4 >> 16));
    out[18] = @as(u8, @truncate(h4 >> 8));
    out[19] = @as(u8, @truncate(h4));
    out[20] = @as(u8, @truncate(h5 >> 24));
    out[21] = @as(u8, @truncate(h5 >> 16));
    out[22] = @as(u8, @truncate(h5 >> 8));
    out[23] = @as(u8, @truncate(h5));
    out[24] = @as(u8, @truncate(h6 >> 24));
    out[25] = @as(u8, @truncate(h6 >> 16));
    out[26] = @as(u8, @truncate(h6 >> 8));
    out[27] = @as(u8, @truncate(h6));
    out[28] = @as(u8, @truncate(h7 >> 24));
    out[29] = @as(u8, @truncate(h7 >> 16));
    out[30] = @as(u8, @truncate(h7 >> 8));
    out[31] = @as(u8, @truncate(h7));
}

export var result: [32]u8 = [_]u8{0} ** 32;

export fn main() void {
    const msg = "avr2mos_torture_test";
    sha256_hash(msg, &result);
}

export fn _halt() void {}

export fn _start() void {
    main();
    _halt();
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
