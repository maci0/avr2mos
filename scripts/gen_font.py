import sys

def create_chr():
    # 8KB CHR-ROM block (512 tiles, 16 bytes each)
    chr_rom = bytearray(8192)
    
    # Tile 0: Empty / Space (all zeros)
    
    # Tile 0x1A: 'Z'
    # 8x8 pixel bitmap representation
    bitmap_Z = [
        0b11111110,
        0b00000010,
        0b00000100,
        0b00001000,
        0b00010000,
        0b00100000,
        0b01000000,
        0b11111110,
    ]
    # Write to CHR index 0x1A (offset = 0x1A * 16)
    offset_Z = 0x1A * 16
    for i in range(8):
        chr_rom[offset_Z + i] = bitmap_Z[i]     # Plane 0
        chr_rom[offset_Z + i + 8] = 0           # Plane 1 (color index 1 = %01)

    # Tile 0x09: 'I'
    bitmap_I = [
        0b11111110,
        0b00010000,
        0b00010000,
        0b00010000,
        0b00010000,
        0b00010000,
        0b00010000,
        0b11111110,
    ]
    offset_I = 0x09 * 16
    for i in range(8):
        chr_rom[offset_I + i] = bitmap_I[i]
        chr_rom[offset_I + i + 8] = 0

    # Tile 0x07: 'G'
    bitmap_G = [
        0b01111100,
        0b10000010,
        0b10000000,
        0b10001110,
        0b10000010,
        0b10000010,
        0b01111100,
        0b00000000,
    ]
    offset_G = 0x07 * 16
    for i in range(8):
        chr_rom[offset_G + i] = bitmap_G[i]
        chr_rom[offset_G + i + 8] = 0

    with open("font.chr", "wb") as f:
        f.write(chr_rom)
        
    print("SUCCESS: Generated 8KB font.chr graphics data.")

if __name__ == "__main__":
    create_chr()
