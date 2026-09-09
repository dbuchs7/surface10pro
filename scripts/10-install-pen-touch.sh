#!/usr/bin/env bash
# Installs the linux-surface kernel + iptsd + libwacom-surface to enable
# pen and touchscreen support on a Surface Pro 10 for Business running
# Zorin OS 18.x (Ubuntu 24.04 LTS base).
#
# This script MODIFIES your system: it adds an apt repository, installs a
# second kernel, and (if Secure Boot is on) enrolls a MOK signing key.
# It does NOT remove your existing kernel, so you can always boot back into
# it from the GRUB "Advanced options" menu.
#
# Run scripts/00-check-system.sh first and review its output.
set -euo pipefail

if [ "$(id -u)" = "0" ]; then
    echo "Please run this as your normal user (it calls sudo itself), not as root." >&2
    exit 1
fi

. /etc/os-release
if [ "${VERSION_ID:-}" != "24.04" ]; then
    echo "Warning: this script targets Ubuntu 24.04 (Zorin OS 18.x)."
    echo "Detected VERSION_ID=${VERSION_ID:-unknown}. Continuing is possible but unverified."
    read -r -p "Continue anyway? [y/N] " ans
    [ "${ans,,}" = "y" ] || exit 1
fi

cat <<'EOF'
This will:
  1. Add the linux-surface apt repository and signing key
  2. Install linux-image-surface, linux-headers-surface, libwacom-surface, iptsd
  3. Enroll a Secure Boot MOK key if Secure Boot is currently enabled
  4. Update GRUB

Your current Zorin kernel stays installed as a fallback.
EOF
read -r -p "Proceed? [y/N] " ans
[ "${ans,,}" = "y" ] || exit 1

echo "==> Importing linux-surface signing key"
wget -qO - https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc \
    | gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/linux-surface.gpg

echo "==> Adding apt repository"
echo "deb [arch=amd64] https://pkg.surfacelinux.com/debian release main" \
    | sudo tee /etc/apt/sources.list.d/linux-surface.list

echo "==> apt update"
sudo apt update

echo "==> Installing surface kernel + pen/touch stack"
sudo apt install -y linux-image-surface linux-headers-surface libwacom-surface iptsd

SECURE_BOOT_ON=0
if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    SECURE_BOOT_ON=1
fi

if [ "$SECURE_BOOT_ON" = "1" ]; then
    echo "==> Secure Boot is enabled: installing MOK enrollment package"
    sudo apt install -y linux-surface-secureboot-mok
    cat <<'EOF'

IMPORTANT: on the next reboot a blue "MokManager" screen appears.
  1. Select "Enroll MOK"
  2. Select "Continue"
  3. Select "Yes" to enroll
  4. Enter the password: surface
  5. Reboot

Without this step the surface kernel will not boot while Secure Boot is on.
EOF
else
    echo "==> Secure Boot not enabled (or mokutil unavailable) - skipping MOK enrollment."
fi

echo "==> Updating GRUB"
sudo update-grub

cat <<'EOF'

==> Done. Next steps:
  1. Reboot:  sudo reboot
  2. If the blue MokManager screen appears, follow the steps printed above.
  3. At the GRUB menu, if it does not boot the surface kernel by default,
     choose "Advanced options for Ubuntu" and pick the entry containing "surface".
  4. After login, verify:      uname -a          (should contain "surface")
  5. Check the daemon:         systemctl status iptsd
  6. Test pen/touch input:     sudo libinput debug-events
     (touch the screen / hover the pen, watch for events, Ctrl+C to stop)

Rollback if needed:  scripts/90-uninstall-surface-kernel.sh
EOF
