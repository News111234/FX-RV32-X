#!/usr/bin/env python3
import sys

def convert_verilog_hex(infile, outfile, depth=512):
    mem = [0] * depth
    current_addr = 0
    total_bytes = 0

    with open(infile, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            if line.startswith('@'):
                current_addr = int(line[1:], 16)
                print(f"[Info] Set address to 0x{current_addr:08X} at line {line_num}")
                continue
            # 这一行是一串十六进制字节
            try:
                bytes_vals = [int(b, 16) for b in line.split()]
            except ValueError:
                print(f"[Warning] Skip line {line_num}: cannot parse")
                continue
            for i, b in enumerate(bytes_vals):
                byte_addr = current_addr + i
                word_addr = byte_addr >> 2          # 除以4
                byte_offset = byte_addr & 0x3       # 字内偏移
                if word_addr < depth:
                    mem[word_addr] |= (b << (byte_offset * 8))
                    total_bytes += 1
            current_addr += len(bytes_vals)

    print(f"[Info] Total bytes loaded: {total_bytes}")

    with open(outfile, 'w') as f:
        for word in mem:
            f.write(f"{word:08X}\n")
    print(f"[Info] Output written to {outfile}")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python3 convert_hex.py input_verilog.hex output_mem.hex")
        sys.exit(1)
    convert_verilog_hex(sys.argv[1], sys.argv[2])