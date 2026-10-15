const std = @import("std");
const decoder = @import("decoder.zig");

pub const BasicBlock = struct {
    start_addr: u16,
    end_addr: u16,
    instructions: []decoder.Instruction,
    successors: [2]?u16 = .{ null, null }, // up to 2 successors (branch/fallthrough)
};

pub const CFG = struct {
    blocks: std.ArrayList(BasicBlock),

    pub fn deinit(self: *CFG, allocator: std.mem.Allocator) void {
        for (self.blocks.items) |block| {
            allocator.free(block.instructions);
        }
        self.blocks.deinit(allocator);
    }
};

pub fn buildCFG(allocator: std.mem.Allocator, text: []const u8, text_vma: u32) !CFG {
    var raw_instructions = std.ArrayList(decoder.Instruction).empty;
    defer raw_instructions.deinit(allocator);

    const vma_word_offset = @as(u32, text_vma / 2);

    // Pass 1: Decode all instructions and identify potential leaders
    var leaders = std.AutoHashMap(u16, bool).init(allocator);
    defer leaders.deinit();

    // The first instruction is always a leader
    try leaders.put(0, true);

    var offset: usize = 0;
    while (offset + 1 < text.len) {
        const word = std.mem.readInt(u16, text[offset .. offset + 2][0..2], .little);
        const addr = @as(u16, @intCast(offset / 2));

        var next_word: ?u16 = null;
        if (offset + 3 < text.len) {
            next_word = std.mem.readInt(u16, text[offset + 2 .. offset + 4][0..2], .little);
        }

        const inst = decoder.decode(word, next_word, addr);
        try raw_instructions.append(allocator, inst);
        offset += inst.size;

        // Identify leaders based on control flow
        switch (inst.opcode) {
            .RJMP => {
                const target = @as(u16, @intCast(@as(i32, @intCast(inst.addr)) + inst.operands.rel + 1));
                try leaders.put(target, true);
                try leaders.put(inst.addr + 1, true); // Instruction after RJMP is a leader
            },
            .JMP, .CALL => {
                const raw_target = @as(u32, inst.operands.addr);
                const target = @as(u16, @intCast(if (raw_target > vma_word_offset) raw_target - vma_word_offset else 0));
                try leaders.put(target, true);
                try leaders.put(inst.addr + 2, true); // Instruction after 4-byte jump/call
            },
            .BRBS, .BRBC => {
                const target = @as(u16, @intCast(@as(i32, @intCast(inst.addr)) + inst.operands.reg_rel.rel + 1));
                try leaders.put(target, true);
                try leaders.put(inst.addr + 1, true); // Fallthrough is a leader
            },
            .RCALL => {
                const target = @as(u16, @intCast(@as(i32, @intCast(inst.addr)) + inst.operands.rel + 1));
                try leaders.put(target, true);
                try leaders.put(inst.addr + 1, true);
            },
            .IJMP, .ICALL => {
                // For indirect jumps, we can't statically know the target.
                // But the instruction AFTER it is potential leader if we ever return.
                try leaders.put(inst.addr + 1, true);
            },
            .CPSE, .SBRC, .SBRS, .SBIC, .SBIS => {
                // Skip instructions skip the next instruction.
                // We need to know the size of the next instruction to find the target.
                var next_size: u16 = 1;
                const next_offset = offset; // offset is already pointing to next instruction
                if (next_offset + 1 < text.len) {
                    const next_word_peek = std.mem.readInt(u16, text[next_offset .. next_offset + 2][0..2], .little);
                    var word2_peek: ?u16 = null;
                    if (next_offset + 3 < text.len) {
                        word2_peek = std.mem.readInt(u16, text[next_offset + 2 .. next_offset + 4][0..2], .little);
                    }
                    const next_inst = decoder.decode(next_word_peek, word2_peek, inst.addr + 1);
                    next_size = if (next_inst.size == 4) @as(u16, 2) else @as(u16, 1);
                }
                const target = inst.addr + 1 + next_size;
                try leaders.put(target, true);
                try leaders.put(inst.addr + 1, true); // The skipped instruction is its own block start
            },
            .RET, .RETI => {
                try leaders.put(inst.addr + 1, true);
            },
            else => {},
        }
    }

    // Pass 2: Extract basic blocks
    var cfg = CFG{ .blocks = std.ArrayList(BasicBlock).empty };
    var current_insts = std.ArrayList(decoder.Instruction).empty;
    defer current_insts.deinit(allocator);

    var start_addr: u16 = 0;
    for (raw_instructions.items, 0..) |inst, i| {
        // If this instruction is a leader and not the first instruction of the current block,
        // finish the previous block.
        if (i > 0 and (leaders.get(inst.addr) != null)) {
            const inst_copy = try allocator.alloc(decoder.Instruction, current_insts.items.len);
            @memcpy(inst_copy, current_insts.items);

            try cfg.blocks.append(allocator, .{
                .start_addr = start_addr,
                .end_addr = current_insts.items[current_insts.items.len - 1].addr,
                .instructions = inst_copy,
            });
            current_insts.clearRetainingCapacity();
            start_addr = inst.addr;
        }
        try current_insts.append(allocator, inst);
    }

    // Add last block
    if (current_insts.items.len > 0) {
        const inst_copy = try allocator.alloc(decoder.Instruction, current_insts.items.len);
        @memcpy(inst_copy, current_insts.items);
        try cfg.blocks.append(allocator, .{
            .start_addr = start_addr,
            .end_addr = current_insts.items[current_insts.items.len - 1].addr,
            .instructions = inst_copy,
        });
    }

    // Pass 3: Resolve successors
    for (cfg.blocks.items) |*block| {
        const last_inst = block.instructions[block.instructions.len - 1];
        switch (last_inst.opcode) {
            .RJMP => {
                block.successors[0] = @as(u16, @intCast(@as(i32, @intCast(last_inst.addr)) + last_inst.operands.rel + 1));
            },
            .RCALL => {
                block.successors[0] = @as(u16, @intCast(@as(i32, @intCast(last_inst.addr)) + last_inst.operands.rel + 1));
                block.successors[1] = last_inst.addr + 1; // Return address
            },
            .JMP => {
                const raw_target = @as(u32, last_inst.operands.addr);
                block.successors[0] = @as(u16, @intCast(if (raw_target > vma_word_offset) raw_target - vma_word_offset else 0));
            },
            .CALL => {
                const raw_target = @as(u32, last_inst.operands.addr);
                block.successors[0] = @as(u16, @intCast(if (raw_target > vma_word_offset) raw_target - vma_word_offset else 0));
                block.successors[1] = last_inst.addr + 2; // Return address (4-byte instruction)
            },
            .BRBS, .BRBC => {
                block.successors[0] = @as(u16, @intCast(@as(i32, @intCast(last_inst.addr)) + last_inst.operands.reg_rel.rel + 1));
                block.successors[1] = last_inst.addr + 1;
            },
            .CPSE, .SBRC, .SBRS, .SBIC, .SBIS => {
                // Find next instruction size to calculate skip target
                const next_addr = last_inst.addr + 1;
                var next_size: u16 = 1;

                const next_offset = @as(usize, @intCast(last_inst.addr + 1)) * 2;
                if (next_offset + 1 < text.len) {
                    const next_word_s3 = std.mem.readInt(u16, text[next_offset .. next_offset + 2][0..2], .little);
                    var word2_s3: ?u16 = null;
                    if (next_offset + 3 < text.len) {
                        word2_s3 = std.mem.readInt(u16, text[next_offset + 2 .. next_offset + 4][0..2], .little);
                    }
                    const next_inst = decoder.decode(next_word_s3, word2_s3, last_inst.addr + 1);
                    next_size = if (next_inst.size == 4) @as(u16, 2) else @as(u16, 1);
                }
                block.successors[0] = last_inst.addr + 1 + next_size; // Skipped target
                block.successors[1] = next_addr; // Non-skipped target
            },
            .RET, .RETI => {
                // Returns have no static successors in the CFG
            },
            else => {
                // Fallthrough
                block.successors[0] = last_inst.addr + (if (last_inst.size == 4) @as(u16, 2) else @as(u16, 1));
            },
        }
    }

    return cfg;
}

