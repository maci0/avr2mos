import sys
from py65.disassembler import Disassembler

from py65.devices.mpu6502 import MPU

with open(sys.argv[1], 'rb') as f:
    data = f.read()

m = MPU()
m.memory = bytearray(65536)
for i, b in enumerate(data):
    m.memory[0x0200 + i] = b

d = Disassembler(m)
pc = 0x0200
end = 0x0200 + len(data)

while pc < end:
    width, inst = d.instruction_at(pc)
    # create hex string for bytes
    hex_bytes = " ".join([f"{m.memory[pc+i]:02X}" for i in range(width)])
    print(f"${pc:04X}: {hex_bytes:8s}  {inst}")
    pc += width
