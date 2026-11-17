#!/bin/bash
# ==============================================================================
# Radius-Streamnet One-Line Fast Installer
# ==============================================================================
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}   🚀 جاري بدء تثبيت نظام Radius-Streamnet المحصن (نسخة Linux)   ${NC}"
echo -e "${BLUE}=================================================================${NC}"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ خطأ: يجب تشغيل التثبيت بصلاحيات الـ root (استخدم sudo bash)${NC}"
    exit 1
fi

if [ ! -f /etc/debian_version ]; then
    echo -e "${RED}❌ خطأ: هذا المثبت مخصص لتوزيعات Debian و Ubuntu فقط!${NC}"
    exit 1
fi

# Detect if local .deb exists in current folder, otherwise download
LOCAL_DEB="$(ls -t ./radius-streamnet_*.deb 2>/dev/null | head -n 1 || true)"
TMP_DEB="/tmp/radius-streamnet_latest.deb"

echo -e "${YELLOW}📦 1. تحديث الحزم وتثبيت التبعيات الأساسية (MariaDB, Curl, Systemd)...${NC}"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server curl systemd libssl-dev ca-certificates fail2ban

# Ensure MariaDB is running and create streamnet database & socket user
systemctl start mariadb >/dev/null 2>&1 || systemctl start mysql >/dev/null 2>&1 || true
if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
    SQL_CLI="$(command -v mariadb || command -v mysql)"
    ${SQL_CLI} -e "
    CREATE DATABASE IF NOT EXISTS streamnet CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS 'streamnet'@'localhost' IDENTIFIED VIA unix_socket;
    GRANT ALL PRIVILEGES ON streamnet.* TO 'streamnet'@'localhost';
    GRANT ALL PRIVILEGES ON streamnet.* TO 'root'@'localhost';
    FLUSH PRIVILEGES;
    " >/dev/null 2>&1 || true
fi

if [ -n "${LOCAL_DEB}" ] && [ -f "${LOCAL_DEB}" ]; then
    echo -e "${YELLOW}📁 استخدام الحزمة المحلية: ${LOCAL_DEB}${NC}"
    INSTALL_TARGET="${LOCAL_DEB}"
else
    GH_DEB_URL="https://github.com/haitham200711/RadiusDeploy/releases/download/v2.4.0/radius-streamnet_2.4.0_amd64.deb"
    MIRROR_DEB_URL="https://197-164-101-4.sslip.io/dist/radius-streamnet_2.4.0_amd64.deb"
    echo -e "${YELLOW}📥 2. جاري تنزيل أحدث حزمة محصنة من GitHub...${NC}"
    if ! curl -f -sSL -L -o "${TMP_DEB}" "${GH_DEB_URL}"; then
        echo -e "${YELLOW}🔄 جاري التنزيل من السيرفر البديل (Mirror)...${NC}"
        curl -f -k -sSL -L -o "${TMP_DEB}" "${MIRROR_DEB_URL}"
    fi
    INSTALL_TARGET="${TMP_DEB}"
fi

echo -e "${YELLOW}⚙️  3. جاري تثبيت الحزمة وتهيئة النظام...${NC}"
dpkg -i "${INSTALL_TARGET}" || apt-get install -f -y

if [ "${INSTALL_TARGET}" = "${TMP_DEB}" ]; then
    rm -f "${TMP_DEB}"
fi

# FreeRADIUS on the same server: packages + sql module + café / license / simultaneous-use policies.
# It needs the panel's tables, which the panel creates on its first start (postinst started it).
if [ -x /usr/lib/streamnet/freeradius/freeradius-all.sh ]; then
    echo -e "${YELLOW}📡 تثبيت وتهيئة FreeRADIUS...${NC}"
    for i in $(seq 60); do
        mysql -N -e "SELECT 1 FROM information_schema.tables WHERE table_schema='streamnet' AND table_name='radacct'" 2>/dev/null | grep -q 1 && break
        sleep 2
    done
    bash /usr/lib/streamnet/freeradius/freeradius-all.sh || echo -e "${YELLOW}⚠️  FreeRADIUS لم يكتمل — شغّل لاحقاً: bash /usr/lib/streamnet/freeradius/freeradius-all.sh${NC}"
fi

