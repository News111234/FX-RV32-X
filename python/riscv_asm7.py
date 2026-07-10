#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
================================================================================
                    RISC-V 完整汇编器 - 最终版 v16
================================================================================
说明：
  - 完全适配你的 CPU：jal/branch 指令直接使用字节偏移（不除以2，不乘以2）
  - 支持所有 RV32I 指令, CSR 指令, 伪指令, 数据定义, 标签跳转
  - 字符常量 'H', 'e', 'l', 'o', ' ' (空格), '\n', '\r', '\t'
  - %hi()/%lo() 操作符
  - 输出与官方 RISC-V 工具链一致的机器码格式（立即数为字节偏移）
================================================================================
"""

import re
import sys

class FullRISCVAssembler:
    def __init__(self):
        # 寄存器映射
        self.reg_map = {
            'x0': 0, 'x1': 1, 'x2': 2, 'x3': 3, 'x4': 4, 'x5': 5, 'x6': 6, 'x7': 7,
            'x8': 8, 'x9': 9, 'x10': 10, 'x11': 11, 'x12': 12, 'x13': 13, 'x14': 14,
            'x15': 15, 'x16': 16, 'x17': 17, 'x18': 18, 'x19': 19, 'x20': 20,
            'x21': 21, 'x22': 22, 'x23': 23, 'x24': 24, 'x25': 25, 'x26': 26,
            'x27': 27, 'x28': 28, 'x29': 29, 'x30': 30, 'x31': 31,
            
            'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
            't0': 5, 't1': 6, 't2': 7, 's0': 8, 'fp': 8,
            's1': 9, 'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13,
            'a4': 14, 'a5': 15, 'a6': 16, 'a7': 17,
            's2': 18, 's3': 19, 's4': 20, 's5': 21, 's6': 22,
            's7': 23, 's8': 24, 's9': 25, 's10': 26, 's11': 27,
            't3': 28, 't4': 29, 't5': 30, 't6': 31,
        }
        
        # CSR寄存器映射
        self.csr_map = {
            'mstatus': 0x300, 'misa': 0x301, 'mie': 0x304, 'mtvec': 0x305,
            'mscratch': 0x340, 'mepc': 0x341, 'mcause': 0x342, 'mtval': 0x343,
            'mip': 0x344, 'mcycle': 0xB00, 'minstret': 0xB02,
            'sstatus': 0x100, 'sie': 0x104, 'stvec': 0x105,
            'sscratch': 0x140, 'sepc': 0x141, 'scause': 0x142, 'stval': 0x143,
            'sip': 0x144, 'satp': 0x180,
        }
        
        # 常量定义表
        self.constants = {}
        
        # 标签地址表
        self.labels = {}
        
        # 当前地址
        self.current_addr = 0
        
        # 输出结果
        self.results = []
    
    def remove_comments(self, line):
        if '//' in line:
            line = line[:line.index('//')]
        if '#' in line:
            line = line[:line.index('#')]
        return line.strip()
    
    def parse_char(self, char_str):
        char_str = char_str.strip()
        
        if char_str.startswith("'") and char_str.endswith("'"):
            inner = char_str[1:-1]
            
            if len(inner) == 0:
                return 0x00
            
            if len(inner) >= 2 and inner[0] == '\\':
                escape = inner[1]
                if escape == 'n':
                    return 0x0A
                elif escape == 'r':
                    return 0x0D
                elif escape == 't':
                    return 0x09
                elif escape == '0':
                    return 0x00
                elif escape == "'":
                    return 0x27
                elif escape == '"':
                    return 0x22
                elif escape == '\\':
                    return 0x5C
                elif escape == 'x':
                    if len(inner) >= 4:
                        return int(inner[2:4], 16)
                return ord(escape)
            
            if len(inner) >= 1:
                return ord(inner[0])
        
        return None
    
    def parse_expression(self, expr_str):
        expr_str = expr_str.strip()
        
        char_val = self.parse_char(expr_str)
        if char_val is not None:
            return char_val
        
        hi_match = re.match(r'%hi\((.*)\)', expr_str)
        if hi_match:
            inner = hi_match.group(1).strip()
            val = self.parse_expression(inner)
            if isinstance(val, int):
                return (val >> 12) & 0xFFFFF
            return val
        
        lo_match = re.match(r'%lo\((.*)\)', expr_str)
        if lo_match:
            inner = lo_match.group(1).strip()
            val = self.parse_expression(inner)
            if isinstance(val, int):
                lo = val & 0xFFF
                if lo > 0x7FF:
                    lo -= 0x1000
                return lo
            return val
        
        shift_match = re.match(r'\(?\s*(\d+)\s*<<\s*(\d+)\s*\)?', expr_str)
        if shift_match:
            val = int(shift_match.group(1))
            shift = int(shift_match.group(2))
            return val << shift
        
        if expr_str in self.constants:
            return self.constants[expr_str]
        
        if expr_str.startswith('0x') or expr_str.startswith('0X'):
            return int(expr_str, 16)
        if expr_str.startswith('0b') or expr_str.startswith('0B'):
            return int(expr_str[2:], 2)
        
        try:
            if '+' in expr_str:
                parts = expr_str.split('+')
                return sum(self.parse_expression(p.strip()) for p in parts)
            if '|' in expr_str:
                parts = expr_str.split('|')
                result = 0
                for p in parts:
                    result |= self.parse_expression(p.strip())
                return result
            if '&' in expr_str:
                parts = expr_str.split('&')
                result = self.parse_expression(parts[0].strip())
                for p in parts[1:]:
                    result &= self.parse_expression(p.strip())
                return result
            if '-' in expr_str and not expr_str.startswith('-'):
                parts = expr_str.split('-')
                val = self.parse_expression(parts[0].strip())
                for p in parts[1:]:
                    val -= self.parse_expression(p.strip())
                return val
            return int(expr_str)
        except ValueError:
            return expr_str
    
    def parse_reg(self, reg_str):
        reg_str = reg_str.strip().lower()
        if reg_str in self.reg_map:
            return self.reg_map[reg_str]
        raise ValueError(f"无效寄存器: {reg_str}")
    
    def parse_imm(self, imm_str, allow_label=False):
        imm_str = imm_str.strip()
        
        expr_val = self.parse_expression(imm_str)
        
        if isinstance(expr_val, int):
            return expr_val
        
        if expr_val in self.constants:
            return self.constants[expr_val]
        
        if allow_label and re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', expr_val):
            return expr_val
        
        raise ValueError(f"无效立即数: {imm_str}")
    
    def parse_memory(self, mem_str):
        mem_str = mem_str.strip()
        
        for name, val in self.constants.items():
            if name in mem_str:
                mem_str = mem_str.replace(name, str(val))
        
        match = re.match(r'^(-?0x[0-9a-fA-F]+|-?\d+)?\((\w+)\)$', mem_str)
        if match:
            imm_str = match.group(1) if match.group(1) else '0'
            reg = match.group(2)
            return imm_str, reg
        
        if re.match(r'^[xst][0-9]+$', mem_str) or mem_str.lower() in self.reg_map:
            return '0', mem_str
        
        raise ValueError(f"无效内存操作数: {mem_str}")
    
    def expand_li(self, rd, imm_val):
        """展开 li 伪指令为 lui + addi (或单条 addi)。
        imm_val 是目标寄存器的完整 32 位值。
        """
        instructions = []

        if -2048 <= imm_val <= 2047:
            code = self.encode_i_type(0b0010011, 0x0, rd, 'zero', str(imm_val))
            instructions.append(code)
        else:
            # upper = bits[31:12] 的值 (即 lui 的立即数)
            upper = (imm_val + 0x800) >> 12
            lower = imm_val & 0xFFF
            if lower > 0x7FF:
                lower -= 0x1000

            if lower == 0:
                code = self.encode_u_type(0b0110111, rd, str(upper))
                instructions.append(code)
            else:
                code1 = self.encode_u_type(0b0110111, rd, str(upper))
                code2 = self.encode_i_type(0b0010011, 0x0, rd, rd, str(lower))
                instructions.extend([code1, code2])

        return instructions
    
    def encode_i_type(self, opcode, funct3, rd, rs1, imm, use_label=False):
        imm_val = self.parse_imm(imm, allow_label=use_label)
        if isinstance(imm_val, str):
            return ('label', imm_val, opcode, funct3, rd, rs1)
        
        if imm_val < 0:
            imm_val = (1 << 12) + imm_val
        imm_bits = imm_val & 0xFFF
        rd_num = self.parse_reg(rd)
        rs1_num = self.parse_reg(rs1)
        return (imm_bits << 20) | (rs1_num << 15) | (funct3 << 12) | (rd_num << 7) | opcode
    
    def encode_r_type(self, opcode, funct3, funct7, rd, rs1, rs2):
        rd_num = self.parse_reg(rd)
        rs1_num = self.parse_reg(rs1)
        rs2_num = self.parse_reg(rs2)
        return (funct7 << 25) | (rs2_num << 20) | (rs1_num << 15) | (funct3 << 12) | (rd_num << 7) | opcode
    
    def encode_s_type(self, funct3, rs2, rs1, imm):
        imm_val = self.parse_imm(imm)
        if isinstance(imm_val, str):
            raise ValueError(f"存储指令不能使用标签: {imm}")
        
        if imm_val < 0:
            imm_val = (1 << 12) + imm_val
        imm_11_5 = (imm_val >> 5) & 0x7F
        imm_4_0 = imm_val & 0x1F
        rs1_num = self.parse_reg(rs1)
        rs2_num = self.parse_reg(rs2)
        return (imm_11_5 << 25) | (rs2_num << 20) | (rs1_num << 15) | (funct3 << 12) | (imm_4_0 << 7) | 0b0100011
    
    def encode_u_type(self, opcode, rd, imm):
        """U型指令编码 (lui/auipc)。
        兼容两种汇编约定：
          1. 标准 RISC-V: lui t0, 0x10001 → bits[31:12]=0x10001 (寄存器=0x10001000)
          2. 完整值:     lui t0, 0x10001000 → 同上结果
        自动判断: 若 imm >= 2^20 则视为完整 32 位值并提取高 20 位。
        """
        rd_num = self.parse_reg(rd)
        imm_val = self.parse_imm(imm)
        if isinstance(imm_val, str):
            raise ValueError(f"U型指令不能使用标签: {imm}")
        # 若值 >= 2^20，视为完整 32 位值，提取 bits[31:12]
        if imm_val >= (1 << 20):
            imm_upper = (imm_val >> 12) & 0xFFFFF
        else:
            # 标准约定：值本身就是 bits[31:12]
            imm_upper = imm_val & 0xFFFFF
        return (imm_upper << 12) | (rd_num << 7) | opcode
    
    def encode_b_type(self, funct3, rs1, rs2, offset):
        """B型分支指令编码 - 直接使用字节偏移（不除以2）"""
        offset_val = self.parse_imm(offset, allow_label=True)
        if isinstance(offset_val, str):
            return ('branch_label', offset_val, funct3, rs1, rs2)
        
        # 直接使用字节偏移
        if offset_val < 0:
            offset_val = (1 << 13) + offset_val
        
        # 提取各个位
        shifted = offset_val >> 1
    
    # 从右移后的值中提取各位
        imm12 = (shifted >> 11) & 0x1
        imm11 = (shifted >> 10) & 0x1
        imm10_5 = (shifted >> 4) & 0x3F   # 注意：这里用 >>5 而不是 >>4
        imm4_1 = (shifted >> 0) & 0xF
        
        rs1_num = self.parse_reg(rs1)
        rs2_num = self.parse_reg(rs2)
        
        instruction = 0
        instruction |= (imm12 << 31)
        instruction |= (imm10_5 << 25)
        instruction |= (rs2_num << 20)
        instruction |= (rs1_num << 15)
        instruction |= (funct3 << 12)
        instruction |= (imm4_1 << 8)
        instruction |= (imm11 << 7)
        instruction |= 0b1100011
        
        return instruction
    
    def encode_j_type(self, opcode, rd, offset):
        """J型跳转指令编码。
        输入为字节偏移，内部转换为半字偏移后编码。
        与 resolve_label 的 J 型路径保持一致。
        """
        offset_val = self.parse_imm(offset, allow_label=True)
        if isinstance(offset_val, str):
            return ('jump_label', offset_val, opcode, rd)

        rd_num = self.parse_reg(rd)
        if offset_val < 0:
            offset_val = (1 << 21) + offset_val

        # 字节偏移 → 半字偏移 (与 resolve_label 一致)
        halfword = offset_val >> 1

        # 提取各个位
        imm20   = (halfword >> 19) & 0x1
        imm19_12 = (halfword >> 11) & 0xFF
        imm11    = (halfword >> 10) & 0x1
        imm10_1  = (halfword >>  0) & 0x3FF

        instruction = 0
        instruction |= (imm20 << 31)
        instruction |= (imm10_1 << 21)
        instruction |= (imm11 << 20)
        instruction |= (imm19_12 << 12)
        instruction |= (rd_num << 7)
        instruction |= opcode

        return instruction
    
    def encode_csr_type(self, funct3, rd, csr, rs1=None, uimm=None):
        csr_str = csr.strip().lower()
        if csr_str in self.constants:
            csr_num = self.constants[csr_str]
        elif csr_str in self.csr_map:
            csr_num = self.csr_map[csr_str]
        else:
            csr_num = self.parse_imm(csr_str)
        rd_num = self.parse_reg(rd)
        if rs1 is not None:
            rs1_num = self.parse_reg(rs1)
            return (csr_num << 20) | (rs1_num << 15) | (funct3 << 12) | (rd_num << 7) | 0b1110011
        else:
            uimm_val = self.parse_imm(uimm) & 0x1F
            return (csr_num << 20) | (uimm_val << 15) | (funct3 << 12) | (rd_num << 7) | 0b1110011
    
    def assemble_instruction(self, line):
        line = self.remove_comments(line)
        if not line:
            return None, False
        
        parts = re.split(r'[,\s]+', line)
        mnemonic = parts[0].lower()
        
        # 伪指令
        if mnemonic == 'nop':
            return 0x00000013, False
        if mnemonic == 'ret':
            return self.encode_i_type(0b1100111, 0x0, 'zero', 'ra', '0'), False
        if mnemonic == 'jr':
            rs = parts[1] if len(parts) > 1 else 'ra'
            return self.encode_i_type(0b1100111, 0x0, 'zero', rs, '0'), False
        if mnemonic == 'j':
            return self.encode_j_type(0b1101111, 'zero', parts[1]), False
        if mnemonic == 'jal':
            if len(parts) == 2:
                return self.encode_j_type(0b1101111, 'ra', parts[1]), False
            else:
                return self.encode_j_type(0b1101111, parts[1], parts[2]), False
        if mnemonic == 'jalr':
            if len(parts) == 3:
                rd, rs = parts[1], parts[2]
                imm = '0'
            elif len(parts) == 2:
                rd, rs = 'ra', parts[1]
                imm = '0'
            else:
                rd, rs = parts[1], parts[2]
                imm = '0'
            if '(' in rs:
                imm, rs = self.parse_memory(rs)
            return self.encode_i_type(0b1100111, 0x0, rd, rs, imm), False
        if mnemonic == 'call':
            return self.encode_j_type(0b1101111, 'ra', parts[1]), False
        if mnemonic == 'tail':
            return self.encode_j_type(0b1101111, 'zero', parts[1]), False
        if mnemonic == 'la':
            # la rd, symbol → lui rd, %hi(symbol) + addi rd, rd, %lo(symbol)
            rd, symbol = parts[1], parts[2]
            return ('la_label', symbol, rd), False
        
        # 分支伪指令
        if mnemonic == 'beqz':
            rs, offset = parts[1], parts[2]
            return self.encode_b_type(0x0, rs, 'zero', offset), False
        if mnemonic == 'bnez':
            rs, offset = parts[1], parts[2]
            return self.encode_b_type(0x1, rs, 'zero', offset), False
        if mnemonic == 'blez':
            rs, offset = parts[1], parts[2]
            return self.encode_b_type(0x4, 'zero', rs, offset), False
        if mnemonic == 'bgez':
            rs, offset = parts[1], parts[2]
            return self.encode_b_type(0x5, rs, 'zero', offset), False
        if mnemonic == 'bltz':
            rs, offset = parts[1], parts[2]
            return self.encode_b_type(0x4, rs, 'zero', offset), False
        if mnemonic == 'bgtz':
            rs, offset = parts[1], parts[2]
            return self.encode_b_type(0x5, 'zero', rs, offset), False
        
        # U型指令
        if mnemonic == 'lui':
            return self.encode_u_type(0b0110111, parts[1], parts[2]), False
        if mnemonic == 'auipc':
            return self.encode_u_type(0b0010111, parts[1], parts[2]), False
        
        # I型指令
        i_type_map = {
            'addi': (0b0010011, 0x0), 'andi': (0b0010011, 0x7),
            'ori': (0b0010011, 0x6), 'xori': (0b0010011, 0x4),
            'slli': (0b0010011, 0x1), 'srli': (0b0010011, 0x5),
            'srai': (0b0010011, 0x5), 'slti': (0b0010011, 0x2),
            'sltiu': (0b0010011, 0x3),
            'lb': (0b0000011, 0x0), 'lh': (0b0000011, 0x1),
            'lw': (0b0000011, 0x2), 'lbu': (0b0000011, 0x4),
            'lhu': (0b0000011, 0x5),
        }
        
        if mnemonic in i_type_map:
            opcode, funct3 = i_type_map[mnemonic]
            if mnemonic in ['lb', 'lh', 'lw', 'lbu', 'lhu']:
                rd, mem = parts[1], parts[2]
                imm, rs1 = self.parse_memory(mem)
                return self.encode_i_type(opcode, funct3, rd, rs1, imm), False
            elif mnemonic in ['slli', 'srli', 'srai']:
                rd, rs1, shamt = parts[1], parts[2], parts[3]
                imm_val = self.parse_imm(shamt)
                if mnemonic == 'srai':
                    imm_val |= 0x400
                return self.encode_i_type(opcode, funct3, rd, rs1, str(imm_val)), False
            else:
                rd, rs1, imm = parts[1], parts[2], parts[3]
                return self.encode_i_type(opcode, funct3, rd, rs1, imm, use_label=(mnemonic == 'jalr')), False
        
        # R型指令
        r_type_map = {
            'add': (0b0110011, 0x0, 0x00), 'sub': (0b0110011, 0x0, 0x20),
            'sll': (0b0110011, 0x1, 0x00), 'slt': (0b0110011, 0x2, 0x00),
            'sltu': (0b0110011, 0x3, 0x00), 'xor': (0b0110011, 0x4, 0x00),
            'srl': (0b0110011, 0x5, 0x00), 'sra': (0b0110011, 0x5, 0x20),
            'or': (0b0110011, 0x6, 0x00), 'and': (0b0110011, 0x7, 0x00),
        }
        
        if mnemonic in r_type_map:
            opcode, funct3, funct7 = r_type_map[mnemonic]
            rd, rs1, rs2 = parts[1], parts[2], parts[3]
            return self.encode_r_type(opcode, funct3, funct7, rd, rs1, rs2), False
        
        # S型指令
        if mnemonic in ['sb', 'sh', 'sw']:
            funct3_map = {'sb': 0x0, 'sh': 0x1, 'sw': 0x2}
            rs2, mem = parts[1], parts[2]
            imm, rs1 = self.parse_memory(mem)
            return self.encode_s_type(funct3_map[mnemonic], rs2, rs1, imm), False
        
        # B型指令
        if mnemonic in ['beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu']:
            funct3_map = {'beq': 0x0, 'bne': 0x1, 'blt': 0x4, 'bge': 0x5, 'bltu': 0x6, 'bgeu': 0x7}
            rs1, rs2, offset = parts[1], parts[2], parts[3]
            return self.encode_b_type(funct3_map[mnemonic], rs1, rs2, offset), False
        
        # CSR指令
        if mnemonic == 'csrrw':
            return self.encode_csr_type(0x1, parts[1], parts[2], rs1=parts[3]), False
        if mnemonic == 'csrrs':
            return self.encode_csr_type(0x2, parts[1], parts[2], rs1=parts[3]), False
        if mnemonic == 'csrrc':
            return self.encode_csr_type(0x3, parts[1], parts[2], rs1=parts[3]), False
        if mnemonic == 'csrrwi':
            return self.encode_csr_type(0x5, parts[1], parts[2], uimm=parts[3]), False
        if mnemonic == 'csrrsi':
            return self.encode_csr_type(0x6, parts[1], parts[2], uimm=parts[3]), False
        if mnemonic == 'csrrci':
            return self.encode_csr_type(0x7, parts[1], parts[2], uimm=parts[3]), False
        
        # CSR伪指令
        if mnemonic == 'csrr':
            return self.encode_csr_type(0x2, parts[1], parts[2], rs1='zero'), False
        if mnemonic == 'csrw':
            return self.encode_csr_type(0x1, 'zero', parts[1], rs1=parts[2]), False
        if mnemonic == 'csrs':
            return self.encode_csr_type(0x2, 'zero', parts[1], rs1=parts[2]), False
        if mnemonic == 'csrc':
            return self.encode_csr_type(0x3, 'zero', parts[1], rs1=parts[2]), False
        if mnemonic == 'csrwi':
            return self.encode_csr_type(0x5, 'zero', parts[1], uimm=parts[2]), False
        if mnemonic == 'csrsi':
            return self.encode_csr_type(0x6, 'zero', parts[1], uimm=parts[2]), False
        if mnemonic == 'csrci':
            return self.encode_csr_type(0x7, 'zero', parts[1], uimm=parts[2]), False
        
        # 系统指令
        if mnemonic == 'ecall':
            return 0x00000073, False
        if mnemonic == 'ebreak':
            return 0x00100073, False
        if mnemonic == 'mret':
            return 0x30200073, False
        if mnemonic == 'sret':
            return 0x30200073, False
        if mnemonic == 'wfi':
            return 0x10500073, False
        
        # li伪指令
        if mnemonic == 'li':
            rd, imm = parts[1], parts[2]
            imm_val = self.parse_imm(imm)
            if isinstance(imm_val, int):
                instructions = self.expand_li(rd, imm_val)
                return instructions, True
        
        # mv伪指令
        if mnemonic == 'mv':
            rd, rs = parts[1], parts[2]
            return self.encode_i_type(0b0010011, 0x0, rd, rs, '0'), False
        
        # not伪指令
        if mnemonic == 'not':
            rd, rs = parts[1], parts[2]
            return self.encode_i_type(0b0010011, 0x4, rd, rs, '-1'), False
        
        # neg伪指令
        if mnemonic == 'neg':
            rd, rs = parts[1], parts[2]
            return self.encode_r_type(0b0110011, 0x0, 0x20, rd, 'zero', rs), False
        
        raise ValueError(f"不支持的指令: {mnemonic}")
    
    def is_directive(self, line):
        directives = ['.section', '.text', '.data', '.bss', '.globl', '.global',
                      '.align', '.org', '.equ', '.byte', '.word', '.ascii', 
                      '.asciz', '.space']
        for d in directives:
            if line.startswith(d):
                return True
        return False
    
    def process_directive(self, line):
        line = self.remove_comments(line)
        if not line:
            return True
        
        if line.startswith('.section') or line.startswith('.text') or \
           line.startswith('.data') or line.startswith('.bss') or \
           line.startswith('.globl') or line.startswith('.global'):
            return True
        
        return False
    
    def process_equ(self, line):
        line = self.remove_comments(line)
        if not line:
            return False
        
        match = re.match(r'\.equ\s+(\w+)\s*,\s*(.+)', line)
        if match:
            name = match.group(1)
            value_str = match.group(2).strip()
            self.constants[name] = self.parse_expression(value_str)
            return True
        return False
    
    def process_data(self, line):
        line_stripped = self.remove_comments(line)
        if not line_stripped:
            return False
        
        if line_stripped.startswith('.byte'):
            data_str = line_stripped[5:].strip()
            for part in data_str.split(','):
                val = self.parse_imm(part.strip())
                self.results.append((self.current_addr, val, f".byte {part.strip()}"))
                self.current_addr += 1
            return True
        
        if line_stripped.startswith('.word'):
            data_str = line_stripped[5:].strip()
            for part in data_str.split(','):
                val = self.parse_imm(part.strip())
                self.results.append((self.current_addr, val, f".word {part.strip()}"))
                self.current_addr += 4
            return True
        
        if line_stripped.startswith('.ascii'):
            match = re.search(r'\.ascii\s+"([^"]*)"', line_stripped)
            if match:
                for ch in match.group(1):
                    self.results.append((self.current_addr, ord(ch), ".ascii"))
                    self.current_addr += 1
            return True
        
        if line_stripped.startswith('.asciz'):
            match = re.search(r'\.asciz\s+"([^"]*)"', line_stripped)
            if match:
                for ch in match.group(1):
                    self.results.append((self.current_addr, ord(ch), ".asciz"))
                    self.current_addr += 1
                self.results.append((self.current_addr, 0, ".asciz null"))
                self.current_addr += 1
            return True
        
        if line_stripped.startswith('.space'):
            match = re.match(r'\.space\s+(\d+)', line_stripped)
            if match:
                size = int(match.group(1))
                self.results.append((self.current_addr, size, f".space {size} bytes"))
                self.current_addr += size
            return True
        
        return False
    
    def is_label_line(self, line):
        clean_line = self.remove_comments(line)
        if not clean_line:
            return False
        if clean_line.endswith(':'):
            return True
        match = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*):', clean_line)
        return match is not None
    
    def extract_label(self, line):
        clean_line = self.remove_comments(line)
        if not clean_line:
            return None
        if clean_line.endswith(':'):
            return clean_line[:-1].strip()
        match = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*):', clean_line)
        if match:
            return match.group(1)
        return None
    
    def extract_instruction(self, line):
        no_comment = self.remove_comments(line)
        if not no_comment:
            return None
        match = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*):\s*(.*)$', no_comment)
        if match:
            instr = match.group(2).strip()
            if not instr or instr.startswith('//') or instr.startswith('#'):
                return None
            return instr
        return no_comment
    
    def resolve_label(self, result, addr):
        """解析标签，返回实际编码（或 la_label 时返回指令列表）"""
        if isinstance(result, tuple) and len(result) >= 1 and result[0] == 'la_label':
            # la rd, symbol → lui rd, %hi(addr) + addi rd, rd, %lo(addr)
            _, label, rd = result
            if label in self.labels:
                target_addr = self.labels[label]
                upper = (target_addr + 0x800) >> 12
                lower = target_addr & 0xFFF
                if lower > 0x7FF:
                    lower -= 0x1000
                lui_inst = self.encode_u_type(0b0110111, rd, str(upper))
                if lower == 0:
                    return [lui_inst]
                addi_inst = self.encode_i_type(0b0010011, 0x0, rd, rd, str(lower))
                return [lui_inst, addi_inst]
            else:
                raise ValueError(f"未定义的标签: {label}")

        if isinstance(result, tuple):
            if result[0] == 'label':
                _, label, opcode, funct3, rd, rs1 = result
                if label in self.labels:
                    byte_offset = self.labels[label] - addr
                    if byte_offset < 0:
                        byte_offset = (1 << 12) + byte_offset
                    imm_bits = byte_offset & 0xFFF
                    rd_num = self.parse_reg(rd)
                    rs1_num = self.parse_reg(rs1)
                    return (imm_bits << 20) | (rs1_num << 15) | (funct3 << 12) | (rd_num << 7) | opcode
                else:
                    raise ValueError(f"未定义的标签: {label}")
            
            elif result[0] == 'branch_label':
                _, label, funct3, rs1, rs2 = result
                if label in self.labels:
                    byte_offset = self.labels[label] - addr
                    
                  # 分支指令的立即数以 2 字节为单位，必须右移 1 位
                    offset = byte_offset >> 1
                    if offset < 0:
                        offset = (1 << 12) + offset
                    
                    imm12 = (offset >> 11) & 0x1
                    imm11 = (offset >> 10) & 0x1
                    imm10_5 = (offset >> 4) & 0x3F
                    imm4_1 = (offset >> 0) & 0xF
                    
                    rs1_num = self.parse_reg(rs1)
                    rs2_num = self.parse_reg(rs2)
                    
                    instruction = 0
                    instruction |= (imm12 << 31)
                    instruction |= (imm10_5 << 25)
                    instruction |= (rs2_num << 20)
                    instruction |= (rs1_num << 15)
                    instruction |= (funct3 << 12)
                    instruction |= (imm4_1 << 8)
                    instruction |= (imm11 << 7)
                    instruction |= 0b1100011
                    
                    return instruction
                else:
                    raise ValueError(f"未定义的标签: {label}")
            
            elif result[0] == 'jump_label':
                _, label, opcode, rd = result
                if label in self.labels:
                    byte_offset = self.labels[label] - addr
                    
                   # 跳转指令的立即数以 2 字节为单位，右移 1 位
                    offset = byte_offset >> 1

                    if offset < 0:
                        offset = (1 << 20) + offset
                    
                    imm20 = (offset >> 19) & 0x1
                    imm19_12 = (offset >> 11) & 0xFF
                    imm11 = (offset >> 10) & 0x1
                    imm10_1 = (offset >> 0) & 0x3FF
                    
                    rd_num = self.parse_reg(rd)
                    
                    instruction = 0
                    instruction |= (imm20 << 31)
                    instruction |= (imm10_1 << 21)
                    instruction |= (imm11 << 20)
                    instruction |= (imm19_12 << 12)
                    instruction |= (rd_num << 7)
                    instruction |= opcode
                    
                    return instruction
                else:
                    raise ValueError(f"未定义的标签: {label}")
        
        return result
    
    def assemble_program(self, lines, start_addr=0):
        """汇编整个程序（两遍扫描）"""
        self.current_addr = start_addr
        self.results = []
        self.constants = {}
        self.labels = {}
        
        # 第一遍：收集常量定义和标签地址
        temp_addr = start_addr
        for line in lines:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            if self.process_equ(line):
                continue
            
            clean_line = self.remove_comments(line)
            if not clean_line:
                continue
            
            # 跳过汇编器指令
            if self.process_directive(clean_line):
                continue
            
            if clean_line.startswith('.org'):
                match = re.match(r'\.org\s+(.+)', clean_line)
                if match:
                    addr_str = match.group(1).strip()
                    temp_addr = self.parse_imm(addr_str)
                continue
            
            if clean_line.startswith('.align'):
                match = re.match(r'\.align\s+(\d+)', clean_line)
                if match:
                    align = int(match.group(1))
                    if temp_addr % (1 << align) != 0:
                        temp_addr = ((temp_addr >> align) + 1) << align
                continue
            
            # 处理标签
            if self.is_label_line(line):
                label = self.extract_label(line)
                if label:
                    self.labels[label] = temp_addr
                instr = self.extract_instruction(line)
                if instr:
                    # la 伪指令展开为 2 条指令 (lui + addi)
                    if instr.lower().startswith('la '):
                        temp_addr += 8
                    elif instr.lower().startswith('li '):
                        parts = re.split(r'[,\s]+', instr)
                        if len(parts) >= 3:
                            try:
                                imm_val = self.parse_imm(parts[2])
                                if isinstance(imm_val, int):
                                    if -2048 <= imm_val <= 2047:
                                        temp_addr += 4
                                    elif (imm_val & 0xFFF) == 0:
                                        temp_addr += 4
                                    else:
                                        temp_addr += 8
                                else:
                                    temp_addr += 4
                            except:
                                temp_addr += 4
                        else:
                            temp_addr += 4
                    else:
                        temp_addr += 4
                continue
            
            # 处理数据定义
            if clean_line.startswith('.byte'):
                data_str = clean_line[5:].strip()
                for part in data_str.split(','):
                    temp_addr += 1
                continue
            if clean_line.startswith('.word'):
                data_str = clean_line[5:].strip()
                for part in data_str.split(','):
                    temp_addr += 4
                continue
            if clean_line.startswith('.ascii'):
                match = re.search(r'\.ascii\s+"([^"]*)"', clean_line)
                if match:
                    temp_addr += len(match.group(1))
                continue
            if clean_line.startswith('.asciz'):
                match = re.search(r'\.asciz\s+"([^"]*)"', clean_line)
                if match:
                    temp_addr += len(match.group(1)) + 1
                continue
            if clean_line.startswith('.space'):
                match = re.match(r'\.space\s+(\d+)', clean_line)
                if match:
                    temp_addr += int(match.group(1))
                continue
            
            # 普通指令 — li/la 伪指令可能展开为多条指令
            clean_lower = clean_line.lower()
            if clean_lower.startswith('la '):
                # la rd, symbol → lui + addi (总是 2 条, 8 字节)
                temp_addr += 8
            elif clean_lower.startswith('li '):
                parts = re.split(r'[,\s]+', clean_line)
                if len(parts) >= 3:
                    try:
                        imm_val = self.parse_imm(parts[2])
                        if isinstance(imm_val, int):
                            if -2048 <= imm_val <= 2047:
                                temp_addr += 4          # single addi
                            elif (imm_val & 0xFFF) == 0:
                                temp_addr += 4          # single lui (lower 12 bits are 0)
                            else:
                                temp_addr += 8          # lui + addi
                        else:
                            temp_addr += 4
                    except:
                        temp_addr += 4
                else:
                    temp_addr += 4
            else:
                temp_addr += 4
        
        # 重置地址
        self.current_addr = start_addr
        
        # 第二遍：生成机器码
        for line in lines:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            if self.process_equ(line):
                continue
            
            clean_line = self.remove_comments(line)
            if not clean_line:
                continue
            
            # 跳过汇编器指令
            if self.process_directive(clean_line):
                continue
            
            if clean_line.startswith('.org'):
                match = re.match(r'\.org\s+(.+)', clean_line)
                if match:
                    addr_str = match.group(1).strip()
                    self.current_addr = self.parse_imm(addr_str)
                continue
            
            if clean_line.startswith('.align'):
                match = re.match(r'\.align\s+(\d+)', clean_line)
                if match:
                    align = int(match.group(1))
                    if self.current_addr % (1 << align) != 0:
                        self.current_addr = ((self.current_addr >> align) + 1) << align
                continue
            
            if self.process_data(line):
                continue
            
            if self.is_label_line(line):
                instr = self.extract_instruction(line)
                if not instr:
                    continue
                try:
                    result, expanded = self.assemble_instruction(instr)
                    if result is not None:
                        if expanded:
                            for code in result:
                                self.results.append((self.current_addr, code, instr))
                                self.current_addr += 4
                        else:
                            code = self.resolve_label(result, self.current_addr)
                            if isinstance(code, list):
                                for inst in code:
                                    self.results.append((self.current_addr, inst, instr))
                                    self.current_addr += 4
                            else:
                                self.results.append((self.current_addr, code, instr))
                                self.current_addr += 4
                except Exception as e:
                    print(f"警告: '{instr}' - {e}")
                continue

            try:
                result, expanded = self.assemble_instruction(clean_line)
                if result is not None:
                    if expanded:
                        for code in result:
                            self.results.append((self.current_addr, code, clean_line))
                            self.current_addr += 4
                    else:
                        code = self.resolve_label(result, self.current_addr)
                        if isinstance(code, list):
                            for inst in code:
                                self.results.append((self.current_addr, inst, clean_line))
                                self.current_addr += 4
                        else:
                            self.results.append((self.current_addr, code, clean_line))
                            self.current_addr += 4
            except Exception as e:
                print(f"警告: '{clean_line}' - {e}")
        
        return self.results


def parse_start_address(prompt="请输入起始地址"):
    while True:
        try:
            addr_input = input(f"{prompt} (直接回车使用默认 0x100): ").strip()
            if not addr_input:
                return 0x100
            if addr_input.startswith('0x') or addr_input.startswith('0X'):
                return int(addr_input, 16)
            elif addr_input.startswith('0b') or addr_input.startswith('0B'):
                return int(addr_input[2:], 2)
            else:
                return int(addr_input)
        except ValueError:
            print("输入无效，请输入有效的数字（如: 0, 0x0, 100, 0x100）")


def main():
    print("=" * 70)
    print("RISC-V 完整汇编器 - 最终版 v16")
    print("支持: 所有RV32I指令, CSR指令, 伪指令, 数据定义, 标签跳转")
    print("字符常量: 'H', 'e', 'l', 'o', ' ' (空格), '\\n', '\\r', '\\t'")
    print("立即数: jal/branch 指令直接使用字节偏移（适配您的CPU）")
    print("=" * 70)
    
    if len(sys.argv) > 1:
        try:
            with open(sys.argv[1], 'r', encoding='utf-8') as f:
                lines = f.readlines()
            print(f"从文件读取: {sys.argv[1]}")
        except Exception as e:
            print(f"读取文件失败: {e}")
            sys.exit(1)
    else:
        print("请输入汇编代码（输入空行结束）:")
        print("-" * 70)
        lines = []
        while True:
            try:
                line = input()
                if line.strip() == '' and len(lines) > 0:
                    break
                lines.append(line)
            except EOFError:
                break
    
    start_addr = parse_start_address()
    print(f"\n起始地址: 0x{start_addr:x}")
    
    assembler = FullRISCVAssembler()
    results = assembler.assemble_program(lines, start_addr)
    
    print("\n" + "=" * 70)
    print("生成的机器码:")
    print("=" * 70)
    
    if not results:
        print("没有生成任何机器码")
        return
    
    instr_count = 0
    data_bytes = 0
    
    for addr, code, comment in results:
        rom_index = addr // 4
        
        if isinstance(code, int) and code <= 0xFFFFFFFF:
            if isinstance(comment, str) and comment.startswith('.space'):
                size = code
                start_rom = addr // 4
                end_rom = (addr + size - 1) // 4
                if start_rom == end_rom:
                    print(f"rom[{start_rom:4d}] = 32'h00000000;  // {comment}")
                else:
                    print(f"rom[{start_rom:4d}] ... rom[{end_rom:4d}] = 32'h00000000;  // {comment}")
                data_bytes += size
            else:
                print(f"rom[{rom_index:4d}] = 32'h{code:08x};  // {comment}")
                instr_count += 1
        else:
            print(f"rom[{rom_index:4d}] = 32'h{code:08x};  // {comment}")
            data_bytes += 1
    
    print("\n" + "=" * 70)
    print(f"完成！共生成 {instr_count} 条指令, {data_bytes} 字节数据")
    print("=" * 70)


if __name__ == "__main__":
    main()
    # python riscv_asm7.py spi_test.s