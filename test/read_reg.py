import json

def parse_file(file_path):
    """
    解析文件，将每个 block 的数据转换为字典格式。
    每个 block 的格式：
      第一行：cycle
      第二行：表头（以 | 分隔的 key 列表）
      后续连续的以 | 开头的行为数据行
    返回一个 block 列表，每个 block 为字典 { 'cycle': ..., 'keys': [...], 'rows': [...] }
    """
    blocks = []
    with open(file_path, 'r', encoding='utf-8') as f:
        # 读取所有非空行，去除首尾空白
        lines = [line.strip() for line in f if line.strip()]
    
    i = 0
    while i < len(lines):
        # 第一行为 cycle
        cycle = lines[i]
        i += 1

        # 第二行为表头，要求以 "|" 开头
        if i >= len(lines) or not lines[i].startswith('|'):
            print(f"第 {i+1} 行未发现表头，跳过当前 block")
            continue
        header_line = lines[i]
        i += 1

        # 去掉首尾的 "|" 后按 "|" 分割，并去除多余空格
        keys = [k.strip() for k in header_line.strip('|').split('|') if k.strip()]

        rows = []
        # 后续所有以 "|" 开头的行为数据行
        while i < len(lines) and lines[i].startswith('|'):
            row_line = lines[i]
            i += 1
            values = [v.strip() for v in row_line.strip('|').split('|')]
            # 将 key 与 value 组合成字典
            row_dict = dict(zip(keys, values))
            rows.append(row_dict)
        
        block = {'cycle': cycle, 'keys': keys, 'rows': rows}
        blocks.append(block)
    
    return blocks

def save_blocks_to_file(blocks, output_file):
    """
    将解析后的 block 数据存储到 JSON 文件中
    """
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(blocks, f, ensure_ascii=False, indent=2)
    print(f"成功将 {len(blocks)} 个 block 保存到 {output_file}")

if __name__ == '__main__':
    # 要解析的文件类型列表，例如 rs 和 bu
    file_types = ['rs', 'bu','rob','fl','mt']
    for file_type in file_types:
        file_path = f'../{file_type}.txt'   # 输入文件路径，根据实际情况调整
        output_file = f'parsed_{file_type}.json'
        try:
            blocks = parse_file(file_path)
            print(f"从 {file_path} 解析到 {len(blocks)} 个 block")
            save_blocks_to_file(blocks, output_file)
        except Exception as e:
            print(f"处理文件 {file_path} 时发生错误：{e}")
