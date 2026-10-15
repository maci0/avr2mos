const std = @import("std");
const decoder = @import("decoder.zig");
const translator = @import("translator.zig");
const emitter = @import("emitter.zig");
const cfg = @import("cfg.zig");
const optimizer = @import("optimizer.zig");
const profile = @import("profile.zig");

fn testTranslate(allocator: std.mem.Allocator, inst: decoder.Instruction, expected: []const u8) !void {
    var emit = emitter.Emitter.init(allocator);
    defer emit.deinit();

    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = inst.addr,
        .end_addr = inst.addr,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x0200);

    try std.testing.expectEqualSlices(u8, expected, emit.bytes.items);
}

test "Arithmetic: ADD" {
    // ADD r16, r17 -> LDA $10, CLC, ADC $11, STA $10
    const inst = decoder.Instruction{
        .opcode = .ADD,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x18, // CLC
        0xA5, 0x10, // LDA $10
        0x65, 0x11, // ADC $11
        0x85, 0x10, // STA $10
    });
}

test "Arithmetic: SUB" {
    // SUB r16, r17 -> SEC, LDA $10, SBC $11, STA $10
    const inst = decoder.Instruction{
        .opcode = .SUB,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x38, // SEC
        0xA5, 0x10, // LDA $10
        0xE5, 0x11, // SBC $11
        0x85, 0x10, // STA $10
    });
}

test "Arithmetic: SBC" {
    // SBC r16, r17 -> LDA $10, SBC $11, STA $10
    const inst = decoder.Instruction{
        .opcode = .SBC,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x2A, 0x49, 0x01, 0x6A, // ROL A, EOR #$01, ROR A (FlipCarry)
        0xA5, 0x10, // LDA $10
        0xE5, 0x11, // SBC $11
        0x85, 0x10, // STA $10
    });
}

test "Arithmetic: ADC" {
    // ADC r16, r17 -> LDA $10, ADC $11, STA $10
    const inst = decoder.Instruction{
        .opcode = .ADC,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x65, 0x11, // ADC $11
        0x85, 0x10, // STA $10
    });
}

test "Compare: CP" {
    // CP r16, r17 -> LDA $10, CMP $11
    const inst = decoder.Instruction{
        .opcode = .CP,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0xC5, 0x11, // CMP $11
    });
}

test "Compare: CPC" {
    // CPC r16, r17 -> LDA $10, SBC $11
    const inst = decoder.Instruction{
        .opcode = .CPC,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x2A, 0x49, 0x01, 0x6A, // ROL A, EOR #$01, ROR A (FlipCarry)
        0xA5, 0x10, // LDA $10
        0xE5, 0x11, // SBC $11
    });
}

test "Compare: CPI" {
    // CPI r16, 0x55 -> LDA $10, CMP #$55
    const inst = decoder.Instruction{
        .opcode = .CPI,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0x55 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0xC9, 0x55, // CMP #$55
    });
}

test "Logic: AND" {
    // AND r16, r17 -> LDA $10, AND $11, STA $10
    const inst = decoder.Instruction{
        .opcode = .AND,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x25, 0x11, // AND $11
        0x85, 0x10, // STA $10
    });
}

test "Logic: OR" {
    // OR r16, r17 -> LDA $10, ORA $11, STA $10
    const inst = decoder.Instruction{
        .opcode = .OR,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x05, 0x11, // ORA $11
        0x85, 0x10, // STA $10
    });
}

test "Logic: EOR" {
    // EOR r16, r17 -> LDA $10, EOR $11, STA $10
    const inst = decoder.Instruction{
        .opcode = .EOR,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x45, 0x11, // EOR $11
        0x85, 0x10, // STA $10
    });
}

test "Logic: ANDI" {
    // ANDI r16, 0x0F -> LDA $10, AND #$0F, STA $10
    const inst = decoder.Instruction{
        .opcode = .ANDI,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0x0F } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x29, 0x0F, // AND #$0F
        0x85, 0x10, // STA $10
    });
}

test "Logic: ORI" {
    // ORI r16, 0xF0 -> LDA $10, ORA #$F0, STA $10
    const inst = decoder.Instruction{
        .opcode = .ORI,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0xF0 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x09, 0xF0, // ORA #$F0
        0x85, 0x10, // STA $10
    });
}

test "Arithmetic: INC" {
    // INC r16 -> INC $10
    const inst = decoder.Instruction{
        .opcode = .INC,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{ 0xE6, 0x10 });
}

test "Arithmetic: DEC" {
    // DEC r16 -> DEC $10
    const inst = decoder.Instruction{
        .opcode = .DEC,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{ 0xC6, 0x10 });
}

test "Logic: COM" {
    // COM r16 -> LDA $10, EOR #$FF, STA $10, SEC
    const inst = decoder.Instruction{
        .opcode = .COM,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x49, 0xFF, // EOR #$FF
        0x85, 0x10, // STA $10
        0x38, // SEC (AVR COM always sets C=1)
    });
}

test "Logic: NEG" {
    // NEG r16 -> LDA #0, SEC, SBC $10, STA $10
    const inst = decoder.Instruction{
        .opcode = .NEG,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA9, 0x00, // LDA #0
        0x38, // SEC
        0xE5, 0x10, // SBC $10
        0x85, 0x10, // STA $10
    });
}

test "Control Flow: BREQ" {
    // BREQ target (BRBS 1, target)
    // 6502: BNE skip; JMP target
    const inst = decoder.Instruction{
        .opcode = .BRBS,
        .operands = .{ .reg_rel = .{ .r = 1, .rel = 2 } }, // offset 2 words = addr 3
        .size = 2,
        .addr = 0,
    };

    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.labels.put(3, 100); // Mock target

    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    // BNE +3 (D0 03), JMP $addr
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xD0, 0x03,
        0x4C, 0x64,
        0x10,
    }, emit.bytes.items);
}

test "Data Transfer: LDI" {
    // LDI r16, 0x55 -> LDA #$55, STA $10
    const inst = decoder.Instruction{
        .opcode = .LDI,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0x55 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA9, 0x55, // LDA #$55
        0x85, 0x10, // STA $10
    });
}

test "Data Transfer: MOV" {
    // MOV r16, r17 -> LDA $11, STA $10
    const inst = decoder.Instruction{
        .opcode = .MOV,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x11, // LDA $11
        0x85, 0x10, // STA $10
    });
}

test "Data Transfer: MOVW" {
    // MOVW r16, r18 -> LDA $12, STA $10, LDA $13, STA $11
    const inst = decoder.Instruction{
        .opcode = .MOVW,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 18 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x12, // LDA r18
        0x85, 0x10, // STA r16
        0xA5, 0x13, // LDA r19
        0x85, 0x11, // STA r17
    });
}

test "Data Transfer: LDS" {
    // LDS r16, 0x1000 -> LDA $1000, STA $10
    const inst = decoder.Instruction{
        .opcode = .LDS,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0x1000 } },
        .size = 4,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xAD, 0x00, 0x10, // LDA $1000
        0x85, 0x10, // STA $10
    });
}

test "Data Transfer: STS" {
    // STS 0x1000, r16 -> LDA $10, STA $1000
    const inst = decoder.Instruction{
        .opcode = .STS,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0x1000 } },
        .size = 4,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x8D, 0x00, 0x10, // STA $1000
    });
}

test "Bit Manipulation: SBRC" {
    // SBRC r16, 3 (skip next instruction if bit 3 clear)
    // 6502: LDA $10, AND #$08, BNE +3, JMP target
    const inst = decoder.Instruction{
        .opcode = .SBRC,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 3 } },
        .size = 2,
        .addr = 0,
    };

    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.labels.put(2, 200); // Mock target

    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
        .successors = .{ 2, null },
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x29, 0x08, // AND #$08
        0xD0, 0x03, // BNE +3 (skip JMP)
        0x4C, 0xC8, 0x10, // JMP $10C8
    }, emit.bytes.items);
}

test "Control Flow: BRNE" {
    // BRNE target (BRBC 1, target)
    // 6502: BEQ skip; JMP target
    const inst = decoder.Instruction{
        .opcode = .BRBC,
        .operands = .{ .reg_rel = .{ .r = 1, .rel = 2 } }, // offset 2 words = addr 3
        .size = 2,
        .addr = 0,
    };

    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.labels.put(3, 256); // Mock target at offset 256

    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x2000);

    // BEQ +3 (F0 03), JMP $2100
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xF0, 0x03,
        0x4C, 0x00,
        0x21,
    }, emit.bytes.items);
}

test "Control Flow: BRCS" {
    // BRCS target (BRBS 0, target)
    const inst = decoder.Instruction{
        .opcode = .BRBS,
        .operands = .{ .reg_rel = .{ .r = 0, .rel = 2 } },
        .size = 2,
        .addr = 0,
    };
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();
    try emit.labels.put(3, 10);
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    // BCC +3 (90 03), JMP $100A
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x90, 0x03, 0x4C, 0x0A, 0x10 }, emit.bytes.items);
}

test "Control Flow: CPSE" {
    // CPSE r16, r17 (skip if equal)
    const inst = decoder.Instruction{
        .opcode = .CPSE,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();
    try emit.labels.put(2, 10); // next + skip size (assume single 2-byte skip)
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts, .successors = .{ 2, null } };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    // LDA $10, CMP $11, BNE +3, JMP $100A
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xA5, 0x10, 0xC5, 0x11, 0xD0, 0x03, 0x4C, 0x0A, 0x10 }, emit.bytes.items);
}

