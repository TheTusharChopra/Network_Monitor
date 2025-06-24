#!/bin/bash

# Check if running as root
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root (sudo ./clear_usb_history.sh)"
    exit 1
fi

echo "===================================="
echo "  Clearing USB History (Ubuntu)"
echo "===================================="

# 1. Clear USB logs from journalctl
echo "Clearing journalctl USB logs..."
journalctl --rotate
journalctl --vacuum-time=1s

# 2. Remove USB logs from syslog/messages
echo "Wiping syslog/messages..."
LOG_FILES=("/var/log/syslog" "/var/log/messages")
for log in "${LOG_FILES[@]}"; do
    if [ -f "$log" ]; then
        cp /dev/null "$log"
        echo "Cleared $log"
    fi
done

# 3. Clear USB device info from udev
echo "Clearing udev USB rules and db..."
rm -f /etc/udev/rules.d/70-persistent-usb.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -rf /run/udev/data/*

# 4. Optional: Clear recent mount points (if USB was mounted)
echo "Clearing recent mount point info..."
rm -rf /media/$USER/*
rm -rf /run/media/$USER/*

# 5. Clear bash history of USB tools (optional)
echo "Clearing recent bash USB tool commands..."
sed -i '/lsusb/d' ~/.bash_history
sed -i '/mount/d' ~/.bash_history
sed -i '/udevadm/d' ~/.bash_history

echo
echo "USB connection traces cleared!"
echo "Please reboot your system for full effect."
