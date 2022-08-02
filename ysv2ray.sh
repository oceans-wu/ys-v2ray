#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
magenta=$(tput setaf 5)
aoi=$(tput setaf 6)

reset=$(tput sgr0)

_red() { echo -e ${red}$*${reset}; }
_green() { echo -e ${green}$*${reset}; }
_yellow() { echo -e ${yellow}$*${reset}; }
_magenta() { echo -e ${magenta}$*${reset}; }
_cyan() { echo -e ${blue}$*${reset}; }
_underline() { echo -e ${underline}$*${reset}; }


[[ $(id -u) != 0 ]] && echo -e "\n 哎呀……请使用 ${red}root ${reset}用户运行 ${yellow}~(^_^) ${reset}\n" && exit 1


#######

DAT_PATH=${DAT_PATH:-/usr/local/share/v2ray}

JSON_PATH=${JSON_PATH:-/usr/local/etc/v2ray}

MODULE_PATH=${MODULE_PATH:-/etc/v2ray/yisu}


curl() {
    $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

identify_the_operating_system_and_architecture() {
    if [[ "$(uname)" == 'Linux' ]]; then
        case "$(uname -m)" in
            'i386' | 'i686')
                MACHINE='32'
                ;;
            'amd64' | 'x86_64')
                MACHINE='64'
                ;;
            'armv5tel')
                MACHINE='arm32-v5'
                ;;
            'armv6l')
                MACHINE='arm32-v6'
                grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
                ;;
            'armv7' | 'armv7l')
                MACHINE='arm32-v7a'
                grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
                ;;
            'armv8' | 'aarch64')
                MACHINE='arm64-v8a'
                ;;
            'mips')
                MACHINE='mips32'
                ;;
            'mipsle')
                MACHINE='mips32le'
                ;;
            'mips64')
                MACHINE='mips64'
                ;;
            'mips64le')
                MACHINE='mips64le'
                ;;
            'ppc64')
                MACHINE='ppc64'
                ;;
            'ppc64le')
                MACHINE='ppc64le'
                ;;
            'riscv64')
                MACHINE='riscv64'
                ;;
            's390x')
                MACHINE='s390x'
                ;;
            *)
                error_log "本脚本不支持改操作系统."
                exit 1
                ;;
        esac
        if [[ ! -f '/etc/os-release' ]]; then
            error_log "不要使用过时的Linux发行版."
            exit 1
        fi

        if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup && [[ "$(type -P systemctl)" ]]; then
            true
        elif [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
            true
        else
            error_log "仅支持使用systemd的Linux发行版."
            exit 1
        fi
        if [[ "$(type -P apt)" ]]; then
            PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
            PACKAGE_MANAGEMENT_REMOVE='apt purge'
            package_provide_tput='ncurses-bin'
            CMD="apt"
        elif [[ "$(type -P dnf)" ]]; then
            PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
            PACKAGE_MANAGEMENT_REMOVE='dnf remove'
            package_provide_tput='ncurses'
            CMD="dnf"
        elif [[ "$(type -P yum)" ]]; then
            PACKAGE_MANAGEMENT_INSTALL='yum -y install'
            PACKAGE_MANAGEMENT_REMOVE='yum remove'
            package_provide_tput='ncurses'
            CMD="yum"
        elif [[ "$(type -P zypper)" ]]; then
            PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
            PACKAGE_MANAGEMENT_REMOVE='zypper remove'
            package_provide_tput='ncurses-utils'
            CMD="zypper"
        elif [[ "$(type -P pacman)" ]]; then
            PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
            PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
            package_provide_tput='ncurses'
            CMD="pacman"
        else
            error_log "该脚本不支持此操作系统中的包管理器."
            exit 1
        fi
    else
            error_log "不支持此操作系统."
            exit 1
    fi
}

install_software() {
    package_name="$1"
    file_to_detect="$2"
    type -P "$file_to_detect" > /dev/null 2>&1 && return
    if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name"; then
        info_log " $package_name 已安装."
    else
        if [[ "$CMD" == "apt" ]]; then
            if [[ -e /etc/debian_version ]]; then

                error_log "安装 $package_name 失败,请执行 [ ${yellow}apt-get update${magenta} ]再重试"
                exit 1
            else
                error_log "安装 $package_name 失败, 请检查您的网络."
                exit 1
            fi
        else
            error_log "安装 $package_name 失败, 请检查您的网络."
            exit 1
        fi
    fi
}

