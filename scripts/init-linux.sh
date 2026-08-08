#!/bin/bash
####################################################################################
#        initialization scripts for CentOS/RadHat 7.0+ and Ubuntu/Debian           #
####################################################################################
set -e
START_TIME=$(date +%s)
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

CMD=$0

# error codes
UNKOWNRELEASE=100
UNKOWNPARAMETER=101
MALFORMEDPARAMTER=110
CANCELREPEAT=201
ILLEGALUSER=202

# Global Variables
OS_FAMILY=""
OS_NAME=""
OS_VERSION=""
PKG_MGR=""
SYSTEM_RELEASE=""
OPERATION=""
EXIT_CODE=0

usage() {
  cat <<EOF
Usage: $CMD <command>
Commands:
   Some <commands> take arguments or -h for usage.
     pkg        install epel-release tools & package mirrors
     vps        run in vps mode (optimized limits/SSH/kernel for VPS)
     init       set timezone, selinux, sshd, kernel parameters, limits, history
     all        execute all initialization tasks (init, mirror, package, docker repo)
     mirror     configure package mirrors to use Aliyun for faster downloads
     security   disable local firewalls (firewalld/ufw) and SELinux
     time       set timezone to Asia/Shanghai and enable NTP via Chrony
     ssh        optimize sshd configurations (disable UseDNS)
     optimize   optimize system parameters (sysctl kernel settings and THP/NUMA)
     docker     setup Docker Hub USTC/Aliyun registry mirrors
     disk       format and mount a selected disk with LVM and filesystem
     autodisk   auto-detect unmounted disks, format, and mount to /dataX
     expand     expand root LVM partition
     history    configure session-only command history with timestamp auditing
     clean      clean package manager cache
EOF
}

detect_cloud() {
  IS_CLOUD=0
  IS_TENCENT_CLOUD=0

  # Detect Tencent Cloud environment
  if [ -f /etc/systemd/system/tat_agent.service ] || [ -d /usr/local/qcloud ] || [ -f /usr/sbin/tat_agent ] || \
     ( [ -f /sys/class/dmi/id/sys_vendor ] && grep -qi "tencent" /sys/class/dmi/id/sys_vendor 2>/dev/null ) || \
     ( [ -f /sys/class/dmi/id/product_name ] && grep -qi "tencent" /sys/class/dmi/id/product_name 2>/dev/null ); then
    IS_TENCENT_CLOUD=1
    IS_CLOUD=1
    echo "[INFO] Detected Tencent Cloud (CVM) environment."
  # Detect general cloud / VPS / hypervisor environment
  elif [ -d /var/lib/cloud ] || command -v cloud-init >/dev/null 2>&1 || \
       ( [ -f /sys/class/dmi/id/sys_vendor ] && grep -qiE "alibaba|amazon|google|microsoft|huawei|qemu|kvm|xen" /sys/class/dmi/id/sys_vendor 2>/dev/null ); then
    IS_CLOUD=1
    echo "[INFO] Detected Cloud / VPS environment."
  fi
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
    case "$ID" in
      centos|rocky|almalinux|redhat|rhel)
        OS_FAMILY="rhel"
        PKG_MGR=$(command -v dnf >/dev/null 2>&1 && echo "dnf" || echo "yum")
        SYSTEM_RELEASE="centos"
        ;;
      debian|ubuntu)
        OS_FAMILY="debian"
        PKG_MGR="apt"
        SYSTEM_RELEASE=$ID
        ;;
      *)
        echo "[ERROR] Unsupported OS: $ID"
        exit $UNKOWNRELEASE
        ;;
    esac
  else
    echo "[ERROR] /etc/os-release not found"
    exit $UNKOWNRELEASE
  fi

  detect_cloud
}

