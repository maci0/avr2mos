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
        cmd = f"zig build-exe -O ReleaseSmall -fno-compiler-rt -T tests/linker.ld -target avr-freestanding-none -mcpu=atmega328p {asm_file} -femit-bin={avr_elf}"
        _, _, code = run_command(cmd)
        if code != 0: return False

        # 2. Translate to 6502
        print("  Translating to 6502 with -O3...")
        cmd = f"./zig-out/bin/avr2mos --input {avr_elf} --output {m6502_bin} -O3 --report {report_file}"
        stdout, stderr, code = run_command(cmd)
        if stderr: print("avr2mos STDERR:", stderr)
        if code != 0: return False

        # 3. Simulate 6502 (using py65)
        print("  Simulating 6502...")
        py65_script = f"""
import sys
import hashlib
from py65.devices.mpu6502 import MPU

with open('{m6502_bin}', 'rb') as f:
    data = f.read()

mem = bytearray(65536)
for i, b in enumerate(data):
    mem[0x0200 + i] = b

mpu = MPU()
mpu.memory = mem
mpu.pc = 0x0200
mpu.sp = 0xFF

count = 0
last_pc = 0x0000
while count < 15000000:
    last_pc = mpu.pc
    try:
        mpu.step()
    except Exception as e:
        print(f"Exception at PC {{mpu.pc:04X}}: {{e}}")
        break
        
    if mpu.pc == last_pc: # Caught in an infinite loop! Program finished.
        break
    count += 1

print(f"6502 finished after {{count}} steps. Final PC: 0x{{mpu.pc:04x}}")

# Dump Target Struct $5000-$501F (32 bytes)
out_bytes = bytearray()
for i in range(32):
    addr = 0x5000 + i
    out_bytes.append(mem[addr])
    
mos_hex = out_bytes.hex()
print(f"MOS-6502 Hash: {{mos_hex}}")

expected_hex = hashlib.sha256(b"avr2mos_torture_test").hexdigest()
print(f"Expected Hash: {{expected_hex}}")

if mos_hex == expected_hex:
    print("  SUCCESS: Memory digest perfectly matches Python hashlib!")
    sys.exit(0)
else:
    print("  FAILED: Memory digest divergence.")
    sys.exit(1)
"""
        stdout, _, code = run_command("uv run --with py65 python3", input_data=py65_script)
        if code != 0:
            print(stdout)
            return False
            
        print(stdout)
        print(f"✅ Successfully verified {asm_file}")
        return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 verify.py <test.asm>")
        sys.exit(1)
    
    if verify(sys.argv[1]):
        sys.exit(0)
    else:
        sys.exit(1)
