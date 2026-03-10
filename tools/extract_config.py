#!/usr/bin/env python3
import sys
import os
import zlib
import argparse

def is_valid_config(data):
    """
    验证解压后的数据是否为内核配置文件（纯文本）
    """
    # 内核配置文件通常不可能小于 1KB
    if len(data) < 1024:
        return False
        
    # 必须包含典型的内核配置关键字
    if b'CONFIG_' not in data:
        return False

    # 抽取前 512 字节进行纯文本检测
    # 允许包含换行(\n, 10), 回车(\r, 13), 制表符(\t, 9)
    sample = data[:512]
    non_printable = sum(1 for b in sample if b < 32 and b not in (9, 10, 13))
    
    # 如果不可见字符超过一定阈值，说明不是纯文本文件
    if non_printable > 0:
        return False

    return True

def extract_ikconfig(image_path):
    """
    在二进制镜像中检索并提取所有的 config.gz 流
    """
    # GZIP 魔数: 1F 8B (gzip) 08 (deflate)
    GZIP_MAGIC = b'\x1f\x8b\x08'
    
    try:
        with open(image_path, 'rb') as f:
            # 对于几百MB以内的内核/boot镜像，直接读入内存分析是最快的
            data = f.read()
    except FileNotFoundError:
        print(f"错误: 找不到文件 '{image_path}'")
        sys.exit(1)

    print(f"[*] 正在分析文件: {image_path} (大小: {len(data) / 1024 / 1024:.2f} MB)")
    
    offset = 0
    configs_found = []

    while True:
        # 查找 GZIP 魔数
        offset = data.find(GZIP_MAGIC, offset)
        if offset == -1:
            break

        # zlib.decompressobj 的 wbits 设置为 31 (15 + 16) 可以处理 gzip header
        decompressor = zlib.decompressobj(wbits=31)
        
        try:
            # 截取从魔数开始的数据块。
            # 限制单次最大读取 10MB，这对于 config.gz（压缩后通常只有几十KB）来说绰绰有余
            chunk = data[offset:offset + 10 * 1024 * 1024]
            decompressed = decompressor.decompress(chunk)
            
            # 如果解压成功且数据有意义，进行文本特征验证
            if decompressed and is_valid_config(decompressed):
                configs_found.append(decompressed)
                print(f"[+] 发现有效配置清单！(位于偏移量: {hex(offset)})")
                
        except zlib.error:
            # 因为二进制文件中可能会随机出现 1f 8b 08，这会导致 zlib 抛出异常。
            # 我们直接忽略这些误报（False Positives）即可。
            pass

        # 前进 1 字节，继续向下搜索
        offset += 1

    return configs_found

def main():
    parser = argparse.ArgumentParser(description="从内核镜像或 boot.img 中免引导提取 config.gz")
    parser.add_argument("image", help="输入的内核镜像文件 (如 boot.img, Image, vmlinux 等)")
    args = parser.parse_args()

    configs = extract_ikconfig(args.image)

    if not configs:
        print("[-] 未能在镜像中找到有效的内核配置清单。可能是内核编译时未开启 CONFIG_IKCONFIG。")
        sys.exit(0)

    # 处理输出文件的命名规则
    if len(configs) == 1:
        filename = "config"
        with open(filename, 'wb') as f:
            f.write(configs[0])
        print(f"[*] 提取成功，已保存至: {filename}")
    else:
        print(f"[*] 镜像中存在多个匹配的配置文件，共 {len(configs)} 个。")
        for i, config_data in enumerate(configs, start=1):
            filename = f"config_{i}"
            with open(filename, 'wb') as f:
                f.write(config_data)
            print(f"[*] 提取成功，已保存至: {filename}")

if __name__ == "__main__":
    main()
