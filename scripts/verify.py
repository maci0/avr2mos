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

        # 1. Assemble AVR using avr-as/avr-ld
        print("  Assembling AVR with avr-as/avr-ld...")
        cmd = f"avr-as -mmcu=atmega328p -o {avr_obj} {asm_file}"
        _, _, code = run_command(cmd)
        if code != 0: return False

        ld_script = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tests", "avr.ld")
        cmd = f"avr-ld -m avr5 -T {ld_script} -o {avr_elf} {avr_obj}"
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
            f.write("info registers\n")
            f.write("x/64xb 0x800020\n") # Dump 64 bytes starting from I/O area
            f.write("quit\n")
        
        cmd = f"avr-gdb -batch -x {gdb_script} {avr_elf}"
        stdout, stderr, code = run_command(cmd)

        avr_regs = {}
        # Parse GDB output for registers
        for line in stdout.splitlines():
            line = line.strip()
            if line.startswith('r') and (len(line) > 1 and line[1].isdigit()):
                try:
                    parts = line.split()
                    reg_name = parts[0]
                    reg_index = int(reg_name.lstrip('r'))
                    val_str = parts[1]
                    val = int(val_str, 0)
                    avr_regs[reg_index] = val & 0xFF
                except: continue
        
        # Parse GDB output for memory (I/O)
        avr_io = {}
        current_addr = 0
        for line in stdout.splitlines():
            line = line.strip()
            if line.startswith('0x8000'):
                try:
                    parts = line.split(':')
                    addr_full = int(parts[0], 16)
                    current_addr = addr_full - 0x800000
                    vals = parts[1].split()
                    for i, v in enumerate(vals):
                        avr_io[current_addr + i] = int(v, 16)
                except: continue
            elif line.startswith('0x') and ':' in line: # generic hex dump
                try:
                    parts = line.split(':')
                    addr = int(parts[0], 16)
                    current_addr = addr
                    vals = parts[1].split()
                    for i, v in enumerate(vals):
                        avr_io[current_addr + i] = int(v, 16)
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

count = 0
while count < 100000:
    if mem[mpu.pc] == 0x00:
        break
    mpu.step()
    count += 1

print(f"6502 finished after {{count}} steps. Final PC: 0x{{mpu.pc:04x}}")

# Dump ZP $00-$5F
for i in range(0x60):
    print("ZP%02x: %02x" % (i, mem[i]))
"""
        stdout, _, code = run_command("uv run --with py65 python3", input_data=py65_script)
        print("6502 OUT:", stdout)
        if code != 0: return False
        
        m6502_regs = {}
        m6502_io = {}
        for line in stdout.splitlines():
            if line.startswith('ZP'):
                try:
                    parts = line.split(':')
                    idx_str = parts[0].strip().lstrip('ZP')
                    idx = int(idx_str, 16)
                    val_str = parts[1].strip()
                    val = int(val_str, 16)
                    if idx < 32:
                        m6502_regs[idx] = val
                    elif idx >= 0x20 and idx < 0x60:
                        m6502_io[idx] = val
                except: continue

        if not avr_regs or not m6502_regs:
            print("  Error: Could not extract registers from one or both simulators.")
            return False

        # 5. Compare
        print("  Comparing states...")
        success = True
        # Registers
        for i in range(32):
            avr_val = avr_regs.get(i, 0)
            mos_val = m6502_regs.get(i, 0)
            if avr_val != mos_val:
                print(f"    Mismatch at r{i}: AVR=0x{avr_val:02x}, 6502=0x{mos_val:02x}")
                success = False
        
        # I/O
        for i in range(0x20, 0x5F): # Exclude SREG at 0x5F for now
            avr_val = avr_io.get(i, 0)
            mos_val = m6502_io.get(i, 0)
            if avr_val != mos_val:
                print(f"    Mismatch at IO 0x{i:02x}: AVR=0x{avr_val:02x}, 6502=0x{mos_val:02x}")
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