test "Control Flow: IJMP" {
    // IJMP -> JMP 0xFFFE
    const inst = decoder.Instruction{
        .opcode = .IJMP,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();
    try emit.labels.put(0xFFFE, 0x0100); // Mock trampoline at 0x0100
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x2000);

    // JMP $2100
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x4C, 0x00, 0x21 }, emit.bytes.items);
}

test "Control Flow: RET" {
    // RET -> RTS
    const inst = decoder.Instruction{
        .opcode = .RET,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{0x60});
}

test "Arithmetic: ADIW" {
    // ADIW r24, 1 -> CLC, LDA $18, ADC #1, STA $18, LDA $19, ADC #0, STA $19
    const inst = decoder.Instruction{
        .opcode = .ADIW,
        .operands = .{ .reg_imm = .{ .r = 24, .imm = 1 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x18, // CLC
        0xA5, 0x18, // LDA $18
        0x69, 0x01, // ADC #1
        0x85, 0x18, // STA $18
        0xA5, 0x19, // LDA $19
        0x69, 0x00, // ADC #0
        0x85, 0x19, // STA $19
    });
}

test "Control Flow: RJMP" {
    // RJMP .+2 -> JMP $0204 (assuming base 0x0200, addr 0, offset 0)
    // RJMP . is at addr 0, target is 0 + 1 + 1 = 2 (words) = addr 2.
    // 6502: JMP label_addr_2
    const inst = decoder.Instruction{
        .opcode = .RJMP,
        .operands = .{ .rel = 1 },
        .size = 2,
        .addr = 0,
    };

    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // We need to define the target label for JMP to resolve
    try emit.defineLabel(2); // Mock target block start

    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);

    // Set offset for label 2 (e.g. at offset 3 after the JMP)
    try emit.labels.put(2, 3);

    try emit.resolveFixups(0x0200);

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x4C, 0x03, 0x02 }, emit.bytes.items);
}
test "Arithmetic: MUL" {
    // MUL r16, r17 -> LDA $10, LDY $11, JSR $FFFF
    const inst = decoder.Instruction{
        .opcode = .MUL,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };

    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // We need to define the runtime label for the JSR to work
    try emit.labels.put(0xFFFF, 100); // Mock runtime at offset 100

    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xA5, 0x10, // LDA $10
        0xA4, 0x11, // LDY $11
        0x20, 0x64, 0x10, // JSR $1064 (1000 + 100 = 1064)
    }, emit.bytes.items);
}

test "Arithmetic: SBIW" {
    // SBIW r24, 1 -> SEC, LDA $18, SBC #1, STA $18, LDA $19, SBC #0, STA $19
    const inst = decoder.Instruction{
        .opcode = .SBIW,
        .operands = .{ .reg_imm = .{ .r = 24, .imm = 1 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x38, // SEC
        0xA5, 0x18, // LDA $18
        0xE9, 0x01, // SBC #1
        0x85, 0x18, // STA $18
        0xA5, 0x19, // LDA $19
        0xE9, 0x00, // SBC #0
        0x85, 0x19, // STA $19
    });
}

// ============================================================
// Shift/Rotate Instructions
// ============================================================

test "Shift: LSR" {
    // LSR r16 -> LSR $10
    const inst = decoder.Instruction{
        .opcode = .LSR,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x46, 0x10, // LSR $10
    });
}

test "Shift: ROR" {
    // ROR r16 (with initial carry_mode = .addition) -> ROR $10
    const inst = decoder.Instruction{
        .opcode = .ROR,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x66, 0x10, // ROR $10
    });
}

test "Shift: ASR" {
    // ASR r16 -> LDA $10, ASL A, ROR $10
    const inst = decoder.Instruction{
        .opcode = .ASR,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x0A, // ASL A (bit 7 -> carry)
        0x66, 0x10, // ROR $10 (carry -> bit 7, preserving sign)
    });
}

test "Logic: SWAP" {
    // SWAP r16 -> LDA $10, ASL, ADC #$80, ROL, ASL, ADC #$80, ROL, STA $10
    const inst = decoder.Instruction{
        .opcode = .SWAP,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x08, // PHP (save flags — AVR SWAP doesn't affect flags)
        0xA5, 0x10, // LDA $10
        0x0A, // ASL A
        0x69, 0x80, // ADC #$80
        0x2A, // ROL A
        0x0A, // ASL A
        0x69, 0x80, // ADC #$80
        0x2A, // ROL A
        0x85, 0x10, // STA $10
        0x28, // PLP (restore flags)
    });
}

// ============================================================
// Stack / Register Operations
// ============================================================

test "Stack: PUSH" {
    // PUSH r16 -> LDA $10, PHA
    const inst = decoder.Instruction{
        .opcode = .PUSH,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x48, // PHA
    });
}

test "Stack: POP" {
    // POP r16 -> PLA, STA $10
    const inst = decoder.Instruction{
        .opcode = .POP,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x68, // PLA
        0x85, 0x10, // STA $10
    });
}

test "Register: CLR" {
    // CLR r16 -> LDA #0, STA $10
    const inst = decoder.Instruction{
        .opcode = .CLR,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA9, 0x00, // LDA #0
        0x85, 0x10, // STA $10
    });
}

test "Register: SER" {
    // SER r16 -> LDA #$FF, STA $10
    const inst = decoder.Instruction{
        .opcode = .SER,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA9, 0xFF, // LDA #$FF
        0x85, 0x10, // STA $10
    });
}

test "Register: TST" {
    // TST r16 -> LDA $10
    const inst = decoder.Instruction{
        .opcode = .TST,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
    });
}

// ============================================================
// I/O Instructions
// ============================================================

test "I/O: IN" {
    // IN r16, 0x10 -> LDA $30, STA $10
    const inst = decoder.Instruction{
        .opcode = .IN,
        .operands = .{ .reg_io = .{ .r = 16, .io = 0x10 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x30, // LDA zp($20 + $10)
        0x85, 0x10, // STA $10
    });
}

test "I/O: OUT" {
    // OUT 0x10, r16 -> LDA $10, STA $30
    const inst = decoder.Instruction{
        .opcode = .OUT,
        .operands = .{ .io_reg = .{ .io = 0x10, .r = 16 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x85, 0x30, // STA zp($20 + $10)
    });
}

test "I/O: SBI" {
    // SBI port 2, bit 3 -> LDA $22, ORA #$08, STA $22
    const inst = decoder.Instruction{
        .opcode = .SBI,
        .operands = .{ .reg_imm = .{ .r = 2, .imm = 3 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x08, // PHP
        0xA5, 0x22, // LDA zp($20 + 2)
        0x09, 0x08, // ORA #$08 (1 << 3)
        0x85, 0x22, // STA zp($20 + 2)
        0x28, // PLP
    });
}

test "I/O: CBI" {
    // CBI port 2, bit 3 -> LDA $22, AND #$F7, STA $22
    const inst = decoder.Instruction{
        .opcode = .CBI,
        .operands = .{ .reg_imm = .{ .r = 2, .imm = 3 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x08, // PHP
        0xA5, 0x22, // LDA zp($20 + 2)
        0x29, 0xF7, // AND #$F7 (~0x08)
        0x85, 0x22, // STA zp($20 + 2)
        0x28, // PLP
    });
}

// ============================================================
// Bit Manipulation
// ============================================================

test "Bit Manipulation: SBRS" {
    // SBRS r16, 3 (skip next instruction if bit 3 set)
    // 6502: LDA $10, AND #$08, BEQ +3, JMP target
    const inst = decoder.Instruction{
        .opcode = .SBRS,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 3 } },
        .size = 2,
        .addr = 0,
    };

    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.labels.put(2, 200); // Mock target
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
        .successors = .{ 2, null },
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x29, 0x08, // AND #$08
        0xF0, 0x03, // BEQ +3 (skip JMP) — inverted: skip if bit clear
        0x4C, 0xC8, 0x10, // JMP $10C8
    }, emit.bytes.items);
}

test "Bit Manipulation: SBR" {
    // SBR r16, 0x0F -> LDA $10, ORA #$0F, STA $10
    const inst = decoder.Instruction{
        .opcode = .SBR,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0x0F } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x09, 0x0F, // ORA #$0F
        0x85, 0x10, // STA $10
    });
}

test "Bit Manipulation: CBR" {
    // CBR r16, 0x0F -> LDA $10, AND #$F0, STA $10
    const inst = decoder.Instruction{
        .opcode = .CBR,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0x0F } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA5, 0x10, // LDA $10
        0x29, 0xF0, // AND #$F0 (~0x0F)
        0x85, 0x10, // STA $10
    });
}

// ============================================================
// Immediate Subtract Instructions
// ============================================================

test "Arithmetic: SUBI" {
    // SUBI r16, 0x10 -> SEC, LDA $10, SBC #$10, STA $10
    const inst = decoder.Instruction{
        .opcode = .SUBI,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0x10 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x38, // SEC
        0xA5, 0x10, // LDA $10
        0xE9, 0x10, // SBC #$10
        0x85, 0x10, // STA $10
    });
}

test "Arithmetic: SBCI" {
    // SBCI r16, 0x00 (after subtraction carry_mode) -> FlipCarry, LDA $10, SBC #$00, STA $10
    // When tested standalone, carry_mode starts as .addition so FlipCarry is emitted
    const inst = decoder.Instruction{
        .opcode = .SBCI,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 0x00 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x2A, 0x49, 0x01, 0x6A, // FlipCarry (ROL A, EOR #1, ROR A)
        0xA5, 0x10, // LDA $10
        0xE9, 0x00, // SBC #$00
        0x85, 0x10, // STA $10
    });
}

// ============================================================
// Control Flow: RETI, RCALL
// ============================================================

