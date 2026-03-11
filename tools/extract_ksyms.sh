#!/bin/bash

# ==============================================================================
# 功能: 自动化验证环境并提取 Linux/Android 内核或内核模块的符号表 (kallsyms)
# 使用方法: 
#   1. 处理内核镜像: ./extract_ksyms.sh <path_to_kernel_image>
#   2. 处理当前目录下所有 .ko 模块: ./extract_ksyms.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# 环境验证与自动化安装函数
# ------------------------------------------------------------------------------
check_and_install_env() {
    echo "[*] 开始检查运行环境..."
    
    # 检查 nm (由 binutils 提供)
    if ! command -v nm &> /dev/null; then
        echo "[-] 未检测到 nm 工具，准备通过 apt 安装 binutils..."
        sudo apt update && sudo apt install -y binutils
    else
        echo "[+] nm 工具已安装."
    fi

    # 检查 pipx (以及 python3)
    if ! command -v pipx &> /dev/null; then
        echo "[-] 未检测到 pipx，准备通过 apt 安装 python3 和 pipx..."
        sudo apt update && sudo apt install -y python3 pipx
    else
        echo "[+] pipx 已安装."
    fi

    # 刷新当前脚本的 PATH，确保能找到 ~/.local/bin 下的命令
    export PATH="$PATH:$HOME/.local/bin"

    # 检查 vmlinux-to-elf
    if ! command -v vmlinux-to-elf &> /dev/null; then
        echo "[-] 未检测到 vmlinux-to-elf，准备通过 pipx 安装..."
        pipx install vmlinux-to-elf
        echo "[*] 运行 pipx ensurepath..."
        pipx ensurepath
        
        # 再次强制刷新 PATH，防止 pipx ensurepath 只修改了 ~/.bashrc 而未在当前终端生效
        export PATH="$PATH:$HOME/.local/bin"
        
        if command -v vmlinux-to-elf &> /dev/null; then
            echo "[+] vmlinux-to-elf 安装并配置成功!"
        else
            echo "[-] 错误: vmlinux-to-elf 安装失败或 PATH 配置未生效，请手动检查。"
            exit 1
        fi
    else
        echo "[+] vmlinux-to-elf 已安装."
    fi
    echo "[*] 环境依赖检查通过！"
    echo "------------------------------------------------------"
}

# ------------------------------------------------------------------------------
# 主逻辑开始
# ------------------------------------------------------------------------------

# 执行环境检测
check_and_install_env

# 判断是否传入了内核镜像参数
if [ -n "$1" ]; then
    # --------------------------------------------------------------------------
    # 模式 A: 传入了参数，处理特定的内核镜像文件
    # --------------------------------------------------------------------------
    IMAGE_PATH="$1"
    
    if [ ! -f "$IMAGE_PATH" ]; then
        echo "[-] 错误: 找不到指定的内核镜像文件 '$IMAGE_PATH'"
        exit 1
    fi

    ELF_PATH="${IMAGE_PATH}.elf"
    MAP_PATH="${IMAGE_PATH}.map"

    echo "[*] 模式 A: 正在处理内核镜像 '$IMAGE_PATH'"
    
    # 1. 使用 vmlinux-to-elf 将镜像还原为 ELF
    echo "[*] 正在利用 vmlinux-to-elf 提取 ELF 文件 (耗时较长，请稍候)..."
    vmlinux-to-elf "$IMAGE_PATH" "$ELF_PATH"

    # 2. 检查生成的 ELF 文件并提取符号
    if [ -f "$ELF_PATH" ]; then
        echo "[+] ELF 文件生成成功: $ELF_PATH"
        echo "[*] 正在使用 nm 导出符号列表至 $MAP_PATH ..."
        
        # 使用 nm 提取符号并重定向到 .map 文件
        nm "$ELF_PATH" > "$MAP_PATH"
        
        echo "[+] 成功! 镜像的符号表已保存至: $MAP_PATH"
    else
        echo "[-] 错误: vmlinux-to-elf 提取失败，未生成 $ELF_PATH 文件。"
        exit 1
    fi

else
    # --------------------------------------------------------------------------
    # 模式 B: 未传入参数，处理当前目录下的所有 .ko 模块
    # --------------------------------------------------------------------------
    echo "[*] 模式 B: 未提供内核镜像路径。准备处理当前目录下的所有 .ko 内核模块..."
    
    # 开启 nullglob 选项，确保当没有 .ko 文件时，数组为空而不是保存字面量 '*.ko'
    shopt -s nullglob
    KO_FILES=(*.ko)
    
    if [ ${#KO_FILES[@]} -eq 0 ]; then
        echo "[-] 当前目录下未发现任何 .ko 文件。"
        exit 0
    fi

    # 创建 symbol 输出目录
    SYMBOL_DIR="./symbol"
    mkdir -p "$SYMBOL_DIR"
    echo "[*] 已创建/确认符号导出目录: $SYMBOL_DIR/"

    # 遍历处理每个 .ko 文件
    for ko_file in "${KO_FILES[@]}"; do
        # 提取去掉 .ko 后缀的文件名
        base_name="${ko_file%.ko}"
        MAP_PATH="${SYMBOL_DIR}/${base_name}.map"
        
        echo "  -> 正在导出 $ko_file 的符号至 $MAP_PATH ..."
        
        # 使用 nm 导出符号。如果某些模块被 strip 可能会报错，这里将错误丢弃以免中断流程
        if nm "$ko_file" > "$MAP_PATH" 2>/dev/null; then
            # 检查导出的 map 文件是否为空
            if [ -s "$MAP_PATH" ]; then
                echo "     [+] 完成"
            else
                echo "     [-] 警告: $MAP_PATH 为空 (该模块可能被 stripped)"
            fi
        else
            echo "     [-] 导出失败: 无法处理 $ko_file"
        fi
    done

    echo "[+] 所有内核模块处理完毕！符号表保存在 $SYMBOL_DIR/ 目录下。"
fi
