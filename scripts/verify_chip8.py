import subprocess
import os
import sys
import tempfile

def run_command(cmd, input_data=None):
    process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, text=True)
    stdout, stderr = process.communicate(input=input_data)
    if process.returncode != 0:
        print(f"Command failed: {cmd}")
        print(f"Stdout: {stdout}")
        print(f"Stderr: {stderr}")
        # sys.exit(1) # Don't exit immediately, let the caller handle it if needed
    return stdout, stderr, process.returncode

def verify(asm_file):
    print(f"Verifying {asm_file}...")
    
    with tempfile.TemporaryDirectory() as tmpdir:
        base = os.path.basename(asm_file).split('.')[0]
        avr_obj = os.path.join(tmpdir, f"{base}.o")
        avr_elf = os.path.join(tmpdir, f"{base}.elf")
        avr_bin = os.path.join(tmpdir, f"{base}.bin")
        m6502_bin = os.path.join(tmpdir, f"{base}_6502.bin")
        report_file = os.path.join(tmpdir, "report.txt")

        # 1. Compile AVR using zig build-exe
        print("  Compiling AVR with zig...")
        cmd = f"zig build-exe -O ReleaseSmall -fno-compiler-rt -target avr-freestanding-none -mcpu=atmega328p {asm_file} -femit-bin={avr_elf}"
        _, _, code = run_command(cmd)
        if code != 0: return False

        # 2. Translate to 6502
        print("  Translating to 6502...")
        cmd = f"./zig-out/bin/avr2mos --input {avr_elf} --output {m6502_bin} --report {report_file}"
        stdout, stderr, code = run_command(cmd)
        if stderr: print("avr2mos STDERR:", stderr)
        if code != 0: return False

        # 3. Simulate AVR using avr-gdb's built-in simulator
        print("  Simulating AVR with avr-gdb target sim...")
        gdb_script = os.path.join(tmpdir, "run.gdb")
        with open(gdb_script, "w") as f:
            f.write("target sim\n")
            f.write("load\n")
            f.write("run\n")
            f.write("x/1422xb 0x800100\n") # Dump 1422 bytes starting from SRAM Base
            f.write("quit\n")
        
        cmd = f"avr-gdb -batch -x {gdb_script} {avr_elf}"
        stdout, stderr, code = run_command(cmd)

        avr_mem = {}
        # Parse GDB output for memory
        current_addr = 0
        for line in stdout.splitlines():
            line = line.strip()
            if line.startswith('0x800'):
                try:
                    parts = line.split(':')
                    addr_full = int(parts[0], 16)
                    current_addr = addr_full - 0x800000
                    vals = parts[1].split()
                    for i, v in enumerate(vals):
                        avr_mem[current_addr + i] = int(v, 16)
                except: continue

        # 4. Simulate 6502 (using py65)
        print("  Simulating 6502...")
        py65_script = f"""
import sys
from py65.devices.mpu6502 import MPU

with open('{m6502_bin}', 'rb') as f:
    data = f.read()

mem = bytearray(65536)
for i, b in enumerate(data):
    mem[0x0200 + i] = b

mpu = MPU()
mpu.memory = mem
mpu.pc = 0x0200

# Stub out the halt vector
mem[0xFFFC] = 0x00
mem[0xFFFD] = 0x00

count = 0
while count < 500000:
    if mem[mpu.pc] == 0x00: # Assuming 00 is HALT for now (or runs off end)
        break
    if mpu.pc == 0x0000:
        break
    try:
        mpu.step()
    except Exception as e:
        print(f"Exception at PC {{mpu.pc:04X}}: {{e}}")
        break
    count += 1

print(f"6502 finished after {{count}} steps. Final PC: 0x{{mpu.pc:04x}}")

# Dump Target Struct $0100-$068E (1422 bytes)
for i in range(1422):
    addr = 0x0100 + i
    print("MEM%04x: %02x" % (addr, mem[addr]))
"""
        stdout, _, code = run_command("uv run --with py65 python3", input_data=py65_script)
        if code != 0: return False
        
        m6502_mem = {}
        for line in stdout.splitlines():
            if line.startswith('MEM'):
                try:
                    parts = line.split(':')
                    idx_str = parts[0].strip().lstrip('MEM')
                    idx = int(idx_str, 16)
                    val_str = parts[1].strip()
                    val = int(val_str, 16)
                    m6502_mem[idx] = val
                except: continue

        if not avr_mem or not m6502_mem:
            print("  Error: Could not extract memory from one or both simulators.")
            return False

        # 5. Compare Struct Fields directly mapped to Memory 1KB boundary
        print("  Comparing states...")
        success = True
        
        for i in range(1422):
            addr = 0x0100 + i
            avr_val = avr_mem.get(addr, 0)
            mos_val = m6502_mem.get(addr, 0)
            if avr_val != mos_val:
                print(f"    Mismatch at Struct Offset +0x{i:04x} / RAM: 0x{addr:04x}: AVR=0x{avr_val:02x}, 6502=0x{mos_val:02x}")
                success = False
        
        if success:
            print("  SUCCESS!")
        else:
            print("  FAILED!")
        return success

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 verify.py <test.asm>")
        sys.exit(1)
    
    if verify(sys.argv[1]):
        sys.exit(0)
    else:
        sys.exit(1)
