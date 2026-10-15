import subprocess
import os
import sys
import re
import tempfile

def compile_avr(tmpdir, root_dir):
    print("[1] Compiling pure Zig target via linker...")
    res = subprocess.run([
        "zig", "build-exe", os.path.join(root_dir, "tests/nes_rom.zig"),
        "-target", "avr-freestanding-none", "-mcpu=atmega328p",
        "-O", "ReleaseSmall", "-fno-compiler-rt", f"-femit-bin={os.path.join(tmpdir, 'nes_rom.elf')}",
        "-T", os.path.join(root_dir, "tests/linker_nes.ld"), "-fno-strip"
    ], capture_output=True, text=True, cwd=root_dir)
    if res.returncode != 0:
        print(f"Compilation Failed:\n{res.stderr}")
        sys.exit(1)

def translate_to_6502(tmpdir, root_dir):
    print("[2] Translating AVR payload cleanly into MOS 6502 binary...")
    res = subprocess.run([
        os.path.join(root_dir, "zig-out/bin/avr2mos"),
        "--input", os.path.join(tmpdir, "nes_rom.elf"),
        "--output", os.path.join(tmpdir, "nes_rom_6502.bin"),
        "--emit-symbol-map",
        "-O3"
    ], cwd=tmpdir)
    if res.returncode != 0:
        print("Translation Failed.")
        sys.exit(1)

def build_ines_rom(tmpdir, root_dir):
    print("[3] Locating Symbols via avr-nm...")
    elf_path = os.path.join(tmpdir, "nes_rom.elf")
    nm_res = subprocess.run(["avr-nm", elf_path], capture_output=True, text=True)
    if nm_res.returncode != 0:
        print("avr-nm failed.")
        sys.exit(1)
        
    start_offset = 0
    nmi_offset = 0
    
    for line in nm_res.stdout.splitlines():
        if "_start" in line:
            addr = int(line.split()[0], 16)
            start_offset = (addr - 0x8000) // 2
        elif "nmi_handler" in line:
            addr = int(line.split()[0], 16)
            nmi_offset = (addr - 0x8000) // 2
            
    start_label_str = f"L{start_offset:04X}"
    nmi_label_str = f"L{nmi_offset:04X}"

    print(f"  -> Discovered _start at index {start_label_str}")
    print(f"  -> Discovered nmi_handler at index {nmi_label_str}")

    print("[4] Parsing 6502 mapping tables...")
    with open(os.path.join(tmpdir, "nes_rom_6502.bin.map"), "r") as f:
        map_lines = f.readlines()
        
    start_addr = 0x8000
    nmi_addr = 0x8000
    
    for line in map_lines:
        match = re.search(r'(L[0-9A-Fa-f]+)\s+=\s+\$([0-9A-Fa-f]+)', line)
        if match:
            label = match.group(1)
            mapped_addr = int(match.group(2), 16)
            if label == start_label_str:
                start_addr = mapped_addr
            elif label == nmi_label_str:
                nmi_addr = mapped_addr

    print("[5] Extracting native Cartridge sections from ELF...")
    header_path = os.path.join(tmpdir, "header.bin")
    subprocess.run(["avr-objcopy", "-O", "binary", "-j", ".inesheader", elf_path, header_path], check=True)
    with open(header_path, "rb") as f:
        header_block = bytearray(f.read())
        
    print("[6] Splicing cart sections...")
    bin_path = os.path.join(tmpdir, "nes_rom_6502.bin")
    with open(bin_path, "rb") as f:
        prg_payload = bytearray(f.read())
        
    prg_block = bytearray(16384)
    for i in range(len(prg_payload)):
        prg_block[i] = prg_payload[i]
    
    nmi_addr_val = int(nmi_addr)
    start_addr_val = int(start_addr)
    
    prg_block[0x3FFA] = nmi_addr_val & 0xFF
    prg_block[0x3FFB] = (nmi_addr_val >> 8) & 0xFF
    prg_block[0x3FFC] = start_addr_val & 0xFF
    prg_block[0x3FFD] = (start_addr_val >> 8) & 0xFF
    prg_block[0x3FFE] = start_addr_val & 0xFF
    prg_block[0x3FFF] = (start_addr_val >> 8) & 0xFF
    
    print("[7] Wrapping CHR-ROM fonts...")
    font_path = os.path.join(root_dir, "font.chr")
    with open(font_path, "rb") as f:
        chr_block = bytearray(f.read())
        
    out_nes = os.path.join(tmpdir, "test.nes")
    with open(out_nes, "wb") as f:
        f.write(header_block)
        f.write(prg_block)
        f.write(chr_block)
        
    print(f"SUCCESS: Cartridge Built successfully as {out_nes}")
    return out_nes

if __name__ == "__main__":
    root_dir = os.path.abspath(os.path.dirname(os.path.dirname(__file__)))
    # We will use mkdtemp instead of TemporaryDirectory if the user wants to keep the output
    tmpdir = tempfile.mkdtemp(prefix="avr2mos_test_")
    compile_avr(tmpdir, root_dir)
    translate_to_6502(tmpdir, root_dir)
    build_ines_rom(tmpdir, root_dir)