get_version() {
    if [[ -n "$VERSION" ]]; then
        RELEASE_VERSION="v${VERSION#v}"
        return 2
    fi
    if [[ -f '/usr/local/bin/v2ray' ]]; then
        VERSION="$(/usr/local/bin/v2ray -version | awk 'NR==1 {print $2}')"
        CURRENT_VERSION="v${VERSION#v}"
        if [[ "$LOCAL_INSTALL" -eq '1' ]]; then
            RELEASE_VERSION="$CURRENT_VERSION"
            return
        fi
    fi
    TMP_FILE="$(mktemp)"
    if ! curl -x "${PROXY}" -sS -H "Accept: application/vnd.github.v3+json" -o "$TMP_FILE" 'https://api.github.com/repos/v2fly/v2ray-core/releases/latest'; then
        "rm" "$TMP_FILE"
        error_log "无法获取发布列表，请检查您的网络。"
        exit 1
    fi
    RELEASE_LATEST="$(sed 'y/,/\n/' "$TMP_FILE" | grep 'tag_name' | awk -F '"' '{print $4}')"
    "rm" "$TMP_FILE"
    RELEASE_VERSION="v${RELEASE_LATEST#v}"
    # 比较V2Ray版本号
    if [[ "$RELEASE_VERSION" != "$CURRENT_VERSION" ]]; then
        RELEASE_VERSIONSION_NUMBER="${RELEASE_VERSION#v}"
        RELEASE_MAJOR_VERSION_NUMBER="${RELEASE_VERSIONSION_NUMBER%%.*}"
        RELEASE_MINOR_VERSION_NUMBER="$(echo "$RELEASE_VERSIONSION_NUMBER" | awk -F '.' '{print $2}')"
        RELEASE_MINIMUM_VERSION_NUMBER="${RELEASE_VERSIONSION_NUMBER##*.}"
        # shellcheck disable=SC2001
        CURRENT_VERSIONSION_NUMBER="$(echo "${CURRENT_VERSION#v}" | sed 's/-.*//')"
        CURRENT_MAJOR_VERSION_NUMBER="${CURRENT_VERSIONSION_NUMBER%%.*}"
        CURRENT_MINOR_VERSION_NUMBER="$(echo "$CURRENT_VERSIONSION_NUMBER" | awk -F '.' '{print $2}')"
        CURRENT_MINIMUM_VERSION_NUMBER="${CURRENT_VERSIONSION_NUMBER##*.}"
        if [[ "$RELEASE_MAJOR_VERSION_NUMBER" -gt "$CURRENT_MAJOR_VERSION_NUMBER" ]]; then
            return 0
        elif [[ "$RELEASE_MAJOR_VERSION_NUMBER" -eq "$CURRENT_MAJOR_VERSION_NUMBER" ]]; then
            if [[ "$RELEASE_MINOR_VERSION_NUMBER" -gt "$CURRENT_MINOR_VERSION_NUMBER" ]]; then
                return 0
            elif [[ "$RELEASE_MINOR_VERSION_NUMBER" -eq "$CURRENT_MINOR_VERSION_NUMBER" ]]; then
                if [[ "$RELEASE_MINIMUM_VERSION_NUMBER" -gt "$CURRENT_MINIMUM_VERSION_NUMBER" ]]; then
                    return 0
                else
                    return 1
                fi
            else
                return 1
            fi
        else
          return 1
        fi
    elif [[ "$RELEASE_VERSION" == "$CURRENT_VERSION" ]]; then
        return 1
    fi
}

download_v2ray() {
    DOWNLOAD_LINK="https://github.com/v2fly/v2ray-core/releases/download/$RELEASE_VERSION/v2ray-linux-$MACHINE.zip"
    echo "下载V2Ray存档: $DOWNLOAD_LINK"
    if ! curl  -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK"; then
        error_log "下载失败！请检查您的网络或重试."
        return 1
    fi
    echo "下载V2Ray存档的验证文件: $DOWNLOAD_LINK.dgst"
    if ! curl  -x "${PROXY}" -sSR -H 'Cache-Control: no-cache' -o "$ZIP_FILE.dgst" "$DOWNLOAD_LINK.dgst"; then
        error_log "下载失败！请检查您的网络或重试."
        return 1
    fi
    if [[ "$(cat "$ZIP_FILE".dgst)" == 'Not Found' ]]; then
        error_log "此版本不支持验证。请替换为其他版本."
        return 1
    fi

    # Verification of V2Ray archive
    for LISTSUM in 'md5' 'sha1' 'sha256' 'sha512'; do
        SUM="$(${LISTSUM}sum "$ZIP_FILE" | sed 's/ .*//')"
        CHECKSUM="$(grep ${LISTSUM^^} "$ZIP_FILE".dgst | grep "$SUM" -o -a | uniq)"
        if [[ "$SUM" != "$CHECKSUM" ]]; then
            error_log "检查失败！请检查您的网络或重试."
            return 1
        fi
    done
}

decompression() {
    if ! unzip -q "$1" -d "$TMP_DIRECTORY"; then
        error_log "V2Ray解压缩失败."
        "rm" -r "$TMP_DIRECTORY"
        echo "removed: $TMP_DIRECTORY"
        exit 1
    fi
    info_log "将V2Ray包解压缩到 $TMP_DIRECTORY 并准备安装."
}

install_file() {
    NAME="$1"
    if [[ "$NAME" == 'v2ray' ]] || [[ "$NAME" == 'v2ctl' ]]; then
        install -m 755 "${TMP_DIRECTORY}/$NAME" "/usr/local/bin/$NAME"
    elif [[ "$NAME" == 'geoip.dat' ]] || [[ "$NAME" == 'geosite.dat' ]]; then
        install -m 644 "${TMP_DIRECTORY}/$NAME" "${DAT_PATH}/$NAME"
    fi
}

install_v2ray() {
    # 将V2Ray二进制文件安装到 /usr/local/bin/ and $DAT_PATH
    install_file v2ray
    install_file v2ctl
    install -d "$DAT_PATH"
    # 如果文件存在，则geoip。dat和geosite。不会安装或更新dat
    if [[ ! -f "${DAT_PATH}/.undat" ]]; then
        install_file geoip.dat
        install_file geosite.dat
    fi

    # 将V2Ray配置文件安装到 $JSON_PATH
    if [[ -z "$JSONS_PATH" ]] && [[ ! -d "$JSON_PATH" ]]; then
        install -d "$JSON_PATH"
        echo "{}" > "${JSON_PATH}/config.json"
    v2_make_conf
        CONFIG_NEW='1'
    fi

    # 将V2Ray配置文件安装到 $JSONS_PATH
    if [[ -n "$JSONS_PATH" ]] && [[ ! -d "$JSONS_PATH" ]]; then
        install -d "$JSONS_PATH"
        for BASE in 00_log 01_api 02_dns 03_routing 04_policy 05_inbounds 06_outbounds 07_transport 08_stats 09_reverse; do
            echo '{}' > "${JSONS_PATH}/${BASE}.json"
        done
        CONFDIR='1'
    fi

    # Used to store V2Ray log files
    if [[ ! -d '/var/log/v2ray/' ]]; then
        if id nobody | grep -qw 'nogroup'; then
            install -d -m 700 -o nobody -g nogroup /var/log/v2ray/
            install -m 600 -o nobody -g nogroup /dev/null /var/log/v2ray/access.log
            install -m 600 -o nobody -g nogroup /dev/null /var/log/v2ray/error.log
        else
            install -d -m 700 -o nobody -g nobody /var/log/v2ray/
            install -m 600 -o nobody -g nobody /dev/null /var/log/v2ray/access.log
            install -m 600 -o nobody -g nobody /dev/null /var/log/v2ray/error.log
        fi
        LOG='1'
    fi
}

install_startup_service_file() {
    install -m 644 "${TMP_DIRECTORY}/systemd/system/v2ray.service" /etc/systemd/system/v2ray.service
    install -m 644 "${TMP_DIRECTORY}/systemd/system/v2ray@.service" /etc/systemd/system/v2ray@.service

    info_log "Systemd服务文件已成功安装!"
    # shellcheck disable=SC2154
    systemctl daemon-reload
    SYSTEMD='1'
}

start_v2ray() {
  if [[ -f '/etc/systemd/system/v2ray.service' ]]; then
      if systemctl start "${V2RAY_CUSTOMIZE:-v2ray}"; then
          info_log  "v2ray 启动成功"
      else
          error_log "v2ray 启动失败"
          exit 1
      fi
  fi
}

stop_v2ray() {
    V2RAY_CUSTOMIZE="$(systemctl list-units | grep 'v2ray' | awk -F ' ' '{print $1}')"
    if [[ -z "$V2RAY_CUSTOMIZE" ]]; then
        local v2ray_daemon_to_stop='v2ray.service'
    else
        local v2ray_daemon_to_stop="$V2RAY_CUSTOMIZE"
    fi
    if ! systemctl stop "$v2ray_daemon_to_stop"; then
        error_log "停止V2Ray服务失败."
        exit 1
    fi
    info_log "停止V2Ray服务."
}

check_update() {
    if [[ -f '/etc/systemd/system/v2ray.service' ]]; then
        get_version
        local get_ver_exit_code=$?
        if [[ "$get_ver_exit_code" -eq '0' ]]; then
            info_log "找到V2Ray $RELEASE_VERSION 的最新版本: $CURRENT_VERSION"
        elif [[ "$get_ver_exit_code" -eq '1' ]]; then
            info_log "没有新版本。V2Ray的当前版本 $CURRENT_VERSION ."
        fi
        exit 0
    else
        error_log "V2Ray未安装."
        exit 1
    fi
}

remove_v2ray() {
  if systemctl list-unit-files | grep -qw 'v2ray'; then
      if [[ -n "$(pidof v2ray)" ]]; then
          stop_v2ray
      fi
      if ! ("rm" -r '/usr/local/bin/v2ray' \
      '/usr/local/etc/v2ray' \
      '/usr/local/bin/v2ctl' \
      "$DAT_PATH" \
      '/etc/systemd/system/v2ray.service' \
      '/etc/systemd/system/v2ray@.service'\
      "$MODULE_PATH"); then
          error_log "无法删除V2Ray."
          exit 1
      else
          echo 'removed: /usr/local/bin/v2ray'
          echo 'removed: /usr/local/bin/v2ctl'
          echo "removed: $DAT_PATH"
          echo 'removed: /etc/systemd/system/v2ray.service'
          echo 'removed: /etc/systemd/system/v2ray@.service'
          echo '请执行命令: systemctl disable v2ray'
          echo "您可能需要执行一个命令来删除相关软件: $PACKAGE_MANAGEMENT_REMOVE curl unzip"
          info_log "V2Ray已删除."
          info_log "如有必要，手动删除配置和日志文件."
          if [[ -n "$JSONS_PATH" ]]; then
              info_log "info: e.g., $JSONS_PATH and /var/log/v2ray/ ..."
          else
              info_log "e.g., $JSON_PATH and /var/log/v2ray/ ..."
          fi
              exit 0
      fi
  else
      error_log "V2Ray未安装."
      exit 1
  fi
}

env_init() {
    install_software git git
    if [[ -d "$MODULE_PATH" ]]; then
        rm -rf "$MODULE_PATH"
    else
        install -d "$MODULE_PATH"
    fi

    if git clone https://github.com/oceans-wu/ys-v2ray -b "main" "$MODULE_PATH" --depth=1; then
        info_log "项目克隆完成"
            echo "

## 请不要删除.修改此文件 ##

v2_port=34254

v2_protocol=vless

v2_uuid=c0c13e1b-7ae3-43b3-9c2b-26588b069247

v2_flow=xtls-rprx-direct

v2_dest_port=80

v2_network=tcp

v2_security=tls

v2_alpn=http/1.1"  >  $v2_global_conf
    else
        error_log "项目克隆失败,请检查你的网络"
        exit 1
    fi
}

main() {

    install_software "$package_provide_tput" 'tput'

    # Two very important variables
    TMP_DIRECTORY="$(mktemp -d)"
    ZIP_FILE="${TMP_DIRECTORY}/v2ray-linux-$MACHINE.zip"

    # 从本地文件安装V2Ray，但仍需要确保网络可用
    if [[ "$LOCAL_INSTALL" -eq '1' ]]; then
        warn_log "从本地文件安装V2Ray，但仍需要确保网络可用."
        warn_log "请确保文件有效，因为我们无法确认。（按任意键） ..."
        read -r
        install_software 'unzip' 'unzip'
        decompression "$LOCAL_FILE"
    else

        install_software 'curl' 'curl'
        get_version
        NUMBER="$?"
        if [[ "$NUMBER" -eq '0' ]] || [[ "$FORCE" -eq '1' ]] || [[ "$NUMBER" -eq 2 ]]; then
            info_log "安装 v2ray  $(uname -m) $RELEASE_VERSION"
            download_v2ray
            if [[ "$?" -eq '1' ]]; then
                "rm" -r "$TMP_DIRECTORY"
                echo "removed: $TMP_DIRECTORY"
                exit 1
            fi
            install_software 'unzip' 'unzip'
            decompression "$ZIP_FILE"
        elif [[ "$NUMBER" -eq '1' ]]; then
            warn_log "已经安装！ V2Ray 版本是： $CURRENT_VERSION "
            exit 0
        fi
    fi

    # 确定V2Ray是否正在运行
    if systemctl list-unit-files | grep -qw 'v2ray'; then
        if [[ -n "$(pidof v2ray)" ]]; then
            stop_v2ray
            V2RAY_RUNNING='1'
        fi
    fi

		get_ip
		v2ray_port
		install_info
    env_init
    install_v2ray
    install_startup_service_file
    echo 'installed: /usr/local/bin/v2ray'
    echo 'installed: /usr/local/bin/v2ctl'
    #
    if [[ ! -f "${DAT_PATH}/.undat" ]]; then
        echo "installed: ${DAT_PATH}/geoip.dat"
        echo "installed: ${DAT_PATH}/geosite.dat"
    fi
    if [[ "$CONFIG_NEW" -eq '1' ]]; then
        echo "installed: ${JSON_PATH}/config.json"
    fi
    if [[ "$CONFDIR" -eq '1' ]]; then
        echo "installed: ${JSON_PATH}/00_log.json"
        echo "installed: ${JSON_PATH}/01_api.json"
        echo "installed: ${JSON_PATH}/02_dns.json"
        echo "installed: ${JSON_PATH}/03_routing.json"
        echo "installed: ${JSON_PATH}/04_policy.json"
        echo "installed: ${JSON_PATH}/05_inbounds.json"
        echo "installed: ${JSON_PATH}/06_outbounds.json"
        echo "installed: ${JSON_PATH}/07_transport.json"
        echo "installed: ${JSON_PATH}/08_stats.json"
        echo "installed: ${JSON_PATH}/09_reverse.json"
    fi
    if [[ "$LOG" -eq '1' ]]; then
        echo 'installed: /var/log/v2ray/'
        echo 'installed: /var/log/v2ray/access.log'
        echo 'installed: /var/log/v2ray/error.log'
    fi
    if [[ "$SYSTEMD" -eq '1' ]]; then
        echo 'installed: /etc/systemd/system/v2ray.service'
        echo 'installed: /etc/systemd/system/v2ray@.service'
    fi
    "rm" -r "$TMP_DIRECTORY"
    echo "removed: $TMP_DIRECTORY"
    if [[ "$LOCAL_INSTALL" -eq '1' ]]; then
        get_version
    fi
  #  info_log "V2Ray $RELEASE_VERSION 已安装."
    echo "您可能需要执行一个命令来删除相关软件: $PACKAGE_MANAGEMENT_REMOVE curl unzip"
    start_v2ray

}

####

protocol=(
    "VLESS + TCP + TLS"
    "VLESS + TCP"
    "VMESS + TCP + TLS"
    "VMESS + TCP"
    "VMESS + WS + TLS"
    "VMESS + WS"
)

flow=(
    xtls-rprx-origin
    xtls-rprx-origin-udp443
    xtls-rprx-direct
    xtls-rprx-direct-udp443
)

pause() {
    read -rsp "$(echo -e "按 ${green} Enter 回车键 ${reset} 继续....或按 ${red} Ctrl + C ${reset} 取消.")" -d $'\n'
    echo
}

get_ip() {
    ip=$(curl -s https://ipinfo.io/ip)
   [[ -z "$ip" ]] && ip=$(curl -s https://api.ip.sb/ip)
   [[ -z "$ip" ]] && ip=$(curl -s https://api.ipify.org)
   [[ -z "$ip" ]] && ip=$(curl -s https://ip.seeip.org)
   [[ -z "$ip" ]] && ip=$(curl -s https://ifconfig.co/ip)
   [[ -z "$ip" ]] && ip=$(curl -s https://api.myip.com | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
   [[ -z "$ip" ]] && ip=$(curl -s icanhazip.com)
   [[ -z "$ip" ]] && ip=$(curl -s myip.ipip.net | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
   [[ -z "$ip" ]] && echo -e "\n$red 这垃圾小鸡扔了吧！$reset\n" && exit
}

v2_uuid=$(cat /proc/sys/kernel/random/uuid)
old_uuid="e1295fd1-0149-44cb-9d3f-499b34a2b0a9"
old_flow="xtls-rprx-direct"
v2_global_conf="/etc/v2ray/yisu/v2_yisu.conf"
v2_tls_conf="/etc/v2ray/yisu/v2_tls.json"
v2_none_conf="/etc/v2ray/yisu/v2_none.json"
v2_conf="/usr/local/etc/v2ray/config.json"
v2_vm_conf="/etc/v2ray/yisu/v2_vm.json"

v2ray_port() {

    local random=$(shuf -i20001-65535 -n1)
    echo
    while :; do 
        echo -e "请输入 "${yellow}"V2Ray"${reset}" 端口 ["${magenta}"20000-65535"${reset}"]"
        read -p "$(echo -e "(默认端口: ${magenta}${random}${reset}):")" v2_port
        [[ -z "$v2_port" ]] && v2_port=$random
        case $v2_port in
            [1-9][0-9][0-9][0-9] | [1-5][0-9][0-9][0-9][0-9] | 6[0-4][0-9][0-9][0-9] | 65[0-4][0-9][0-9] | 655[0-3][0-5])

                 echo
                 echo -e "${yellow} V2Ray 端口${reset} = ${mangenta}$v2_port${reset}"
                 echo "----------------------------------------------------------------"
                 echo
                 break
                 ;;
            *)
                 continue
                 ;;
        esac
    done
	v2ray_protocol
}

v2ray_protocol() {
    echo 
    while :; do 
        echo -e "请选择 "${yellow}"协议组合"${reset}" [${magenta}1-${#protocol[*]}${reset}]"
        for ((i = 1; i <= ${#protocol[*]}; i++)) ; do
            protocol_show="${protocol[$i - 1]}"
            echo 
            echo -e "$yellow $i${reset}. ${aoi}${protocol_show}${reset}"
		    done
        echo 
        read -p "$(echo -e "(默认传输组合: ${aoi}${protocol[0]}${reset})"):" protocol_num
		    [[ -z "$protocol_num" ]] && protocol_num=1
        case $protocol_num in 
            1)
                v2_protocol='vless'
                v2_network='tcp'
                v2_security='tls'
                v2_protocol_network_security=${protocol[${protocol_num} - 1]}
                echo
                break
                ;;
            2)
                v2_protocol='vless'
                v2_network='tcp'
                v2_security='none'
                v2_protocol_network_security=${protocol[${protocol_num} - 1]}
                echo
                break
                ;;
            3)
                v2_protocol='vmess'
                v2_network='tcp'
                v2_security='tls'
                v2_protocol_network_security=${protocol[${protocol_num} - 1]}
                echo
                break
                ;;
            4)
                v2_protocol='vmess'
                v2_network='tcp'
                v2_security='none'
                v2_protocol_network_security=${protocol[${protocol_num} - 1]}
                echo
                break
                ;;
            5)
                v2_protocol='vmess'
                v2_network='ws'
                v2_security='tls'
                v2_protocol_network_security=${protocol[${protocol_num} - 1]}
                echo
                break
                ;;
            6)
                v2_protocol='vmess'
                v2_network='ws'
                v2_security='none'
                v2_protocol_network_security=${protocol[${protocol_num} - 1]}
                echo
                break
                ;;
            *)
                error
                ;;
        esac
    done
    echo -e "${yellow} 传输组合 = ${aoi}${v2_protocol_network_security}${reset}"
    echo "----------------------------------------------------------------"
    echo
    v2_flow="xtls-rprx-direct"
#		v2ray_flow
}

v2ray_flow() {
    echo
    while :; do
        echo -e "请选择 "${yellow}"流控"${reset}" [${magenta}1-${#flow[*]}${reset}]"
            for ((i = 1; i <= ${#flow[*]}; i++)); do 
                flow_show="${flow[$i - 1]}"
                echo 
                echo -e "${yellow} $i${reset}. ${aoi}${flow_show}${reset}"
            done
	      echo
	      read -p "$(echo -e "(默认流控：${aoi}${flow[2]}${reset})"):" v2_flow
	      [[ -z "$v2_flow" ]] && v2_flow=3
	      case $v2_flow in
            [1-4])
                v2_flow=${flow[$v2_flow - 1]}
                echo
                echo
                echo -e "${yellow} 流控${reset} = ${aoi}${v2_flow}${reset}"
                echo "----------------------------------------------------------------"
                echo
                break
                ;;
            *)
                error
                ;;
	      esac
	  done

}

install_info() {

    clear
    echo
    echo " ....准备安装了咯..看看配置..."
    echo
    echo "---------- 安装信息 -------------"
	  echo -e "${yellow} 地址 (Address) ${reset} = ${aoi}${ip}${reset}"
    echo
	  echo -e "${yellow} 端 口 (Port)${reset} = ${aoi}${v2_port}${reset}"
	  echo
	  echo -e "${yellow} 用户ID (User ID / UUID) ${reset} = ${aoi}${v2_uuid}${reset}"
    echo
    echo -e "${yellow} 传输组合(protocol) ${reset} = ${aoi}${v2_protocol_network_security}${reset}"
	  echo
#	  echo -e "${yellow} 流控为(flow) ${reset} = ${aoi}${v2_flow}${reset}"
#	  echo
	  echo "------------- END ----------------"
	  echo
    pause
	  echo
}

info_mes() {

    echo "------------------------------------ 配置信息 --------------------------------------------"
    echo -e "${yellow} 地址 (Address) ${reset} = ${aoi}${ip}${reset}"
    echo
    echo -e "${yellow} 端 口 (Port)${reset} = ${aoi}${v2_port}${reset}"
    echo
    echo -e "${yellow} 用户ID (User ID / UUID) ${reset} = ${aoi}${v2_uuid}${reset}"
    echo
    echo -e "${yellow} 传输组合(protocol) ${reset} = ${v2_protocol_network_security}${reset}"
    echo
#    echo -e "${yellow} 流控为(flow) ${reset} = ${aoi}${v2_flow}${reset}"
#    echo
    echo -e "${yellow} 加密(encryption) ${reset} = ${aoi}none${reset}"
    echo
    echo -e "${yellow} 伪装类型(type) ${reset} = ${aoi}none${reset}"
    echo
    echo -e "---------- V2Ray vless URL / V2RayNG v0.4.1+ / V2RayN v2.1+ / 仅适合部分客户端 -------------"
    echo
    echo -e "${aoi}${v2_url}${reset}"
    echo
    echo "--------------------------------------- END --------------------------------------------------"
}

get_install_info() {

    clear
    if [[ ! -f $"$v2_global_conf" ]]  && [[ ! -f $"v2_conf" ]]; then
        error_log "参数有误！ 请重新安装!!"
        exit 0
    fi
	  if [[ -z "$v2_protocol_network_security" ]]; then

        . ${v2_global_conf}
        case $v2_security in
            "none")
                v2_protocol_network_security="${v2_protocol} + ${v2_network}"
                ;;
            *)
                v2_protocol_network_security="${v2_protocol} + ${v2_security} + ${v2_network}"
                ;;
        esac

        get_ip
        get_vless_url
        info_mes
	  else
	      get_vless_url
		    info_mes
  	fi
}

get_vless_url() {
    v2_url="vless://${v2_uuid}@${ip}:${v2_port}?security=${v2_security}&#www.yisu.com_v2ray"
}

v2_make_conf() {
		if [[ -f "$v2_conf" ]]; then
        rm -rf $v2_conf
		fi 
		sed -i "s/^v2_port.*$/v2_port=${v2_port}/" $v2_global_conf
    sed -i "s/^v2_uuid=.*$/v2_uuid=${v2_uuid}/" $v2_global_conf
		sed -i "s/^v2_protocol=.*$/v2_protocol=${v2_protocol}/" $v2_global_conf
		sed -i "s/^v2_flow=.*$/v2_flow=${v2_flow}/" $v2_global_conf
		sed -i "s/^v2_network=.*$/v2_network=${v2_network}/" $v2_global_conf
    sed -i "s/^v2_security=.*$/v2_security=${v2_security}/" $v2_global_conf
		echo $v2_protocol_network_security
    case $v2_protocol_network_security in

		    "VLESS + TCP + TLS")
            cp $v2_v2_none_conf $v2_conf
            sed -i "9s/44330/${v2_port}/;
            14s/${old_uuid}/${v2_uuid}/;
            32s/none/${v2_security}/" $v2_conf
				    ;;
		    "VLESS + TCP")
            cp $v2_none_conf $v2_conf
            sed -i "9s/44330/${v2_port}/;
            14s/${old_uuid}/${v2_uuid}/" $v2_conf
				    ;;
				"VMESS + TCP + TLS")
				    cp $v2_vm_conf  $v2_conf
            sed -i "9s/44330/${v2_port}/;
            14s/${old_uuid}/${v2_uuid}/;
            33s/none/${v2_security}/" $v2_conf
				    ;;
				"VMESS + TCP")
				    cp $v2_vm_conf  $v2_conf
            sed -i "9s/44330/${v2_port}/;
            14s/${old_uuid}/${v2_uuid}/" $v2_conf
				    ;;
        "VMESS + WS + TLS")
            cp $v2_vm_conf  $v2_conf
            sed -i "9s/44330/${v2_port}/;
            14s/${old_uuid}/${v2_uuid}/;
            32s/tcp/${v2_network}/;
            33s/none/${v2_security}/" $v2_conf
            ;;
        "VMESS + WS")
            cp $v2_vm_conf  $v2_conf
            sed -i "9s/44330/${v2_port}/;
            14s/${old_uuid}/${v2_uuid}/;
            32s/tcp/${v2_network}/" $v2_conf
            ;;
		    *)
            error
				    ;;
    esac





}

