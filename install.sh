#!/usr/bin/env bash
set -e

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/alan19991/mtproto-installer/main}"
INSTALL_DIR="${INSTALL_DIR:-$(pwd)/mtproxy-data}"
FAKE_DOMAIN_IS_SET=0
[[ -n "${FAKE_DOMAIN+x}" ]] && FAKE_DOMAIN_IS_SET=1
FAKE_DOMAIN="${FAKE_DOMAIN:-www.microsoft.com}"
AD_TAG_IS_SET=0
[[ -n "${AD_TAG+x}" ]] && AD_TAG_IS_SET=1
AD_TAG="${AD_TAG:-}"
TELEMT_INTERNAL_PORT="${TELEMT_INTERNAL_PORT:-1234}"
LISTEN_PORT="${LISTEN_PORT:-443}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

escape_sed_replacement() {
	printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

fetch() {
	local url="$1"
	local dest="$2"
	if ! curl -fsSL "$url" -o "$dest"; then
		err "下载失败: $url"
	fi
}

rerun_cmd() {
	if [[ "$0" == *bash* ]] || [[ "$0" == -* ]]; then
		echo "curl -sSL https://raw.githubusercontent.com/alan19991/mtproto-installer/main/install.sh | bash"
	else
		local dir
		dir="$(cd "$(dirname "$0")" && pwd)"
		echo "bash ${dir}/$(basename "$0")"
	fi
}

check_docker() {
	if command -v docker &>/dev/null; then
		if docker info &>/dev/null 2>&1; then
			info "Docker 可用。"
			return 0
		fi
		echo ""
		warn "Docker 已安装，但当前用户不在 docker 组。"
		echo ""
		echo "请执行以下命令后重试："
		echo -e "  ${GREEN}sudo usermod -aG docker \$USER && newgrp docker${NC}"
		echo -e "  ${GREEN}$(rerun_cmd)${NC}"
		exit 1
	fi
	info "安装 Docker..."
	curl -fsSL https://get.docker.com | sh
	if ! docker info &>/dev/null 2>&1; then
		echo ""
		warn "Docker 已安装，请把当前用户加入 docker 组后重试。"
		echo ""
		echo -e "  ${GREEN}sudo usermod -aG docker \$USER && newgrp docker${NC}"
		echo -e "  ${GREEN}$(rerun_cmd)${NC}"
		exit 1
	fi
}

is_port_in_use() {
	local port="$1"
	if command -v ss &>/dev/null; then
		ss -tuln 2>/dev/null | grep -qE "[.:]${port}[[:space:]]"
		return $?
	fi
	if command -v nc &>/dev/null; then
		nc -z 127.0.0.1 "$port" 2>/dev/null
		return $?
	fi
	return 1
}

prompt_port() {
	local suggested=443
	if is_port_in_use 443; then
		warn "端口 443 已被占用。"
		suggested=1443
		while true; do
			if [[ -t 0 ]]; then
				echo -n "请输入监听端口 [${suggested}]: "
				read -r input
				[[ -z "$input" ]] && input=$suggested
			else
				LISTEN_PORT=$suggested
				return
			fi
			if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= 65535 )); then
				if is_port_in_use "$input"; then
					warn "端口 ${input} 也被占用，请换一个。"
				else
					LISTEN_PORT=$input
					return
				fi
			else
				warn "请输入 1-65535 之间的数字。"
			fi
		done
	else
		if [[ -t 0 ]]; then
			echo -n "代理监听端口 [443]: "
			read -r input
			[[ -n "$input" ]] || input=443
			while true; do
				if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= 65535 )); then
					if is_port_in_use "$input"; then
						warn "端口 ${input} 已被占用，请换一个。"
						echo -n "请输入监听端口: "
						read -r input
					else
						LISTEN_PORT=$input
						return
					fi
				else
					warn "请输入 1-65535 之间的数字。"
					echo -n "代理监听端口 [443]: "
					read -r input
					[[ -z "$input" ]] && input=443
				fi
			done
		fi
	fi
}

prompt_fake_domain() {
	if [[ "${FAKE_DOMAIN_IS_SET}" -eq 1 ]]; then
		return
	fi
	if [[ -t 0 ]]; then
		echo -n "请输入 Fake TLS 伪装域名 [${FAKE_DOMAIN}]: "
		read -r input
		[[ -n "$input" ]] && FAKE_DOMAIN="$input"
	fi
}

prompt_ad_tag() {
	if [[ "${AD_TAG_IS_SET}" -eq 1 ]]; then
		return
	fi
	if [[ -t 0 ]]; then
		echo -n "请输入 ad_tag（可留空）: "
		read -r input
		AD_TAG="$input"
	fi
}

generate_secret() {
	openssl rand -hex 16
}

