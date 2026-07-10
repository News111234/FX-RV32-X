import sys

def main():
    # 从命令行参数获取文件名，若无参数则从标准输入读取
    if len(sys.argv) > 1:
        with open(sys.argv[1], 'r') as f:
            lines = f.readlines()
    else:
        lines = sys.stdin.readlines()

    index = 0
    for line in lines:
        line = line.strip()
        if not line:               # 跳过空行
            continue
        # 一行内可能有多个机器码，按空白字符分割
        tokens = line.split()
        for token in tokens:
            # 去掉可选的 0x 或 0X 前缀
            if token.startswith('0x') or token.startswith('0X'):
                token = token[2:]
            # 输出固定格式（保留原十六进制的大小写）
            print(f"rom[{index}]=32'h{token};")
            index += 1

if __name__ == "__main__":
    main()
    #python gen_rom.py rom.txt > output.txt