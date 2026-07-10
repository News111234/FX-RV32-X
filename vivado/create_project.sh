#!/bin/bash
# ============================================================================
# Vivado 工程创建 - Linux/WSL 一键启动
# 用法: bash vivado/create_project.sh
# 前提: Vivado 已安装且在 PATH 中
# ============================================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "============================================="
echo " 启动 Vivado 并创建工程..."
echo "============================================="
vivado -source "${SCRIPT_DIR}/create_project.tcl"
