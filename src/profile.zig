pub const CpuProfile = enum {
    nmos6502,
    c6502, // 65c02 normally, but zig enum can't start with number
    c65816,
};
