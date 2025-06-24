$ErrorActionPreference = "SilentlyContinue"
  $master_url = "http://192.168.29.3:8000/devices/report"
  $logs_url = "http://192.168.29.3:8000/devices/logs"
  $cache_file = "$env:TEMP\device_data.json"
  $logs_cache_file = "$env:TEMP\device_logs.json"

  while ($true) {
      # Check network connectivity
      $network = Test-Connection -ComputerName 192.168.29.3 -Count 1 -Quiet
      if (-not $network) {
          Write-Host "Network unavailable. Caching data and retrying in 60 seconds..."
          Start-Sleep -Seconds 60
          continue
      }

      $usb_last_connected = "Unknown"
      try {
          $logName = "Microsoft-Windows-DriverFrameworks-UserMode/Operational"

        # Enable log once (you can comment this after first run)
        #   wevtutil set-log $logName /enabled:true | Out-Null

        # Fetch USB connect (2003) and disconnect (2100) events
          $usb_event = Get-WinEvent -LogName $logName -MaxEvents 100 |
                      Where-Object { $_.Id -in 2003, 2100 } |
                      Sort-Object TimeCreated -Descending |
                      Select-Object -First 1

          if ($usb_event) {
              $usb_last_connected = $usb_event.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ssZ")
          }
      } catch {
          $usb_last_connected = "Error retrieving USB data"
      }


      # Collect system information
      $computer = Get-CimInstance -ClassName Win32_ComputerSystem
      $os = Get-CimInstance -ClassName Win32_OperatingSystem
      $cpu = Get-CimInstance -ClassName Win32_Processor
      $bios = Get-CimInstance -ClassName Win32_BIOS
      $disks = Get-CimInstance -ClassName Win32_DiskDrive
      $network = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
      $software = Get-CimInstance -ClassName Win32_Product | Select-Object -ExpandProperty Name
      $system_product = Get-CimInstance -ClassName Win32_ComputerSystemProduct

      # Collect system logs
      $logs = @()
      try {
          $events = Get-EventLog -LogName System -Newest 10 -ErrorAction Stop
          $logs = $events | ForEach-Object {
              @{
                  time = $_.TimeGenerated.ToString("yyyy-MM-ddTHH:mm:ssZ")
                  source = $_.Source
                  event_id = $_.EventID
                  message = $_.Message
              }
          }
      } catch {
          $logs = @(@{ time = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ"); source = "Error"; event_id = 0; message = "Failed to retrieve logs" })
      }

      # Build data object
      $data = @{
          hostname = $computer.Name
          os = $os.Caption
          os_version = $os.Version
          cpu = $cpu.Name
          cpu_cores = $cpu.NumberOfCores
          memory_total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
          disks = @($disks | ForEach-Object { @{
              device = $_.DeviceID
              model = $_.Model
              size = [math]::Round($_.Size / 1GB, 2)
          }})
          serial_number = $bios.SerialNumber
          hwid = $system_product.UUID
          mac_address = $network.MACAddress
          ip_address = $network.IPAddress[0]
          bios_version = $bios.SMBIOSBIOSVersion
          installed_software = @($software)
          last_seen = ""
          usb_last_connected = $usb_last_connected
      }

      # Build logs object
      $logs_data = @{
          hostname = $computer.Name
          ip_address = $network.IPAddress[0]
          logs = $logs
      }

      # Convert to JSON
      $json_data = $data | ConvertTo-Json -Depth 4
      $logs_json = $logs_data | ConvertTo-Json -Depth 4

      # Send device data
      try {
          Invoke-RestMethod -Uri $master_url -Method Post -Body $json_data -ContentType "application/json"
          Write-Host "Data sent successfully at $(Get-Date)"
          if (Test-Path $cache_file) {
              Remove-Item $cache_file
          }
      } catch {
          Write-Host "Failed to send data. Caching and retrying in 60 seconds..."
          $json_data | Out-File -FilePath $cache_file
      }

      # Send logs
      try {
          Invoke-RestMethod -Uri $logs_url -Method Post -Body $logs_json -ContentType "application/json"
          Write-Host "Logs sent successfully at $(Get-Date)"
          if (Test-Path $logs_cache_file) {
              Remove-Item $logs_cache_file
          }
      } catch {
          Write-Host "Failed to send logs. Caching and retrying in 60 seconds..."
          $logs_json | Out-File -FilePath $logs_cache_file
      }

      # Send cached device data if exists
      if (Test-Path $cache_file) {
          try {
              $cached_data = Get-Content -Raw $cache_file | ConvertFrom-Json
              $cached_json = $cached_data | ConvertTo-Json -Depth 4
              Invoke-RestMethod -Uri $master_url -Method Post -Body $cached_json -ContentType "application/json"
              Write-Host "Cached data sent successfully at $(Get-Date)"
              Remove-Item $cache_file
          } catch {
              Write-Host "Failed to send cached data. Retrying in 60 seconds..."
          }
      }

      # Send cached logs if exists
      if (Test-Path $logs_cache_file) {
          try {
              $cached_logs = Get-Content -Raw $logs_cache_file | ConvertFrom-Json
              $cached_logs_json = $cached_logs | ConvertTo-Json -Depth 4
              Invoke-RestMethod -Uri $logs_url -Method Post -Body $cached_logs_json -ContentType "application/json"
              Write-Host "Cached logs sent successfully at $(Get-Date)"
              Remove-Item $logs_cache_file
          } catch {
              Write-Host "Failed to send cached logs. Retrying in 60 seconds..."
          }
      }

      Start-Sleep -Seconds 60
  }