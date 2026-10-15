const std = @import("std");

pub const Label = u16;

pub const Fixup = struct {
    offset: usize,
    target_addr: u16,
};

pub const Emitter = struct {
    bytes: std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    labels: std.AutoHashMap(u16, usize), // AVR addr -> 6502 offset
    fixups: std.ArrayListUnmanaged(Fixup),

    pub fn init(allocator: std.mem.Allocator) Emitter {
        return Emitter{
            .bytes = .{},
            .allocator = allocator,
            .labels = std.AutoHashMap(u16, usize).init(allocator),
            .fixups = .{},
        };
    }

    pub fn deinit(self: *Emitter) void {
        self.bytes.deinit(self.allocator);
        self.labels.deinit();
        self.fixups.deinit(self.allocator);
    }

    pub fn defineLabel(self: *Emitter, avr_addr: u16) !void {
        try self.labels.put(avr_addr, self.bytes.items.len);
    }

    fn addFixup(self: *Emitter, target_avr_addr: u16) !void {
        try self.fixups.append(self.allocator, .{
            .offset = self.bytes.items.len,
            .target_addr = target_avr_addr,
        });
        try self.emitWord(0x0000); // Placeholder
    }

    pub fn resolveFixups(self: *Emitter, base_addr: u16) !void {
        for (self.fixups.items) |fixup| {
            if (self.labels.get(fixup.target_addr)) |offset| {
                const target_6502 = base_addr + @as(u16, @intCast(offset));
                // Replace the word at fixup.offset
                self.bytes.items[fixup.offset] = @truncate(target_6502);
                self.bytes.items[fixup.offset + 1] = @truncate(target_6502 >> 8);
            } else {
                std.debug.print("Warning: Unresolved label: 0x{X}\n", .{fixup.target_addr});
            }
        }
    }

    pub fn generateJumpTable(self: *Emitter, base_addr: u16) !u16 {
        const count = self.labels.count();
        if (count == 0) return 0;

        const start_offset = self.bytes.items.len;
        const table_6502_addr = base_addr + @as(u16, @intCast(start_offset));

        var keys = std.ArrayListUnmanaged(u16){};
        defer keys.deinit(self.allocator);
        var values = std.ArrayListUnmanaged(u16){};
        defer values.deinit(self.allocator);

        var it = self.labels.iterator();
        while (it.next()) |entry| {
            try keys.append(self.allocator, entry.key_ptr.*);
            // NESDev Optimization: - 1 for RTS Trick! Use wrapping subtraction so we don't crash on absolute 0.
            try values.append(self.allocator, (base_addr + @as(u16, @intCast(entry.value_ptr.*))) -% 1);
        }

        // For now, linear search is okay if count is small.
        // Parallel arrays for better 6502 indexing.

        // table_avr_lo
        for (keys.items) |k| try self.emitByte(@truncate(k));
        // table_avr_hi
        for (keys.items) |k| try self.emitByte(@truncate(k >> 8));
        // table_6502_lo
        for (values.items) |v| try self.emitByte(@truncate(v));
        // table_6502_hi
        for (values.items) |v| try self.emitByte(@truncate(v >> 8));

        return table_6502_addr;
    }

    pub fn emitDataSection(self: *Emitter, base_addr: u16, target_addr: u16, data: []const u8) !void {
        const current_offset = @as(u16, @intCast(self.bytes.items.len));
        const target_offset = target_addr - base_addr;

        if (target_offset < current_offset) {
            return error.DataTargetAddressTooLow;
        }

        // Fill with zeros until target_offset
        const padding = target_offset - current_offset;
        for (0..padding) |_| try self.emitByte(0x00);

        // Append data, gracefully translating pointers mapped into the base_addr range directly into output 6502 logic
        var i: usize = 0;
        while (i < data.len) {
            // Can we form a 16-bit word natively at this offset safely?
            if (i + 1 < data.len) {
                const word = std.mem.readInt(u16, data[i .. i + 2][0..2], .little);
                if (word >= base_addr) {
                    // It is a valid absolute address mathematically matching our .text boundaries!
                    // If we translated it, substitute the true M6502 VMA mapping in little endian instead
                    const avr_offset = word - base_addr;
                    if (self.labels.get(avr_offset)) |translated_offset| {
                        const m6502_addr = base_addr + @as(u16, @intCast(translated_offset));
                        try self.emitByte(@truncate(m6502_addr));
                        try self.emitByte(@truncate(m6502_addr >> 8));
                        i += 2;
                        continue;
                    }
                }
            }
            try self.emitByte(data[i]);
            i += 1;
        }
    }

    pub fn generateReport(self: *Emitter, base_addr: u16) ![]u8 {
        var list = std.ArrayListUnmanaged(u8){};
        errdefer list.deinit(self.allocator);
        const writer = list.writer(self.allocator);

        try writer.print("AVR Address -> 6502 Address Translation Report\n", .{});
        try writer.print("---------------------------------------------\n", .{});

        var keys = std.ArrayListUnmanaged(u16){};
        defer keys.deinit(self.allocator);
        var it = self.labels.keyIterator();
        while (it.next()) |k| try keys.append(self.allocator, k.*);
        std.mem.sort(u16, keys.items, {}, std.sort.asc(u16));

        for (keys.items) |avr_addr| {
            const offset = self.labels.get(avr_addr).?;
            const m6502_addr = base_addr + @as(u16, @intCast(offset));
            try writer.print("0x{X:04} -> 0x{X:04}\n", .{ avr_addr, m6502_addr });
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn generateSymbolMap(self: *Emitter, base_addr: u16) ![]u8 {
        var list = std.ArrayListUnmanaged(u8){};
        errdefer list.deinit(self.allocator);
        const writer = list.writer(self.allocator);

        var keys = std.ArrayListUnmanaged(u16){};
        defer keys.deinit(self.allocator);
        var it = self.labels.keyIterator();
        while (it.next()) |k| try keys.append(self.allocator, k.*);
        std.mem.sort(u16, keys.items, {}, std.sort.asc(u16));

        for (keys.items) |avr_addr| {
            const offset = self.labels.get(avr_addr).?;
            const m6502_addr = base_addr + @as(u16, @intCast(offset));
            try writer.print("L{X:04} = ${X:04}\n", .{ avr_addr, m6502_addr });
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn emitTrampoline(self: *Emitter, base_addr: u16, table_addr: u16, table_len: usize) !u16 {
        const start_offset = self.bytes.items.len;
        const tramp_addr = base_addr + @as(u16, @intCast(start_offset));

        // Trampoline (linear search)
        // LDX #table_len-1
        try self.emitLDX_imm(@intCast(table_len - 1));

        // @loop:
        const loop_offset = self.bytes.items.len;
        // LDA table_avr_lo, x
        try self.emitLDA_abs_x(table_addr);
        // CMP r30 ($1E)
        try self.emitCMP_zp(0x1E);
        // BNE @next
        try self.emitBNE_rel(7); // skip checking high byte and jumping to found

        // LDA table_avr_hi, x (at table_addr + len)
        try self.emitLDA_abs_x(table_addr + @as(u16, @intCast(table_len)));
        // CMP r31 ($1F)
        try self.emitCMP_zp(0x1F);
        // BEQ @found
        try self.emitBEQ_rel(7); // skip to found (DEX=1 + BMI=2 + JMP=3 + BRK=1 = 7)

        // @next:
        // DEX
        try self.emitDEX();
        // BMI @not_found
        try self.emitBMI_rel(3); // skip JMP @loop (3 bytes) to reach @not_found BRK

        // JMP @loop
        try self.emitJMP_abs(base_addr + @as(u16, @intCast(loop_offset)));

        // @not_found:
        try self.emitBRK();

        // @found: (addr relative to loop start)
        // RTS Trick: Push Target High, Push Target Low, RTS
        // LDA table_6502_hi, x (at table_addr + 3*len)
        try self.emitLDA_abs_x(table_addr + @as(u16, @intCast(table_len * 3)));
        try self.emitPHA();
        // LDA table_6502_lo, x (at table_addr + 2*len)
        try self.emitLDA_abs_x(table_addr + @as(u16, @intCast(table_len * 2)));
        try self.emitPHA();
        try self.emitRTS();

        return tramp_addr;
    }

    pub fn emitByte(self: *Emitter, byte: u8) !void {
        try self.bytes.append(self.allocator, byte);
    }

    fn emitWord(self: *Emitter, word: u16) !void {
        try self.emitByte(@truncate(word));
        try self.emitByte(@truncate(word >> 8));
    }

    // Add 6502 opcodes here as methods for convenience
    // NOP
    pub fn emitNOP(self: *Emitter) !void {
        try self.emitByte(0xEA);
    }

    // CLC
    pub fn emitCLC(self: *Emitter) !void {
        try self.emitByte(0x18);
    }

    // ADC zp
    pub fn emitADC_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0x65);
        try self.emitByte(zp);
    }

    // LDA zp
    pub fn emitLDA_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0xA5);
        try self.emitByte(zp);
    }

    // LDA #imm
    pub fn emitLDA_imm(self: *Emitter, imm: u8) !void {
        try self.emitByte(0xA9);
        try self.emitByte(imm);
    }

    // STA zp
    pub fn emitSTA_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0x85);
        try self.emitByte(zp);
    }
    // CMP zp
    pub fn emitCMP_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0xC5);
        try self.emitByte(zp);
    }

    // BNE rel
    pub fn emitBNE_rel(self: *Emitter, rel: i8) !void {
        try self.emitByte(0xD0);
        try self.emitByte(@bitCast(rel));
    }

    // INC zp
    pub fn emitINC_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0xE6);
        try self.emitByte(zp);
    }

    // JMP abs (internal: used by trampoline)
    fn emitJMP_abs(self: *Emitter, target: u16) !void {
        try self.emitByte(0x4C);
        try self.emitWord(target);
    }
    // LDY zp
    pub fn emitLDY_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0xA4);
        try self.emitByte(zp);
    }

    // RTS
    pub fn emitRTS(self: *Emitter) !void {
        try self.emitByte(0x60);
    }

    // RTI
    pub fn emitRTI(self: *Emitter) !void {
        try self.emitByte(0x40);
    }
    // AND #imm
    pub fn emitAND_imm(self: *Emitter, imm: u8) !void {
        try self.emitByte(0x29);
        try self.emitByte(imm);
    }

    // BEQ rel
    pub fn emitBEQ_rel(self: *Emitter, rel: i8) !void {
        try self.emitByte(0xF0);
        try self.emitByte(@bitCast(rel));
    }

    // PHA
    pub fn emitPHA(self: *Emitter) !void {
        try self.emitByte(0x48);
    }

    // PLA
    pub fn emitPLA(self: *Emitter) !void {
        try self.emitByte(0x68);
    }
    // DEX (internal: used by trampoline/runtime)
    fn emitDEX(self: *Emitter) !void {
        try self.emitByte(0xCA);
    }
    // TYA (internal: used by runtime)
    fn emitTYA(self: *Emitter) !void {
        try self.emitByte(0x98);
    }
    // LDA abs
    pub fn emitLDA_abs(self: *Emitter, addr: u16) !void {
        try self.emitByte(0xAD);
        try self.emitWord(addr);
    }

    // STA abs
    pub fn emitSTA_abs(self: *Emitter, addr: u16) !void {
        try self.emitByte(0x8D);
        try self.emitWord(addr);
    }
    // ADC #imm
    pub fn emitADC_imm(self: *Emitter, imm: u8) !void {
        try self.emitByte(0x69);
        try self.emitByte(imm);
    }

    // LSR zp
    pub fn emitLSR_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0x46);
        try self.emitByte(zp);
    }

    // LSR A
    pub fn emitLSR_A(self: *Emitter) !void {
        try self.emitByte(0x4A);
    }

    // ASL A
    pub fn emitASL_A(self: *Emitter) !void {
        try self.emitByte(0x0A);
    }

    // ROL A
    pub fn emitROL_A(self: *Emitter) !void {
        try self.emitByte(0x2A);
    }

    // ROR A (internal: used by FlipCarry/runtime)
    fn emitROR_A(self: *Emitter) !void {
        try self.emitByte(0x6A);
    }

    // ROR zp
    pub fn emitROR_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0x66);
        try self.emitByte(zp);
    }
    // ORA #imm
    pub fn emitORA_imm(self: *Emitter, imm: u8) !void {
        try self.emitByte(0x09);
        try self.emitByte(imm);
    }

    // DEC zp
    pub fn emitDEC_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0xC6);
        try self.emitByte(zp);
    }
    // SBC zp
    pub fn emitSBC_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0xE5);
        try self.emitByte(zp);
    }
    // SBC #imm
    pub fn emitSBC_imm(self: *Emitter, imm: u8) !void {
        try self.emitByte(0xE9);
        try self.emitByte(imm);
    }
    // AND zp
    pub fn emitAND_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0x25);
        try self.emitByte(zp);
    }
    // ORA zp
    pub fn emitORA_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0x05);
        try self.emitByte(zp);
    }
    // EOR zp
    pub fn emitEOR_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0x45);
        try self.emitByte(zp);
    }
    // EOR #imm
    pub fn emitEOR_imm(self: *Emitter, imm: u8) !void {
        try self.emitByte(0x49);
        try self.emitByte(imm);
    }
    // CMP #imm
    pub fn emitCMP_imm(self: *Emitter, imm: u8) !void {
        try self.emitByte(0xC9);
        try self.emitByte(imm);
    }
    // BCS rel
    pub fn emitBCS_rel(self: *Emitter, rel: i8) !void {
        try self.emitByte(0xB0);
        try self.emitByte(@bitCast(rel));
    }
    // BCC rel
    pub fn emitBCC_rel(self: *Emitter, rel: i8) !void {
        try self.emitByte(0x90);
        try self.emitByte(@bitCast(rel));
    }
    // BMI rel
    pub fn emitBMI_rel(self: *Emitter, rel: i8) !void {
        try self.emitByte(0x30);
        try self.emitByte(@bitCast(rel));
    }
    // BPL rel
    pub fn emitBPL_rel(self: *Emitter, rel: i8) !void {
        try self.emitByte(0x10);
        try self.emitByte(@bitCast(rel));
    }
    // BVS rel
    pub fn emitBVS_rel(self: *Emitter, rel: i8) !void {
        try self.emitByte(0x70);
        try self.emitByte(@bitCast(rel));
    }
    // BVC rel
    pub fn emitBVC_rel(self: *Emitter, rel: i8) !void {
        try self.emitByte(0x50);
        try self.emitByte(@bitCast(rel));
    }
    // SEC
    pub fn emitSEC(self: *Emitter) !void {
        try self.emitByte(0x38);
    }
    // SEI
    pub fn emitSEI(self: *Emitter) !void {
        try self.emitByte(0x78);
    }
    // CLI
    pub fn emitCLI(self: *Emitter) !void {
        try self.emitByte(0x58);
    }
    // CLV
    pub fn emitCLV(self: *Emitter) !void {
        try self.emitByte(0xB8);
    }
    // JMP label
    pub fn emitJMP_label(self: *Emitter, avr_addr: u16) !void {
        try self.emitByte(0x4C);
        try self.addFixup(avr_addr);
    }

    // JSR label
    pub fn emitJSR_label(self: *Emitter, avr_addr: u16) !void {
        try self.emitByte(0x20);
        try self.addFixup(avr_addr);
    }
    // LDY #imm
    pub fn emitLDY_imm(self: *Emitter, imm: u8) !void {
        try self.emitByte(0xA0);
        try self.emitByte(imm);
    }

    // LDA (zp), y
    pub fn emitLDA_indir_y(self: *Emitter, zp: u8) !void {
        try self.emitByte(0xB1);
        try self.emitByte(zp);
    }

    // STA (zp), y
    pub fn emitSTA_indir_y(self: *Emitter, zp: u8) !void {
        try self.emitByte(0x91);
        try self.emitByte(zp);
    }
    // REP #imm (65816)
    pub fn emitREP(self: *Emitter, imm: u8) !void {
        try self.emitByte(0xC2);
        try self.emitByte(imm);
    }

    // SEP #imm (65816)
    pub fn emitSEP(self: *Emitter, imm: u8) !void {
        try self.emitByte(0xE2);
        try self.emitByte(imm);
    }
    // LDX #imm (internal: used by trampoline/runtime)
    fn emitLDX_imm(self: *Emitter, imm: u8) !void {
        try self.emitByte(0xA2);
        try self.emitByte(imm);
    }

    // LDA abs,x (internal: used by trampoline)
    fn emitLDA_abs_x(self: *Emitter, addr: u16) !void {
        try self.emitByte(0xBD);
        try self.emitWord(addr);
    }

    // BRK
    pub fn emitBRK(self: *Emitter) !void {
        try self.emitByte(0x00);
    }

    // PHP
    pub fn emitPHP(self: *Emitter) !void {
        try self.emitByte(0x08);
    }
    // PLP
    pub fn emitPLP(self: *Emitter) !void {
        try self.emitByte(0x28);
    }

    // STZ zp (65C02+) - Store zero to zero page
    pub fn emitSTZ_zp(self: *Emitter, zp: u8) !void {
        try self.emitByte(0x64);
        try self.emitByte(zp);
    }

    // Flip Carry flag (ROL A, EOR #1, ROR A)
    // Corrupts A and N/Z, but all callers overwrite A with LDA and
    // subsequent ADC/SBC sets all flags, so this is safe.
    pub fn emitFlipCarry(self: *Emitter) !void {
        try self.emitROL_A();
        try self.emitEOR_imm(0x01);
        try self.emitROR_A();
    }

    pub fn emitRuntime(self: *Emitter) !u16 {
        const start_addr = @as(u16, @intCast(self.bytes.items.len));
        try self.defineLabel(0xFFFF); // Special label for runtime start (mul_u8)

        // Standard NESDev 8-bit multiply: A * Y -> r1:r0 ($01:$00)
        // A = Multiplicand, Y = Multiplier
        // Uses shift-and-add: extract multiplier bits via LSR/ROR $00,
        // conditionally add multiplicand, then ROR A + ROR $00 to shift
        // the 16-bit result right (preserving carry from ADC overflow).

        try self.emitSTA_zp(0x80); // Multiplicand in $80
        try self.emitTYA(); // Y -> A
        try self.emitSTA_zp(0x00); // Multiplier in $00 (will become result lo)
        try self.emitLDA_imm(0); // Clear A (will become result hi)
        try self.emitLDX_imm(8); // Loop 8 times
        try self.emitLSR_zp(0x00); // Extract first multiplier bit -> C

        const loop_label = @as(u16, @intCast(self.bytes.items.len));

        try self.emitBCC_rel(3); // If C=0, skip add (CLC=1 + ADC zp=2 = 3 bytes)
        try self.emitCLC();
        try self.emitADC_zp(0x80); // A = A + Multiplicand (carry preserved for ROR)

        try self.emitROR_A(); // Rotate carry into result_hi, bit 0 -> carry
        try self.emitROR_zp(0x00); // Shift result into $00, next multiplier bit -> carry

        try self.emitDEX();
        const offset = -@as(i8, @intCast(self.bytes.items.len - loop_label + 2));
        try self.emitBNE_rel(offset);

        try self.emitSTA_zp(0x01); // Store result hi in $01

        try self.emitRTS();

        try self.defineLabel(0xFFFD); // mul_s8 stub
        try self.emitJMP_label(0xFFFF);

        try self.defineLabel(0xFFFC); // extended mul stub
        try self.emitJMP_label(0xFFFF);

        return start_addr;
    }
};

test "emit basic instructions" {
    var emitter = Emitter.init(std.testing.allocator);
    defer emitter.deinit();

    try emitter.emitLDA_imm(0x42);
    try emitter.emitSTA_zp(0x10);

    try std.testing.expectEqual(@as(usize, 4), emitter.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xA9), emitter.bytes.items[0]);
    try std.testing.expectEqual(@as(u8, 0x42), emitter.bytes.items[1]);
    try std.testing.expectEqual(@as(u8, 0x85), emitter.bytes.items[2]);
    try std.testing.expectEqual(@as(u8, 0x10), emitter.bytes.items[3]);
}