test "Control Flow: RETI" {
    // RETI -> RTI
    const inst = decoder.Instruction{
        .opcode = .RETI,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{0x40});
}

test "Control Flow: RCALL" {
    const inst = decoder.Instruction{
        .opcode = .RCALL,
        .operands = .{ .rel = 5 },
        .size = 2,
        .addr = 0,
    };

    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.labels.put(6, 50); // target = addr + rel + 1 = 0 + 5 + 1 = 6
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    // JSR $1032 (0x1000 + 50)
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x20, 0x32, 0x10 }, emit.bytes.items);
}

// ============================================================
// Interrupt / Flag Instructions
// ============================================================

test "Interrupt: CLI (AVR disable interrupts -> 6502 SEI)" {
    const inst = decoder.Instruction{
        .opcode = .CLI,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{0x78}); // SEI
}

test "Interrupt: SEI (AVR enable interrupts -> 6502 CLI)" {
    const inst = decoder.Instruction{
        .opcode = .SEI,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{0x58}); // CLI
}

test "Misc: NOP" {
    const inst = decoder.Instruction{
        .opcode = .NOP,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{0xEA}); // NOP
}

test "Misc: BREAK" {
    const inst = decoder.Instruction{
        .opcode = .BREAK,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{0x00}); // BRK
}

// ============================================================
// Indirect Memory Access (LD/ST with pointer registers)
// ============================================================

test "Memory: LD X (indirect load via X pointer)" {
    // LD r16, X -> LDY #0, LDA ($1A),Y, STA $10
    const inst = decoder.Instruction{
        .opcode = .LD_X,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA0, 0x00, // LDY #0
        0xB1, 0x1A, // LDA ($1A),Y
        0x85, 0x10, // STA $10
    });
}

test "Memory: ST X (indirect store via X pointer)" {
    // ST X, r16 -> LDY #0, LDA $10, STA ($1A),Y
    const inst = decoder.Instruction{
        .opcode = .ST_X,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA0, 0x00, // LDY #0
        0xA5, 0x10, // LDA $10
        0x91, 0x1A, // STA ($1A),Y
    });
}

test "Memory: LD X+ (post-increment)" {
    // LD r16, X+ -> LDY #0, LDA ($1A),Y, STA $10, then INC/BNE/INC
    const inst = decoder.Instruction{
        .opcode = .LD_X_INC,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA0, 0x00, // LDY #0
        0xB1, 0x1A, // LDA ($1A),Y
        0x85, 0x10, // STA $10
        // Post-increment: INC/BNE/INC (doesn't corrupt carry)
        0xE6, 0x1A, // INC $1A
        0xD0, 0x02, // BNE +2 (skip INC hi)
        0xE6, 0x1B, // INC $1B
    });
}

test "Memory: LD -X (pre-decrement)" {
    // LD r16, -X -> LDA/BNE/DEC/DEC, then LDY #0, LDA ($1A),Y, STA $10
    const inst = decoder.Instruction{
        .opcode = .LD_X_DEC,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        // Pre-decrement: LDA/BNE/DEC/DEC (doesn't corrupt carry)
        0xA5, 0x1A, // LDA $1A
        0xD0, 0x02, // BNE +2 (skip DEC hi)
        0xC6, 0x1B, // DEC $1B
        0xC6, 0x1A, // DEC $1A
        // Load
        0xA0, 0x00, // LDY #0
        0xB1, 0x1A, // LDA ($1A),Y
        0x85, 0x10, // STA $10
    });
}

test "Memory: LDD Z+q (load with displacement)" {
    // LDD r16, Z+5 -> LDY #5, LDA ($1E),Y, STA $10
    const inst = decoder.Instruction{
        .opcode = .LDD_Z_Q,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 5 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA0, 0x05, // LDY #5
        0xB1, 0x1E, // LDA ($1E),Y
        0x85, 0x10, // STA $10
    });
}

test "Memory: STD Z+q (store with displacement)" {
    // STD Z+5, r16 -> LDY #5, LDA $10, STA ($1E),Y
    const inst = decoder.Instruction{
        .opcode = .STD_Z_Q,
        .operands = .{ .reg_imm = .{ .r = 16, .imm = 5 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA0, 0x05, // LDY #5
        0xA5, 0x10, // LDA $10
        0x91, 0x1E, // STA ($1E),Y
    });
}

// ============================================================
// LPM (Load Program Memory)
// ============================================================

test "Memory: LPM Rd, Z" {
    // LPM r16, Z -> LDY #0, LDA ($1E),Y, STA $10
    const inst = decoder.Instruction{
        .opcode = .LPM,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA0, 0x00, // LDY #0
        0xB1, 0x1E, // LDA ($1E),Y
        0x85, 0x10, // STA $10
    });
}

// ============================================================
// Decoder Tests
// ============================================================

test "Decoder: ADD r0, r1" {
    // ADD r0, r1 = 0000 1100 0000 0001 = 0x0C01
    const inst = decoder.decode(0x0C01, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ADD, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg_reg.r1);
    try std.testing.expectEqual(@as(u8, 1), inst.operands.reg_reg.r2);
}

test "Decoder: LDI r16, 0xAB" {
    // LDI r16, 0xAB = 1110 1010 0000 1011 = 0xEA0B
    const inst = decoder.decode(0xEA0B, null, 0);
    try std.testing.expectEqual(decoder.Opcode.LDI, inst.opcode);
    try std.testing.expectEqual(@as(u8, 16), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0xAB), inst.operands.reg_imm.imm);
}

test "Decoder: RJMP -1 (infinite loop)" {
    // RJMP .-2 = 1100 1111 1111 1111 = 0xCFFF
    const inst = decoder.decode(0xCFFF, null, 5);
    try std.testing.expectEqual(decoder.Opcode.RJMP, inst.opcode);
    try std.testing.expectEqual(@as(i16, -1), inst.operands.rel);
}

test "Decoder: BRBS (BREQ) +3" {
    // BRBS 1, +3 = 1111 0000 0001 1001 = 0xF019
    const inst = decoder.decode(0xF019, null, 0);
    try std.testing.expectEqual(decoder.Opcode.BRBS, inst.opcode);
    try std.testing.expectEqual(@as(u8, 1), inst.operands.reg_rel.r);
    try std.testing.expectEqual(@as(i16, 3), inst.operands.reg_rel.rel);
}

test "Decoder: PUSH r16" {
    // PUSH r16 = 1001 0010 0000 1111 = 0x920F
    // With d=16: 1001 001d dddd 1111, d=10000 -> 1001 0011 0000 1111 = 0x930F
    const inst = decoder.decode(0x930F, null, 0);
    try std.testing.expectEqual(decoder.Opcode.PUSH, inst.opcode);
    try std.testing.expectEqual(@as(u8, 16), inst.operands.reg);
}

test "Decoder: LDS r16, 0x1234 (32-bit)" {
    // LDS r16, $1234 = word1: 1001 000d dddd 0000 with d=16 -> 0x9100
    const inst = decoder.decode(0x9100, 0x1234, 0);
    try std.testing.expectEqual(decoder.Opcode.LDS, inst.opcode);
    try std.testing.expectEqual(@as(u8, 16), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0x1234), inst.operands.reg_imm.imm);
    try std.testing.expectEqual(@as(u8, 4), inst.size);
}

test "Decoder: ADIW r24, 1" {
    // ADIW r24, 1 = 1001 0110 0000 0001 = 0x9601
    // dd=0 -> r24, K=1
    const inst = decoder.decode(0x9601, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ADIW, inst.opcode);
    try std.testing.expectEqual(@as(u8, 24), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 1), inst.operands.reg_imm.imm);
}

test "Decoder: LD Z (not shadowed by LDD Z+q)" {
    // LD r16, Z = 1000 0000 0000 0000 with d=16 -> 1000 0001 0000 0000 = 0x8100
    const inst = decoder.decode(0x8100, null, 0);
    try std.testing.expectEqual(decoder.Opcode.LD_Z, inst.opcode);
    try std.testing.expectEqual(@as(u8, 16), inst.operands.reg);
}

test "Decoder: ST Z (not shadowed by STD Z+q)" {
    // ST Z, r16 = 1000 0010 0000 0000 with r=16 -> 1000 0011 0000 0000 = 0x8300
    const inst = decoder.decode(0x8300, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ST_Z, inst.opcode);
    try std.testing.expectEqual(@as(u8, 16), inst.operands.reg);
}

// ============================================================
// Translator: BLD (load T flag into bit)
// ============================================================

test "Data Transfer: BLD r5, 3" {
    // BLD r5, bit 3: should clear bit 3 in r5, shift T into position, OR and store
    const inst = decoder.Instruction{
        .opcode = .BLD,
        .operands = .{ .reg_imm = .{ .r = 5, .imm = 3 } },
        .size = 2,
        .addr = 0,
    };
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);

    const bytes = emit.bytes.items;
    // Should start with PHP (save flags)
    try std.testing.expectEqual(@as(u8, 0x08), bytes[0]); // PHP
    // LDA zp(5)
    try std.testing.expectEqual(@as(u8, 0xA5), bytes[1]); // LDA zp
    try std.testing.expectEqual(@as(u8, 0x05), bytes[2]); // r5
    // AND #~(1<<3) = AND #0xF7
    try std.testing.expectEqual(@as(u8, 0x29), bytes[3]); // AND #imm
    try std.testing.expectEqual(@as(u8, 0xF7), bytes[4]); // ~0x08
    // STA zp(5)
    try std.testing.expectEqual(@as(u8, 0x85), bytes[5]); // STA zp
    try std.testing.expectEqual(@as(u8, 0x05), bytes[6]); // r5
    // LDA zp($60) -- load T flag
    try std.testing.expectEqual(@as(u8, 0xA5), bytes[7]); // LDA zp
    try std.testing.expectEqual(@as(u8, 0x60), bytes[8]); // T flag
    // 3x ASL A to shift T into bit position 3
    try std.testing.expectEqual(@as(u8, 0x0A), bytes[9]); // ASL A
    try std.testing.expectEqual(@as(u8, 0x0A), bytes[10]); // ASL A
    try std.testing.expectEqual(@as(u8, 0x0A), bytes[11]); // ASL A
    // ORA zp(5)
    try std.testing.expectEqual(@as(u8, 0x05), bytes[12]); // ORA zp
    try std.testing.expectEqual(@as(u8, 0x05), bytes[13]); // r5
    // STA zp(5)
    try std.testing.expectEqual(@as(u8, 0x85), bytes[14]); // STA zp
    try std.testing.expectEqual(@as(u8, 0x05), bytes[15]); // r5
    // PLP (restore flags)
    try std.testing.expectEqual(@as(u8, 0x28), bytes[16]); // PLP
}

