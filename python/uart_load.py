#!/usr/bin/env python3
"""
UART Program Loader — send .hex file to FPGA bootloader via serial port

Usage:
    python uart_load.py <hex_file> <serial_port> [baudrate]

Examples:
    python uart_load.py mytest.hex COM3
    python uart_load.py mytest.hex /dev/ttyUSB0 115200

Protocol (PC -> FPGA):
    Byte 0-3: program size in words (big-endian)
    Byte 4-N: program data (4 bytes per word, big-endian)
"""

import sys
import time


def load_hex(filepath):
    """Read .hex file, return list of 32-bit words."""
    words = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("@") or line.startswith("//"):
                continue
            # Each line is one 32-bit hex word
            try:
                words.append(int(line, 16))
            except ValueError:
                print(f"Warning: skipping invalid line: {line}")
    return words


def send_program(ser, words):
    """Send program to FPGA bootloader over serial."""
    size = len(words)
    print(f"Program size: {size} words ({size * 4} bytes)")

    # 1. Send program size (4 bytes, big-endian)
    ser.write(size.to_bytes(4, "big"))
    print(f"  Sent size header: {size} (0x{size:08X})")

    # 2. Send each word (4 bytes per word, big-endian)
    for i, w in enumerate(words):
        ser.write(w.to_bytes(4, "big"))
        if (i + 1) % 256 == 0:
            print(f"  Progress: {i + 1}/{size} words sent")

    print(f"Sent complete: {size} instructions")
    print("FPGA bootloader will auto-jump to execute...")


def main():
    if len(sys.argv) < 3:
        print("Usage: python uart_load.py <hex_file> <serial_port> [baudrate]")
        print("Example: python uart_load.py mytest.hex COM3 115200")
        sys.exit(1)

    hex_file = sys.argv[1]
    port = sys.argv[2]
    baudrate = int(sys.argv[3]) if len(sys.argv) > 3 else 115200

    # Read hex file
    words = load_hex(hex_file)
    if not words:
        print(f"Error: no valid instructions found in {hex_file}")
        sys.exit(1)
    print(f"Loaded {len(words)} instructions from {hex_file}")

    # Open serial port
    try:
        import serial
    except ImportError:
        print("Error: pyserial is required. Install with: pip install pyserial")
        sys.exit(1)

    try:
        ser = serial.Serial(port, baudrate, timeout=1)
        print(f"Connected to {port} @ {baudrate} bps")
    except Exception as e:
        print(f"Error opening serial port {port}: {e}")
        sys.exit(1)

    time.sleep(0.1)  # Wait for serial to stabilize

    try:
        send_program(ser, words)
    except Exception as e:
        print(f"Error during transmission: {e}")
    finally:
        ser.close()
        print("Serial port closed.")


if __name__ == "__main__":
    main()
