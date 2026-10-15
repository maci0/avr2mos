const std = @import("std");

pub const Opcode = enum {
    NOP,
    ADD,
    ADC,
    SUB,
    SUBI,
    AND,
    ANDI,
    OR,
    ORI,
    EOR,
    COM,
    NEG,
    INC,
    DEC,
    TST,
    CLR,
    SER,
    MUL,
    MULS,
    MOV,
    MOVW,
    LDI,
    // Branching
    RJMP,
    IJMP,
    JMP,
    RCALL,
    ICALL,
    CALL,
    RET,
    RETI,
    CPSE,
    CP,
    CPC,
    CPI,
    SBIS,
    SBI,
    CBI,
    ADIW,
    BRBC,
    BRBS,
    SBRC,
    SBRS,
    SBIC,
    // Data transfer
    LD_X,
    LD_X_INC,
    LD_X_DEC, // X instructions
    LD_Y,
    LD_Y_INC,
    LD_Y_DEC,
    LDD_Y_Q, // Y instructions
    LD_Z,
    LD_Z_INC,
    LD_Z_DEC,
    LDD_Z_Q, // Z instructions
    ST_X,
    ST_X_INC,
    ST_X_DEC,
    ST_Y,
    ST_Y_INC,
    ST_Y_DEC,
    STD_Y_Q,
    ST_Z,
    ST_Z_INC,
    ST_Z_DEC,
    STD_Z_Q,
    LDS,
    STS,
    IN,
    OUT,
    PUSH,
    POP,
    SBC,
    SBCI,
    SBR,
    CBR,
    BSET,
    BCLR,
    SBIW,
    LPM,
    SPM,
    LSR,
    ROR,
    ASR,
    BREAK,
    CLI,
    SEI,
    SWAP,
    BST,
    BLD,
    MULSU,
    FMUL,
    FMULS,
    FMULSU,
    ELPM,
    SLEEP,
    WDR,
    UNKNOWN,
};

pub const Operand = union(enum) {
    none,
    reg: u8,
    imm: u16,
    reg_reg: struct { r1: u8, r2: u8 },
    reg_imm: struct { r: u8, imm: u16 },
    addr: u32,
    rel: i16,
    reg_rel: struct { r: u8, rel: i16 },
    io_reg: struct { io: u8, r: u8 },
    reg_io: struct { r: u8, io: u8 },
};

pub const Instruction = struct {
    opcode: Opcode,
    operands: Operand,
    size: u8, // size in bytes (2 or 4)
    addr: u16, // address in words
};