// ============================================================
// Decoder: JMP with high address bits
// ============================================================

test "Decoder: JMP 22-bit address" {
    // JMP k: word1 = 1001 010k kkkk 110k, word2 = kkkk kkkk kkkk kkkk
    // For target 0x20100: k_high = 0x02, k_low = 0x0100
    // word1 high bits: k[21:17] in bits [8:4], k[16] in bit [0]
    // k = 0x20100 = 0b 10 0000 0001 0000 0000
    // k_high = (0x20100 >> 16) = 0x02 = 0b000010
    // bit[0] of word1 = k[16] = 0
    // bits[8:4] of word1 = k[21:17] = 0b00001 -> shifted to [8:4] = 0b000010000
    // word1 = 1001 0100 0001 1100 = 0x941C
    // word2 = 0x0100
    const inst = decoder.decode(0x941C, 0x0100, 0);
    try std.testing.expectEqual(decoder.Opcode.JMP, inst.opcode);
    try std.testing.expectEqual(@as(u32, 0x20100), inst.operands.addr);
}

test "Decoder: JMP simple 16-bit address" {
    // JMP to 0x1234: k_high = 0, so word1 has all k bits = 0
    // word1 = 1001 0100 0000 1100 = 0x940C
    // word2 = 0x1234
    const inst = decoder.decode(0x940C, 0x1234, 0);
    try std.testing.expectEqual(decoder.Opcode.JMP, inst.opcode);
    try std.testing.expectEqual(@as(u32, 0x1234), inst.operands.addr);
}

// ============================================================
// Bit Manipulation: BST (store bit to T flag)
// ============================================================

test "Bit Manipulation: BST r5, 3" {
    // BST r5, 3: load r5, shift right 3, AND 1, store to T flag ($22)
    const inst = decoder.Instruction{
        .opcode = .BST,
        .operands = .{ .reg_imm = .{ .r = 5, .imm = 3 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x08, // PHP (save flags)
        0xA5, 0x05, // LDA $05
        0x4A, // LSR A (1)
        0x4A, // LSR A (2)
        0x4A, // LSR A (3)
        0x29, 0x01, // AND #$01
        0x85, 0x60, // STA $60
        0x28, // PLP (restore flags)
    });
}

// ============================================================
// BSET/BCLR carry_mode: verify carry set/clear
// ============================================================

test "Bit Manipulation: BSET 0 (SEC)" {
    const inst = decoder.Instruction{
        .opcode = .BSET,
        .operands = .{ .imm = 0 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x38, // SEC
    });
}

test "Bit Manipulation: BCLR 0 (CLC)" {
    const inst = decoder.Instruction{
        .opcode = .BCLR,
        .operands = .{ .imm = 0 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x18, // CLC
    });
}

test "Bit Manipulation: BSET 0 updates carry_mode for subsequent BRBS" {
    // BSET 0 (SEC) followed by BRBS 0 (branch if carry set)
    // After BSET 0, carry_mode should be .addition, so BRBS 0 should use BCC skip pattern
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // First emit a SUB to set carry_mode to .subtraction
    const sub_inst = decoder.Instruction{
        .opcode = .SUB,
        .operands = .{ .reg_reg = .{ .r1 = 0, .r2 = 1 } },
        .size = 2,
        .addr = 0,
    };
    // Then BSET 0 should reset carry_mode to .addition
    const bset_inst = decoder.Instruction{
        .opcode = .BSET,
        .operands = .{ .imm = 0 },
        .size = 2,
        .addr = 1,
    };
    // Then BRBS 0 should use addition semantics (BCC skip)
    const brbs_inst = decoder.Instruction{
        .opcode = .BRBS,
        .operands = .{ .reg_rel = .{ .r = 0, .rel = 5 } },
        .size = 2,
        .addr = 2,
    };

    var insts = [_]decoder.Instruction{ sub_inst, bset_inst, brbs_inst };
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 2,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);

    // Find the branch instruction after BSET (SEC)
    // SUB = SEC(1) + LDA(2) + SBC(2) + STA(2) = 7 bytes
    // BSET = SEC(1) = 1 byte
    // BRBS = branch(2) + JMP(3) = 5 bytes
    // The branch at offset 8 should be BCC (0x90) for addition mode, NOT BCS (0xB0) for subtraction
    try std.testing.expectEqual(@as(u8, 0x90), emit.bytes.items[8]); // BCC (addition semantics)
}

test "Logic: COM sets carry for subsequent BRBS" {
    // COM r16 followed by BRBS 0 (branch if carry set)
    // COM always sets C=1 with carry_mode=.addition, so BRBS 0 should use BCC skip (addition semantics)
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const com_inst = decoder.Instruction{
        .opcode = .COM,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    const brbs_inst = decoder.Instruction{
        .opcode = .BRBS,
        .operands = .{ .reg_rel = .{ .r = 0, .rel = 5 } },
        .size = 2,
        .addr = 1,
    };

    var insts = [_]decoder.Instruction{ com_inst, brbs_inst };
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 1,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);

    // COM = LDA(2) + EOR(2) + STA(2) + SEC(1) = 7 bytes
    // BRBS = branch(2) + JMP(3) = 5 bytes
    // At offset 7: should be BCC (0x90) since carry_mode is .addition after COM
    try std.testing.expectEqual(@as(u8, 0x90), emit.bytes.items[7]); // BCC (addition semantics)
}

test "Logic: SWAP preserves carry_mode for subsequent BRBS" {
    // SUB sets carry_mode=.subtraction, SWAP preserves it, BRBS 0 should use subtraction semantics
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const sub_inst = decoder.Instruction{
        .opcode = .SUB,
        .operands = .{ .reg_reg = .{ .r1 = 0, .r2 = 1 } },
        .size = 2,
        .addr = 0,
    };
    const swap_inst = decoder.Instruction{
        .opcode = .SWAP,
        .operands = .{ .reg = 2 },
        .size = 2,
        .addr = 1,
    };
    const brbs_inst = decoder.Instruction{
        .opcode = .BRBS,
        .operands = .{ .reg_rel = .{ .r = 0, .rel = 5 } },
        .size = 2,
        .addr = 2,
    };

    var insts = [_]decoder.Instruction{ sub_inst, swap_inst, brbs_inst };
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 2,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);

    // SUB = SEC(1) + LDA(2) + SBC(2) + STA(2) = 7 bytes
    // SWAP = PHP(1) + LDA(2) + ASL(1) + ADC(2) + ROL(1) + ASL(1) + ADC(2) + ROL(1) + STA(2) + PLP(1) = 14 bytes
    // BRBS at offset 21: should use subtraction semantics (BCS skip = 0xB0)
    try std.testing.expectEqual(@as(u8, 0xB0), emit.bytes.items[21]); // BCS (subtraction semantics preserved)
}

test "Carry mode: SUB → ADC requires FlipCarry" {
    // SUB sets carry_mode=.subtraction, ADC should emit FlipCarry
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const sub_inst = decoder.Instruction{
        .opcode = .SUB,
        .operands = .{ .reg_reg = .{ .r1 = 0, .r2 = 1 } },
        .size = 2,
        .addr = 0,
    };
    const adc_inst = decoder.Instruction{
        .opcode = .ADC,
        .operands = .{ .reg_reg = .{ .r1 = 2, .r2 = 3 } },
        .size = 2,
        .addr = 1,
    };

    var insts = [_]decoder.Instruction{ sub_inst, adc_inst };
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 1,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);

    // SUB = SEC(1) + LDA(2) + SBC(2) + STA(2) = 7 bytes
    // ADC with .subtraction carry_mode emits FlipCarry first = ROL(1)+EOR(2)+ROR(1) = 4 bytes
    // Then LDA(2) + ADC(2) + STA(2) = 6 bytes
    // Total = 7 + 4 + 6 = 17 bytes (was 19 with old 6-byte FlipCarry)
    try std.testing.expectEqual(@as(usize, 17), emit.bytes.items.len);

    // Verify FlipCarry at offset 7
    try std.testing.expectEqual(@as(u8, 0x2A), emit.bytes.items[7]); // ROL A
    try std.testing.expectEqual(@as(u8, 0x49), emit.bytes.items[8]); // EOR #imm
    try std.testing.expectEqual(@as(u8, 0x01), emit.bytes.items[9]); // #$01
    try std.testing.expectEqual(@as(u8, 0x6A), emit.bytes.items[10]); // ROR A
}

// ============================================================
// Emitter: Runtime Multiply
// ============================================================

