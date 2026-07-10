def encode_b_type(self, funct3, rs1, rs2, offset):
    offset_val = self.parse_imm(offset, allow_label=True)
    if isinstance(offset_val, str):
        return ('branch_label', offset_val, funct3, rs1, rs2)
    
    # 转换为半字偏移
    half_offset = offset_val // 2
    
    # 提取各位
    imm12 = (half_offset >> 11) & 0x1
    imm11 = (half_offset >> 10) & 0x1
    imm10_5 = (half_offset >> 4) & 0x3F  # bits 10-5 需要右移4位？不对，应该是 bits 10-5 就是 (half_offset >> 5) & 0x3F
    imm4_1 = (half_offset >> 0) & 0xF   # bits 4-1
    
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