uninstall() {
    remove_v2ray
}

install_all() {
    identify_the_operating_system_and_architecture
		main
		get_install_info
}

error_log() {
    echo -e "${red} error ${reset}: ${magenta} "$*" ${reset}"
}

warn_log() {
    echo -e "${yellow} warnning ${reset}: ${magenta}"$*" ${reset}"
}

info_log() {
    echo -e "${yellow} info ${reset}: ${magenta}"$*" ${reset}"
}

error() {
    echo -e "${red} 输入错误! ${reset}"
}

clear
while :; do
    echo
    echo -e "...........${yellow} V2Ray by www.yisu.com ${reset}.........."
    echo
    echo
    echo "${yellow}香港高速服务器: https://www.yisu.com${reset}"
    echo
    echo
    echo "${yellow} 1 ${reset}.${aoi} 安   装 ${reset}"
    echo
    echo "${yellow} 2 ${reset}.${aoi} 查看配置信息 ${reset}"
    echo
    echo "${yellow} 3 ${reset}.${aoi} 卸   载 ${reset}"
    echo
    echo
    echo ".................... END .................."
    echo
    read -p "$(echo -e "请选择 [${magenta}1-3${reset}]:")" choose
    case $choose in
        1)
            install_all
            break
            ;;
        2)
            get_install_info
            break
            ;;
        3)
            uninstall
            break
            ;;

        *)
            error
            ;;
    esac
done