test "Emitter: runtime multiply structure" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    _ = try emit.emitRuntime();

    // Verify the runtime defines the expected labels
    try std.testing.expect(emit.labels.get(0xFFFF) != null); // mul_u8
    try std.testing.expect(emit.labels.get(0xFFFD) != null); // mul_s8 stub
    try std.testing.expect(emit.labels.get(0xFFFC) != null); // extended mul stub

    // Verify the runtime ends with RTS (at the mul_u8 end)
    // The mul_u8 body should contain: STA $80, TYA, STA $00, LDA #0, LDX #8,
    // <loop body>, LSR A, ROR $00, STA $01, RTS
    // Check that we find RTS (0x60) followed by the stubs
    const bytes = emit.bytes.items;
    try std.testing.expect(bytes.len > 0);

    // Find the RTS that ends mul_u8 (before the mul_s8 stub label)
    const mul_s8_offset = emit.labels.get(0xFFFD).?;
    // The byte before the mul_s8 label should be RTS (0x60)
    try std.testing.expectEqual(@as(u8, 0x60), bytes[mul_s8_offset - 1]);

    // Verify mul_s8 stub jumps to mul_u8 (JMP instruction)
    try std.testing.expectEqual(@as(u8, 0x4C), bytes[mul_s8_offset]);
}

test "Emitter: runtime multiply uses ROR A (preserves carry)" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    _ = try emit.emitRuntime();

    // The loop body should contain ROR A (0x6A) NOT LSR A (0x4A)
    // Find the loop: after STA $80, TYA, STA $00, LDA #0, LDX #8, LSR $00
    // Setup: STA(2) + TYA(1) + STA(2) + LDA(2) + LDX(2) + LSR(2) = 11 bytes
    // Loop starts at offset 11: BCC(2) + CLC(1) + ADC(2) + ROR_A(1) + ROR_zp(2) + DEX(1) + BNE(2)
    const mul_u8_offset = emit.labels.get(0xFFFF).?;
    // ROR A should be at offset 16 (11 + BCC(2) + CLC(1) + ADC(2) = 16)
    try std.testing.expectEqual(@as(u8, 0x6A), emit.bytes.items[mul_u8_offset + 16]); // ROR A (not LSR A = 0x4A)
}

// ============================================================
// Emitter: Fixup Resolution
// ============================================================

test "Emitter: resolveFixups resolves forward references" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // Emit a JMP to label at AVR addr 0x0010
    try emit.emitJMP_label(0x0010);

    // Define the label after the JMP
    try emit.defineLabel(0x0010);
    try emit.emitNOP();

    // Resolve with base_addr 0x8000
    try emit.resolveFixups(0x8000);

    // JMP should point to 0x8000 + 3 (offset of label after JMP)
    try std.testing.expectEqual(@as(u8, 0x4C), emit.bytes.items[0]);
    try std.testing.expectEqual(@as(u8, 0x03), emit.bytes.items[1]); // lo byte
    try std.testing.expectEqual(@as(u8, 0x80), emit.bytes.items[2]); // hi byte
}

// ============================================================
// Emitter: Jump Table
// ============================================================

test "Emitter: generateJumpTable with entries" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // Define two labels
    try emit.defineLabel(0x0010); // at offset 0
    try emit.emitNOP();
    try emit.defineLabel(0x0020); // at offset 1

    const table_addr = try emit.generateJumpTable(0x8000);
    const count = emit.labels.count();

    // Table should start after the NOP
    try std.testing.expect(table_addr > 0x8000);
    // Should have entries for both labels
    try std.testing.expect(count >= 2);

    // The table has 4 parallel arrays: avr_lo, avr_hi, 6502_lo, 6502_hi
    // Total table size = 4 * count
    // After the NOP (1 byte), the table starts at offset 1
    // Total bytes should be 1 (NOP) + 4 * count (table)
    try std.testing.expectEqual(@as(usize, 1 + 4 * count), emit.bytes.items.len);
}

// ============================================================
// Emitter: Data Section
// ============================================================

test "Emitter: emitDataSection basic" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // Emit some code first (10 bytes of NOPs)
    for (0..10) |_| try emit.emitNOP();

    // Emit data section at offset 20 (relative to base 0x8000)
    // So target_addr = 0x8000 + 20 = 0x8014
    const data = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    try emit.emitDataSection(0x8000, 0x8014, &data);

    // Should have 10 NOPs + 10 padding zeros + 4 data bytes = 24
    try std.testing.expectEqual(@as(usize, 24), emit.bytes.items.len);

    // Check data bytes at the end
    try std.testing.expectEqual(@as(u8, 0xDE), emit.bytes.items[20]);
    try std.testing.expectEqual(@as(u8, 0xAD), emit.bytes.items[21]);
    try std.testing.expectEqual(@as(u8, 0xBE), emit.bytes.items[22]);
    try std.testing.expectEqual(@as(u8, 0xEF), emit.bytes.items[23]);

    // Check padding is zeros
    for (10..20) |i| {
        try std.testing.expectEqual(@as(u8, 0x00), emit.bytes.items[i]);
    }
}

// ============================================================
// Emitter: Trampoline
// ============================================================

test "Emitter: trampoline structure" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // Setup: define a label and generate jump table first
    try emit.defineLabel(0x0010);
    try emit.emitNOP();

    const table_addr = try emit.generateJumpTable(0x8000);
    const table_len = emit.labels.count();

    const tramp_addr = try emit.emitTrampoline(0x8000, table_addr, table_len);

    // Trampoline should start after the table
    try std.testing.expect(tramp_addr > table_addr);

    // Verify the trampoline starts with LDX #imm (0xA2)
    const tramp_offset = tramp_addr - 0x8000;
    try std.testing.expectEqual(@as(u8, 0xA2), emit.bytes.items[tramp_offset]);

    // The trampoline should end with RTS (0x60) for the RTS trick
    const last_byte = emit.bytes.items[emit.bytes.items.len - 1];
    try std.testing.expectEqual(@as(u8, 0x60), last_byte);
}

// ============================================================
// Bug fix tests: CPSE carry_mode update
// ============================================================

test "Carry mode: CPSE updates carry_mode to subtraction" {
    // CPSE uses CMP internally, which sets carry with subtraction semantics.
    // A following ADC should emit FlipCarry since carry_mode was changed to .subtraction.
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const cpse_inst = decoder.Instruction{
        .opcode = .CPSE,
        .operands = .{ .reg_reg = .{ .r1 = 0, .r2 = 1 } },
        .size = 2,
        .addr = 0,
    };
    const adc_inst = decoder.Instruction{
        .opcode = .ADC,
        .operands = .{ .reg_reg = .{ .r1 = 2, .r2 = 3 } },
        .size = 2,
        .addr = 1,
    };

    var insts = [_]decoder.Instruction{ cpse_inst, adc_inst };
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 1,
        .instructions = &insts,
        .successors = .{ 2, null },
    };

    try emit.labels.put(2, 200);
    try translator.translateBlock(block, .nmos6502, &emit, 0);

    // CPSE = LDA(2) + CMP(2) + BNE(2) + JMP(3) = 9 bytes
    // ADC should start with FlipCarry (4 bytes) since carry_mode is .subtraction
    try std.testing.expectEqual(@as(u8, 0x2A), emit.bytes.items[9]); // ROL A (start of FlipCarry)
}

// ============================================================
// BRBS/BRBC with unknown flag bits (fallback)
// ============================================================

test "Control Flow: BRBS with unknown flag bit 4 uses fallback JMP" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // BRBS 4, target — bit 4 (S flag) is not directly mapped, uses fallback
    const inst = decoder.Instruction{
        .opcode = .BRBS,
        .operands = .{ .reg_rel = .{ .r = 4, .rel = 2 } },
        .size = 2,
        .addr = 0,
    };

    try emit.labels.put(3, 100);
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    // Should emit just a JMP (fallback for unknown flag bits)
    try std.testing.expectEqual(@as(u8, 0x4C), emit.bytes.items[0]); // JMP
    try std.testing.expectEqual(@as(usize, 3), emit.bytes.items.len); // Only JMP, no conditional skip
}

// ============================================================
// Decoder: SBIC/SBIS
// ============================================================

test "Decoder: SBIC port 5, bit 2" {
    // SBIC A, b = 1001 1001 AAAA Abbb
    // A=5 (00101), b=2 (010) -> 1001 1001 0010 1010 = 0x992A
    const inst = decoder.decode(0x992A, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SBIC, inst.opcode);
    try std.testing.expectEqual(@as(u8, 5), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 2), inst.operands.reg_imm.imm);
}

test "Decoder: SBIS port 3, bit 7" {
    // SBIS A, b = 1001 1011 AAAA Abbb
    // A=3 (00011), b=7 (111) -> 1001 1011 0001 1111 = 0x9B1F
    const inst = decoder.decode(0x9B1F, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SBIS, inst.opcode);
    try std.testing.expectEqual(@as(u8, 3), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 7), inst.operands.reg_imm.imm);
}

// ============================================================
// Decoder: BST/BLD
// ============================================================

test "Decoder: BST r10, 5" {
    // BST Rd, b = 1111 101d dddd 0bbb
    // d=10 (01010), b=5 (101) -> 1111 1010 1010 0101 = 0xFAA5
    const inst = decoder.decode(0xFAA5, null, 0);
    try std.testing.expectEqual(decoder.Opcode.BST, inst.opcode);
    try std.testing.expectEqual(@as(u8, 10), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 5), inst.operands.reg_imm.imm);
}