download_and_configure() {
	mkdir -p "${INSTALL_DIR}/traefik/dynamic" "${INSTALL_DIR}/traefik/static"
	info "从 ${REPO_RAW} 下载配置文件..."
	fetch "${REPO_RAW}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
	fetch "${REPO_RAW}/traefik/dynamic/tcp.yml" "${INSTALL_DIR}/traefik/dynamic/tcp.yml"
	fetch "${REPO_RAW}/telemt.toml.example" "${INSTALL_DIR}/telemt.toml.example"
	sed "s/443:443/${LISTEN_PORT}:443/" "${INSTALL_DIR}/docker-compose.yml" > "${INSTALL_DIR}/docker-compose.yml.tmp" && mv "${INSTALL_DIR}/docker-compose.yml.tmp" "${INSTALL_DIR}/docker-compose.yml"

	SECRET=$(generate_secret)
	local escaped_domain
	local escaped_ad_tag
	local escaped_secret
	escaped_domain="$(escape_sed_replacement "${FAKE_DOMAIN}")"
	escaped_ad_tag="$(escape_sed_replacement "${AD_TAG}")"
	escaped_secret="$(escape_sed_replacement "${SECRET}")"

	cp "${INSTALL_DIR}/telemt.toml.example" "${INSTALL_DIR}/telemt.toml"
	sed -E -i \
	    -e "s|^[[:space:]]*tls_domain[[:space:]]*=.*$|tls_domain = \"${escaped_domain}\"|" \
	    -e "s|^[[:space:]]*ad_tag[[:space:]]*=.*$|ad_tag = \"${escaped_ad_tag}\"|" \
	    -e "s|^[[:space:]]*docker[[:space:]]*=.*$|docker = \"${escaped_secret}\"|" \
	    "${INSTALL_DIR}/telemt.toml"

	# 兼容旧模板：如果没有 ad_tag 字段，则在 [general] 段补一行
	if ! grep -qE "^[[:space:]]*ad_tag[[:space:]]*=" "${INSTALL_DIR}/telemt.toml"; then
		sed -E -i "/^[[:space:]]*use_middle_proxy[[:space:]]*=.*$/a ad_tag = \"${escaped_ad_tag}\"" "${INSTALL_DIR}/telemt.toml"
	fi

	grep -qF "tls_domain = \"${FAKE_DOMAIN}\"" "${INSTALL_DIR}/telemt.toml" \
		|| err "写入 tls_domain 失败"
	grep -qE "^[[:space:]]*ad_tag[[:space:]]*=" "${INSTALL_DIR}/telemt.toml" \
		|| err "写入 ad_tag 失败"
	grep -qE "^[[:space:]]*docker[[:space:]]*=[[:space:]]*\"[0-9a-fA-F]{32}\"$" "${INSTALL_DIR}/telemt.toml" \
		|| err "写入密钥失败"
	rm -f "${INSTALL_DIR}/telemt.toml.example"
	info "已生成 ${INSTALL_DIR}/telemt.toml（SNI: ${FAKE_DOMAIN}）"

	local tcp_yml="${INSTALL_DIR}/traefik/dynamic/tcp.yml"
	sed -e "s/www\.microsoft\.com/${escaped_domain}/g" \
	    -e "s/telemt:1234/telemt:${TELEMT_INTERNAL_PORT}/g" \
	    "$tcp_yml" > "${tcp_yml}.tmp" && mv "${tcp_yml}.tmp" "$tcp_yml"
	info "Traefik 路由已设置: SNI ${FAKE_DOMAIN} -> telemt:${TELEMT_INTERNAL_PORT}"

	printf '%s' "$SECRET" > "${INSTALL_DIR}/.secret"
}

run_compose() {
	cd "${INSTALL_DIR}"
	docker compose pull -q 2>/dev/null || true
	docker compose up -d
	info "容器已启动。"
}

print_link() {
	local SECRET TLS_DOMAIN DOMAIN_HEX LONG_SECRET SERVER_IP LINK
	SECRET=$(cat "${INSTALL_DIR}/.secret" 2>/dev/null | tr -d '\n\r')
	[[ -z "$SECRET" ]] && err "未找到密钥文件: ${INSTALL_DIR}/.secret"

	TLS_DOMAIN=$(grep -E '^[[:space:]]*tls_domain[[:space:]]*=' "${INSTALL_DIR}/telemt.toml" \
		| head -n1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
	[[ -z "$TLS_DOMAIN" ]] && err "在 telemt.toml 中未找到 tls_domain"

	DOMAIN_HEX=$(printf '%s' "$TLS_DOMAIN" | od -An -tx1 | tr -d ' \n')
	if [[ "$SECRET" =~ ^[0-9a-fA-F]{32}$ ]]; then
		LONG_SECRET="ee${SECRET}${DOMAIN_HEX}"
	else
		LONG_SECRET="$SECRET"
	fi

	SERVER_IP=""
	for url in https://ifconfig.me/ip https://icanhazip.com https://api.ipify.org https://checkip.amazonaws.com; do
		raw=$(curl -s --connect-timeout 3 "$url" 2>/dev/null | tr -d '\n\r')
		if [[ -n "$raw" ]] && [[ ! "$raw" =~ [[:space:]] ]] && [[ ! "$raw" =~ (error|timeout|upstream|reset|refused) ]] && [[ "$raw" =~ ^([0-9.]+|[0-9a-fA-F:]+)$ ]]; then
			SERVER_IP="$raw"
			break
		fi
	done
	if [[ -z "$SERVER_IP" ]]; then
		SERVER_IP="YOUR_SERVER_IP"
		warn "无法自动获取公网 IP，请手动替换链接中的 YOUR_SERVER_IP。"
	fi
	LINK="tg://proxy?server=${SERVER_IP}&port=${LISTEN_PORT}&secret=${LONG_SECRET}"
	echo ""
	echo -e "${GREEN}Telegram 代理链接（Fake TLS）:${NC}"
	echo -e "  ${GREEN}${LINK}${NC}"
	echo ""
	echo "请妥善保管此链接，不要公开分享。"
	echo "安装目录: ${INSTALL_DIR}"
	echo "查看日志: cd ${INSTALL_DIR} && docker compose logs -f"
	echo "停止服务: cd ${INSTALL_DIR} && docker compose down"
	echo ""
}

main() {
	[[ "${INSTALL_DIR}" != /* ]] && INSTALL_DIR="$(pwd)/${INSTALL_DIR}"
	check_docker
	prompt_port
	prompt_fake_domain
	prompt_ad_tag
	download_and_configure
	run_compose
	print_link
}

main "$@"