pub fn decode(word: u16, next_word: ?u16, addr: u16) Instruction {
    // NOP
    if (word == 0x0000) {
        return .{ .opcode = .NOP, .operands = .none, .size = 2, .addr = addr };
    }

    // ADD Rd, Rr (0000 11rd dddd rrrr)
    if ((word & 0xFC00) == 0x0C00) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .ADD, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // ADC Rd, Rr (0001 11rd dddd rrrr)
    if ((word & 0xFC00) == 0x1C00) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .ADC, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // SUB Rd, Rr (0001 10rd dddd rrrr)
    if ((word & 0xFC00) == 0x1800) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .SUB, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // SBC Rd, Rr (0000 10rd dddd rrrr)
    if ((word & 0xFC00) == 0x0800) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .SBC, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // AND Rd, Rr (0010 00rd dddd rrrr)
    if ((word & 0xFC00) == 0x2000) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .AND, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // OR Rd, Rr (0010 10rd dddd rrrr)
    if ((word & 0xFC00) == 0x2800) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .OR, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // EOR Rd, Rr (0010 01rd dddd rrrr)
    if ((word & 0xFC00) == 0x2400) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .EOR, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // CP Rd, Rr (0001 01rd dddd rrrr)
    if ((word & 0xFC00) == 0x1400) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .CP, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // CPC Rd, Rr (0000 01rd dddd rrrr)
    if ((word & 0xFC00) == 0x0400) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .CPC, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // SUBI Rd, K (0101 KKKK dddd KKKK)
    if ((word & 0xF000) == 0x5000) {
        const d = 16 + ((word >> 4) & 0x0F);
        const k = ((word >> 4) & 0xF0) | (word & 0x0F);
        return .{ .opcode = .SUBI, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = k } }, .size = 2, .addr = addr };
    }

    // LPM (Rd=r0, Z) (1001 0101 1100 1000)
    if (word == 0x95C8) {
        return .{ .opcode = .LPM, .operands = .{ .reg = 0 }, .size = 2, .addr = addr };
    }
    // LPM Rd, Z (1001 000d dddd 0100)
    if ((word & 0xFE0F) == 0x9004) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LPM, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }
    // LPM Rd, Z+ (1001 000d dddd 0101)
    if ((word & 0xFE0F) == 0x9005) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_Z_INC, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr }; // Re-use LD_Z_INC for simplicity or use new opcode
    }
    // SPM (1001 0101 1110 1000)
    if (word == 0x95E8) {
        return .{ .opcode = .SPM, .operands = .none, .size = 2, .addr = addr };
    }
    // SLEEP (1001 0101 1000 1000)
    if (word == 0x9588) {
        return .{ .opcode = .SLEEP, .operands = .none, .size = 2, .addr = addr };
    }

    // ELPM (1001 0101 1101 1000)
    if (word == 0x95D8) {
        return .{ .opcode = .ELPM, .operands = .none, .size = 2, .addr = addr };
    }
    // ELPM Rd, Z (1001 000d dddd 0110)
    if ((word & 0xFE0F) == 0x9006) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .ELPM, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }
    // ELPM Rd, Z+ (1001 000d dddd 0111)
    if ((word & 0xFE0F) == 0x9007) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .ELPM, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr }; // Ignoring Z+ semantics for now in decoder struct (needs new operand)
    }

    // SPM Z+ (1001 0101 1111 1000)
    if (word == 0x95F8) {
        return .{ .opcode = .SPM, .operands = .none, .size = 2, .addr = addr }; // Z+ semantic
    }
    // WDR (1001 0101 1010 1000)
    if (word == 0x95A8) {
        return .{ .opcode = .WDR, .operands = .none, .size = 2, .addr = addr };
    }
    // BREAK (1001 0101 1001 1000)
    if (word == 0x9598) {
        return .{ .opcode = .BREAK, .operands = .none, .size = 2, .addr = addr };
    }
    // CLI (1001 0100 1111 1000)
    if (word == 0x94F8) {
        return .{ .opcode = .CLI, .operands = .none, .size = 2, .addr = addr };
    }
    // SEI (1001 0100 0111 1000)
    if (word == 0x9478) {
        return .{ .opcode = .SEI, .operands = .none, .size = 2, .addr = addr };
    }

    // SBCI Rd, K (0100 KKKK dddd KKKK)
    if ((word & 0xF000) == 0x4000) {
        const d = 16 + ((word >> 4) & 0x0F);
        const k = ((word >> 4) & 0xF0) | (word & 0x0F);
        return .{ .opcode = .SBCI, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = k } }, .size = 2, .addr = addr };
    }

    // ANDI Rd, K (0111 KKKK dddd KKKK)
    if ((word & 0xF000) == 0x7000) {
        const d = 16 + ((word >> 4) & 0x0F);
        const k = ((word >> 4) & 0xF0) | (word & 0x0F);
        return .{ .opcode = .ANDI, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = k } }, .size = 2, .addr = addr };
    }

    // ORI Rd, K (0110 KKKK dddd KKKK)
    if ((word & 0xF000) == 0x6000) {
        const d = 16 + ((word >> 4) & 0x0F);
        const k = ((word >> 4) & 0xF0) | (word & 0x0F);
        return .{ .opcode = .ORI, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = k } }, .size = 2, .addr = addr };
    }

    // CPI Rd, K (0011 KKKK dddd KKKK)
    if ((word & 0xF000) == 0x3000) {
        const d = 16 + ((word >> 4) & 0x0F);
        const k = ((word >> 4) & 0xF0) | (word & 0x0F);
        return .{ .opcode = .CPI, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = k } }, .size = 2, .addr = addr };
    }

    // INC Rd (1001 010d dddd 0011)
    if ((word & 0xFE0F) == 0x9403) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .INC, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // DEC Rd (1001 010d dddd 1010)
    if ((word & 0xFE0F) == 0x940A) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .DEC, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // COM Rd (1001 010d dddd 0000)
    if ((word & 0xFE0F) == 0x9400) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .COM, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // SWAP Rd (1001 010d dddd 0010)
    if ((word & 0xFE0F) == 0x9402) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .SWAP, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // LSR Rd (1001 010d dddd 0110)
    if ((word & 0xFE0F) == 0x9406) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LSR, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // BST Rd, b (1111 101d dddd 0bbb)
    if ((word & 0xFE08) == 0xFA00) {
        const d = (word >> 4) & 0x1F;
        const b = word & 0x07;
        return .{ .opcode = .BST, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = @truncate(b) } }, .size = 2, .addr = addr };
    }

    // BLD Rd, b (1111 100d dddd 0bbb)
    if ((word & 0xFE08) == 0xF800) {
        const d = (word >> 4) & 0x1F;
        const b = word & 0x07;
        return .{ .opcode = .BLD, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = @truncate(b) } }, .size = 2, .addr = addr };
    }

    // BSET s (1001 0100 0sss 1000)
    if ((word & 0xFF8F) == 0x9408) {
        const s = (word >> 4) & 0x07;
        return .{ .opcode = .BSET, .operands = .{ .imm = @truncate(s) }, .size = 2, .addr = addr };
    }

    // BCLR s (1001 0100 1sss 1000)
    if ((word & 0xFF8F) == 0x9488) {
        const s = (word >> 4) & 0x07;
        return .{ .opcode = .BCLR, .operands = .{ .imm = @truncate(s) }, .size = 2, .addr = addr };
    }

    // ROR Rd (1001 010d dddd 0111)
    if ((word & 0xFE0F) == 0x9407) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .ROR, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // MULSU Rd, Rr (0000 0011 0000 0000 ... 0000 0011 0111 0111) mapped 16..23
    if ((word & 0xFF88) == 0x0300) {
        const d = 16 + ((word >> 4) & 0x07);
        const r = 16 + (word & 0x07);
        return .{ .opcode = .MULSU, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // FMUL Rd, Rr (0000 0011 0000 1000 ...)
    if ((word & 0xFF88) == 0x0308) {
        const d = 16 + ((word >> 4) & 0x07);
        const r = 16 + (word & 0x07);
        return .{ .opcode = .FMUL, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // FMULS Rd, Rr (0000 0011 1000 0000 ...)
    if ((word & 0xFF88) == 0x0380) {
        const d = 16 + ((word >> 4) & 0x07);
        const r = 16 + (word & 0x07);
        return .{ .opcode = .FMULS, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // FMULSU Rd, Rr (0000 0011 1000 1000 ...)
    if ((word & 0xFF88) == 0x0388) {
        const d = 16 + ((word >> 4) & 0x07);
        const r = 16 + (word & 0x07);
        return .{ .opcode = .FMULSU, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // ASR Rd (1001 010d dddd 0101)
    if ((word & 0xFE0F) == 0x9405) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .ASR, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // NEG Rd (1001 010d dddd 0001)
    if ((word & 0xFE0F) == 0x9401) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .NEG, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // PUSH Rd (1001 001d dddd 1111)
    if ((word & 0xFE0F) == 0x920F) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .PUSH, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // POP Rd (1001 000d dddd 1111)
    if ((word & 0xFE0F) == 0x900F) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .POP, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // IN Rd, P (1011 0PPd dddd PPPP)
    if ((word & 0xF800) == 0xB000) {
        const d = (word >> 4) & 0x1F;
        const p = ((word >> 5) & 0x30) | (word & 0x0F);
        return .{ .opcode = .IN, .operands = .{ .reg_io = .{ .r = @truncate(d), .io = @truncate(p) } }, .size = 2, .addr = addr };
    }

    // OUT P, Rr (1011 1PPr rrrr PPPP)
    if ((word & 0xF800) == 0xB800) {
        const r = (word >> 4) & 0x1F;
        const p = ((word >> 5) & 0x30) | (word & 0x0F);
        return .{ .opcode = .OUT, .operands = .{ .io_reg = .{ .io = @truncate(p), .r = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // SBIW Rd, K (1001 0111 KKdd KKKK)
    if ((word & 0xFF00) == 0x9700) {
        const dd = (word >> 4) & 0x03;
        const k = ((word >> 2) & 0x30) | (word & 0x0F);
        const rd = 24 + 2 * dd;
        return .{ .opcode = .SBIW, .operands = .{ .reg_imm = .{ .r = @truncate(rd), .imm = k } }, .size = 2, .addr = addr };
    }

    // MUL Rd, Rr (1001 11rd dddd rrrr)
    if ((word & 0xFC00) == 0x9C00) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .MUL, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }
    // MULS Rd, Rr (0000 0010 dddd rrrr)
    if ((word & 0xFF00) == 0x0200) {
        const d = 16 + ((word >> 4) & 0x0F);
        const r = 16 + (word & 0x0F);
        return .{ .opcode = .MULS, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }
    // LDI Rd, K (1110 KKKK dddd KKKK)
    if ((word & 0xF000) == 0xE000) {
        const d = 16 + ((word >> 4) & 0x0F);
        const k = ((word >> 4) & 0xF0) | (word & 0x0F);
        return .{ .opcode = .LDI, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = k } }, .size = 2, .addr = addr };
    }
    // RJMP k (1100 kkkk kkkk kkkk)
    if ((word & 0xF000) == 0xC000) {
        const k = word & 0x0FFF;
        // Sign extend 12-bit to 16-bit
        const rel: i16 = if ((k & 0x0800) != 0) @as(i16, @intCast(k)) - 0x1000 else @as(i16, @intCast(k));
        return .{ .opcode = .RJMP, .operands = .{ .rel = rel }, .size = 2, .addr = addr };
    }

    // RCALL k (1101 kkkk kkkk kkkk)
    if ((word & 0xF000) == 0xD000) {
        const k = word & 0x0FFF;
        // Sign extend 12-bit to 16-bit
        const rel: i16 = if ((k & 0x0800) != 0) @as(i16, @intCast(k)) - 0x1000 else @as(i16, @intCast(k));
        return .{ .opcode = .RCALL, .operands = .{ .rel = rel }, .size = 2, .addr = addr };
    }

    // JMP k (1001 010k kkkk 110k followed by kkkk kkkk kkkk kkkk)
    if ((word & 0xFE0E) == 0x940C) {
        const k_high = (@as(u32, (word >> 3) & 0x3E) | (word & 0x01));
        if (next_word) |k_low| {
            const k = (k_high << 16) | k_low;
            return .{ .opcode = .JMP, .operands = .{ .addr = k }, .size = 4, .addr = addr };
        }
        return .{ .opcode = .JMP, .operands = .none, .size = 4, .addr = addr };
    }

    // CALL k (1001 010k kkkk 111k)
    if ((word & 0xFE0E) == 0x940E) {
        const k_high = (@as(u32, (word >> 3) & 0x3E) | (word & 0x01));
        if (next_word) |k_low| {
            const k = (k_high << 16) | k_low;
            return .{ .opcode = .CALL, .operands = .{ .addr = k }, .size = 4, .addr = addr };
        }
        return .{ .opcode = .CALL, .operands = .none, .size = 4, .addr = addr };
    }

    // IJMP (1001 0100 0000 1001)
    if (word == 0x9409) {
        return .{ .opcode = .IJMP, .operands = .none, .size = 2, .addr = addr };
    }

    // ICALL (1001 0101 0000 1001)
    if (word == 0x9509) {
        return .{ .opcode = .ICALL, .operands = .none, .size = 2, .addr = addr };
    }

    // RET (1001 0101 0000 1000)
    if (word == 0x9508) {
        return .{ .opcode = .RET, .operands = .none, .size = 2, .addr = addr };
    }

    // RETI (1001 0101 0001 1000)
    if (word == 0x9518) {
        return .{ .opcode = .RETI, .operands = .none, .size = 2, .addr = addr };
    }

    // BRBS s, k (1111 00kk kkkk ksss)
    if ((word & 0xFC00) == 0xF000) {
        const s = word & 0x07;
        const k = (word >> 3) & 0x7F;
        // Sign extend 7-bit to 16-bit
        const rel: i16 = if ((k & 0x40) != 0) @as(i16, @intCast(k)) - 0x80 else @as(i16, @intCast(k));
        return .{ .opcode = .BRBS, .operands = .{ .reg_rel = .{ .r = @truncate(s), .rel = rel } }, .size = 2, .addr = addr };
    }

    // BRBC s, k (1111 01kk kkkk ksss)
    if ((word & 0xFC00) == 0xF400) {
        const s = word & 0x07;
        const k = (word >> 3) & 0x7F;
        // Sign extend 7-bit to 16-bit
        const rel: i16 = if ((k & 0x40) != 0) @as(i16, @intCast(k)) - 0x80 else @as(i16, @intCast(k));
        return .{ .opcode = .BRBC, .operands = .{ .reg_rel = .{ .r = @truncate(s), .rel = rel } }, .size = 2, .addr = addr };
    }

    // CPSE Rd, Rr (0001 00rd dddd rrrr)
    if ((word & 0xFC00) == 0x1000) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .CPSE, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // SBRC r, b (1111 110r rrrr 0bbb)
    if ((word & 0xFE08) == 0xFC00) {
        const r = (word >> 4) & 0x1F;
        const b = word & 0x07;
        return .{ .opcode = .SBRC, .operands = .{ .reg_imm = .{ .r = @truncate(r), .imm = b } }, .size = 2, .addr = addr };
    }

    // SBRS r, b (1111 111r rrrr 0bbb)
    if ((word & 0xFE08) == 0xFE00) {
        const r = (word >> 4) & 0x1F;
        const b = word & 0x07;
        return .{ .opcode = .SBRS, .operands = .{ .reg_imm = .{ .r = @truncate(r), .imm = b } }, .size = 2, .addr = addr };
    }

    // ADIW Rd, K (1001 0110 KKdd KKKK)
    if ((word & 0xFF00) == 0x9600) {
        const dd = (word >> 4) & 0x03;
        const k = ((word >> 2) & 0x30) | (word & 0x0F);
        const rd = 24 + 2 * dd;
        return .{ .opcode = .ADIW, .operands = .{ .reg_imm = .{ .r = @truncate(rd), .imm = k } }, .size = 2, .addr = addr };
    }

    // SBI P, b (1001 1010 AAAA Abbb)
    if ((word & 0xFF00) == 0x9A00) {
        const a = (word >> 3) & 0x1F;
        const b = word & 0x07;
        return .{ .opcode = .SBI, .operands = .{ .reg_imm = .{ .r = @truncate(a), .imm = b } }, .size = 2, .addr = addr };
    }

    // CBI P, b (1001 1000 AAAA Abbb)
    if ((word & 0xFF00) == 0x9800) {
        const a = (word >> 3) & 0x1F;
        const b = word & 0x07;
        return .{ .opcode = .CBI, .operands = .{ .reg_imm = .{ .r = @truncate(a), .imm = b } }, .size = 2, .addr = addr };
    }

    // SBIC P, b (1001 1001 AAAA Abbb)
    if ((word & 0xFF00) == 0x9900) {
        const a = (word >> 3) & 0x1F;
        const b = word & 0x07;
        return .{ .opcode = .SBIC, .operands = .{ .reg_imm = .{ .r = @truncate(a), .imm = b } }, .size = 2, .addr = addr };
    }

    // SBIS P, b (1001 1011 AAAA Abbb)
    if ((word & 0xFF00) == 0x9B00) {
        const a = (word >> 3) & 0x1F;
        const b = word & 0x07;
        return .{ .opcode = .SBIS, .operands = .{ .reg_imm = .{ .r = @truncate(a), .imm = b } }, .size = 2, .addr = addr };
    }

    // LD Rd, X (1001 000d dddd 1100)
    if ((word & 0xFE0F) == 0x900C) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_X, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // LD Rd, X+ (1001 000d dddd 1101)
    if ((word & 0xFE0F) == 0x900D) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_X_INC, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // LD Rd, -X (1001 000d dddd 1110)
    if ((word & 0xFE0F) == 0x900E) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_X_DEC, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // ST X, Rr (1001 001r rrrr 1100)
    if ((word & 0xFE0F) == 0x920C) {
        const r = (word >> 4) & 0x1F;
        return .{ .opcode = .ST_X, .operands = .{ .reg = @truncate(r) }, .size = 2, .addr = addr };
    }

    // ST X+, Rr (1001 001r rrrr 1101)
    if ((word & 0xFE0F) == 0x920D) {
        const r = (word >> 4) & 0x1F;
        return .{ .opcode = .ST_X_INC, .operands = .{ .reg = @truncate(r) }, .size = 2, .addr = addr };
    }

    // ST -X, Rr (1001 001r rrrr 1110)
    if ((word & 0xFE0F) == 0x920E) {
        const r = (word >> 4) & 0x1F;
        return .{ .opcode = .ST_X_DEC, .operands = .{ .reg = @truncate(r) }, .size = 2, .addr = addr };
    }

    // LD Rd, Y (1000 000d dddd 1000)
    if ((word & 0xFE0F) == 0x8008) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_Y, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // LD Rd, Y+ (1001 000d dddd 1001)
    if ((word & 0xFE0F) == 0x9009) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_Y_INC, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // LD Rd, -Y (1001 000d dddd 1010)
    if ((word & 0xFE0F) == 0x900A) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_Y_DEC, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // ST Y, Rr (1000 001r rrrr 1000)
    if ((word & 0xFE0F) == 0x8208) {
        const r = (word >> 4) & 0x1F;
        return .{ .opcode = .ST_Y, .operands = .{ .reg = @truncate(r) }, .size = 2, .addr = addr };
    }

    // ST Y+, Rr (1001 001r rrrr 1001)
    if ((word & 0xFE0F) == 0x9209) {
        const r = (word >> 4) & 0x1F;
        return .{ .opcode = .ST_Y_INC, .operands = .{ .reg = @truncate(r) }, .size = 2, .addr = addr };
    }

    // ST -Y, Rr (1001 001r rrrr 1010)
    if ((word & 0xFE0F) == 0x920A) {
        const r = (word >> 4) & 0x1F;
        return .{ .opcode = .ST_Y_DEC, .operands = .{ .reg = @truncate(r) }, .size = 2, .addr = addr };
    }

    // MOV Rd, Rr (0010 11rd dddd rrrr)
    if ((word & 0xFC00) == 0x2C00) {
        const r = ((word >> 5) & 0x10) | (word & 0x0F);
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .MOV, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // MOVW Rd, Rr (0000 0001 dddd rrrr)
    if ((word & 0xFF00) == 0x0100) {
        const r = (word & 0x0F) << 1;
        const d = ((word >> 4) & 0x0F) << 1;
        return .{ .opcode = .MOVW, .operands = .{ .reg_reg = .{ .r1 = @truncate(d), .r2 = @truncate(r) } }, .size = 2, .addr = addr };
    }

    // LDD Rd, Y+q
    if ((word & 0xD208) == 0x8008) {
        const d = (word >> 4) & 0x1F;
        const q = ((word & 0x2000) >> 8) | ((word & 0x0C00) >> 7) | (word & 0x0007);
        return .{ .opcode = .LDD_Y_Q, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = q } }, .size = 2, .addr = addr };
    }

    // LD Rd, Z (1000 000d dddd 0000) — must be checked before LDD Z+q
    if ((word & 0xFE0F) == 0x8000) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_Z, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // LDD Rd, Z+q
    if ((word & 0xD208) == 0x8000) {
        const d = (word >> 4) & 0x1F;
        const q = ((word & 0x2000) >> 8) | ((word & 0x0C00) >> 7) | (word & 0x0007);
        return .{ .opcode = .LDD_Z_Q, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = q } }, .size = 2, .addr = addr };
    }

    // ST Z, Rr (1000 001r rrrr 0000) — must be checked before STD Z+q
    if ((word & 0xFE0F) == 0x8200) {
        const r = (word >> 4) & 0x1F;
        return .{ .opcode = .ST_Z, .operands = .{ .reg = @truncate(r) }, .size = 2, .addr = addr };
    }

    // STD Y+q, Rr
    if ((word & 0xD208) == 0x8208) {
        const r = (word >> 4) & 0x1F;
        const q = ((word & 0x2000) >> 8) | ((word & 0x0C00) >> 7) | (word & 0x0007);
        return .{ .opcode = .STD_Y_Q, .operands = .{ .reg_imm = .{ .r = @truncate(r), .imm = q } }, .size = 2, .addr = addr };
    }

    // STD Z+q, Rr
    if ((word & 0xD208) == 0x8200) {
        const r = (word >> 4) & 0x1F;
        const q = ((word & 0x2000) >> 8) | ((word & 0x0C00) >> 7) | (word & 0x0007);
        return .{ .opcode = .STD_Z_Q, .operands = .{ .reg_imm = .{ .r = @truncate(r), .imm = q } }, .size = 2, .addr = addr };
    }

    // LD Rd, Z+ (1001 000d dddd 0001)
    if ((word & 0xFE0F) == 0x9001) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_Z_INC, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // LD Rd, -Z (1001 000d dddd 0010)
    if ((word & 0xFE0F) == 0x9002) {
        const d = (word >> 4) & 0x1F;
        return .{ .opcode = .LD_Z_DEC, .operands = .{ .reg = @truncate(d) }, .size = 2, .addr = addr };
    }

    // ST Z+, Rr (1001 001r rrrr 0001)
    if ((word & 0xFE0F) == 0x9201) {
        const r = (word >> 4) & 0x1F;
        return .{ .opcode = .ST_Z_INC, .operands = .{ .reg = @truncate(r) }, .size = 2, .addr = addr };
    }

    // ST -Z, Rr (1001 001r rrrr 0010)
    if ((word & 0xFE0F) == 0x9202) {
        const r = (word >> 4) & 0x1F;
        return .{ .opcode = .ST_Z_DEC, .operands = .{ .reg = @truncate(r) }, .size = 2, .addr = addr };
    }

    // LDS Rd, k (1001 000d dddd 0000)
    if ((word & 0xFE0F) == 0x9000) {
        const d = (word >> 4) & 0x1F;
        if (next_word) |k| {
            return .{ .opcode = .LDS, .operands = .{ .reg_imm = .{ .r = @truncate(d), .imm = k } }, .size = 4, .addr = addr };
        }
        return .{ .opcode = .LDS, .operands = .none, .size = 4, .addr = addr };
    }

    // STS k, Rr (1001 001r rrrr 0000)
    if ((word & 0xFE0F) == 0x9200) {
        const r = (word >> 4) & 0x1F;
        if (next_word) |k| {
            return .{ .opcode = .STS, .operands = .{ .reg_imm = .{ .r = @truncate(r), .imm = k } }, .size = 4, .addr = addr };
        }
        return .{ .opcode = .STS, .operands = .none, .size = 4, .addr = addr };
    }

    return .{ .opcode = .UNKNOWN, .operands = .none, .size = 2, .addr = addr };
}

test "decode basic instructions" {
    const inst1 = decode(0x0000, null, 0);
    try std.testing.expectEqual(Opcode.NOP, inst1.opcode);
}