countdown() {
  local OS=$(grep -E "^PRETTY_NAME" /etc/os-release | awk -F '=' '{print $2}' | sed 's/\"//g')
  for ((s=5; s>0; s--)); do
    echo -e "\033[41;37mYour system is ${OS}\033[0m"
    echo -e "\033[41;37mRun initialization after $s seconds.\033[0m"
    sleep 1
    clear
  done
}

init_kernel() {
  echo -e "\033[41;05m Start configuration kernel parameter! \033[0m"
  sleep 1
  local ipforward=1
  if [ "$OPERATION" = "vps" ]; then
    ipforward=0
  fi
  
  mkdir -p /etc/sysctl.d
  cat <<EOF > /etc/sysctl.d/99-custom.conf
net.ipv4.tcp_mem = 94500000 915000000 927000000
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_max_orphans = 3276800
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216 
net.core.wmem_max = 16777216 
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 65535
net.ipv4.tcp_fin_timeout = 5
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_rmem = 4096 87380 16777216 
net.ipv4.tcp_wmem = 4096 65536 16777216 
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_max_tw_buckets = 360000
net.ipv4.ip_local_port_range = 10001 65000
net.ipv4.tcp_synack_retries = 2 
net.ipv4.tcp_syn_retries = 2 
net.netfilter.nf_conntrack_max = 655360
kernel.ctrl-alt-del = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv4.ip_forward = ${ipforward}
EOF
  sysctl --system || true
}

configure_mirrors_and_pkgs() {
  case "${SYSTEM_RELEASE}" in
    debian|ubuntu)
      echo -e "\033[41;05m Start configuration apt mirrors site! \033[0m"
      sleep 1
      if [ "$OPERATION" != "vps" ]; then
        [ -f /etc/apt/sources.list ] && [ ! -f /etc/apt/sources.list.bak ] && cp /etc/apt/sources.list /etc/apt/sources.list.bak
        
        if [ "${SYSTEM_RELEASE}" = "debian" ]; then
          if [ -f /etc/apt/sources.list ]; then
            sed -i 's|http://.*deb.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list
            sed -i 's|http://.*security.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list
          fi
          if [ -f /etc/apt/sources.list.d/debian.sources ]; then
            sed -i 's|http://.*deb.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources
            sed -i 's|http://.*security.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources
          fi
        else
          # Ubuntu Aliyun mirror replacement
          sed -i 's|http://.*archive.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list
          sed -i 's|http://.*security.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list
          if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
            sed -i 's|http://.*archive.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list.d/ubuntu.sources
            sed -i 's|http://.*security.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list.d/ubuntu.sources
          fi
        fi
        apt-get update -y || true
        
        local PACKAGELIST=(lrzsz bash-completion curl apt-transport-https ca-certificates gnupg2 vim software-properties-common xfsprogs e2fsprogs lvm2 parted)
        for n in "${PACKAGELIST[@]}"; do
          dpkg -l "${n}" | grep -q "${n}" || apt-get install -y "${n}" || true
        done
      fi
      ;;
    centos|rocky|almalinux|redhat)
      echo -e "\033[41;05m Start configuration yum mirrors site! \033[0m"
      sleep 1
      if [ "$OPERATION" != "vps" ]; then
        if ! grep -q mirrors.aliyun.com /etc/yum.repos.d/CentOS-Base.repo 2>/dev/null; then
          rm -rf /var/cache/yum
          mkdir -p /etc/yum.repos.d
          curl -s -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo || true
          curl -s -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo || true
          curl -s -o /etc/yum.repos.d/docker-ce.repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo || true
        fi
        local PACKAGELIST=(wget lrzsz iftop traceroute telnet lsof net-tools docker-ce bash-completion)
        for n in "${PACKAGELIST[@]}"; do
          rpm -q "${n}" | grep -q "${n}" || yum install -y "${n}" || true
        done
      fi
      ;;
  esac
}

