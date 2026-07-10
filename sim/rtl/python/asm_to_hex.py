#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
================================================================================
                    RISC-V Assembly → Plain Hex Converter
================================================================================
说明：
  - 读取 .s 汇编文件，调用 riscv_asm7.py 的 FullRISCVAssembler 生成机器码
  - 输出纯 hex 格式：每行一个 32-bit 字（8 位十六进制）
  - 可直接用于：
      sim/program.hex      (Verilator 仿真)
      uvm/*.hex            (Modelsim/UVM 仿真)
  - 不修改 riscv_asm7.py

用法：
  python asm_to_hex.py input.s                  → 输出到 stdout
  python asm_to_hex.py input.s output.hex       → 输出到文件
  python asm_to_hex.py input.s -                → 输出到 stdout
  python asm_to_hex.py input.s --rom            → 输出 Verilog ROM 格式
  python asm_to_hex.py input.s --base 0x0000    → 指定起始地址（默认 0x0000）

示例：
  cd python
  python asm_to_hex.py ../uvm/alu_test.s ../uvm/alu_test.hex
  python asm_to_hex.py ../mytests/test2_fib.S ../sim/program.hex
================================================================================
"""

import sys
import os

# 将本脚本所在目录加入路径，以便 import 同目录下的 riscv_asm7
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from riscv_asm7 import FullRISCVAssembler


def assemble_to_hex(lines, start_addr=0x0000):
    """
    汇编并返回纯 hex 字符串（每行一个 32-bit 字）。
    对于 .space 等数据指令，用 0x00000000 填充。
    """
    asm = FullRISCVAssembler()
    results = asm.assemble_program(lines, start_addr)

    if not results:
        return ""

    # 找出最大地址，确定内存映像大小
    max_addr = max(addr + (4 if not (isinstance(code, int) and isinstance(comment, str) and comment.startswith('.space')) else code)
                   for addr, code, comment in results)

    # 按 4 字节对齐
    num_words = (max_addr + 3) // 4
    mem = [0] * num_words

    for addr, code, comment in results:
        if isinstance(comment, str) and comment.startswith('.space'):
            # .space: code 是字节数，保持为 0（已初始化）
            continue
        elif isinstance(code, int) and code <= 0xFFFFFFFF:
            word_idx = addr // 4
            if word_idx < num_words:
                mem[word_idx] = code
        else:
            word_idx = addr // 4
            if word_idx < num_words:
                mem[word_idx] = code

    return '\n'.join(f"{w:08X}" for w in mem)


def assemble_to_rom(lines, start_addr=0x0000):
    """
    汇编并返回 Verilog ROM 格式字符串（rom[i]=32'hXXXXX;）。
    保留给需要生成 inst_rom.v 内容的场景。
    """
    asm = FullRISCVAssembler()
    results = asm.assemble_program(lines, start_addr)

    if not results:
        return ""

    out_lines = []
    for addr, code, comment in results:
        rom_index = addr // 4
        if isinstance(comment, str) and comment.startswith('.space'):
            size = code
            start_rom = addr // 4
            end_rom = (addr + size - 1) // 4
            if start_rom == end_rom:
                out_lines.append(f"rom[{start_rom:4d}] = 32'h00000000;  // {comment}")
            else:
                out_lines.append(f"rom[{start_rom:4d}] ... rom[{end_rom:4d}] = 32'h00000000;  // {comment}")
        else:
            out_lines.append(f"rom[{rom_index:4d}] = 32'h{code:08x};  // {comment}")

    return '\n'.join(out_lines)


def parse_start_address(arg):
    """解析起始地址参数"""
    s = arg.strip()
    if s.startswith('0x') or s.startswith('0X'):
        return int(s, 16)
    elif s.startswith('0b') or s.startswith('0B'):
        return int(s[2:], 2)
    else:
        return int(s)


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='RISC-V Assembly → Plain Hex Converter',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python asm_to_hex.py input.s output.hex
  python asm_to_hex.py input.s               # 输出到 stdout
  python asm_to_hex.py input.s --rom         # 输出 Verilog ROM 格式
  python asm_to_hex.py input.s --base 0x100  # 指定起始地址
        """
    )
    parser.add_argument('input', help='输入汇编文件 (.s/.S)')
    parser.add_argument('output', nargs='?', default=None,
                        help='输出 hex 文件 (省略则输出到 stdout)')
    parser.add_argument('--base', default='0x0000',
                        help='起始地址 (默认 0x0000)')
    parser.add_argument('--rom', action='store_true',
                        help='输出 Verilog ROM 格式 (rom[i]=32\'hXXXXX;) 而非纯 hex')

    args = parser.parse_args()

    # 解析起始地址
    start_addr = parse_start_address(args.base)

    # 读取输入文件（自动尝试多种编码）
    lines = None
    for enc in ['utf-8', 'gbk', 'gb2312', 'latin-1']:
        try:
            with open(args.input, 'r', encoding=enc) as f:
                lines = f.readlines()
            break
        except (UnicodeDecodeError, UnicodeError):
            continue
        except FileNotFoundError:
            print(f"错误: 找不到文件 '{args.input}'", file=sys.stderr)
            sys.exit(1)
    if lines is None:
        print(f"错误: 无法以任何编码读取文件 '{args.input}'", file=sys.stderr)
        sys.exit(1)

    # 汇编
    if args.rom:
        output = assemble_to_rom(lines, start_addr)
    else:
        output = assemble_to_hex(lines, start_addr)

    # 输出
    if args.output and args.output != '-':
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(output)
            f.write('\n')
        print(f"已生成: {args.output}  (起始地址 0x{start_addr:08X}, {len(output.splitlines())} 个字)",
              file=sys.stderr)
    else:
        print(output)


if __name__ == '__main__':
    main()
