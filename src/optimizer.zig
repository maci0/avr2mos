const std = @import("std");
const emitter = @import("emitter.zig");

const Rule = struct {
    min_level: u8,
    /// Returns the number of bytes removed, or 0 if no match.
    apply: *const fn (out: *emitter.Emitter, i: usize, is_label: []bool) usize,
};

pub const Optimizer = struct {
    pub fn optimize(out: *emitter.Emitter, level: u8) !void {
        if (level == 0) return;

        // Initialize declarative rules
        const rules = [_]Rule{
            .{ .min_level = 2, .apply = applyDCE },
            .{ .min_level = 1, .apply = applyRedundantLdaImm },
            .{ .min_level = 1, .apply = applyRedundantStaLda },
            .{ .min_level = 1, .apply = applyRedundantLdaZp },
            .{ .min_level = 3, .apply = applyRedundantLdxImm },
            .{ .min_level = 3, .apply = applyRedundantLdyImm },
            .{ .min_level = 3, .apply = applyRedundantCarryFlags },
            .{ .min_level = 4, .apply = applyAbsoluteToZP },
        };

        // Build O(1) label lookup once
        var is_label = try out.allocator.alloc(bool, 65536);
        defer out.allocator.free(is_label);

        var changed = true;
        while (changed) {
            changed = false;

            @memset(is_label, false);
            var it = out.labels.valueIterator();
            while (it.next()) |val| {
                if (val.* < 65536) is_label[val.*] = true;
            }

            var i: usize = 0;
            while (i < out.bytes.items.len) {
                var removed: usize = 0;

                for (rules) |rule| {
                    if (level >= rule.min_level) {
                        removed = rule.apply(out, i, is_label);
                        if (removed > 0) {
                            changed = true;
                            break;
                        }
                    }
                }

                if (changed) {
                    break; // Restart scan from i=0
                }

                i += getInstructionLength(out.bytes.items[i]);
            }
        }
    }

    fn getInstructionLength(opcode: u8) usize {
        switch (opcode) {
            // 3-byte instructions (abs, abs,X, abs,Y, ind, etc)
            0x0D, 0x0E, 0x19, 0x1D, 0x1E, 0x20, 0x2C, 0x2D, 0x2E, 0x39, 0x3D, 0x3E, 0x4C, 0x4D, 0x4E, 0x59, 0x5D, 0x5E, 0x6C, 0x6D, 0x6E, 0x79, 0x7D, 0x7E, 0x8C, 0x8D, 0x8E, 0x99, 0x9D, 0xAC, 0xAD, 0xAE, 0xBC, 0xBD, 0xBE, 0xCC, 0xCD, 0xCE, 0xD9, 0xDD, 0xDE, 0xEC, 0xED, 0xEE, 0xF9, 0xFD, 0xFE => return 3,

            // 2-byte instructions (imm, zp, zp,X, zp,Y, ind,X, ind,Y, rel)
            0x01, 0x05, 0x06, 0x09, 0x10, 0x11, 0x15, 0x16, 0x21, 0x24, 0x25, 0x26, 0x29, 0x30, 0x31, 0x35, 0x36, 0x41, 0x45, 0x46, 0x49, 0x50, 0x51, 0x55, 0x56, 0x61, 0x64, 0x65, 0x66, 0x69, 0x70, 0x71, 0x75, 0x76, 0x80, 0x81, 0x84, 0x85, 0x86, 0x89, 0x90, 0x91, 0x94, 0x95, 0x96, 0xA0, 0xA1, 0xA4, 0xA5, 0xA6, 0xA9, 0xB0, 0xB1, 0xB4, 0xB5, 0xB6, 0xC0, 0xC1, 0xC2, 0xC4, 0xC5, 0xC6, 0xC9, 0xD0, 0xD1, 0xD5, 0xD6, 0xE0, 0xE1, 0xE2, 0xE4, 0xE5, 0xE6, 0xE9, 0xF0, 0xF1, 0xF5, 0xF6 => return 2,

            // 1-byte instructions (implied, accumulator)
            else => return 1,
        }
    }

    fn removeAt(out: *emitter.Emitter, offset: usize, count: usize, is_label: []bool) void {
        std.mem.copyForwards(bool, is_label[offset .. 65536 - count], is_label[offset + count .. 65536]);
        var it = out.labels.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* > offset) {
                entry.value_ptr.* -= count;
            }
        }

        var j: usize = 0;
        while (j < out.fixups.items.len) {
            if (out.fixups.items[j].offset >= offset and out.fixups.items[j].offset < offset + count) {
                _ = out.fixups.orderedRemove(j);
            } else {
                if (out.fixups.items[j].offset >= offset + count) {
                    out.fixups.items[j].offset -= count;
                }
                j += 1;
            }
        }

        for (0..count) |_| {
            _ = out.bytes.orderedRemove(offset);
        }
    }

    // --- LEVEL 2: Dead Code Elimination (DCE) ---
    fn applyDCE(out: *emitter.Emitter, i: usize, is_label: []bool) usize {
        const b0 = out.bytes.items[i];
        if (b0 == 0x4C or b0 == 0x60 or b0 == 0x40 or b0 == 0x00) { // JMP, RTS, RTI, BRK
            const inst_len: usize = if (b0 == 0x4C) 3 else 1;

            var delete_count: usize = 0;
            var curr = i + inst_len;
            while (curr < out.bytes.items.len) {
                if (is_label[curr]) break;
                delete_count += 1;
                curr += 1;
            }

            if (delete_count > 0) {
                removeAt(out, i + inst_len, delete_count, is_label);
                return delete_count;
            }
        }
        return 0;
    }

    // --- LEVEL 1: Pattern 2: Redundant LDA #imm (A9 XX A9 YY) ---
    // First LDA is overwritten by second; remove first regardless of value
    fn applyRedundantLdaImm(out: *emitter.Emitter, i: usize, is_label: []bool) usize {
        if (i + 4 <= out.bytes.items.len and
            out.bytes.items[i] == 0xA9 and // LDA #imm
            out.bytes.items[i + 2] == 0xA9) // LDA #imm (any value)
        {
            if (!is_label[i + 2]) {
                removeAt(out, i, 2, is_label);
                return 2;
            }
        }
        return 0;
    }

    // --- LEVEL 1: Pattern 2b: Redundant STA zp + LDA zp (85 XX A5 XX) ---
    fn applyRedundantStaLda(out: *emitter.Emitter, i: usize, is_label: []bool) usize {
        if (i + 4 <= out.bytes.items.len and
            out.bytes.items[i] == 0x85 and // STA zp
            out.bytes.items[i + 2] == 0xA5 and // LDA zp
            out.bytes.items[i + 1] == out.bytes.items[i + 3]) // same zp address
        {
            if (!is_label[i + 2]) {
                removeAt(out, i + 2, 2, is_label);
                return 2;
            }
        }
        return 0;
    }

    // --- LEVEL 1: Pattern 2c: Redundant LDA zp + LDA zp (A5 XX A5 YY) ---
    // First LDA is overwritten by second; remove first regardless of address
    fn applyRedundantLdaZp(out: *emitter.Emitter, i: usize, is_label: []bool) usize {
        if (i + 4 <= out.bytes.items.len and
            out.bytes.items[i] == 0xA5 and // LDA zp
            out.bytes.items[i + 2] == 0xA5) // LDA zp (any address)
        {
            if (!is_label[i + 2]) {
                // Remove first LDA (second one overwrites A and flags)
                removeAt(out, i, 2, is_label);
                return 2;
            }
        }
        return 0;
    }

    // --- LEVEL 3: Pattern 3: Redundant LDX #imm (A2 XX A2 XX) ---
    fn applyRedundantLdxImm(out: *emitter.Emitter, i: usize, is_label: []bool) usize {
        if (i + 4 <= out.bytes.items.len and
            out.bytes.items[i] == 0xA2 and // LDX #imm
            out.bytes.items[i + 2] == 0xA2 and // LDX #imm
            out.bytes.items[i + 1] == out.bytes.items[i + 3]) // same imm
        {
            if (!is_label[i + 2]) {
                removeAt(out, i + 2, 2, is_label);
                return 2;
            }
        }
        return 0;
    }

    // --- LEVEL 3: Pattern 4: Redundant LDY #imm (A0 XX A0 XX) ---
    fn applyRedundantLdyImm(out: *emitter.Emitter, i: usize, is_label: []bool) usize {
        if (i + 4 <= out.bytes.items.len and
            out.bytes.items[i] == 0xA0 and // LDY #imm
            out.bytes.items[i + 2] == 0xA0 and // LDY #imm
            out.bytes.items[i + 1] == out.bytes.items[i + 3]) // same imm
        {
            if (!is_label[i + 2]) {
                removeAt(out, i + 2, 2, is_label);
                return 2;
            }
        }
        return 0;
    }

    // --- LEVEL 3: Pattern 5: Redundant Carry Flags (SEC/CLC followed by SEC/CLC) ---
    fn applyRedundantCarryFlags(out: *emitter.Emitter, i: usize, is_label: []bool) usize {
        if (i + 2 <= out.bytes.items.len) {
            const b0 = out.bytes.items[i];
            const b1 = out.bytes.items[i + 1];

            if ((b0 == 0x38 or b0 == 0x18) and (b1 == 0x38 or b1 == 0x18)) {
                if (!is_label[i + 1]) {
                    // First flag mutation is immediately overwritten
                    removeAt(out, i, 1, is_label);
                    return 1;
                }
            }
        }
        return 0;
    }

    // --- Size Pass (-Os / Level 4): Absolute to Zero-Page (LDA $004A -> LDA $4A) ---
    fn applyAbsoluteToZP(out: *emitter.Emitter, i: usize, is_label: []bool) usize {
        if (i + 3 <= out.bytes.items.len and out.bytes.items[i + 2] == 0x00) {
            // Mapping: abs opcode -> zp opcode
            const zp_opcode: ?u8 = switch (out.bytes.items[i]) {
                0xAD => 0xA5, // LDA
                0x8D => 0x85, // STA
                0xED => 0xE5, // SBC
                0x6D => 0x65, // ADC
                0x2D => 0x25, // AND
                0x0D => 0x05, // ORA
                0x4D => 0x45, // EOR
                0xCD => 0xC5, // CMP
                0xEE => 0xE6, // INC
                0xCE => 0xC6, // DEC
                else => null,
            };
            if (zp_opcode) |zp| {
                out.bytes.items[i] = zp;
                removeAt(out, i + 2, 1, is_label);
                return 1;
            }
        }
        return 0;
    }
};