clean_self_start() {
  echo -e "\033[41;05m Start clean self start! \033[0m"
  sleep 1

  # Base protected services (SSH, time sync, cron, power management, security, networking)
  local protected_pattern="autovt|getty|ssh|sshd|cron|crond|rsyslog|network|Networking|timesyncd|chrony|chronyd|hwclock|acpid|apparmor|selinux|dbus|systemd-resolved|systemd-networkd|systemd-logind"

  # Protect cloud provider agents & cloud-init if cloud or VPS environment is detected
  if [ "$IS_CLOUD" -eq 1 ] || [ "$OPERATION" = "vps" ] || command -v cloud-init >/dev/null 2>&1 || [ -d /var/lib/cloud ]; then
    protected_pattern="${protected_pattern}|cloud-init|cloud-config|cloud-final|cloud-init-local"
    protected_pattern="${protected_pattern}|tat_agent|barad_agent|sgagent|Yunjing|aliyun|aegis|qemu-guest-agent"
  fi

  echo "[INFO] Filtering self-start services with protected pattern: ${protected_pattern}"

  for n in $(systemctl list-unit-files --type=service | grep enabled | awk '{print $1}' | grep -Ev "${protected_pattern}"); do
    echo "[INFO] Disabling non-essential service: $n"
    systemctl disable "$n" 2>/dev/null || true
    if [ "$OPERATION" != "vps" ]; then
      systemctl stop "$n" 2>/dev/null || true
    fi
  done
}

disable_selinux() {
  echo -e "\033[41;05m Start stop selinux! \033[0m"
  sleep 1
  case "${SYSTEM_RELEASE}" in
    centos|rocky|almalinux|redhat)
      if [ -f /etc/selinux/config ]; then
        local status=$(grep -E "^SELINUX=" /etc/selinux/config | awk -F '=' '{print $2}')
        if [ "${status}" = "disabled" ]; then
          echo -e "\033[41;05m SELinux is disabled! \033[0m"
          sleep 1
        else
          setenforce 0 2>/dev/null || true
          sed -i "s/SELINUX=enforcing/SELINUX=disabled/" /etc/selinux/config
          sed -i "s/SELINUX=enforcing/SELINUX=disabled/" /etc/sysconfig/selinux 2>/dev/null || true
        fi
      fi
      ;;
  esac
  
  # Also stop firewalls
  if [ "$OS_FAMILY" = "rhel" ]; then
    systemctl disable --now firewalld 2>/dev/null || true
  elif [ "$OS_FAMILY" = "debian" ]; then
    systemctl disable --now ufw 2>/dev/null || true
  fi
}

init_limits() {
  echo -e "\033[41;05m Start configuration limit file! \033[0m"
  sleep 1
  if ! grep -q "work" /etc/security/limits.conf 2>/dev/null; then
    cat <<EOF >> /etc/security/limits.conf
* soft    nofile  655360
* hard    nofile  655360
* soft    nproc   655360
* hard    nproc   655360
work soft nofile  655360
work hard nofile  655360
work soft nproc   655360
work hard nproc   655360
EOF
  fi
}