# Detect if custom domain or IP was passed
CUSTOM_TARGET="${1:-${DOMAIN:-${IP}}}"
CUSTOM_PORT="${2:-${PORT:-8080}}"
# panel admin password: given by the installer, else the panel makes a random one (admin-password.txt)
CUSTOM_PASS="${3:-${PASS:-${ADMIN_PASS:-}}}"

if [ -n "${CUSTOM_TARGET}" ] && [[ "${CUSTOM_TARGET}" =~ [a-zA-Z] ]]; then
    DOMAIN="${CUSTOM_TARGET}"
    SERVER_IP="$(curl -s -4 --max-time 3 https://ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '')"
else
    if [ -n "${CUSTOM_TARGET}" ]; then
        SERVER_IP="${CUSTOM_TARGET}"
    else
        SERVER_IP="$(curl -s -4 --max-time 3 https://ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
    fi
    if [ "${SERVER_IP}" != "127.0.0.1" ] && [ "${SERVER_IP}" != "localhost" ]; then
        DOMAIN="$(echo "${SERVER_IP}" | tr '.' '-').sslip.io"
    else
        DOMAIN=""
    fi
fi

# Set custom admin password if supplied
if [ -n "${CUSTOM_PASS}" ] && [ -x /usr/bin/streamnet ]; then
    /usr/bin/streamnet -reset-admin "${CUSTOM_PASS}" >/dev/null 2>&1 || true
fi

echo -e "${YELLOW}🔑 4. تفعيل حساب الروت (Root) وتأمين بورت الـ SSH (1992)...${NC}"

# Enable and set root password
# a RANDOM root password for THIS server (it was one fixed password for every install, printed in this public file)
ROOT_PASS="${ROOT_PASS:-$(head -c 32 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 18)}"
echo "root:${ROOT_PASS}" | chpasswd
passwd -u root >/dev/null 2>&1 || true

# Configure SSH for Port 1992 & PermitRootLogin
if [ -f /etc/ssh/sshd_config ]; then
    if grep -qE "^#?Port " /etc/ssh/sshd_config; then
        sed -i -E 's/^#?Port .*/Port 1992/' /etc/ssh/sshd_config
    else
        echo "Port 1992" >> /etc/ssh/sshd_config
    fi

    if grep -qE "^#?PermitRootLogin " /etc/ssh/sshd_config; then
        sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi

    if grep -qE "^#?PasswordAuthentication " /etc/ssh/sshd_config; then
        sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    else
        echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    fi
fi

# Modern Debian/Ubuntu drop-in configuration
if [ -d /etc/ssh/sshd_config.d ]; then
    cat << 'SSHEOF' > /etc/ssh/sshd_config.d/99-streamnet-security.conf
Port 1992
PermitRootLogin yes
PasswordAuthentication yes
SSHEOF
    chmod 644 /etc/ssh/sshd_config.d/99-streamnet-security.conf
fi

# Open port in firewall if UFW is active
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 1992/tcp >/dev/null 2>&1 || true
fi

# Debian 12 socket activation handling
if systemctl is-active --quiet ssh.socket 2>/dev/null || systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
    systemctl disable --now ssh.socket >/dev/null 2>&1 || true
    systemctl enable --now ssh.service >/dev/null 2>&1 || true
fi

# Restart SSH service
systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || service ssh restart >/dev/null 2>&1 || true

echo -e "${YELLOW}🌐 5. إعداد وتثبيت خادم Caddy وتفعيل شهادة الأمان (Auto SSL)...${NC}"

# Install Caddy if not installed
if ! command -v caddy >/dev/null 2>&1; then
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg >/dev/null 2>&1 || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes 2>/dev/null || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null 2>&1 || true
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y caddy >/dev/null 2>&1 || true
fi

# Configure Caddy reverse proxy with Auto SSL
if command -v caddy >/dev/null 2>&1 && [ -n "${DOMAIN}" ]; then
    mkdir -p /etc/caddy
    cat << CADDYEOF > /etc/caddy/Caddyfile