test "Decoder: BLD r20, 0" {
    // BLD Rd, b = 1111 100d dddd 0bbb
    // d=20 (10100), b=0 (000) -> 1111 1001 0100 0000 = 0xF940
    const inst = decoder.decode(0xF940, null, 0);
    try std.testing.expectEqual(decoder.Opcode.BLD, inst.opcode);
    try std.testing.expectEqual(@as(u8, 20), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0), inst.operands.reg_imm.imm);
}

// ============================================================
// Translator: MULS
// ============================================================

test "Arithmetic: MULS" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const inst = decoder.Instruction{
        .opcode = .MULS,
        .operands = .{ .reg_reg = .{ .r1 = 16, .r2 = 17 } },
        .size = 2,
        .addr = 0,
    };

    try emit.labels.put(0xFFFD, 100); // mul_s8 runtime
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xA5, 0x10, // LDA $10
        0xA4, 0x11, // LDY $11
        0x20, 0x64, 0x10, // JSR $1064 (mul_s8)
    }, emit.bytes.items);
}

// ============================================================
// Translator: BCLR 3 (CLV)
// ============================================================

test "Bit Manipulation: BCLR 3 (CLV)" {
    const inst = decoder.Instruction{
        .opcode = .BCLR,
        .operands = .{ .imm = 3 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xB8, // CLV
    });
}

// ============================================================
// Carry mode: SUBI → SBCI sequence (no extra FlipCarry needed)
// ============================================================

test "Carry mode: SUBI then SBCI (no FlipCarry)" {
    // SUBI sets carry_mode=.subtraction, so SBCI should NOT emit FlipCarry
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const subi_inst = decoder.Instruction{
        .opcode = .SUBI,
        .operands = .{ .reg_imm = .{ .r = 24, .imm = 0x01 } },
        .size = 2,
        .addr = 0,
    };
    const sbci_inst = decoder.Instruction{
        .opcode = .SBCI,
        .operands = .{ .reg_imm = .{ .r = 25, .imm = 0x00 } },
        .size = 2,
        .addr = 1,
    };

    var insts = [_]decoder.Instruction{ subi_inst, sbci_inst };
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 1, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);

    // SUBI: SEC(1) + LDA(2) + SBC(2) + STA(2) = 7 bytes
    // SBCI: no FlipCarry needed, just LDA(2) + SBC(2) + STA(2) = 6 bytes
    try std.testing.expectEqual(@as(usize, 13), emit.bytes.items.len);
    // Verify SBCI starts directly with LDA (no PHP/FlipCarry)
    try std.testing.expectEqual(@as(u8, 0xA5), emit.bytes.items[7]); // LDA zp (not PHP=0x08)
}

// ============================================================
// Session 6: New Tests
// ============================================================

test "Register: CLR on 65C02 uses STZ" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const inst = decoder.Instruction{
        .opcode = .CLR,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };

    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .c6502, &emit, 0);

    // 65C02: STZ $10 (2 bytes instead of 4)
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x64, 0x10, // STZ $10
    }, emit.bytes.items);
}

test "Optimizer Level 4: absolute to zero-page INC" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.emitByte(0xEE); // INC abs
    try emit.emitByte(0x10);
    try emit.emitByte(0x00);

    try optimizer.Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xE6), emit.bytes.items[0]); // INC zp
    try std.testing.expectEqual(@as(u8, 0x10), emit.bytes.items[1]);
}

test "Optimizer Level 4: absolute to zero-page DEC" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.emitByte(0xCE); // DEC abs
    try emit.emitByte(0x10);
    try emit.emitByte(0x00);

    try optimizer.Optimizer.optimize(&emit, 4);
    try std.testing.expectEqual(@as(usize, 2), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0xC6), emit.bytes.items[0]); // DEC zp
    try std.testing.expectEqual(@as(u8, 0x10), emit.bytes.items[1]);
}

test "Decoder: MOVW r0:r1 <- r2:r3" {
    // MOVW Rd, Rr = 0000 0001 dddd rrrr
    // d=0 (pair 0:1), r=1 (pair 2:3) -> 0000 0001 0000 0001 = 0x0101
    const inst = decoder.decode(0x0101, null, 0);
    try std.testing.expectEqual(decoder.Opcode.MOVW, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg_reg.r1);
    try std.testing.expectEqual(@as(u8, 2), inst.operands.reg_reg.r2);
}

test "Decoder: MOV r0, r31" {
    // MOV Rd, Rr = 0010 11rd dddd rrrr
    // d=0, r=31: r[4]=1, r[3:0]=1111 -> 0010 1110 0000 1111 = 0x2E0F
    const inst = decoder.decode(0x2E0F, null, 0);
    try std.testing.expectEqual(decoder.Opcode.MOV, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg_reg.r1);
    try std.testing.expectEqual(@as(u8, 31), inst.operands.reg_reg.r2);
}

test "Decoder: SBIW r24, 63" {
    // SBIW Rd, K = 1001 0111 KKdd KKKK
    // dd=0 (r24), K=63=0b110000|001111 -> KK=11, KKKK=1111
    // 1001 0111 1100 1111 = 0x97CF
    const inst = decoder.decode(0x97CF, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SBIW, inst.opcode);
    try std.testing.expectEqual(@as(u8, 24), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 63), inst.operands.reg_imm.imm);
}

test "Decoder: MULS r16, r17" {
    // MULS Rd, Rr = 0000 0010 dddd rrrr (d+16, r+16)
    // d=0 (r16), r=1 (r17) -> 0000 0010 0000 0001 = 0x0201
    const inst = decoder.decode(0x0201, null, 0);
    try std.testing.expectEqual(decoder.Opcode.MULS, inst.opcode);
    try std.testing.expectEqual(@as(u8, 16), inst.operands.reg_reg.r1);
    try std.testing.expectEqual(@as(u8, 17), inst.operands.reg_reg.r2);
}

test "Translator: ICALL emits JSR to trampoline" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const inst = decoder.Instruction{
        .opcode = .ICALL,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };

    try emit.labels.put(0xFFFE, 0x0100);
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x2000);

    // JSR $2100 (trampoline)
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x20, 0x00, 0x21 }, emit.bytes.items);
}

test "Translator: ELPM emits NOP stub" {
    const inst = decoder.Instruction{
        .opcode = .ELPM,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };

    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try std.testing.expectEqualSlices(u8, &[_]u8{0xEA}, emit.bytes.items);
}

test "Translator: WDR emits NOP" {
    const inst = decoder.Instruction{
        .opcode = .WDR,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };

    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try std.testing.expectEqualSlices(u8, &[_]u8{0xEA}, emit.bytes.items);
}

test "Translator: SBIC (skip if I/O bit clear)" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const inst = decoder.Instruction{
        .opcode = .SBIC,
        .operands = .{ .reg_imm = .{ .r = 5, .imm = 2 } },
        .size = 2,
        .addr = 0,
    };

    try emit.labels.put(2, 200);
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
        .successors = .{ 2, null },
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xA5, 0x25, // LDA zp($20 + 5)
        0x29, 0x04, // AND #$04 (1 << 2)
        0xD0, 0x03, // BNE +3 (skip if bit set — SBIC skips when clear)
        0x4C, 0xC8, 0x10, // JMP $10C8
    }, emit.bytes.items);
}

test "Decoder: CALL 0x1234" {
    // CALL to 0x1234: word1 = 1001 0100 0000 1110 = 0x940E, word2 = 0x1234
    const inst = decoder.decode(0x940E, 0x1234, 0);
    try std.testing.expectEqual(decoder.Opcode.CALL, inst.opcode);
    try std.testing.expectEqual(@as(u32, 0x1234), inst.operands.addr);
    try std.testing.expectEqual(@as(u8, 4), inst.size);
}

test "Decoder: RET" {
    const inst = decoder.decode(0x9508, null, 0);
    try std.testing.expectEqual(decoder.Opcode.RET, inst.opcode);
}

test "Decoder: RETI" {
    const inst = decoder.decode(0x9518, null, 0);
    try std.testing.expectEqual(decoder.Opcode.RETI, inst.opcode);
}

test "Decoder: COM r5" {
    // COM Rd = 1001 010d dddd 0000, d=5 -> 1001 0100 0101 0000 = 0x9450
    const inst = decoder.decode(0x9450, null, 0);
    try std.testing.expectEqual(decoder.Opcode.COM, inst.opcode);
    try std.testing.expectEqual(@as(u8, 5), inst.operands.reg);
}

test "Decoder: NEG r10" {
    // NEG Rd = 1001 010d dddd 0001, d=10 -> 1001 0100 1010 0001 = 0x94A1
    const inst = decoder.decode(0x94A1, null, 0);
    try std.testing.expectEqual(decoder.Opcode.NEG, inst.opcode);
    try std.testing.expectEqual(@as(u8, 10), inst.operands.reg);
}

test "Decoder: SWAP r7" {
    // SWAP Rd = 1001 010d dddd 0010, d=7 -> 1001 0100 0111 0010 = 0x9472
    const inst = decoder.decode(0x9472, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SWAP, inst.opcode);
    try std.testing.expectEqual(@as(u8, 7), inst.operands.reg);
}

test "Decoder: ASR r3" {
    // ASR Rd = 1001 010d dddd 0101, d=3 -> 1001 0100 0011 0101 = 0x9435
    const inst = decoder.decode(0x9435, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ASR, inst.opcode);
    try std.testing.expectEqual(@as(u8, 3), inst.operands.reg);
}

test "Decoder: ROR r12" {
    // ROR Rd = 1001 010d dddd 0111, d=12 -> 1001 0100 1100 0111 = 0x94C7
    const inst = decoder.decode(0x94C7, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ROR, inst.opcode);
    try std.testing.expectEqual(@as(u8, 12), inst.operands.reg);
}

