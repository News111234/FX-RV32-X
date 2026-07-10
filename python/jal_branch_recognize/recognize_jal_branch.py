#!/usr/bin/env python3
"""
解析 RISC-V 32 位指令（十六进制），识别 J‑type 和 B‑type 指令，
在每个 J/B 指令后插入 2 条 NOP，生成连续编号的 inst_rom.txt 文件，
并输出分类索引、指令条数统计和 NOP 数量。
"""
import sys
import re

# RISC-V opcode (低 7 位)
JAL_OPCODE    = 0b1101111   # 0x6F  → J-type (jal)
BRANCH_OPCODE = 0b1100011   # 0x63  → B-type (beq/bne/blt/bge/bltu/bgeu)
NOP           = 0x00000013  # addi x0, x0, 0

def parse_input(text: str):
    """提取 (原始索引, 32位机器码) 列表，按索引排序"""
    pattern = re.compile(r'rom\s*\[\s*(\d+)\s*\]\s*=\s*32\s*\'\s*h\s*([0-9a-fA-F]+)\s*;')
    instructions = []
    for line in text.splitlines():
        line = line.lstrip('\ufeff')          # 去除 BOM
        match = pattern.search(line)
        if match:
            idx = int(match.group(1))
            code = int(match.group(2), 16)
            instructions.append((idx, code))
    instructions.sort(key=lambda x: x[0])
    return instructions

def classify_and_insert_nops(instructions):
    """
    分类，生成插入 NOP 后的连续指令序列。
    返回: (jal_indices, branch_indices, new_codes, nop_count)
    """
    jal_list = []
    branch_list = []
    new_codes = []
    nop_inserted = 0

    for orig_idx, code in instructions:
        new_codes.append(code)
        opcode = code & 0x7F
        if opcode == JAL_OPCODE:
            jal_list.append(orig_idx)
            # 插入两条 NOP
            new_codes.append(NOP)
            new_codes.append(NOP)
            nop_inserted += 2
        elif opcode == BRANCH_OPCODE:
            branch_list.append(orig_idx)
            new_codes.append(NOP)
            new_codes.append(NOP)
            nop_inserted += 2
        # 其他指令不处理

    return jal_list, branch_list, new_codes, nop_inserted

def write_inst_rom(codes, output_file='inst_rom.txt'):
    """将连续的机器码列表写入文件，索引从 0 开始"""
    with open(output_file, 'w', encoding='utf-8') as f:
        for i, code in enumerate(codes):
            f.write(f"rom[{i}]=32'h{code:08x};\n")
    print(f"\n已生成 {output_file}，共 {len(codes)} 条指令。")

def main():
    # ---------- 1. 读取输入 ----------
    text = None
    if len(sys.argv) > 1:
        input_file = sys.argv[1]
        try:
            with open(input_file, 'r', encoding='utf-8-sig') as f:
                text = f.read()
        except FileNotFoundError:
            print(f"错误：找不到文件 {input_file}")
            sys.exit(1)
    elif not sys.stdin.isatty():
        raw = sys.stdin.buffer.read()
        text = raw.decode('utf-8-sig')
    else:
        # 无输入时使用的内置示例（含您提供的 0～15 测试数据）
        sample = """\
rom[0]=32'hff010113;
rom[1]=32'h01212023;
rom[2]=32'h01c52903;
rom[3]=32'h00112623;
rom[4]=32'h02052c23;
rom[5]=32'h02052e23;
rom[6]=32'h04090e63;
rom[7]=32'h00812423;
rom[8]=32'h00912223;
rom[9]=32'h00050413;
rom[10]=32'h00000493;
rom[11]=32'h00100593;
rom[12]=32'h00040513;
rom[13]=32'h500000ef;
rom[14]=32'h03845583;
rom[15]=32'h0a9010ef;
"""
        print("未检测到输入，使用内置示例数据：")
        text = sample

    instructions = parse_input(text)
    print(f"\n共解析到 {len(instructions)} 条指令")
    if not instructions:
        print("未解析到任何有效的指令行。")
        sys.exit(1)

    # ---------- 2. 分类并插入 NOP ----------
    jal_indices, branch_indices, new_codes, nop_count = classify_and_insert_nops(instructions)

    # ---------- 3. 屏幕输出 ----------
    # 原有索引输出
    jal_str = ', '.join(str(i) for i in jal_indices) if jal_indices else '无'
    branch_str = ', '.join(str(i) for i in branch_indices) if branch_indices else '无'
    print(f"JAL型指令 (索引): {jal_str}")
    print(f"BRANCH型指令 (索引): {branch_str}")

    # 新增统计信息
    j_count = len(jal_indices)
    b_count = len(branch_indices)
    print(f"Jal型指令共有 {j_count} 条")
    print(f"B-type型指令共有 {b_count} 条")
    print(f"添加的NOP指令数: {nop_count} 条")

    # ---------- 4. 写入 inst_rom.txt ----------
    write_inst_rom(new_codes)

if __name__ == "__main__":
    main()
    #python recognize_jal_branch.py rom.txt