const std = @import("std");

// Memory mapped PPU registers on the NES
const PPU_CTRL = @as(*volatile u8, @ptrFromInt(0x2000));
const PPU_MASK = @as(*volatile u8, @ptrFromInt(0x2001));
const PPU_STATUS = @as(*volatile u8, @ptrFromInt(0x2002));
const PPU_OAM_ADDR = @as(*volatile u8, @ptrFromInt(0x2003));
const PPU_OAM_DATA = @as(*volatile u8, @ptrFromInt(0x2004));
const PPU_SCROLL = @as(*volatile u8, @ptrFromInt(0x2005));
const PPU_ADDR = @as(*volatile u8, @ptrFromInt(0x2006));
const PPU_DATA = @as(*volatile u8, @ptrFromInt(0x2007));

// iNES Header directly embedded in the ROM image
export const ines_header align(1) linksection(".inesheader") = [_]u8{
    0x4E, 0x45, 0x53, 0x1A, // "NES" + EOF
    0x01, // 1x 16KB PRG ROM
    0x01, // 1x 8KB CHR ROM
    0x00, // Mapper 0, mirroring 0
    0x00, 0x00, 0x00, 0x00, // padding
    0x00, 0x00, 0x00, 0x00,
    0x00,
};

fn vblank_wait() void {
    // Wait for bit 7 of PPU_STATUS to be set
    while ((PPU_STATUS.* & 0x80) == 0) {}
}

export fn _start() void {
    // Initialize standard NES state
    PPU_CTRL.* = 0;
    PPU_MASK.* = 0;

    // Warm up the PPU (requires ~2 full vblank frames to stabilize on startup)
    vblank_wait();
    vblank_wait();

    // Set Palette Base Address at $3F00
    PPU_ADDR.* = 0x3F;
    PPU_ADDR.* = 0x00;

    // Background color: Deep Blue (0x11)
    PPU_DATA.* = 0x11;
    // Base Palette 0, color 1: White (0x30)
    PPU_DATA.* = 0x30;
    // Base Palette 0, color 2: Red (0x16)
    PPU_DATA.* = 0x16;
    // Base Palette 0, color 3: Green (0x1A)
    PPU_DATA.* = 0x1A;

    // Clear Nametable 0 (Background Map at $2000)
    PPU_ADDR.* = 0x20;
    PPU_ADDR.* = 0x00;

    comptime var i: u16 = 0;
    inline while (i < 960) : (i += 1) {
        PPU_DATA.* = 0x00; // empty blank tile ID mapped in CHR-ROM
    }

    // Write "ZIG" to roughly the middle of the screen
    PPU_ADDR.* = 0x21; // High byte location
    PPU_ADDR.* = 0xCA; // Low byte location natively
    PPU_DATA.* = 0x1A; // 'Z' tile pattern
    PPU_DATA.* = 0x09; // 'I' tile pattern
    PPU_DATA.* = 0x07; // 'G' tile pattern

    // Reset scroll values to lock rendering onto the top left of Nametable 0
    PPU_ADDR.* = 0x20;
    PPU_ADDR.* = 0x00;
    PPU_SCROLL.* = 0x00;
    PPU_SCROLL.* = 0x00;

    // Re-enable PPU graphical rendering features
    PPU_CTRL.* = 0x80; // Triggers NMI Interrupt enablement alongside rendering
    PPU_MASK.* = 0x0A; // Show background tiles

    // CPU execution halts but the PPU takes over infinitely
    while (true) {}
}

export fn nmi_handler() void {
    // Basic acknowledge of the NMI interrupt signal natively in the PPU
    _ = PPU_STATUS.*;
}

// 6502 Vector Map targets located directly at block's end ($FFFA)
// The block maps mathematically directly to physical boundaries
export const vectors align(1) linksection(".nesvectors") = [_]*const fn () callconv(.c) void{
    nmi_handler, // $FFFA (NMI)
    _start, // $FFFC (Reset)
    _start, // $FFFE (IRQ)
};