init_history() {
  echo -e "\033[41;05m Start configuration profile! \033[0m"
  sleep 1
  local WORK_DIR=(/root/.bashrc)
  if id work &>/dev/null; then
    WORK_DIR+=(/home/work/.bashrc)
  fi
  
  case "${SYSTEM_RELEASE}" in
    debian|ubuntu)
      for n in "${WORK_DIR[@]}"; do
        if [ -f "$n" ] && ! grep -q "#export http_proxy=10.0.0.1:10810" "$n"; then
          [ "${SYSTEM_RELEASE}" = "debian" ] && sed -i s@"# export LS_OPTIONS='--color=auto'"@"export LS_OPTIONS='--color=auto'"@ "$n" 2>/dev/null || true
          [ "${SYSTEM_RELEASE}" = "debian" ] && sed -i s@"# alias ls='ls \$LS_OPTIONS'"@"alias ls='ls \$LS_OPTIONS'"@ "$n" 2>/dev/null || true
          [ "${SYSTEM_RELEASE}" = "debian" ] && sed -i s@"# alias ll='ls \$LS_OPTIONS -l'"@"alias ll='ls \$LS_OPTIONS -l'"@ "$n" 2>/dev/null || true
          [ "${SYSTEM_RELEASE}" = "debian" ] && sed -i s@"# alias l='ls \$LS_OPTIONS -lA'"@"alias l='ls \$LS_OPTIONS -lA'"@ "$n" 2>/dev/null || true
        fi
      done
      ;;
  esac
  
  for n in "${WORK_DIR[@]}"; do
    if [ -f "$n" ] && ! grep -q "#export http_proxy=10.0.0.1:10810" "$n"; then
      grep -q HISTTIMEFORMAT "$n" || echo "export HISTTIMEFORMAT=\"%F %T [\`whoami\`]: \"" >> "$n"
      grep -q HISTFILESIZE "$n" || echo "export HISTFILESIZE=10000" >> "$n"
      grep -q HISTSIZE "$n" || echo "export HISTSIZE=2000" >> "$n"
      grep -q HISTORY_FILE "$n" || echo "export HISTORY_FILE=/var/log/\`date '+%Y-%m-%d'\`.log" >> "$n"
      grep -q PROMPT_COMMAND "$n" || echo "export PROMPT_COMMAND='{ command=\$(history 1 | { read x y; echo \$y; }); logger -p local1.notice -t bash -i \"user=\$USER,ppid=\$PPID,from=\$SSH_CLIENT,pwd=\$PWD,command:\$command\"; }'" >> "$n"
      echo "#export http_proxy=10.0.0.1:10810" >> "$n"
      echo "#export https_proxy=10.0.0.1:10810" >> "$n"
    fi
  done
}

set_docker_repo() {
  if [ "$OPERATION" != "vps" ]; then
    case "${SYSTEM_RELEASE}" in
      centos|rocky|almalinux|redhat)
        mkdir -p /etc/docker
        if ! grep -q "https://docker.mirrors.ustc.edu.cn/" /etc/docker/daemon.json 2>/dev/null; then
          cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn/"]
}
EOF
        fi
        ;;
      debian|ubuntu)
        if ! systemctl list-unit-files | grep -q docker; then
          curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/${SYSTEM_RELEASE}/gpg | apt-key add - || true
          add-apt-repository -y "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/${SYSTEM_RELEASE} $(lsb_release -cs) stable" || true
          apt-get update -y || true
          apt-get install -y docker-ce || true
          systemctl stop docker || true
          systemctl disable docker || true
        else
          if systemctl status docker | grep -q "active (running)"; then
            systemctl stop docker.socket || true
            systemctl stop docker || true
            systemctl disable docker || true
          fi
        fi
        ;;
    esac
  fi
}

config_sshd() {
  echo -e "\033[41;05m Start modify ssh config file! \033[0m"
  sleep 1
  if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config || true
    sed -i 's/UseDNS yes/UseDNS no/' /etc/ssh/sshd_config || true
    if [ "$OPERATION" != "vps" ]; then
      sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
      sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
    fi
    if [ "${SYSTEM_RELEASE}" = "debian" ] || [ "${SYSTEM_RELEASE}" = "ubuntu" ]; then
      sed -i 's/X11Forwarding yes/#X11Forwarding yes/' /etc/ssh/sshd_config || true
    fi
    
    local service="sshd"
    if [ "$OS_FAMILY" = "debian" ]; then
      service="ssh"
    fi
    systemctl restart "$service" || true
  fi
}

set_timezone_ntp() {
  echo "[INFO] Setting timezone to Asia/Shanghai and enabling NTP..."
  timedatectl set-timezone Asia/Shanghai || true
  if [ "$OS_FAMILY" = "rhel" ]; then
    $PKG_MGR install -y chrony || true
    systemctl enable --now chronyd || true
  elif [ "$OS_FAMILY" = "debian" ]; then
    $PKG_MGR install -y chrony || true
    systemctl enable --now chrony || true
  fi
  timedatectl set-ntp true || true
}

