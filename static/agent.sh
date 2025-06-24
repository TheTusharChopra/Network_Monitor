#!/bin/bash
  MASTER_URL="http://192.168.29.3:8000/devices/report"
  LOGS_URL="http://192.168.29.3:8000/devices/logs"
  CACHE_FILE="/tmp/device_data.json"
  LOGS_CACHE_FILE="/tmp/device_logs.json"
  DEBUG_LOG="/tmp/agent_debug.log"

  # Function to log debug messages
  log_debug() {
      echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$DEBUG_LOG"
  }

  # Function to safely escape JSON strings
  escape_json() {
      printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null | sed 's/^"//;s/"$//'
      if [ $? -ne 0 ]; then
          echo "Unknown"
      fi
  }

  # Function to validate JSON
  validate_json() {
      echo "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
      return $?
  }

  while true; do
      # Check network connectivity
      if ! ping -q -c 1 192.168.29.3 &>/dev/null; then
          echo "Network unavailable. Retrying in 30 seconds..."
          log_debug "Network unavailable to 192.168.29.3"
          sleep 30
          continue
      fi

      # Test HTTP connectivity
      if ! curl -s -f -m 5 http://192.168.29.3:8000/devices >/dev/null; then
          echo "Cannot reach master server at $MASTER_URL. Retrying in 30 seconds..."
          log_debug "HTTP connectivity failed to $MASTER_URL"
          sleep 30
          continue
      fi

      # Collect USB last connection time
      USB_LAST_CONNECTED="Unknown"
      if [ -f /var/log/syslog ]; then
          LAST_USB=$(grep -i "usb.*new.*device" /var/log/syslog | tail -n 1 | awk '{print $1,$2,$3}')
          if [ -n "$LAST_USB" ]; then
              USB_LAST_CONNECTED=$(date -d "$LAST_USB" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "Unknown")
          fi
      elif [ -f /var/log/messages ]; then
          LAST_USB=$(grep -i "usb.*new.*device" /var/log/messages | tail -n 1 | awk '{print $1,$2,$3}')
          if [ -n "$LAST_USB" ]; then
              USB_LAST_CONNECTED=$(date -d "$LAST_USB" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "Unknown")
          fi
      fi
      USB_LAST_CONNECTED=$(escape_json "$USB_LAST_CONNECTED")

      # Collect system logs
      LOGS="[]"
      if [ -f /var/log/syslog ]; then
          LOGS=$(tail -n 10 /var/log/syslog | while read -r line; do
              TIME=$(echo "$line" | awk '{print $1,$2,$3}' | xargs)
              if [ -n "$TIME" ]; then
                  TIME=$(date -d "$TIME" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "Unknown")
                  MESSAGE=$(echo "$line" | cut -d' ' -f4- | sed 's/"/\\"/g')
                  printf '{"time":"%s","source":"syslog","event_id":0,"message":"%s"},' "$TIME" "$(escape_json "$MESSAGE")"
              fi
          done | sed 's/,$//' | sed 's/^/[/;s/$/]/')
      elif [ -f /var/log/messages ]; then
          LOGS=$(tail -n 10 /var/log/messages | while read -r line; do
              TIME=$(echo "$line" | awk '{print $1,$2,$3}' | xargs)
              if [ -n "$TIME" ]; then
                  TIME=$(date -d "$TIME" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "Unknown")
                  MESSAGE=$(echo "$line" | cut -d' ' -f4- | sed 's/"/\\"/g')
                  printf '{"time":"%s","source":"messages","event_id":0,"message":"%s"},' "$TIME" "$(escape_json "$MESSAGE")"
              fi
          done | sed 's/,$//' | sed 's/^/[/;s/$/]/')
      fi
      if [ -z "$LOGS" ] || [ "$LOGS" = "[]" ]; then
          LOGS='[{"time":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'","source":"error","event_id":0,"message":"Failed to retrieve logs"}]'
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
      # Get IP address from default route (avoid 127.0.0.1)
      IP_ADDRESS=$(ip route get 192.168.29.3 2>/dev/null | grep -oP 'src \K[\d.]+' | head -n 1)
      if [ -z "$IP_ADDRESS" ]; then
          IP_ADDRESS=$(ip addr show | grep -E "inet " | awk '{print $2}' | cut -d'/' -f1 | grep -v "127.0.0.1" | head -n 1)
      fi
      if [ -z "$IP_ADDRESS" ]; then
          IP_ADDRESS="Unknown"
      fi
      BIOS_VERSION=$(dmidecode -s bios-version 2>/dev/null || echo "Unknown")
      INSTALLED_SOFTWARE=$(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' | tr '\n' '\0' | xargs -0 -I {} sh -c 'echo -n "$(printf %s "{}" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" 2>/dev/null),"' | sed 's/,$//')

      # Collect disk information (handle WSL2)
      DISKS=$(lsblk -b -o NAME,MODEL,SIZE | awk '/disk/ {printf "{\"device\":\"%s\",\"model\":\"%s\",\"size\":%.2f}", $1, ($2 != "" ? $2 : "Unknown"), $3/1024/1024/1024}' | sed ':a;N;$!ba;s/\n/,/g')
      if [ -z "$DISKS" ]; then
          DISKS='[{"device":"wsl-disk","model":"Virtual","size":0}]'
      else
          DISKS="[$DISKS]"
      fi

      # Escape special characters for JSON
      HOSTNAME=$(escape_json "$HOSTNAME")
      OS=$(escape_json "$OS")
      CPU=$(escape_json "$CPU")
      SERIAL_NUMBER=$(escape_json "$SERIAL_NUMBER")
      HWID=$(escape_json "$HWID")
      MAC_ADDRESS=$(escape_json "$MAC_ADDRESS")
      IP_ADDRESS=$(escape_json "$IP_ADDRESS")
      BIOS_VERSION=$(escape_json "$BIOS_VERSION")
      if [ -n "$INSTALLED_SOFTWARE" ]; then
          INSTALLED_SOFTWARE="[$INSTALLED_SOFTWARE]"
      else
          INSTALLED_SOFTWARE='[]'
      fi

      # Build device data
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
          "last_seen": "",
          "usb_last_connected": "%s"
      }' "$HOSTNAME" "$OS" "$OS_VERSION" "$CPU" "$CPU_CORES" "$MEMORY_TOTAL" "$DISKS" "$SERIAL_NUMBER" "$HWID" "$MAC_ADDRESS" "$IP_ADDRESS" "$BIOS_VERSION" "$INSTALLED_SOFTWARE" "$USB_LAST_CONNECTED")

      # Debug JSON
      log_debug "Generated JSON: $DATA"

      # Validate device JSON
      if ! validate_json "$DATA"; then
          echo "Invalid device JSON generated. Caching and retrying in 30 seconds..."
          log_debug "Invalid JSON detected"
          echo "$DATA" > "$CACHE_FILE"
          sleep 30
          continue
      fi

      # Build logs data
      LOGS_DATA=$(printf '{
          "hostname": "%s",
          "ip_address": "%s",
          "logs": %s
      }' "$HOSTNAME" "$IP_ADDRESS" "$LOGS")

      # Validate logs JSON
      if ! validate_json "$LOGS_DATA"; then
          echo "Invalid logs JSON generated. Caching and retrying in 30 seconds..."
          log_debug "Invalid logs JSON detected"
          echo "$LOGS_DATA" > "$LOGS_CACHE_FILE"
          sleep 30
          continue
      fi

      # Send device data
      CURL_OUT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$MASTER_URL" -H "Content-Type: application/json" -d "$DATA" 2>&1)
      if [ "$CURL_OUT" = "200" ]; then
          echo "Data sent successfully at $(date '+%Y-%m-%d %H:%M:%S')"
          log_debug "Device data sent successfully"
          [ -f "$CACHE_FILE" ] && rm "$CACHE_FILE"
      else
          echo "Failed to send data (HTTP $CURL_OUT). Caching and retrying in 30 seconds..."
          log_debug "Failed to send device data (HTTP $CURL_OUT)"
          echo "$DATA" > "$CACHE_FILE"
      fi

      # Send logs
      CURL_OUT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$LOGS_URL" -H "Content-Type: application/json" -d "$LOGS_DATA" 2>&1)
      if [ "$CURL_OUT" = "200" ]; then
          echo "Logs sent successfully at $(date '+%Y-%m-%d %H:%M:%S')"
          log_debug "Logs sent successfully"
          [ -f "$LOGS_CACHE_FILE" ] && rm "$LOGS_CACHE_FILE"
      else
          echo "Failed to send logs (HTTP $CURL_OUT). Caching and retrying in 30 seconds..."
          log_debug "Failed to send logs (HTTP $CURL_OUT)"
          echo "$LOGS_DATA" > "$LOGS_CACHE_FILE"
      fi

      # Send cached device data if exists
      if [ -f "$CACHE_FILE" ]; then
          CURL_OUT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$MASTER_URL" -H "Content-Type: application/json" -d @"$CACHE_FILE" 2>&1)
          if [ "$CURL_OUT" = "200" ]; then
              echo "Cached data sent successfully at $(date '+%Y-%m-%d %H:%M:%S')"
              log_debug "Cached device data sent successfully"
              rm "$CACHE_FILE"
          else
              echo "Failed to send cached data (HTTP $CURL_OUT). Retrying in 30 seconds..."
              log_debug "Failed to send cached device data (HTTP $CURL_OUT)"
          fi
      fi

      # Send cached logs if exists
      if [ -f "$LOGS_CACHE_FILE" ]; then
          CURL_OUT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$LOGS_URL" -H "Content-Type: application/json" -d @"$LOGS_CACHE_FILE" 2>&1)
          if [ "$CURL_OUT" = "200" ]; then
              echo "Cached logs sent successfully at $(date '+%Y-%m-%d %H:%M:%S')"
              log_debug "Cached logs sent successfully"
              rm "$LOGS_CACHE_FILE"
          else
              echo "Failed to send cached logs (HTTP $CURL_OUT). Retrying in 30 seconds..."
              log_debug "Failed to send cached logs (HTTP $CURL_OUT)"
          fi
      fi

      sleep 30
  done