// ============================================================
// Optimizer Tests
// ============================================================

test "Optimizer Level 0: no optimization" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // LDA #$42, LDA #$42 (redundant pair)
    try emit.emitByte(0xA9);
    try emit.emitByte(0x42);
    try emit.emitByte(0xA9);
    try emit.emitByte(0x42);

    try Optimizer.optimize(&emit, 0);
    try std.testing.expectEqual(@as(usize, 4), emit.bytes.items.len);
}

test "Optimizer Level 1: redundant LDA #imm same value" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // LDA #$42, LDA #$42 -> remove first (overwritten by second)
    try emit.emitByte(0xA9);
    try emit.emitByte(0x42);
    try emit.emitByte(0xA9);
    try emit.emitByte(0x42);

    try Optimizer.optimize(&emit, 1);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xA9), emit.bytes.items[0]);
    try std.testing.expectEqual(@as(u8, 0x42), emit.bytes.items[1]);
}

test "Optimizer Level 1: different LDA #imm also removed" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // LDA #$42, LDA #$43 -> first is dead, remove it
    try emit.emitByte(0xA9);
    try emit.emitByte(0x42);
    try emit.emitByte(0xA9);
    try emit.emitByte(0x43);

    try Optimizer.optimize(&emit, 1);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xA9), emit.bytes.items[0]);
    try std.testing.expectEqual(@as(u8, 0x43), emit.bytes.items[1]); // second value survives
}

