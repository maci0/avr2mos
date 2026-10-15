import json, subprocess
out = subprocess.check_output(['zig', 'targets'])
data = json.loads(out)
avr_cpus = data.get('cpus', {}).get('avr', [])
print(f"Total AVR CPUs: {len(avr_cpus)}")
for i, cpu in enumerate(avr_cpus):
    if i < 20:
        print(f" - {cpu['name']}")
if len(avr_cpus) > 20:
    print(" ... and many more")