disable_thp_numa() {
  echo "[INFO] Disabling transparent huge pages and NUMA..."
  if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled || true
    echo never > /sys/kernel/mm/transparent_hugepage/defrag || true
    mkdir -p /etc/rc.d
    cat <<EOF >> /etc/rc.d/rc.local
#!/bin/bash
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
  echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi
if [ -f /sys/kernel/mm/transparent_hugepage/defrag ]; then
  echo never > /sys/kernel/mm/transparent_hugepage/defrag
fi
EOF
    chmod +x /etc/rc.d/rc.local || true
  fi

  if ! grep -q "numa=off" /etc/default/grub 2>/dev/null; then
    if [ -f /etc/default/grub ]; then
      sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/ numa=off"/' /etc/default/grub || true
      if [ "$OS_FAMILY" = "rhel" ]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg || true
        [ -d /boot/efi/EFI/"$OS_NAME" ] && grub2-mkconfig -o /boot/efi/EFI/"$OS_NAME"/grub.cfg || true
      else
        update-grub || true
      fi
    fi
  fi
}

clean_cache() {
  echo "[INFO] Cleaning package manager cache..."
  if [ "$OS_FAMILY" = "rhel" ]; then
    $PKG_MGR clean all || true
  elif [ "$OS_FAMILY" = "debian" ]; then
    $PKG_MGR clean || true
  fi
}

init_system_module() {
  clean_self_start
  init_limits
  disable_selinux
  init_history
}

ensure_lvm_installed() {
  modprobe dm_mod 2>/dev/null || true
  if ! command -v lvs &>/dev/null || ! command -v parted &>/dev/null || ! command -v mkfs.xfs &>/dev/null || ! command -v mkfs.ext4 &>/dev/null; then
    echo "[INFO] Installing lvm2, parted, xfsprogs, and e2fsprogs..."
    if [ "$OS_FAMILY" = "rhel" ]; then
      $PKG_MGR install -y lvm2 parted xfsprogs e2fsprogs || {
        echo "[ERROR] Failed to install lvm2, parted, xfsprogs or e2fsprogs"
        exit 1
      }
    elif [ "$OS_FAMILY" = "debian" ]; then
      $PKG_MGR update -y || {
        echo "[ERROR] Failed to update package sources"
        exit 1
      }
      $PKG_MGR install -y lvm2 parted xfsprogs e2fsprogs || {
        echo "[ERROR] Failed to install lvm2, parted, xfsprogs or e2fsprogs"
        exit 1
      }
    fi
  fi

  # Activate all LVM volume groups and refresh devtmpfs nodes
  modprobe dm_mod 2>/dev/null || true
  vgchange -ay 2>/dev/null || true
  vgmknodes 2>/dev/null || true
  dmsetup mknodes 2>/dev/null || true
  udevadm trigger --action=add 2>/dev/null || true
  udevadm settle 2>/dev/null || true
}

