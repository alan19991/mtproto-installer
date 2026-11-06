#!/usr/bin/env bash
set -e

INSTALL_DIR="${INSTALL_DIR:-$(pwd)/mtproxy-data}"
FORCE=

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		-y|--yes)
			FORCE=1
			shift
			;;
		-h|--help)
			echo "用法: $0 [-y|--yes] [安装目录]"
			echo "说明: 停止并删除 MTProxy 容器，然后删除安装目录。"
			echo "默认目录: $(pwd)/mtproxy-data"
			echo "-y, --yes: 跳过确认"
			exit 0
			;;
		*)
			INSTALL_DIR="$1"
			shift
			break
			;;
	esac
done

[[ "${INSTALL_DIR}" != /* ]] && INSTALL_DIR="$(pwd)/${INSTALL_DIR}"

if [[ ! -d "$INSTALL_DIR" ]]; then
	err "目录不存在: ${INSTALL_DIR}"
fi

if [[ ! -f "${INSTALL_DIR}/docker-compose.yml" ]] || [[ ! -f "${INSTALL_DIR}/telemt.toml" ]]; then
	err "目标目录看起来不是 MTProxy 安装目录: ${INSTALL_DIR}"
fi

if [[ -z "$FORCE" ]] && [[ -t 0 ]]; then
	echo -n "确认卸载并删除 ${INSTALL_DIR} ? [y/N] "
	read -r ans
	[[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]] && exit 0
fi

info "停止并移除容器..."
(cd "${INSTALL_DIR}" && docker compose down -v 2>/dev/null) || true

info "删除目录 ${INSTALL_DIR} ..."
rm -rf "${INSTALL_DIR}"
info "卸载完成。"
