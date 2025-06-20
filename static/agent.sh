#!/bin/bash
  MASTER_URL="http://192.168.29.2:8000/devices/report"  # Replace with master URL
  CACHE_FILE="/tmp/device_data.json"

  while true; do
      # Check network connectivity
      if ! ping -q -c 1 192.168.29.2 &>/dev/null; then
          echo "Network unavailable. Caching data and retrying in 30 seconds..."
          sleep 30
          continue
      fi

      # Collect system information
      HOSTNAME=$(hostname)
      OS=$(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep -E '^PRETTY_NAME=' | cut -d'"' -f2)
      OS_VERSION=$(uname -r)
      CPU=$(lscpu | grep -E "^Model name:" | cut -d':' -f2- | xargs)
      CPU_CORES=$(nproc)
      MEMORY_TOTAL=$(awk '/MemTotal|Mem:/ {print $2/1024/1024}' /proc/meminfo | head -n 1)
      SERIAL_NUMBER=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo "Unknown")
      HWID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null || echo "Unknown")
      MAC_ADDRESS=$(ip link show | grep -E "ether" | awk '{print $2}' | head -n 1)
      IP_ADDRESS=$(ip addr show | grep -E "inet " | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
      BIOS_VERSION=$(dmidecode -s bios-version 2>/dev/null || echo "Unknown")
      INSTALLED_SOFTWARE=$(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' | tr '\n' ',' | sed 's/,$//')

      # Collect disk information
      DISKS=$(lsblk -b -o NAME,MODEL,SIZE | awk '/disk/ {printf "{\"device\":\"%s\",\"model\":\"%s\",\"size\":%.2f}", $1, $2, $3/1024/1024/1024}')
      if [ -z "$DISKS" ]; then
          DISKS='[]'
      else
          DISKS="[$DISKS]"
      fi

      # Escape special characters for JSON
      escape_json() {
          printf '%s' "$1" | sed 's/"/\\"/g; s/\\/\\\\/g; s/\n/\\n/g'
      }

      HOSTNAME=$(escape_json "$HOSTNAME")
      OS=$(escape_json "$OS")
      CPU=$(escape_json "$CPU")
      SERIAL_NUMBER=$(escape_json "$SERIAL_NUMBER")
      HWID=$(escape_json "$HWID")
      MAC_ADDRESS=$(escape_json "$MAC_ADDRESS")
      IP_ADDRESS=$(escape_json "$IP_ADDRESS")
      BIOS_VERSION=$(escape_json "$BIOS_VERSION")
      INSTALLED_SOFTWARE=$(echo "$INSTALLED_SOFTWARE" | sed 's/,/","/g')
      if [ -n "$INSTALLED_SOFTWARE" ]; then
          INSTALLED_SOFTWARE="[\"$INSTALLED_SOFTWARE\"]"
      else
          INSTALLED_SOFTWARE='[]'
      fi

      # Build JSON data
      DATA=$(printf '{
          "hostname": "%s",
          "os": "%s",
          "os_version": "%s",
          "cpu": "%s",
          "cpu_cores": %d,
          "memory_total": %.2f,
          "disks": %s,
          "serial_number": "%s",
          "hwid": "%s",
          "mac_address": "%s",
          "ip_address": "%s",
          "bios_version": "%s",
          "installed_software": %s,
          "last_seen": ""
      }' "$HOSTNAME" "$OS" "$OS_VERSION" "$CPU" "$CPU_CORES" "$MEMORY_TOTAL" "$DISKS" "$SERIAL_NUMBER" "$HWID" "$MAC_ADDRESS" "$IP_ADDRESS" "$BIOS_VERSION" "$INSTALLED_SOFTWARE")

      # Send to master
      if curl -s -X POST "$MASTER_URL" -H "Content-Type: application/json" -d "$DATA"; then
          echo "Data sent successfully at $(date)"
          [ -f "$CACHE_FILE" ] && rm "$CACHE_FILE"
      else
          echo "Failed to send data. Caching and retrying in 30 seconds..."
          echo "$DATA" > "$CACHE_FILE"
      fi

      # Send cached data if exists
      if [ -f "$CACHE_FILE" ]; then
          if curl -s -X POST "$MASTER_URL" -H "Content-Type: application/json" -d @"$CACHE_FILE"; then
              echo "Cached data sent successfully at $(date)"
              rm "$CACHE_FILE"
          else
              echo "Failed to send cached data. Retrying in 30 seconds..."
          fi
      fi

      sleep 30
  done