setup_disk_lvm() {
  local DISK=$1
  local MOUNTDIR=$2
  local FSTYPE=${3:-xfs}

  if [ -z "$DISK" ] || [ -z "$MOUNTDIR" ]; then
    echo "[ERROR] Missing arguments for disk formatting."
    echo "Usage: init-linux.sh disk <disk_name_e.g_sdb> <mount_directory_e.g_/data> [filesystem_type_xfs_or_ext4]"
    exit 1
  fi

  ensure_lvm_installed

  echo "[INFO] Formatting disk /dev/$DISK as LVM mounted to $MOUNTDIR ($FSTYPE)..."
  echo "[INFO] Available disks:"
  lsblk -d -e 7,11 -o NAME,SIZE,TYPE | grep disk

  DEV=/dev/$DISK
  if [ ! -b "$DEV" ]; then
    echo "[ERROR] Disk $DEV does not exist"
    exit 1
  fi

  if lsblk "$DEV" | grep -q "${DISK}[0-9]"; then
    echo "[INFO] Detected partitions on $DEV, clearing..."
    for PART in $(lsblk -ln $DEV | awk '$1 ~ /[0-9]$/ {print $1}'); do
      MOUNTED=$(lsblk -n -o MOUNTPOINT "/dev/$PART")
      if [ -n "$MOUNTED" ]; then
        echo "[INFO] Unmounting $MOUNTED"
        umount -f "$MOUNTED" || true
      fi
    done
    wipefs -a "$DEV" || true
    parted -s "$DEV" mklabel gpt || true
  else
    echo "[INFO] No partitions on $DEV, creating GPT label"
    parted -s "$DEV" mklabel gpt || true
  fi

  echo "[INFO] Creating partition and LVM..."
  parted -s "$DEV" mkpart primary 0% 100% || true
  PARTITION="${DEV}1"
  [ -b "${DEV}p1" ] && PARTITION="${DEV}p1"

  pvcreate "$PARTITION" || true
  vgcreate vg_data "$PARTITION" || true
  lvcreate -l 100%FREE -n lv_data vg_data || true

  mkfs.$FSTYPE /dev/vg_data/lv_data || true
  mkdir -p "$MOUNTDIR" || true
  echo "/dev/vg_data/lv_data $MOUNTDIR $FSTYPE defaults 0 0" >> /etc/fstab
  mount -a || true
  echo "[INFO] LVM filesystem mounted at $MOUNTDIR"
}