test "Optimizer Level 2: DCE after RTS" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // RTS, NOP, NOP -> dead NOPs removed
    try emit.emitByte(0x60); // RTS
    try emit.emitByte(0xEA); // NOP (dead)
    try emit.emitByte(0xEA); // NOP (dead)

    try Optimizer.optimize(&emit, 2);
    try std.testing.expectEqual(@as(usize, 1), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x60), emit.bytes.items[0]);
}

test "Optimizer Level 2: DCE after BRK" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // BRK, NOP, NOP -> dead NOPs removed
    try emit.emitByte(0x00); // BRK
    try emit.emitByte(0xEA); // NOP (dead)
    try emit.emitByte(0xEA); // NOP (dead)

    try Optimizer.optimize(&emit, 2);
    try std.testing.expectEqual(@as(usize, 1), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x00), emit.bytes.items[0]);
}

test "Optimizer Level 2: DCE after JMP" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // JMP $1234, NOP, NOP -> dead code after JMP removed
    try emit.emitByte(0x4C); // JMP
    try emit.emitByte(0x34);
    try emit.emitByte(0x12);
    try emit.emitByte(0xEA); // NOP (dead)
    try emit.emitByte(0xEA); // NOP (dead)

    try Optimizer.optimize(&emit, 2);
    try std.testing.expectEqual(@as(usize, 3), emit.bytes.items.len);
}

