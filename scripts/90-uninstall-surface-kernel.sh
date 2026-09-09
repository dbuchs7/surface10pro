#!/usr/bin/env bash
# Rollback for scripts/10-install-pen-touch.sh.
# Removes the linux-surface kernel/packages and the apt repository.
# Your original Zorin kernel is untouched, so this is safe to run even after
# booting into the surface kernel - the stock kernel takes over on next boot.
set -euo pipefail

if [ "$(id -u)" = "0" ]; then
    echo "Please run this as your normal user (it calls sudo itself), not as root." >&2
    exit 1
fi

cat <<'EOF'
This will remove:
  linux-image-surface, linux-headers-surface, libwacom-surface, iptsd,
  linux-surface-secureboot-mok (if present), and the linux-surface apt repo.
EOF
read -r -p "Proceed? [y/N] " ans
[ "${ans,,}" = "y" ] || exit 1

sudo apt purge -y linux-image-surface linux-headers-surface libwacom-surface \
    iptsd linux-surface-secureboot-mok 2>/dev/null || true
sudo apt autoremove -y
sudo rm -f /etc/apt/sources.list.d/linux-surface.list \
           /etc/apt/trusted.gpg.d/linux-surface.gpg
sudo apt update
sudo update-grub

echo "==> Done. Reboot to return to your stock Zorin kernel: sudo reboot"