test "CALL has two successors (target + return address)" {
    var text2 = [_]u8{
        0x0E, 0x94, 0x04, 0x00, // CALL 0x0004 at word addr 0
        0x00, 0x00, // NOP at word addr 2
        0x00, 0x00, // NOP at word addr 3
        0x00, 0x00, // NOP at word addr 4 (CALL target)
    };
    var cfg2 = try buildCFG(std.testing.allocator, &text2, 0);
    defer cfg2.deinit(std.testing.allocator);

    // Find the block containing the CALL instruction
    var found_call = false;
    for (cfg2.blocks.items) |block| {
        const last = block.instructions[block.instructions.len - 1];
        if (last.opcode == .CALL) {
            // successor[0] = target (word addr 4)
            try std.testing.expectEqual(@as(u16, 4), block.successors[0].?);
            // successor[1] = return address (word addr 2, since CALL is 4-byte = 2 words)
            try std.testing.expectEqual(@as(u16, 2), block.successors[1].?);
            found_call = true;
        }
    }
    try std.testing.expect(found_call);
}

test "build simple cfg" {
    // 0: NOP
    // 1: RJMP .-2 (to 0)
    var text = [_]u8{ 0x00, 0x00, 0xFE, 0xCF };
    var cfg = try buildCFG(std.testing.allocator, &text, 0);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), cfg.blocks.items.len);
    try std.testing.expectEqual(@as(u16, 0), cfg.blocks.items[0].start_addr);
    try std.testing.expectEqual(@as(u16, 1), cfg.blocks.items[0].end_addr);
    // RJMP .-2 at addr 1 jumps to 1 + (-1) = 0
    try std.testing.expectEqual(@as(u16, 0), cfg.blocks.items[0].successors[0].?);
}