test "Optimizer Level 2: DCE preserves code at labels" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // RTS, NOP (at label) -> NOP is reachable via label, not removed
    try emit.emitByte(0x60); // RTS
    try emit.labels.put(0x1234, 1); // Label at offset 1 (the NOP)
    try emit.emitByte(0xEA); // NOP (at label, reachable)

    try Optimizer.optimize(&emit, 2);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
}

test "Optimizer Level 3: redundant LDX #imm" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // LDX #$08, LDX #$08 -> remove second
    try emit.emitByte(0xA2);
    try emit.emitByte(0x08);
    try emit.emitByte(0xA2);
    try emit.emitByte(0x08);

    try Optimizer.optimize(&emit, 3);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
}

test "Optimizer Level 3: redundant LDY #imm" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // LDY #$00, LDY #$00 -> remove second
    try emit.emitByte(0xA0);
    try emit.emitByte(0x00);
    try emit.emitByte(0xA0);
    try emit.emitByte(0x00);

    try Optimizer.optimize(&emit, 3);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
}

test "Optimizer Level 3: redundant carry flags (SEC, CLC)" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // SEC, CLC -> remove first (SEC is immediately overwritten by CLC)
    try emit.emitByte(0x38); // SEC
    try emit.emitByte(0x18); // CLC

    try Optimizer.optimize(&emit, 3);
    try std.testing.expectEqual(@as(usize, 1), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x18), emit.bytes.items[0]); // CLC remains
}

test "Optimizer Level 3: redundant carry flags (CLC, SEC)" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // CLC, SEC -> remove first
    try emit.emitByte(0x18); // CLC
    try emit.emitByte(0x38); // SEC

    try Optimizer.optimize(&emit, 3);
    try std.testing.expectEqual(@as(usize, 1), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x38), emit.bytes.items[0]); // SEC remains
}

test "Optimizer Level 4: absolute to zero-page LDA" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // LDA $004A -> LDA $4A (abs to zp optimization)
    try emit.emitByte(0xAD); // LDA abs
    try emit.emitByte(0x4A); // lo byte
    try emit.emitByte(0x00); // hi byte = 0

    try Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xA5), emit.bytes.items[0]); // LDA zp
    try std.testing.expectEqual(@as(u8, 0x4A), emit.bytes.items[1]);
}

test "Optimizer Level 4: absolute to zero-page STA" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // STA $0010 -> STA $10
    try emit.emitByte(0x8D); // STA abs
    try emit.emitByte(0x10);
    try emit.emitByte(0x00);

    try Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x85), emit.bytes.items[0]); // STA zp
    try std.testing.expectEqual(@as(u8, 0x10), emit.bytes.items[1]);
}

test "Optimizer Level 4: absolute to zero-page ADC" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // ADC $0020 -> ADC $20
    try emit.emitByte(0x6D); // ADC abs
    try emit.emitByte(0x20);
    try emit.emitByte(0x00);

    try Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x65), emit.bytes.items[0]); // ADC zp
}

test "Optimizer Level 4: absolute to zero-page SBC" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // SBC $0030 -> SBC $30
    try emit.emitByte(0xED); // SBC abs
    try emit.emitByte(0x30);
    try emit.emitByte(0x00);

    try Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xE5), emit.bytes.items[0]); // SBC zp
}

test "Optimizer Level 4: absolute to zero-page AND" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.emitByte(0x2D); // AND abs
    try emit.emitByte(0x10);
    try emit.emitByte(0x00);

    try Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x25), emit.bytes.items[0]); // AND zp
}