http://${DOMAIN} {
    handle /api/router/* {
        reverse_proxy 127.0.0.1:8080
    }
    handle /end* {
        reverse_proxy 127.0.0.1:8080
    }
    handle /api/end/* {
        reverse_proxy 127.0.0.1:8080
    }
    handle {
        redir https://{host}{uri} permanent
    }
}

https://${DOMAIN} {
    reverse_proxy 127.0.0.1:8080
    encode gzip
}
CADDYEOF

    if [ -n "${SERVER_IP}" ] && [ "${SERVER_IP}" != "${DOMAIN}" ] && [ "${SERVER_IP}" != "127.0.0.1" ]; then
        cat << CADDYIP >> /etc/caddy/Caddyfile

http://${SERVER_IP} {
    handle /api/router/* {
        reverse_proxy 127.0.0.1:8080
    }
    handle /end* {
        reverse_proxy 127.0.0.1:8080
    }
    handle /api/end/* {
        reverse_proxy 127.0.0.1:8080
    }
    handle {
        redir https://${DOMAIN}{uri} permanent
    }
}
CADDYIP
    fi

    # Set SN_LISTEN to 127.0.0.1:8080 so traffic is secured through Caddy
    if [ -f /etc/streamnet/streamnet.env ]; then
        sed -i "s/^SN_LISTEN=.*/SN_LISTEN=127.0.0.1:8080/" /etc/streamnet/streamnet.env
        systemctl restart streamnet.service || true
    fi

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
    fi

    systemctl daemon-reload
    systemctl enable --now caddy >/dev/null 2>&1 || true
    systemctl restart caddy >/dev/null 2>&1 || true
else
    # Fallback to direct port if Caddy is not available
    if [ -f /etc/streamnet/streamnet.env ]; then
        sed -i "s/^SN_LISTEN=.*/SN_LISTEN=0.0.0.0:${CUSTOM_PORT}/" /etc/streamnet/streamnet.env
        systemctl restart streamnet.service || true
    fi
fi

ADMIN_PASS=""
if [ -f /var/lib/streamnet/admin-password.txt ]; then
    ADMIN_PASS="$(cat /var/lib/streamnet/admin-password.txt)"
fi

if [ -n "${DOMAIN}" ] && command -v caddy >/dev/null 2>&1; then
    PANEL_URL="https://${DOMAIN}"
    SSL_NOTE="🔒 مفعل تلقائياً (Let's Encrypt Auto SSL)"
else
    PANEL_URL="http://${SERVER_IP}:${CUSTOM_PORT}"
    SSL_NOTE="غير مفعل (اتصال HTTP)"
fi

echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}  🎉 تم تثبيت وتشغيل نظام Radius-Streamnet بنجاح وبأعلى أداء!   ${NC}"
echo -e "${GREEN}  - رابط لوحة التحكم:   ${PANEL_URL}${NC}"
echo -e "${GREEN}  - حالة شهادة الـ SSL: ${SSL_NOTE}${NC}"
echo -e "${GREEN}  - اسم مستخدم اللوحة:  admin${NC}"
if [ -n "${ADMIN_PASS}" ]; then
echo -e "${GREEN}  - كلمة مرور اللوحة:   ${ADMIN_PASS}${NC}"
fi
echo -e "${GREEN}  ---------------------------------------------------------------${NC}"
echo -e "${GREEN}  🔐 بيانات السيرفر (SSH & Root):${NC}"
echo -e "${GREEN}  - مستخدم الروت:       root${NC}"
echo -e "${GREEN}  - كلمة مرور الروت:    ${ROOT_PASS}   (احفظها دلوقتي — مش هتظهر تاني)${NC}"
echo -e "${GREEN}  - بورت الـ SSH:       1992${NC}"
if [ -n "${SERVER_IP}" ]; then
echo -e "${GREEN}  - أمر الدخول السريع:  ssh -p 1992 root@${SERVER_IP}${NC}"
fi
echo -e "${GREEN}  ---------------------------------------------------------------${NC}"
echo -e "${GREEN}  - حالة خدمة النظام:   systemctl status streamnet.service${NC}"
if command -v caddy >/dev/null 2>&1; then
echo -e "${GREEN}  - حالة خدمة الـ SSL:  systemctl status caddy.service${NC}"
fi
echo -e "${GREEN}  - مسار الإعدادات:     /etc/streamnet/streamnet.env${NC}"
echo -e "${GREEN}  - متابعة السجلات:     journalctl -u streamnet.service -f${NC}"
echo -e "${GREEN}=================================================================${NC}"