test "Decoder: LSR r20" {
    // LSR Rd = 1001 010d dddd 0110, d=20 -> 1001 0101 0100 0110 = 0x9546
    const inst = decoder.decode(0x9546, null, 0);
    try std.testing.expectEqual(decoder.Opcode.LSR, inst.opcode);
    try std.testing.expectEqual(@as(u8, 20), inst.operands.reg);
}

test "Translator: JMP with VMA offset" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    // JMP target at AVR word addr 0x100, with text_vma=0x100 (word offset 0x80)
    // Translator subtracts vma_word_offset: 0x100 - 0x80 = 0x80
    const inst = decoder.Instruction{
        .opcode = .JMP,
        .operands = .{ .addr = 0x100 },
        .size = 4,
        .addr = 0,
    };

    try emit.labels.put(0x80, 50);
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0x100);
    try emit.resolveFixups(0x1000);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x4C, 0x32, 0x10, // JMP $1032 (0x1000 + 50)
    }, emit.bytes.items);
}

// ============================================================
// Session 7: New Tests
// ============================================================

test "Memory: LD X+ preserves carry flag for subsequent branch" {
    // SUB sets carry_mode=.subtraction, then LD X+ should NOT corrupt carry,
    // so BRBS 0 should still use subtraction semantics (BCS skip).
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const sub_inst = decoder.Instruction{
        .opcode = .SUB,
        .operands = .{ .reg_reg = .{ .r1 = 0, .r2 = 1 } },
        .size = 2,
        .addr = 0,
    };
    const ld_inc_inst = decoder.Instruction{
        .opcode = .LD_X_INC,
        .operands = .{ .reg = 2 },
        .size = 2,
        .addr = 1,
    };
    const brbs_inst = decoder.Instruction{
        .opcode = .BRBS,
        .operands = .{ .reg_rel = .{ .r = 0, .rel = 5 } },
        .size = 2,
        .addr = 2,
    };

    var insts = [_]decoder.Instruction{ sub_inst, ld_inc_inst, brbs_inst };
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 2,
        .instructions = &insts,
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);

    // SUB = SEC(1) + LDA(2) + SBC(2) + STA(2) = 7 bytes
    // LD X+ = LDY(2) + LDA(2) + STA(2) + INC(2) + BNE(2) + INC(2) = 12 bytes
    // BRBS at offset 19: should use subtraction semantics (BCS = 0xB0)
    try std.testing.expectEqual(@as(u8, 0xB0), emit.bytes.items[19]); // BCS (subtraction semantics preserved)
}

test "Memory: ST -Y (pre-decrement pattern)" {
    // ST -Y, r16 -> LDA/BNE/DEC/DEC, LDY #0, LDA $10, STA ($1C),Y
    const inst = decoder.Instruction{
        .opcode = .ST_Y_DEC,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        // Pre-decrement
        0xA5, 0x1C, // LDA $1C (Y lo)
        0xD0, 0x02, // BNE +2
        0xC6, 0x1D, // DEC $1D (Y hi)
        0xC6, 0x1C, // DEC $1C (Y lo)
        // Store
        0xA0, 0x00, // LDY #0
        0xA5, 0x10, // LDA $10
        0x91, 0x1C, // STA ($1C),Y
    }, emit.bytes.items);
}

test "Memory: ST Z+ (post-increment pattern)" {
    // ST Z+, r16 -> LDY #0, LDA $10, STA ($1E),Y, INC/BNE/INC
    const inst = decoder.Instruction{
        .opcode = .ST_Z_INC,
        .operands = .{ .reg = 16 },
        .size = 2,
        .addr = 0,
    };
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xA0, 0x00, // LDY #0
        0xA5, 0x10, // LDA $10
        0x91, 0x1E, // STA ($1E),Y
        // Post-increment
        0xE6, 0x1E, // INC $1E (Z lo)
        0xD0, 0x02, // BNE +2
        0xE6, 0x1F, // INC $1F (Z hi)
    }, emit.bytes.items);
}

test "Emitter: FlipCarry is 4 bytes (ROL/EOR/ROR)" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    try emit.emitFlipCarry();

    try std.testing.expectEqual(@as(usize, 4), emit.bytes.items.len);
    try std.testing.expectEqual(@as(u8, 0x2A), emit.bytes.items[0]); // ROL A
    try std.testing.expectEqual(@as(u8, 0x49), emit.bytes.items[1]); // EOR #imm
    try std.testing.expectEqual(@as(u8, 0x01), emit.bytes.items[2]); // #$01
    try std.testing.expectEqual(@as(u8, 0x6A), emit.bytes.items[3]); // ROR A
}

test "Decoder: SBI port 4, bit 6" {
    // SBI A, b = 1001 1010 AAAA Abbb
    // A=4 (00100), b=6 (110) -> 1001 1010 0010 0110 = 0x9A26
    const inst = decoder.decode(0x9A26, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SBI, inst.opcode);
    try std.testing.expectEqual(@as(u8, 4), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 6), inst.operands.reg_imm.imm);
}

test "Decoder: CBI port 1, bit 0" {
    // CBI A, b = 1001 1000 AAAA Abbb
    // A=1 (00001), b=0 (000) -> 1001 1000 0000 1000 = 0x9808
    const inst = decoder.decode(0x9808, null, 0);
    try std.testing.expectEqual(decoder.Opcode.CBI, inst.opcode);
    try std.testing.expectEqual(@as(u8, 1), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0), inst.operands.reg_imm.imm);
}

test "Decoder: INC r31" {
    // INC Rd = 1001 010d dddd 0011, d=31 -> 1001 0101 1111 0011 = 0x95F3
    const inst = decoder.decode(0x95F3, null, 0);
    try std.testing.expectEqual(decoder.Opcode.INC, inst.opcode);
    try std.testing.expectEqual(@as(u8, 31), inst.operands.reg);
}

test "Decoder: DEC r0" {
    // DEC Rd = 1001 010d dddd 1010, d=0 -> 1001 0100 0000 1010 = 0x940A
    const inst = decoder.decode(0x940A, null, 0);
    try std.testing.expectEqual(decoder.Opcode.DEC, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg);
}

test "Translator: SPM emits indirect store via Z" {
    const inst = decoder.Instruction{
        .opcode = .SPM,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xA0, 0x00, // LDY #0
        0xA5, 0x00, // LDA $00 (r0)
        0x91, 0x1E, // STA ($1E),Y (Z pointer)
    }, emit.bytes.items);
}

test "Translator: SLEEP emits NOP" {
    const inst = decoder.Instruction{
        .opcode = .SLEEP,
        .operands = .none,
        .size = 2,
        .addr = 0,
    };
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try std.testing.expectEqualSlices(u8, &[_]u8{0xEA}, emit.bytes.items);
}

// ============================================================
// Session 8: New Tests
// ============================================================

test "Decoder: SBRC r5, bit 2" {
    // SBRC r, b = 1111 110r rrrr 0bbb
    // r=5 (00101), b=2 (010) -> 1111 1100 0101 0010 = 0xFC52
    const inst = decoder.decode(0xFC52, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SBRC, inst.opcode);
    try std.testing.expectEqual(@as(u8, 5), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 2), inst.operands.reg_imm.imm);
}

test "Decoder: SBRS r20, bit 7" {
    // SBRS r, b = 1111 111r rrrr 0bbb
    // r=20 (10100), b=7 (111) -> 1111 1111 0100 0111 = 0xFF47
    const inst = decoder.decode(0xFF47, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SBRS, inst.opcode);
    try std.testing.expectEqual(@as(u8, 20), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 7), inst.operands.reg_imm.imm);
}

test "Decoder: RCALL +10" {
    // RCALL k = 1101 kkkk kkkk kkkk, k=10 -> 1101 0000 0000 1010 = 0xD00A
    const inst = decoder.decode(0xD00A, null, 0);
    try std.testing.expectEqual(decoder.Opcode.RCALL, inst.opcode);
    try std.testing.expectEqual(@as(i16, 10), inst.operands.rel);
}

test "Decoder: RCALL -5" {
    // k = -5 -> 12-bit: 0xFFB -> 1101 1111 1111 1011 = 0xDFFB
    const inst = decoder.decode(0xDFFB, null, 0);
    try std.testing.expectEqual(decoder.Opcode.RCALL, inst.opcode);
    try std.testing.expectEqual(@as(i16, -5), inst.operands.rel);
}

test "Decoder: BRBC 0, +5" {
    // BRBC s, k = 1111 01kk kkkk ksss, s=0, k=5
    // k=5 -> 0000101, bits: 1111 0100 0010 1000 = 0xF428
    const inst = decoder.decode(0xF428, null, 0);
    try std.testing.expectEqual(decoder.Opcode.BRBC, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg_rel.r);
    try std.testing.expectEqual(@as(i16, 5), inst.operands.reg_rel.rel);
}

test "Decoder: CPSE r0, r1" {
    // CPSE Rd, Rr = 0001 00rd dddd rrrr
    // d=0, r=1 -> 0001 0000 0000 0001 = 0x1001
    const inst = decoder.decode(0x1001, null, 0);
    try std.testing.expectEqual(decoder.Opcode.CPSE, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg_reg.r1);
    try std.testing.expectEqual(@as(u8, 1), inst.operands.reg_reg.r2);
}

test "Decoder: IN r0, port 0x3F" {
    // IN Rd, P = 1011 0PPd dddd PPPP
    // d=0, P=0x3F (110000 | 1111) -> 1011 0110 0000 1111 = 0xB60F
    const inst = decoder.decode(0xB60F, null, 0);
    try std.testing.expectEqual(decoder.Opcode.IN, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg_io.r);
    try std.testing.expectEqual(@as(u8, 0x3F), inst.operands.reg_io.io);
}

