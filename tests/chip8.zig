var rom = @embedFile("chip8-test-suite/bin/3-corax+.ch8");

pub const Chip8 = extern struct {
    memory: [1024]u8 = [_]u8{0} ** 1024,
    V: [16]u8 = [_]u8{0} ** 16,
    I: u16 = 0,
    pc: u16 = 0x200,
    stack: [16]u16 = [_]u16{0} ** 16,
    sp: u8 = 0,
    display: [32][8]u8 = [_][8]u8{[_]u8{0} ** 8} ** 32,
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,

    pub fn loadROM(self: *Chip8, param_rom: []const u8) void {
        var i: usize = 0;
        while (i < param_rom.len) : (i += 1) {
            self.memory[0x200 + i] = param_rom[i];
        }
    }

    pub fn step(self: *Chip8) void {
        const opcode = (@as(u16, self.memory[self.pc]) << 8) | self.memory[self.pc + 1];
        self.pc += 2;

        const nnn = opcode & 0x0FFF;
        const n = @as(u8, @truncate(opcode & 0x000F));
        const x = @as(u4, @truncate((opcode & 0x0F00) >> 8));
        const y = @as(u4, @truncate((opcode & 0x00F0) >> 4));
        const kk = @as(u8, @truncate(opcode & 0x00FF));

        switch (opcode & 0xF000) {
            0x0000 => {
                switch (kk) {
                    0xE0 => { // CLS
                        for (&self.display) |*row| {
                            for (row) |*byte| {
                                byte.* = 0;
                            }
                        }
                    },
                    0xEE => { // RET
                        self.sp -%= 1;
                        self.pc = self.stack[self.sp];
                    },
                    else => {},
                }
            },
            0x1000 => { // JP addr
                self.pc = nnn;
            },
            0x2000 => { // CALL addr
                self.stack[self.sp] = self.pc;
                self.sp +%= 1;
                self.pc = nnn;
            },
            0x3000 => { // SE Vx, byte
                if (self.V[x] == kk) self.pc += 2;
            },
            0x4000 => { // SNE Vx, byte
                if (self.V[x] != kk) self.pc += 2;
            },
            0x5000 => { // SE Vx, Vy
                if (self.V[x] == self.V[y]) self.pc += 2;
            },
            0x6000 => { // LD Vx, byte
                self.V[x] = kk;
            },
            0x7000 => { // ADD Vx, byte
                self.V[x] +%= kk;
            },
            0x8000 => {
                switch (n) {
                    0x0 => {
                        self.V[x] = self.V[y];
                    }, // LD Vx, Vy
                    0x1 => {
                        self.V[x] |= self.V[y];
                        self.V[15] = 0;
                    }, // OR Vx, Vy
                    0x2 => {
                        self.V[x] &= self.V[y];
                        self.V[15] = 0;
                    }, // AND Vx, Vy
                    0x3 => {
                        self.V[x] ^= self.V[y];
                        self.V[15] = 0;
                    }, // XOR Vx, Vy
                    0x4 => { // ADD Vx, Vy
                        const sum = @as(u16, self.V[x]) + self.V[y];
                        self.V[x] = @truncate(sum);
                        self.V[15] = if (sum > 255) 1 else 0;
                    },
                    0x5 => { // SUB Vx, Vy
                        const borrow = if (self.V[x] >= self.V[y]) @as(u8, 1) else 0;
                        self.V[x] -%= self.V[y];
                        self.V[15] = borrow;
                    },
                    0x6 => { // SHR Vx {, Vy}
                        self.V[x] = self.V[y];
                        const bit = self.V[x] & 1;
                        self.V[x] >>= 1;
                        self.V[15] = bit;
                    },
                    0x7 => { // SUBN Vx, Vy
                        const borrow = if (self.V[y] >= self.V[x]) @as(u8, 1) else 0;
                        self.V[x] = self.V[y] -% self.V[x];
                        self.V[15] = borrow;
                    },
                    0xE => { // SHL Vx {, Vy}
                        self.V[x] = self.V[y];
                        const bit = (self.V[x] >> 7) & 1;
                        self.V[x] <<= 1;
                        self.V[15] = bit;
                    },
                    else => {},
                }
            },
            0x9000 => { // SNE Vx, Vy
                if (self.V[x] != self.V[y]) self.pc += 2;
            },
            0xA000 => { // LD I, addr
                self.I = nnn;
            },
            0xB000 => { // JP V0, addr
                self.pc = nnn + self.V[0];
            },
            0xC000 => { // RND Vx, byte
                // Deterministic PRNG for testing
                self.V[x] = 0x42 & kk;
            },
            0xD000 => { // DRW Vx, Vy, nibble
                const px = self.V[x] & 63;
                const py = self.V[y] & 31;
                self.V[15] = 0;

                var row: u16 = 0;
                while (row < n) : (row += 1) {
                    if (py + row >= 32) break;
                    const sprite_byte = self.memory[self.I + row];

                    var col: u16 = 0;
                    while (col < 8) : (col += 1) {
                        if (px + col >= 64) break;

                        const bit = @as(u8, @truncate((sprite_byte >> @as(u3, @truncate(7 - col))) & 1));

                        const byte_idx = @as(usize, px + col) >> 3;
                        const bit_idx = @as(u3, @truncate(7 - ((px + col) & 7)));
                        const mask = @as(u8, 1) << bit_idx;

                        if (bit == 1) {
                            if ((self.display[py + row][byte_idx] & mask) != 0) {
                                self.V[15] = 1;
                            }
                            self.display[py + row][byte_idx] ^= mask;
                        }
                    }
                }
            },
            0xE000 => {
                switch (kk) {
                    0x9E => { // SKP Vx
                        // Keypad ignored for now
                    },
                    0xA1 => { // SKNP Vx
                        self.pc += 2; // Always not pressed
                    },
                    else => {},
                }
            },
            0xF000 => {
                switch (kk) {
                    0x07 => {
                        self.V[x] = self.delay_timer;
                    },
                    0x15 => {
                        self.delay_timer = self.V[x];
                    },
                    0x18 => {
                        self.sound_timer = self.V[x];
                    },
                    0x1E => {
                        self.I +%= self.V[x];
                    },
                    0x29 => { // LD F, Vx
                        // self.I = self.V[x] * 5; // standard font
                    },
                    0x33 => { // LD B, Vx
                        var val = self.V[x];
                        var hundreds: u8 = 0;
                        if (val >= 200) {
                            val -= 200;
                            hundreds += 2;
                        } else if (val >= 100) {
                            val -= 100;
                            hundreds += 1;
                        }

                        var tens: u8 = 0;
                        if (val >= 90) {
                            val -= 90;
                            tens += 9;
                        } else if (val >= 80) {
                            val -= 80;
                            tens += 8;
                        } else if (val >= 70) {
                            val -= 70;
                            tens += 7;
                        } else if (val >= 60) {
                            val -= 60;
                            tens += 6;
                        } else if (val >= 50) {
                            val -= 50;
                            tens += 5;
                        } else if (val >= 40) {
                            val -= 40;
                            tens += 4;
                        } else if (val >= 30) {
                            val -= 30;
                            tens += 3;
                        } else if (val >= 20) {
                            val -= 20;
                            tens += 2;
                        } else if (val >= 10) {
                            val -= 10;
                            tens += 1;
                        }
                        self.memory[self.I] = hundreds;
                        self.memory[self.I + 1] = tens;
                        self.memory[self.I + 2] = val;
                    },
                    0x55 => { // LD [I], Vx
                        var idx: usize = 0;
                        while (idx <= x) : (idx += 1) {
                            self.memory[self.I + idx] = self.V[idx];
                        }
                        self.I += x + 1; // Or just x for original semantics
                    },
                    0x65 => { // LD Vx, [I]
                        var idx: usize = 0;
                        while (idx <= x) : (idx += 1) {
                            self.V[idx] = self.memory[self.I + idx];
                        }
                        self.I += x + 1;
                    },
                    else => {},
                }
            },
            else => {},
        }
    }
};

export var vm: Chip8 = .{};

export fn main() void {
    vm.loadROM(rom);

    var iter: usize = 0;
    while (iter < 1000) : (iter += 1) {
        vm.step();
    }
}

export fn _start() void {
    main();
    while (true) {}
}