test "Optimizer Level 4: absolute to zero-page ORA" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.emitByte(0x0D); // ORA abs
    try emit.emitByte(0x10);
    try emit.emitByte(0x00);

    try Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x05), emit.bytes.items[0]); // ORA zp
}

test "Optimizer Level 4: absolute to zero-page EOR" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.emitByte(0x4D); // EOR abs
    try emit.emitByte(0x10);
    try emit.emitByte(0x00);

    try Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x45), emit.bytes.items[0]); // EOR zp
}

test "Optimizer Level 4: absolute to zero-page CMP" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.emitByte(0xCD); // CMP abs
    try emit.emitByte(0x10);
    try emit.emitByte(0x00);

    try Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xC5), emit.bytes.items[0]); // CMP zp
}

test "Optimizer: no abs-to-zp when high byte nonzero" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // LDA $014A -> high byte is 0x01, should not optimize
    try emit.emitByte(0xAD);
    try emit.emitByte(0x4A);
    try emit.emitByte(0x01);

    try Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 3), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xAD), emit.bytes.items[0]); // Still LDA abs
}

test "Optimizer: fixups adjusted after removal" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // NOP, LDA #$42, LDA #$42, JMP $1234
    // Level 1 removes the redundant LDA #$42, which should adjust the JMP fixup
    try emit.emitByte(0xEA); // NOP
    try emit.emitByte(0xA9); // LDA #$42
    try emit.emitByte(0x42);
    try emit.emitByte(0xA9); // LDA #$42 (redundant)
    try emit.emitByte(0x42);
    // Add a JMP with manual fixup at offset 6 (within the JMP)
    try emit.emitByte(0x4C);
    try emit.fixups.append(emit.allocator, .{ .offset = 6, .target_addr = 0x1234 });
    try emit.emitByte(0x00);
    try emit.emitByte(0x00);

    try Optimizer.optimize(&emit, 1);

    // After removing 2 bytes (redundant LDA #$42), JMP moves from offset 5 to 3
    // Fixup should be adjusted from offset 6 to 4
    try std.testing.expectEqual(@as(usize, 6), emit.bytes.items.len); // NOP + LDA #$42 + JMP
    try std.testing.expectEqual(@as(usize, 1), emit.fixups.items.len);
    try std.testing.expectEqual(@as(usize, 4), emit.fixups.items[0].offset);
}

test "Optimizer Level 1: redundant STA zp + LDA zp" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // STA $10, LDA $10 -> remove the LDA (A still holds the value)
    try emit.emitByte(0x85); // STA zp
    try emit.emitByte(0x10);
    try emit.emitByte(0xA5); // LDA zp
    try emit.emitByte(0x10);

    try Optimizer.optimize(&emit, 1);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x85), emit.bytes.items[0]); // STA zp
    try std.testing.expectEqual(@as(u8, 0x10), emit.bytes.items[1]);
}

test "Optimizer Level 1: STA/LDA different addresses not removed" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // STA $10, LDA $11 -> different addresses, no removal
    try emit.emitByte(0x85);
    try emit.emitByte(0x10);
    try emit.emitByte(0xA5);
    try emit.emitByte(0x11);

    try Optimizer.optimize(&emit, 1);
    try std.testing.expectEqual(@as(usize, 4), emit.bytes.items.len);
}

test "Optimizer Level 1: redundant LDA zp + LDA zp" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // LDA $10, LDA $10 -> remove first (second sets same A and flags)
    try emit.emitByte(0xA5); // LDA zp
    try emit.emitByte(0x10);
    try emit.emitByte(0xA5); // LDA zp
    try emit.emitByte(0x10);

    try Optimizer.optimize(&emit, 1);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xA5), emit.bytes.items[0]);
    try std.testing.expectEqual(@as(u8, 0x10), emit.bytes.items[1]);
}

test "Optimizer Level 1: LDA zp different addresses also removed" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // LDA $10, LDA $11 -> first is dead, remove it
    try emit.emitByte(0xA5);
    try emit.emitByte(0x10);
    try emit.emitByte(0xA5);
    try emit.emitByte(0x11);

    try Optimizer.optimize(&emit, 1);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xA5), emit.bytes.items[0]);
    try std.testing.expectEqual(@as(u8, 0x11), emit.bytes.items[1]); // second address survives
}