auto_format_disks() {
  local PREFIX=${1:-/data}
  ensure_lvm_installed
  echo "自动检测未挂载磁盘并初始化/挂载到 ${PREFIX}X..."
  local index=1
  for dev in $(lsblk -dpno NAME,TYPE | grep disk | awk '{print $1}'); do
    # 过滤掉有任何挂载点的磁盘（包含系统根盘和已挂载的数据盘）
    local mounted_count=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | grep -v '^$' | wc -l)
    if [ "$mounted_count" -eq 0 ]; then
      local vg_name="vg_data${index}"
      local lv_name="lv_data${index}"

      # 如果该磁盘关联了已有 VG，直接使用已有 VG 名字
      local existing_vg=$(pvs --noheadings -o vg_name "$dev" "${dev}1" "${dev}p1" 2>/dev/null | awk '{print $1}' | grep -v '^$' | head -n1 || true)
      if [ -n "$existing_vg" ]; then
        vg_name="$existing_vg"
      fi

      # 避免挂载点或 VG 命名冲突
      while grep -q "${PREFIX}${index}" /etc/fstab 2>/dev/null && [ -z "$existing_vg" ]; do
        ((index++))
        vg_name="vg_data${index}"
        lv_name="lv_data${index}"
      done

      # 显式激活 VG，防止逻辑卷处于 Inactive 状态
      vgchange -ay "$vg_name" 2>/dev/null || true
      vgmknodes 2>/dev/null || true
      udevadm settle 2>/dev/null || true

      local mount_dir="${PREFIX}${index}"
      echo "[INFO] 发现待处理磁盘 $dev -> 挂载点目标: $mount_dir (VG: $vg_name)"

      local part="${dev}1"
      if ! lsblk -no NAME "$dev" 2>/dev/null | grep -qE "${dev##*/}1|${dev##*/}p1"; then
        echo "[INFO] 为 $dev 创建 GPT 分区表..."
        parted -s "$dev" mklabel gpt mkpart primary 0% 100% || true
        sleep 1
      fi
      [ -b "${dev}p1" ] && part="${dev}p1"

      if ! pvs "$part" &>/dev/null; then
        echo "[INFO] 创建 LVM 物理卷 (PV): $part"
        pvcreate -ff -y "$part" || true
      fi

      if ! vgs "$vg_name" &>/dev/null; then
        echo "[INFO] 创建 LVM 卷组 (VG): $vg_name"
        vgcreate "$vg_name" "$part" || true
      fi

      # 再次确保 VG 已激活
      vgchange -ay "$vg_name" 2>/dev/null || true

      if ! lvs "$vg_name/$lv_name" &>/dev/null && ! lvs "$vg_name" 2>/dev/null | grep -q "$lv_name"; then
        echo "[INFO] 创建 LVM 逻辑卷 (LV): $lv_name"
        lvcreate -l 100%FREE -n "$lv_name" "$vg_name" || true
      else
        echo "[INFO] 检测到已存在逻辑卷 $vg_name/$lv_name"
      fi

      vgchange -ay "$vg_name" 2>/dev/null || true
      vgmknodes 2>/dev/null || true
      udevadm settle 2>/dev/null || true

      # 动态获取活跃的逻辑卷块设备路径
      local lv_path=""
      if [ -b "/dev/${vg_name}/${lv_name}" ]; then
        lv_path="/dev/${vg_name}/${lv_name}"
      elif [ -b "/dev/mapper/${vg_name}-${lv_name}" ]; then
        lv_path="/dev/mapper/${vg_name}-${lv_name}"
      elif [ -b "/dev/mapper/${vg_name}--${lv_name}" ]; then
        lv_path="/dev/mapper/${vg_name}--${lv_name}"
      fi

      if [ -z "$lv_path" ] || [ ! -b "$lv_path" ]; then
        echo "[ERROR] 无法找到活跃的逻辑卷块设备节点: /dev/${vg_name}/${lv_name}"
        exit 1
      fi

      # 2. 格式化逻辑卷（若未格式化，补做格式化）
      local lv_fstype=$(lsblk -no FSTYPE "$lv_path" 2>/dev/null | grep -v '^$' | head -n1 || true)
      if [ -z "$lv_fstype" ]; then
        echo "[INFO] 格式化逻辑卷 $lv_path 为 XFS 文件系统..."
        mkfs.xfs -f "$lv_path"
      else
        echo "[INFO] 逻辑卷 $lv_path 已存在文件系统: $lv_fstype"
      fi

      # 3. 配置 /etc/fstab 自动挂载
      mkdir -p "$mount_dir"
      if ! grep -q "$mount_dir" /etc/fstab; then
        echo "$lv_path $mount_dir xfs defaults 0 0" >> /etc/fstab
        echo "[INFO] 已添加自动挂载项到 /etc/fstab: $lv_path -> $mount_dir"
      fi

      # 4. 执行挂载
      echo "[INFO] 正在挂载 $mount_dir..."
      mount "$mount_dir" 2>/dev/null || mount -a || true
      echo "[SUCCESS] $dev 已成功初始化并挂载至 $mount_dir"

      ((index++))
    fi
  done
}

