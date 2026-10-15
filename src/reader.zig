const std = @import("std");

pub const Program = struct {
    text: []const u8,
    data: []const u8 = &[_]u8{},
    rodata: []const u8 = &[_]u8{},
    text_vma: u32 = 0,
    data_vma: u32 = 0,
    rodata_vma: u32 = 0,

    pub fn deinit(self: *Program, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.data.len > 0) allocator.free(self.data);
        if (self.rodata.len > 0) allocator.free(self.rodata);
    }
};

pub fn readInput(allocator: std.mem.Allocator, filepath: []const u8) !Program {
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(contents); // We will copy sections out

    // Check for ELF magic bytes '\x7f', 'E', 'L', 'F'
    if (contents.len >= 4 and std.mem.eql(u8, contents[0..4], "\x7fELF")) {
        return readElf(allocator, contents);
    } else {
        // Assume raw binary if not ELF
        const text_copy = try allocator.alloc(u8, contents.len);
        @memcpy(text_copy, contents);
        return Program{
            .text = text_copy,
        };
    }
}

fn readElf(allocator: std.mem.Allocator, contents: []const u8) !Program {
    var stream = std.io.fixedBufferStream(contents);
    const reader = stream.reader();

    // Read ELF header directly
    const ehdr = try reader.readStructEndian(std.elf.Elf32_Ehdr, .little);

    var text_section: []const u8 = &[_]u8{};
    var data_section: []const u8 = &[_]u8{};
    var rodata_section: []const u8 = &[_]u8{};

    const shstrndx = ehdr.e_shstrndx;
    const shoff = ehdr.e_shoff;

    var i: usize = 0;
    var shdrs = std.ArrayList(std.elf.Elf32_Shdr).empty;
    defer shdrs.deinit(allocator);

    while (i < ehdr.e_shnum) : (i += 1) {
        const offset = shoff + i * ehdr.e_shentsize;
        var shdr_stream = std.io.fixedBufferStream(contents[offset..]);
        const shdr = try shdr_stream.reader().readStructEndian(std.elf.Elf32_Shdr, .little);
        try shdrs.append(allocator, shdr);
    }

    if (shstrndx >= ehdr.e_shnum) return error.InvalidElfStringTable;

    const shstrtab_shdr = shdrs.items[shstrndx];
    const shstrtab = contents[shstrtab_shdr.sh_offset .. shstrtab_shdr.sh_offset + shstrtab_shdr.sh_size];

    var text_vma: u32 = 0;
    var data_vma: u32 = 0;
    var rodata_vma: u32 = 0;

    errdefer {
        if (text_section.len > 0) allocator.free(text_section);
        if (data_section.len > 0) allocator.free(data_section);
        if (rodata_section.len > 0) allocator.free(rodata_section);
    }

    for (shdrs.items) |shdr| {
        const name = std.mem.sliceTo(shstrtab[shdr.sh_name..], 0);
        if (std.mem.eql(u8, name, ".text")) {
            const buf = try allocator.alloc(u8, shdr.sh_size);
            @memcpy(buf, contents[shdr.sh_offset .. shdr.sh_offset + shdr.sh_size]);
            text_section = buf;
            text_vma = shdr.sh_addr;
        } else if (std.mem.eql(u8, name, ".data")) {
            const buf = try allocator.alloc(u8, shdr.sh_size);
            @memcpy(buf, contents[shdr.sh_offset .. shdr.sh_offset + shdr.sh_size]);
            data_section = buf;
            data_vma = shdr.sh_addr;
        } else if (std.mem.eql(u8, name, ".rodata")) {
            const buf = try allocator.alloc(u8, shdr.sh_size);
            @memcpy(buf, contents[shdr.sh_offset .. shdr.sh_offset + shdr.sh_size]);
            rodata_section = buf;
            rodata_vma = shdr.sh_addr;
        }
    }

    return Program{
        .text = text_section,
        .data = data_section,
        .rodata = rodata_section,
        .text_vma = text_vma,
        .data_vma = data_vma,
        .rodata_vma = rodata_vma,
    };
}

test "can read binary" {
    // Basic compilation test
    _ = readInput;
}