test "Decoder: OUT port 0x3F, r0" {
    // OUT P, Rr = 1011 1PPr rrrr PPPP
    // r=0, P=0x3F -> 1011 1110 0000 1111 = 0xBE0F
    const inst = decoder.decode(0xBE0F, null, 0);
    try std.testing.expectEqual(decoder.Opcode.OUT, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0x3F), inst.operands.io_reg.io);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.io_reg.r);
}

test "Decoder: POP r0" {
    // POP Rd = 1001 000d dddd 1111, d=0 -> 1001 0000 0000 1111 = 0x900F
    const inst = decoder.decode(0x900F, null, 0);
    try std.testing.expectEqual(decoder.Opcode.POP, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg);
}

test "Decoder: STS 0xABCD, r5" {
    // STS k, Rr = 1001 001r rrrr 0000, d=5 -> 1001 0010 0101 0000 = 0x9250
    const inst = decoder.decode(0x9250, 0xABCD, 0);
    try std.testing.expectEqual(decoder.Opcode.STS, inst.opcode);
    try std.testing.expectEqual(@as(u8, 5), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0xABCD), inst.operands.reg_imm.imm);
    try std.testing.expectEqual(@as(u8, 4), inst.size);
}

test "Decoder: ANDI r20, 0x55" {
    // ANDI Rd, K = 0111 KKKK dddd KKKK, d=20 (idx 4), K=0x55
    // K high=0101, d=0100, K low=0101 -> 0111 0101 0100 0101 = 0x7545
    const inst = decoder.decode(0x7545, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ANDI, inst.opcode);
    try std.testing.expectEqual(@as(u8, 20), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0x55), inst.operands.reg_imm.imm);
}

test "Decoder: ORI r16, 0xFF" {
    // ORI Rd, K = 0110 KKKK dddd KKKK, d=16 (idx 0), K=0xFF
    // 0110 1111 0000 1111 = 0x6F0F
    const inst = decoder.decode(0x6F0F, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ORI, inst.opcode);
    try std.testing.expectEqual(@as(u8, 16), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0xFF), inst.operands.reg_imm.imm);
}

test "Decoder: SUBI r31, 0x01" {
    // SUBI Rd, K = 0101 KKKK dddd KKKK, d=31 (idx 15), K=0x01
    // 0101 0000 1111 0001 = 0x50F1
    const inst = decoder.decode(0x50F1, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SUBI, inst.opcode);
    try std.testing.expectEqual(@as(u8, 31), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0x01), inst.operands.reg_imm.imm);
}

test "Decoder: SBCI r16, 0x00" {
    // SBCI Rd, K = 0100 KKKK dddd KKKK, d=16 (idx 0), K=0x00
    // 0100 0000 0000 0000 = 0x4000
    const inst = decoder.decode(0x4000, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SBCI, inst.opcode);
    try std.testing.expectEqual(@as(u8, 16), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0x00), inst.operands.reg_imm.imm);
}

test "Translator: ADIW on 65816 uses REP/SEP" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const inst = decoder.Instruction{
        .opcode = .ADIW,
        .operands = .{ .reg_imm = .{ .r = 24, .imm = 5 } },
        .size = 2,
        .addr = 0,
    };

    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{ .start_addr = 0, .end_addr = 0, .instructions = &insts };
    try translator.translateBlock(block, .c65816, &emit, 0);

    // REP #$20, CLC, LDA $18, ADC #5, 0x00 (hi), STA $18, SEP #$20
    try std.testing.expectEqual(@as(u8, 0xC2), emit.bytes.items[0]); // REP
    try std.testing.expectEqual(@as(u8, 0x20), emit.bytes.items[1]); // #$20
    try std.testing.expectEqual(@as(u8, 0x18), emit.bytes.items[2]); // CLC
    try std.testing.expectEqual(@as(u8, 0xE2), emit.bytes.items[emit.bytes.items.len - 2]); // SEP
    try std.testing.expectEqual(@as(u8, 0x20), emit.bytes.items[emit.bytes.items.len - 1]); // #$20
}

test "Memory: LDD Y+q (load with Y displacement)" {
    const inst = decoder.Instruction{
        .opcode = .LDD_Y_Q,
        .operands = .{ .reg_imm = .{ .r = 10, .imm = 3 } },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xA0, 0x03, // LDY #3
        0xB1, 0x1C, // LDA ($1C),Y  (Y pointer)
        0x85, 0x0A, // STA $0A (r10)
    });
}

test "Translator: SBIS (skip if I/O bit set)" {
    var emit = emitter.Emitter.init(std.testing.allocator);
    defer emit.deinit();

    const inst = decoder.Instruction{
        .opcode = .SBIS,
        .operands = .{ .reg_imm = .{ .r = 5, .imm = 2 } },
        .size = 2,
        .addr = 0,
    };

    try emit.labels.put(2, 200);
    var insts = [_]decoder.Instruction{inst};
    const block = cfg.BasicBlock{
        .start_addr = 0,
        .end_addr = 0,
        .instructions = &insts,
        .successors = .{ 2, null },
    };

    try translator.translateBlock(block, .nmos6502, &emit, 0);
    try emit.resolveFixups(0x1000);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xA5, 0x25, // LDA zp($20 + 5)
        0x29, 0x04, // AND #$04 (1 << 2)
        0xF0, 0x03, // BEQ +3 (skip if bit clear — SBIS skips when set)
        0x4C, 0xC8, 0x10, // JMP $10C8
    }, emit.bytes.items);
}

test "Bit Manipulation: BCLR 7 (SEI — disable interrupts)" {
    const inst = decoder.Instruction{
        .opcode = .BCLR,
        .operands = .{ .imm = 7 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x78, // SEI (AVR BCLR 7 = CLI -> 6502 SEI)
    });
}

test "Bit Manipulation: BSET 7 (CLI — enable interrupts)" {
    const inst = decoder.Instruction{
        .opcode = .BSET,
        .operands = .{ .imm = 7 },
        .size = 2,
        .addr = 0,
    };
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0x58, // CLI (AVR BSET 7 = SEI -> 6502 CLI)
    });
}

test "Bit Manipulation: BSET 3 (unsupported, emits NOP stub)" {
    const inst = decoder.Instruction{
        .opcode = .BSET,
        .operands = .{ .imm = 3 },
        .size = 2,
        .addr = 0,
    };
    // BSET 3 = SEV (set overflow) - no 6502 equivalent, emits NOP
    try testTranslate(std.testing.allocator, inst, &[_]u8{
        0xEA, // NOP (stub)
    });
}

test "Decoder: LD r0, X+" {
    // LD Rd, X+ = 1001 000d dddd 1101, d=0 -> 1001 0000 0000 1101 = 0x900D
    const inst = decoder.decode(0x900D, null, 0);
    try std.testing.expectEqual(decoder.Opcode.LD_X_INC, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg);
}

test "Decoder: ST -X, r31" {
    // ST -X, Rr = 1001 001r rrrr 1110, r=31 -> 1001 0011 1111 1110 = 0x93FE
    const inst = decoder.decode(0x93FE, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ST_X_DEC, inst.opcode);
    try std.testing.expectEqual(@as(u8, 31), inst.operands.reg);
}

test "Decoder: LD r10, -Y" {
    // LD Rd, -Y = 1001 000d dddd 1010, d=10 -> 1001 0000 1010 1010 = 0x90AA
    const inst = decoder.decode(0x90AA, null, 0);
    try std.testing.expectEqual(decoder.Opcode.LD_Y_DEC, inst.opcode);
    try std.testing.expectEqual(@as(u8, 10), inst.operands.reg);
}

test "Decoder: ST Z+, r0" {
    // ST Z+, Rr = 1001 001r rrrr 0001, r=0 -> 1001 0010 0000 0001 = 0x9201
    const inst = decoder.decode(0x9201, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ST_Z_INC, inst.opcode);
    try std.testing.expectEqual(@as(u8, 0), inst.operands.reg);
}

test "Decoder: CPI r24, 0x80" {
    // CPI Rd, K = 0011 KKKK dddd KKKK, d=24 (idx 8), K=0x80
    // K_hi=1000, d=1000, K_lo=0000 -> 0011 1000 1000 0000 = 0x3880
    const inst = decoder.decode(0x3880, null, 0);
    try std.testing.expectEqual(decoder.Opcode.CPI, inst.opcode);
    try std.testing.expectEqual(@as(u8, 24), inst.operands.reg_imm.r);
    try std.testing.expectEqual(@as(u16, 0x80), inst.operands.reg_imm.imm);
}

test "Decoder: SLEEP" {
    const inst = decoder.decode(0x9588, null, 0);
    try std.testing.expectEqual(decoder.Opcode.SLEEP, inst.opcode);
}

test "Decoder: WDR" {
    const inst = decoder.decode(0x95A8, null, 0);
    try std.testing.expectEqual(decoder.Opcode.WDR, inst.opcode);
}

test "Decoder: BREAK" {
    const inst = decoder.decode(0x9598, null, 0);
    try std.testing.expectEqual(decoder.Opcode.BREAK, inst.opcode);
}

test "Decoder: IJMP" {
    const inst = decoder.decode(0x9409, null, 0);
    try std.testing.expectEqual(decoder.Opcode.IJMP, inst.opcode);
}

test "Decoder: ICALL" {
    const inst = decoder.decode(0x9509, null, 0);
    try std.testing.expectEqual(decoder.Opcode.ICALL, inst.opcode);
}