expand_root_lvm() {
  echo "[INFO] Expanding root partition..."
  if ! command -v growpart &>/dev/null; then
    echo "[INFO] Installing growpart tool..."
    if [ "$OS_FAMILY" = "rhel" ]; then
      $PKG_MGR install -y cloud-utils-growpart || true
    elif [ "$OS_FAMILY" = "debian" ]; then
      $PKG_MGR update -y || true
      $PKG_MGR install -y cloud-guest-utils || true
    fi
  fi
  if ! command -v lvs &>/dev/null; then
    echo "[INFO] Installing lvm2..."
    if [ "$OS_FAMILY" = "rhel" ]; then
      $PKG_MGR install -y lvm2 || true
    elif [ "$OS_FAMILY" = "debian" ]; then
      $PKG_MGR update -y || true
      $PKG_MGR install -y lvm2 || true
    fi
  fi

  local ROOT_DEV=$(df / | awk 'NR==2 {print $1}')
  if [ -z "$ROOT_DEV" ]; then
    echo "[ERROR] Unable to detect root device"
    exit 1
  fi

  local LV_PATH=$(lvs --noheadings -o lv_path | grep -E "$ROOT_DEV|/" || true)
  [ -z "$LV_PATH" ] && LV_PATH="$ROOT_DEV"
  local VG_NAME=$(lvs "$LV_PATH" -o vg_name --noheadings | awk '{print $1}' || true)
  local PV_NAME=$(pvs --noheadings -o pv_name | grep -E 'sd|nvme|vd' | head -n1 || true)

  if [ -z "$VG_NAME" ] || [ -z "$PV_NAME" ]; then
    echo "[ERROR] Unable to identify VG or PV for expansion"
    exit 1
  fi

  local DISK=$(echo "$PV_NAME" | sed -E 's/p?[0-9]+$//')
  local PART=$(echo "$PV_NAME" | sed "s|$DISK||")
  growpart "$DISK" "${PART/#p/}" || true
  pvresize "$PV_NAME" || true
  lvextend -l +100%FREE "$LV_PATH" || true

  local FSTYPE=$(lsblk -no FSTYPE "$LV_PATH" 2>/dev/null)
  if [ "$FSTYPE" = "xfs" ]; then
    xfs_growfs / || true
  elif [ "$FSTYPE" = "ext4" ]; then
    resize2fs "$LV_PATH" || true
  fi
  df -h /
}

MAIN() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[41;05m Sorry, this script must be run as root! \033[0m"
    exit $ILLEGALUSER
  fi

  if [ $# -eq 0 ]; then
    usage
    exit $MALFORMEDPARAMTER
  fi

  OPERATION=$1
  shift

  # Check repeat initialization
  case "$OPERATION" in
    all|vps|init)
      if grep -q "net.netfilter.nf_conntrack_max" /etc/sysctl.conf 2>/dev/null || grep -q "net.netfilter.nf_conntrack_max" /etc/sysctl.d/99-custom.conf 2>/dev/null; then
        echo -e "\033[33m[WARN] Already initialized, overwriting configurations...\033[0m"
      fi
      detect_os
      countdown
      ;;
    pkg|mirror|security|time|ssh|optimize|docker|disk|autodisk|expand|history|clean)
      detect_os
      ;;
    *)
      echo "[ERROR] Unknown command: $OPERATION"
      usage
      exit $UNKOWNPARAMETER
      ;;
  esac

  case "$OPERATION" in
    all)
      init_system_module
      configure_mirrors_and_pkgs
      init_kernel
      config_sshd
      set_docker_repo
      set_timezone_ntp
      disable_thp_numa
      clean_cache
      ;;
    vps)
      init_system_module
      init_kernel
      config_sshd
      ;;
    init)
      init_system_module
      init_kernel
      ;;
    pkg|mirror)
      configure_mirrors_and_pkgs
      ;;
    security)
      disable_selinux
      ;;
    time)
      set_timezone_ntp
      ;;
    ssh)
      config_sshd
      ;;
    optimize)
      init_kernel
      disable_thp_numa
      ;;
    docker)
      set_docker_repo
      ;;
    disk)
      setup_disk_lvm "$@"
      ;;
    autodisk)
      auto_format_disks "$@"
      ;;
    expand)
      expand_root_lvm
      ;;
    history)
      init_history
      ;;
    clean)
      clean_cache
      ;;
  esac

  END_TIME=$(date +%s)
  EXECUTING_TIME=$((END_TIME - START_TIME))
  echo -e "\033[42;30m Time had spent $EXECUTING_TIME seconds. \033[0m"
  echo -e "\033[40;34m ######################################################### \033[0m"
  echo -e '\n'

  # Safe self-deletion
  if [ -f "$CMD" ] && [[ "$CMD" != *"/scripts/init-linux.sh" ]]; then
    rm -f "$CMD"
  fi
  exit 0
}

MAIN "$@"