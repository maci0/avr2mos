const std = @import("std");
const cfg = @import("cfg.zig");
const decoder = @import("decoder.zig");
const emitter = @import("emitter.zig");

const profile = @import("profile.zig");

pub fn translateBlock(block: cfg.BasicBlock, cpu_profile: profile.CpuProfile, out: *emitter.Emitter, text_vma: u32) !void {
    const vma_word_offset = @as(u32, text_vma / 2);

    // Define label for the start of this block
    if (block.instructions.len > 0) {
        const blk_addr = block.instructions[0].addr; // Already relative
        try out.defineLabel(blk_addr);
    }

    const CarryMode = enum { addition, subtraction };
    var carry_mode: CarryMode = .addition;

    for (block.instructions) |inst| {
        switch (inst.opcode) {
            .NOP => {
                try out.emitNOP();
            },
            .CLI => {
                // AVR CLI (Clear Global Interrupt Flag -> Disable Interrupts)
                // 6502 SEI (Set Interrupt Disable -> Disable Interrupts)
                try out.emitSEI();
            },
            .SEI => {
                // AVR SEI (Set Global Interrupt Flag -> Enable Interrupts)
                // 6502 CLI (Clear Interrupt Disable -> Enable Interrupts)
                try out.emitCLI();
            },
            .MOV => {
                if (inst.operands == .reg_reg) {
                    const d = inst.operands.reg_reg.r1;
                    const r = inst.operands.reg_reg.r2;
                    try out.emitLDA_zp(r);
                    try out.emitSTA_zp(d);
                }
            },
            .MOVW => {
                if (inst.operands == .reg_reg) {
                    const d = inst.operands.reg_reg.r1;
                    const r = inst.operands.reg_reg.r2;
                    // Low byte
                    try out.emitLDA_zp(r);
                    try out.emitSTA_zp(d);
                    // High byte
                    try out.emitLDA_zp(r + 1);
                    try out.emitSTA_zp(d + 1);
                }
            },
            .LDI => {
                if (inst.operands == .reg_imm) {
                    const r = inst.operands.reg_imm.r;
                    const imm = inst.operands.reg_imm.imm;
                    try out.emitLDA_imm(@truncate(imm));
                    try out.emitSTA_zp(r);
                }
            },
            .ADD => {
                // ADD Rd, Rr
                if (inst.operands == .reg_reg) {
                    const r1 = inst.operands.reg_reg.r1;
                    const r2 = inst.operands.reg_reg.r2;
                    try out.emitCLC();
                    try out.emitLDA_zp(r1);
                    try out.emitADC_zp(r2);
                    try out.emitSTA_zp(r1);
                    carry_mode = .addition;
                }
            },
            .ADC => {
                // ADC Rd, Rr
                if (inst.operands == .reg_reg) {
                    const r1 = inst.operands.reg_reg.r1;
                    const r2 = inst.operands.reg_reg.r2;
                    if (carry_mode == .subtraction) {
                        try out.emitFlipCarry();
                        carry_mode = .addition;
                    }
                    try out.emitLDA_zp(r1);
                    try out.emitADC_zp(r2);
                    try out.emitSTA_zp(r1);
                }
            },
            .SUB => {
                // SUB Rd, Rr
                if (inst.operands == .reg_reg) {
                    const r1 = inst.operands.reg_reg.r1;
                    const r2 = inst.operands.reg_reg.r2;
                    try out.emitSEC();
                    try out.emitLDA_zp(r1);
                    try out.emitSBC_zp(r2);
                    try out.emitSTA_zp(r1);
                    carry_mode = .subtraction;
                }
            },
            .SBC => {
                // SBC Rd, Rr
                if (inst.operands == .reg_reg) {
                    const r1 = inst.operands.reg_reg.r1;
                    const r2 = inst.operands.reg_reg.r2;
                    if (carry_mode == .addition) {
                        try out.emitFlipCarry();
                        carry_mode = .subtraction;
                    }
                    try out.emitLDA_zp(r1);
                    try out.emitSBC_zp(r2);
                    try out.emitSTA_zp(r1);
                }
            },
            .SUBI, .SBCI => {
                if (inst.operands == .reg_imm) {
                    const d = inst.operands.reg_imm.r;
                    const k = inst.operands.reg_imm.imm;
                    if (inst.opcode == .SUBI) {
                        try out.emitSEC();
                        carry_mode = .subtraction;
                    } else if (carry_mode == .addition) {
                        try out.emitFlipCarry();
                        carry_mode = .subtraction;
                    }
                    try out.emitLDA_zp(d);
                    try out.emitSBC_imm(@truncate(k));
                    try out.emitSTA_zp(d);
                }
            },
            .CP, .CPC => {
                if (inst.operands == .reg_reg) {
                    const d = inst.operands.reg_reg.r1;
                    const r = inst.operands.reg_reg.r2;
                    if (inst.opcode == .CP) {
                        try out.emitLDA_zp(d);
                        try out.emitCMP_zp(r);
                        carry_mode = .subtraction;
                    } else {
                        if (carry_mode == .addition) {
                            try out.emitFlipCarry();
                            carry_mode = .subtraction;
                        }
                        try out.emitLDA_zp(d);
                        try out.emitSBC_zp(r);
                    }
                }
            },
            .CPI => {
                if (inst.operands == .reg_imm) {
                    const d = inst.operands.reg_imm.r;
                    const k = inst.operands.reg_imm.imm;
                    try out.emitLDA_zp(d);
                    try out.emitCMP_imm(@truncate(k));
                    carry_mode = .subtraction;
                }
            },
            .AND, .OR, .EOR => {
                if (inst.operands == .reg_reg) {
                    const d = inst.operands.reg_reg.r1;
                    const r = inst.operands.reg_reg.r2;
                    try out.emitLDA_zp(d);
                    switch (inst.opcode) {
                        .AND => try out.emitAND_zp(r),
                        .OR => try out.emitORA_zp(r),
                        .EOR => try out.emitEOR_zp(r),
                        else => unreachable,
                    }
                    try out.emitSTA_zp(d);
                }
            },
            .ANDI, .ORI => {
                if (inst.operands == .reg_imm) {
                    const d = inst.operands.reg_imm.r;
                    const k = inst.operands.reg_imm.imm;
                    try out.emitLDA_zp(d);
                    if (inst.opcode == .ANDI) {
                        try out.emitAND_imm(@truncate(k));
                    } else {
                        try out.emitORA_imm(@truncate(k));
                    }
                    try out.emitSTA_zp(d);
                }
            },
            .SBRC, .SBRS => {
                if (inst.operands == .reg_imm) {
                    const r = inst.operands.reg_imm.r;
                    const b = inst.operands.reg_imm.imm;
                    const mask = @as(u8, 1) << @as(u3, @truncate(b));
                    try out.emitLDA_zp(r);
                    try out.emitAND_imm(mask);
                    if (block.successors[0]) |skipped| {
                        if (inst.opcode == .SBRC) {
                            // Skip if bit clear (zero set)
                            try out.emitBNE_rel(3); // skip JMP
                        } else {
                            // Skip if bit set (zero clear)
                            try out.emitBEQ_rel(3);
                        }
                        try out.emitJMP_label(skipped);
                    }
                }
            },
            .SBIC, .SBIS => {
                // I/O skip. Assume I/O starts at 0x20
                if (inst.operands == .reg_imm) {
                    const a = inst.operands.reg_imm.r; // I/O address
                    const b = inst.operands.reg_imm.imm;
                    const mask = @as(u8, 1) << @as(u3, @truncate(b));
                    try out.emitLDA_zp(0x20 + a);
                    try out.emitAND_imm(mask);
                    if (block.successors[0]) |skipped| {
                        if (inst.opcode == .SBIC) {
                            try out.emitBNE_rel(3);
                        } else {
                            try out.emitBEQ_rel(3);
                        }
                        try out.emitJMP_label(skipped);
                    }
                }
            },
            .SBI, .CBI => {
                // I/O bit set/clear. I/O starts at 0x20
                // AVR SBI/CBI don't affect flags, but our 6502 impl uses LDA/ORA/AND which do.
                if (inst.operands == .reg_imm) {
                    const a = inst.operands.reg_imm.r; // I/O address
                    const b = inst.operands.reg_imm.imm;
                    const mask = @as(u8, 1) << @as(u3, @truncate(b));

                    try out.emitPHP();
                    try out.emitLDA_zp(0x20 + a);
                    if (inst.opcode == .SBI) {
                        try out.emitORA_imm(mask);
                    } else {
                        try out.emitAND_imm(~mask);
                    }
                    try out.emitSTA_zp(0x20 + a);
                    try out.emitPLP();
                }
            },

            .RJMP, .RCALL => {
                const target = @as(u16, @intCast(@as(i32, @intCast(inst.addr)) + inst.operands.rel + 1));
                if (inst.opcode == .RJMP) {
                    try out.emitJMP_label(target);
                } else {
                    try out.emitJSR_label(target);
                }
            },
            .BRBS, .BRBC => {
                const bit = inst.operands.reg_rel.r;
                const offset_avr = inst.operands.reg_rel.rel;
                const target = @as(u16, @intCast(@as(i32, @intCast(inst.addr)) + offset_avr + 1));
                const is_set = (inst.opcode == .BRBS);
                const skip_len: i8 = 3; // Length of JMP label target

                switch (bit) {
                    0 => { // Carry
                        if (carry_mode == .subtraction) {
                            // Subtraction semantics: BCS skip if no borrow (AVR C=0), BCC skip if borrow (AVR C=1)
                            if (is_set) try out.emitBCS_rel(skip_len) else try out.emitBCC_rel(skip_len);
                        } else {
                            // Addition semantics: BCC skip if no carry (AVR C=0), BCS skip if carry (AVR C=1)
                            if (is_set) try out.emitBCC_rel(skip_len) else try out.emitBCS_rel(skip_len);
                        }
                    },
                    1 => { // Zero
                        if (is_set) try out.emitBNE_rel(skip_len) else try out.emitBEQ_rel(skip_len);
                    },
                    2 => { // Negative
                        if (is_set) try out.emitBPL_rel(skip_len) else try out.emitBMI_rel(skip_len);
                    },
                    3 => { // Overflow
                        if (is_set) try out.emitBVC_rel(skip_len) else try out.emitBVS_rel(skip_len);
                    },
                    else => {
                        try out.emitJMP_label(target); // Fallback
                        continue;
                    },
                }
                try out.emitJMP_label(target);
            },
            .INC, .DEC => {
                if (inst.operands == .reg) {
                    const d = inst.operands.reg;
                    if (inst.opcode == .INC) {
                        try out.emitINC_zp(d);
                    } else {
                        try out.emitDEC_zp(d);
                    }
                }
            },
            .COM => {
                if (inst.operands == .reg) {
                    const d = inst.operands.reg;
                    try out.emitLDA_zp(d);
                    try out.emitEOR_imm(0xFF);
                    try out.emitSTA_zp(d);
                    try out.emitSEC(); // AVR COM always sets C=1
                    carry_mode = .addition;
                }
            },
            .SWAP => {
                if (inst.operands == .reg) {
                    const d = inst.operands.reg;
                    // AVR SWAP doesn't affect flags, but NESDev algorithm uses carry.
                    // Save and restore processor status to preserve all flags.
                    try out.emitPHP();
                    try out.emitLDA_zp(d);
                    try out.emitASL_A();
                    try out.emitADC_imm(0x80);
                    try out.emitROL_A();
                    try out.emitASL_A();
                    try out.emitADC_imm(0x80);
                    try out.emitROL_A();
                    try out.emitSTA_zp(d);
                    try out.emitPLP();
                }
            },
            .NEG => {
                if (inst.operands == .reg) {
                    const d = inst.operands.reg;
                    try out.emitLDA_imm(0);
                    try out.emitSEC();
                    try out.emitSBC_zp(d);
                    try out.emitSTA_zp(d);
                    carry_mode = .subtraction;
                }
            },
            .LSR => {
                if (inst.operands == .reg) {
                    const d = inst.operands.reg;
                    try out.emitLSR_zp(d);
                    carry_mode = .addition;
                }
            },
            .ROR => {
                if (inst.operands == .reg) {
                    const d = inst.operands.reg;
                    if (carry_mode == .subtraction) {
                        try out.emitFlipCarry();
                        carry_mode = .addition;
                    }
                    try out.emitROR_zp(d);
                    carry_mode = .addition;
                }
            },
            .ASR => {
                if (inst.operands == .reg) {
                    const d = inst.operands.reg;
                    try out.emitLDA_zp(d);
                    try out.emitASL_A(); // bit 7 to Carry
                    try out.emitROR_zp(d); // Rotate in bit 7, shift out bit 0
                    carry_mode = .addition;
                }
            },
            .BSET, .BCLR => {
                const is_set = (inst.opcode == .BSET);
                const bit_idx = inst.operands.imm;
                // For simplicity, we implement C and V and I
                switch (bit_idx) {
                    0 => {
                        if (is_set) try out.emitSEC() else try out.emitCLC();
                        carry_mode = .addition; // Direct carry manipulation, no inversion
                    },
                    3 => {
                        if (!is_set) {
                            try out.emitCLV(); // CLV
                        } else {
                            try out.emitNOP(); // SEV stub (no SEV in 6502)
                        }
                    },
                    7 => if (is_set) try out.emitCLI() else try out.emitSEI(), // AVR SEI/CLI -> 6502 CLI/SEI (inverted)
                    else => try out.emitNOP(), // stub for others
                }
            },
            .CPSE => {
                if (inst.operands == .reg_reg) {
                    const r1 = inst.operands.reg_reg.r1;
                    const r2 = inst.operands.reg_reg.r2;
                    try out.emitLDA_zp(r1);
                    try out.emitCMP_zp(r2);
                    carry_mode = .subtraction; // CMP uses subtraction semantics
                    // Successor[0] is skipped, Successor[1] is next
                    if (block.successors[0]) |skipped| {
                        try out.emitBNE_rel(3); // skip the JMP (3 bytes)
                        try out.emitJMP_label(skipped);
                    }
                }
            },
            .MUL, .MULS => {
                if (inst.operands == .reg_reg) {
                    const r1 = inst.operands.reg_reg.r1;
                    const r2 = inst.operands.reg_reg.r2;
                    try out.emitLDA_zp(r1);
                    try out.emitLDY_zp(r2);
                    if (inst.opcode == .MUL) {
                        try out.emitJSR_label(0xFFFF);
                    } else {
                        try out.emitJSR_label(0xFFFD); // Use 0xFFFD for mul_s8
                    }
                }
            },
            .IJMP => {
                try out.emitJMP_label(0xFFFE);
            },
            .ICALL => {
                try out.emitJSR_label(0xFFFE);
            },
            .RET => {
                try out.emitRTS();
            },
            .RETI => {
                try out.emitRTI();
            },

            .BST, .BLD => {
                // BST/BLD interact with the 'T' flag in AVR SREG.
                // 6502 doesn't have a direct 'T' flag, so we'll use a reserved Zero Page
                // location ($22) to simulate it.
                // AVR: BST only affects T flag, BLD affects no flags.
                // Our 6502 impl uses LSR/AND/ASL/ORA which corrupt C/N/Z, so save/restore.
                if (inst.operands == .reg_imm) {
                    const d = inst.operands.reg_imm.r;
                    const b = inst.operands.reg_imm.imm;
                    try out.emitPHP();
                    try out.emitLDA_zp(d);
                    if (inst.opcode == .BST) {
                        var i: u8 = 0;
                        while (i < b) : (i += 1) {
                            try out.emitLSR_A();
                        }
                        try out.emitAND_imm(0x01);
                        try out.emitSTA_zp(0x60);
                    } else {
                        const mask = @as(u8, 1) << @as(u3, @truncate(b));
                        try out.emitAND_imm(~mask);
                        try out.emitSTA_zp(d);
                        try out.emitLDA_zp(0x60);
                        var i: u8 = 0;
                        while (i < b) : (i += 1) {
                            try out.emitASL_A();
                        }
                        try out.emitORA_zp(d);
                        try out.emitSTA_zp(d);
                    }
                    try out.emitPLP();
                }
            },
            .MULSU, .FMUL, .FMULS, .FMULSU => {
                // Extended multiplications - delegate to runtimes
                if (inst.operands == .reg_reg) {
                    const r1 = inst.operands.reg_reg.r1;
                    const r2 = inst.operands.reg_reg.r2;
                    try out.emitLDA_zp(r1);
                    try out.emitLDY_zp(r2);
                    // We assume runtime stubs will be added at FFFC, FFFB etc for these
                    try out.emitJSR_label(0xFFFC);
                }
            },
            .ELPM => {
                // Architectural specifics; stub with NOPs
                try out.emitNOP();
            },
            .JMP, .CALL => {
                const raw_target = @as(u32, inst.operands.addr);
                const target = @as(u16, @intCast(if (raw_target > vma_word_offset) raw_target - vma_word_offset else 0));
                if (inst.opcode == .JMP) {
                    try out.emitJMP_label(target);
                } else {
                    try out.emitJSR_label(target);
                }
            },
            .LD_X, .LD_Y, .LD_Z, .LD_X_INC, .LD_Y_INC, .LD_Z_INC, .LD_X_DEC, .LD_Y_DEC, .LD_Z_DEC, .LDD_Y_Q, .LDD_Z_Q => {
                if (inst.operands == .reg or inst.operands == .reg_imm) {
                    const d = if (inst.operands == .reg) inst.operands.reg else inst.operands.reg_imm.r;
                    const zp_ptr: u8 = switch (inst.opcode) {
                        .LD_X, .LD_X_INC, .LD_X_DEC => 0x1A,
                        .LD_Y, .LD_Y_INC, .LD_Y_DEC, .LDD_Y_Q => 0x1C,
                        .LD_Z, .LD_Z_INC, .LD_Z_DEC, .LDD_Z_Q => 0x1E,
                        else => unreachable,
                    };

                    // Pre-decrement (LDA/BNE/DEC/DEC pattern — doesn't corrupt carry flag)
                    if (inst.opcode == .LD_X_DEC or inst.opcode == .LD_Y_DEC or inst.opcode == .LD_Z_DEC) {
                        try out.emitLDA_zp(zp_ptr);
                        try out.emitBNE_rel(2); // skip DEC hi if lo != 0 (no borrow)
                        try out.emitDEC_zp(zp_ptr + 1);
                        try out.emitDEC_zp(zp_ptr);
                    }

                    if (inst.opcode == .LDD_Y_Q or inst.opcode == .LDD_Z_Q) {
                        const q = inst.operands.reg_imm.imm;
                        try out.emitLDY_imm(@truncate(q));
                    } else {
                        try out.emitLDY_imm(0);
                    }

                    try out.emitLDA_indir_y(zp_ptr);
                    try out.emitSTA_zp(d);

                    // Post-increment (INC/BNE/INC pattern — doesn't corrupt carry flag)
                    if (inst.opcode == .LD_X_INC or inst.opcode == .LD_Y_INC or inst.opcode == .LD_Z_INC) {
                        try out.emitINC_zp(zp_ptr);
                        try out.emitBNE_rel(2); // skip INC hi if lo didn't wrap to 0
                        try out.emitINC_zp(zp_ptr + 1);
                    }
                }
            },
            .ST_X, .ST_Y, .ST_Z, .ST_X_INC, .ST_Y_INC, .ST_Z_INC, .ST_X_DEC, .ST_Y_DEC, .ST_Z_DEC, .STD_Y_Q, .STD_Z_Q => {
                if (inst.operands == .reg or inst.operands == .reg_imm) {
                    const r = if (inst.operands == .reg) inst.operands.reg else inst.operands.reg_imm.r;
                    const zp_ptr: u8 = switch (inst.opcode) {
                        .ST_X, .ST_X_INC, .ST_X_DEC => 0x1A,
                        .ST_Y, .ST_Y_INC, .ST_Y_DEC, .STD_Y_Q => 0x1C,
                        .ST_Z, .ST_Z_INC, .ST_Z_DEC, .STD_Z_Q => 0x1E,
                        else => unreachable,
                    };

                    // Pre-decrement (LDA/BNE/DEC/DEC pattern — doesn't corrupt carry flag)
                    if (inst.opcode == .ST_X_DEC or inst.opcode == .ST_Y_DEC or inst.opcode == .ST_Z_DEC) {
                        try out.emitLDA_zp(zp_ptr);
                        try out.emitBNE_rel(2); // skip DEC hi if lo != 0 (no borrow)
                        try out.emitDEC_zp(zp_ptr + 1);
                        try out.emitDEC_zp(zp_ptr);
                    }

                    if (inst.opcode == .STD_Y_Q or inst.opcode == .STD_Z_Q) {
                        const q = inst.operands.reg_imm.imm;
                        try out.emitLDY_imm(@truncate(q));
                    } else {
                        try out.emitLDY_imm(0);
                    }

                    try out.emitLDA_zp(r);
                    try out.emitSTA_indir_y(zp_ptr);

                    // Post-increment (INC/BNE/INC pattern — doesn't corrupt carry flag)
                    if (inst.opcode == .ST_X_INC or inst.opcode == .ST_Y_INC or inst.opcode == .ST_Z_INC) {
                        try out.emitINC_zp(zp_ptr);
                        try out.emitBNE_rel(2); // skip INC hi if lo didn't wrap to 0
                        try out.emitINC_zp(zp_ptr + 1);
                    }
                }
            },
            .LPM => {
                if (inst.operands == .reg) {
                    const d = inst.operands.reg;
                    const zp_ptr: u8 = 0x1E; // Z register
                    try out.emitLDY_imm(0);
                    try out.emitLDA_indir_y(zp_ptr);
                    try out.emitSTA_zp(d);
                }
            },
            .LDS => {
                if (inst.operands == .reg_imm) {
                    try out.emitLDA_abs(@truncate(inst.operands.reg_imm.imm));
                    try out.emitSTA_zp(inst.operands.reg_imm.r);
                }
            },
            .STS => {
                if (inst.operands == .reg_imm) {
                    try out.emitLDA_zp(inst.operands.reg_imm.r);
                    try out.emitSTA_abs(@truncate(inst.operands.reg_imm.imm));
                }
            },
            .ADIW => {
                if (inst.operands == .reg_imm) {
                    const r = inst.operands.reg_imm.r;
                    const imm = inst.operands.reg_imm.imm;
                    if (cpu_profile == .c65816) {
                        try out.emitREP(0x20); // 16-bit accumulator
                        try out.emitCLC();
                        try out.emitLDA_zp(r);
                        try out.emitADC_imm(@truncate(imm));
                        try out.emitByte(0); // High byte of imm
                        try out.emitSTA_zp(r);
                        try out.emitSEP(0x20); // 8-bit accumulator
                    } else {
                        try out.emitCLC();
                        try out.emitLDA_zp(r);
                        try out.emitADC_imm(@truncate(imm));
                        try out.emitSTA_zp(r);
                        try out.emitLDA_zp(r + 1);
                        try out.emitADC_imm(0);
                        try out.emitSTA_zp(r + 1);
                    }
                    carry_mode = .addition;
                }
            },
            .SBIW => {
                if (inst.operands == .reg_imm) {
                    const r = inst.operands.reg_imm.r;
                    const imm = inst.operands.reg_imm.imm;
                    try out.emitSEC();
                    try out.emitLDA_zp(r);
                    try out.emitSBC_imm(@truncate(imm));
                    try out.emitSTA_zp(r);
                    try out.emitLDA_zp(r + 1);
                    try out.emitSBC_imm(0);
                    try out.emitSTA_zp(r + 1);
                    carry_mode = .subtraction;
                }
            },
            .PUSH => {
                if (inst.operands == .reg) {
                    try out.emitLDA_zp(inst.operands.reg);
                    try out.emitPHA();
                }
            },
            .POP => {
                if (inst.operands == .reg) {
                    try out.emitPLA();
                    try out.emitSTA_zp(inst.operands.reg);
                }
            },
            .IN => {
                if (inst.operands == .reg_io) {
                    const r = inst.operands.reg_io.r;
                    const io = inst.operands.reg_io.io;
                    try out.emitLDA_zp(0x20 + io);
                    try out.emitSTA_zp(r);
                }
            },
            .OUT => {
                if (inst.operands == .io_reg) {
                    const io = inst.operands.io_reg.io;
                    const r = inst.operands.io_reg.r;
                    try out.emitLDA_zp(r);
                    try out.emitSTA_zp(0x20 + io);
                }
            },
            .TST => {
                if (inst.operands == .reg) {
                    try out.emitLDA_zp(inst.operands.reg);
                }
            },
            .CLR => {
                if (inst.operands == .reg) {
                    if (cpu_profile != .nmos6502) {
                        try out.emitSTZ_zp(inst.operands.reg);
                    } else {
                        try out.emitLDA_imm(0);
                        try out.emitSTA_zp(inst.operands.reg);
                    }
                }
            },
            .SER => {
                if (inst.operands == .reg) {
                    try out.emitLDA_imm(0xFF);
                    try out.emitSTA_zp(inst.operands.reg);
                }
            },
            .SBR => {
                if (inst.operands == .reg_imm) {
                    const d = inst.operands.reg_imm.r;
                    const k = inst.operands.reg_imm.imm;
                    try out.emitLDA_zp(d);
                    try out.emitORA_imm(@truncate(k));
                    try out.emitSTA_zp(d);
                }
            },
            .CBR => {
                if (inst.operands == .reg_imm) {
                    const d = inst.operands.reg_imm.r;
                    const k = inst.operands.reg_imm.imm;
                    try out.emitLDA_zp(d);
                    try out.emitAND_imm(~@as(u8, @truncate(k)));
                    try out.emitSTA_zp(d);
                }
            },
            .SPM => {
                // SPM: usually involves Z pointer and r0 (data)
                // For now, treat as indirect store (ST Z, r0)
                try out.emitLDY_imm(0);
                try out.emitLDA_zp(0); // r0
                try out.emitSTA_indir_y(0x1E); // Z
            },
            .SLEEP => {
                try out.emitNOP(); // SLEEP: emit NOP (0x02 is JAM/KIL on NMOS 6502)
            },
            .WDR => {
                try out.emitNOP();
            },
            .BREAK => {
                try out.emitBRK();
            },
            else => {
                // Return an error for unimplemented instructions for now
                std.debug.print("Unsupported instruction: {s} at addr 0x{X}\n", .{ @tagName(inst.opcode), inst.addr });
                return error.UnsupportedInstruction;
            },
        }
    }
}
