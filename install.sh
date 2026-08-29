#!/bin/sh
set -eu

REPO="Hannimal/udm-voip"
BRANCH="${UDM_VOIP_BRANCH:-main}"
SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || SOURCE_DIR=""
DATA_DIR="/data/udm-voip"
XML_CURL="/etc/freeswitch/autoload_configs/xml_curl.conf.xml"
LEGACY_DATA="/data/vodafone-voip"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root" >&2
    exit 1
fi

command -v systemctl >/dev/null 2>&1 || { echo "systemd is required" >&2; exit 1; }
command -v busybox >/dev/null 2>&1 || { echo "busybox is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }
command -v iptables >/dev/null 2>&1 || { echo "iptables is required" >&2; exit 1; }

# Fetch the tree when the script is piped straight from the network
# (sh -c "$(curl .../install.sh)") instead of run from a checkout.
if [ -z "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/udm-voipd" ]; then
    command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
    BOOTSTRAP_DIR=$(mktemp -d)
    trap 'rm -rf "$BOOTSTRAP_DIR"' EXIT INT TERM
    echo "Downloading udm-voip ($BRANCH)..."
    curl -sSfL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" \
        | tar -xzf - -C "$BOOTSTRAP_DIR"
    SOURCE_DIR="$BOOTSTRAP_DIR/udm-voip-$BRANCH"
    [ -f "$SOURCE_DIR/udm-voipd" ] || { echo "Download failed" >&2; exit 1; }
fi

mkdir -p "$DATA_DIR/profiles"

for file in \
    VERSION \
    udm-voip-common \
    udm-voip-apply \
    udm-voip-cleanup \
    udm-voipd \
    udm-voip-diag \
    udm-voip-migrate-legacy \
    udhcpc.hook \
    acl-proxy.py \
    udm-voip-acl-proxyd; do
    cp "$SOURCE_DIR/$file" "$DATA_DIR/"
done

cp "$SOURCE_DIR"/profiles/*.conf "$DATA_DIR/profiles/"
chmod +x "$DATA_DIR"/udm-voip-* "$DATA_DIR/udm-voipd" \
    "$DATA_DIR/udhcpc.hook" "$DATA_DIR/acl-proxy.py"

[ -f /etc/udm-voip.conf ] || cp "$SOURCE_DIR/udm-voip.conf" /etc/udm-voip.conf

# Preserve the true pre-proxy FreeSWITCH configuration for uninstall/rollback.
if [ -f "$XML_CURL" ] && [ ! -f "$DATA_DIR/xml_curl.conf.xml.original" ]; then
    if [ -f "$LEGACY_DATA/xml_curl.conf.xml.original" ]; then
        cp "$LEGACY_DATA/xml_curl.conf.xml.original" "$DATA_DIR/xml_curl.conf.xml.original"
    else
        cp "$XML_CURL" "$DATA_DIR/xml_curl.conf.xml.original"
        # If a manual setup already redirected configuration to 3424, normalize the backup to 3423.
        sed -i \
          's#http://127.0.0.1:3424/api/pbx/configuration#http://127.0.0.1:3423/api/pbx/configuration#g' \
          "$DATA_DIR/xml_curl.conf.xml.original"
    fi
fi

cp "$SOURCE_DIR/systemd/udm-voip.service" /etc/systemd/system/
cp "$SOURCE_DIR/systemd/udm-voip-acl-proxy.service" /etc/systemd/system/
cp "$SOURCE_DIR/udm-voip" /usr/local/sbin/udm-voip
chmod +x /usr/local/sbin/udm-voip

systemctl daemon-reload
systemctl enable udm-voip.service udm-voip-acl-proxy.service >/dev/null

# Stop only the legacy ACL proxy first so port 3424 becomes available.
if systemctl list-unit-files vodafone-talk-xml-proxy.service --no-legend 2>/dev/null | grep -q '^vodafone-talk-xml-proxy.service'; then
    systemctl disable vodafone-talk-xml-proxy.service >/dev/null 2>&1 || true
    systemctl stop vodafone-talk-xml-proxy.service >/dev/null 2>&1 || true
fi

systemctl restart udm-voip-acl-proxy.service

# Cut over a legacy manual setup if present; otherwise start normally.
if [ -x "$DATA_DIR/udm-voip-migrate-legacy" ] && \
   { [ -f /etc/systemd/system/vodafone-voip.service ] || \
     systemctl is-active --quiet vodafone-voip.service 2>/dev/null; }; then
    "$DATA_DIR/udm-voip-migrate-legacy"
else
    systemctl restart udm-voip.service
fi

# Let the daemon redirect xml_curl once the ACL proxy is listening.
sleep 2
systemctl restart udm-voip.service
sleep 2
fs_cli -x "reload mod_xml_curl" >/dev/null 2>&1 || true
fs_cli -x "reloadacl" >/dev/null 2>&1 || true

echo
echo "udm-voip installed."
echo "Run: udm-voip diagnose"
