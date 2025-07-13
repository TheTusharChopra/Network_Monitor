$ErrorActionPreference = "SilentlyContinue"
$master_url = "http://192.168.29.2:8000/devices/report"
$logs_url = "http://192.168.29.2:8000/devices/logs"
$cache_file = "$env:TEMP\device_data.json"
$logs_cache_file = "$env:TEMP\device_logs.json"
$debug_log = "$env:TEMP\agent_debug.log"

# Function to log debug messages
function Write-DebugLog {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $debug_log -Append
}

# Check if running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator to access USB event logs."
    Write-DebugLog "Script not running as Administrator"
    exit 1
}

# Prompt for proxy credentials
$proxy = "http://your-proxy-server:port" # Replace with your proxy server (e.g., from proxy.pac)
$cred = Get-Credential -Message "Enter proxy credentials (username and password)"
$proxyUser = $cred.UserName
$proxyPass = $cred.GetNetworkCredential().Password
$proxyAuth = "-u ${proxyUser}:${proxyPass}"

while ($true) {
    # Check network connectivity
    $network = Test-Connection -ComputerName 192.168.29.2 -Count 1 -Quiet
    if (-not $network) {
        Write-Host "Network unavailable. Caching data and retrying in 30 seconds..."
        Write-DebugLog "Network unavailable to 192.168.29.2"
        Start-Sleep -Seconds 30
        continue
    }

    # Collect USB last connection time from Event Log
    $usb_last_connected = "Unknown"
    try {
        $usb_events = Get-WinEvent -LogName System -MaxEvents 100 -ErrorAction Stop | 
            Where-Object { $_.Id -eq 2003 -or $_.Id -eq 1006 -or $_.Message -match "USB" } | 
            Sort-Object TimeCreated -Descending | 
            Select-Object -First 1
        if ($usb_events) {
            $usb_last_connected = $usb_events.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ssZ")
            Write-DebugLog "USB event found: $usb_last_connected"
        } else {
            $usb_devices = Get-WmiObject -Class Win32_USBDevice | Where-Object { $_.LastErrorCode -eq $null }
            if ($usb_devices) {
                $latest_usb = $usb_devices | Sort-Object -Property CreationDate -Descending | Select-Object -First 1
                if ($latest_usb.CreationDate) {
                    $usb_last_connected = $latest_usb.CreationDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    Write-DebugLog "USB fallback used: $usb_last_connected"
                } else {
                    Write-DebugLog "No CreationDate in Win32_USBDevice"
                }
            } else {
                Write-DebugLog "No USB devices found in Win32_USBDevice"
            }
        }
    } catch {
        $usb_last_connected = "Error retrieving USB data"
        Write-DebugLog "Error retrieving USB data: $_"
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

    # Sanitize installed software to prevent JSON issues
    $software = $software | ForEach-Object { $_ -replace '"', '""' }

    # Collect system logs
    $logs = @()
    try {
        $events = Get-EventLog -LogName System -Newest 10 -ErrorAction Stop
        $logs = $events | ForEach-Object {
            @{
                time = $_.TimeGenerated.ToString("yyyy-MM-ddTHH:mm:ssZ")
                source = $_.Source -replace '"', '""'
                event_id = $_.EventID
                message = $_.Message -replace '"', '""'
            }
        }
    } catch {
        $logs = @(@{ time = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ"); source = "Error"; event_id = 0; message = "Failed to retrieve logs" })
        Write-DebugLog "Error retrieving logs: $_"
    }

    # Get IP address (avoid loopback)
    $ip_address = $network.IPAddress | Where-Object { $_ -notlike "127.*" -and $_ -notlike "::*" } | Select-Object -First 1
    if (-not $ip_address) {
        $ip_address = "Unknown"
        Write-DebugLog "No valid IP address found"
    }

    # Build data object
    $data = @{
        hostname = $computer.Name
        os = $os.Caption -replace '"', '""'
        os_version = $os.Version
        cpu = $cpu.Name -replace '"', '""'
        cpu_cores = $cpu.NumberOfCores
        memory_total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        disks = @($disks | ForEach-Object { @{
            device = $_.DeviceID
            model = $_.Model -replace '"', '""'
            size = [math]::Round($_.Size / 1GB, 2)
        }})
        serial_number = $bios.SerialNumber -replace '"', '""'
        hwid = $system_product.UUID -replace '"', '""'
        mac_address = $network.MACAddress | Select-Object -First 1
        ip_address = $ip_address
        bios_version = $bios.SMBIOSBIOSVersion -replace '"', '""'
        installed_software = @($software)
        last_seen = ""
        usb_last_connected = $usb_last_connected
    }

    # Build logs object
    $logs_data = @{
        hostname = $computer.Name
        ip_address = $ip_address
        logs = $logs
    }

    # Convert to JSON
    $json_data = $data | ConvertTo-Json -Depth 4
    $logs_json = $logs_data | ConvertTo-Json -Depth 4

    # Validate JSON
    try {
        $json_data | ConvertFrom-Json | Out-Null
    } catch {
        Write-Host "Invalid device JSON generated. Caching and retrying in 30 seconds..."
        Write-DebugLog "Invalid device JSON: $_"
        $json_data | Out-File -FilePath $cache_file
        Start-Sleep -Seconds 30
        continue
    }

    try {
        $logs_json | ConvertFrom-Json | Out-Null
    } catch {
        Write-Host "Invalid logs JSON generated. Caching and retrying in 30 seconds..."
        Write-DebugLog "Invalid logs JSON: $_"
        $logs_json | Out-File -FilePath $logs_cache_file
        Start-Sleep -Seconds 30
        continue
    }

    # Send device data using curl
    try {
        $curlCommand = "curl -s -X POST $master_url -H 'Content-Type: application/json' -d '$json_data' --proxy $proxy $proxyAuth"
        $response = Invoke-Expression $curlCommand
        Write-Host "Data sent successfully at $(Get-Date)"
        Write-DebugLog "Device data sent successfully: $response"
        if (Test-Path $cache_file) {
            Remove-Item $cache_file
        }
    } catch {
        Write-Host "Failed to send data: $_"
        Write-DebugLog "Failed to send device data: $_"
        $json_data | Out-File -FilePath $cache_file
    }

    # Send logs using curl
    try {
        $curlCommand = "curl -s -X POST $logs_url -H 'Content-Type: application/json' -d '$logs_json' --proxy $proxy $proxyAuth"
        $response = Invoke-Expression $curlCommand
        Write-Host "Logs sent successfully at $(Get-Date)"
        Write-DebugLog "Logs sent successfully: $response"
        if (Test-Path $logs_cache_file) {
            Remove-Item $logs_cache_file
        }
    } catch {
        Write-Host "Failed to send logs: $_"
        Write-DebugLog "Failed to send logs: $_"
        $logs_json | Out-File -FilePath $logs_cache_file
    }

    # Send cached device data if exists
    if (Test-Path $cache_file) {
        try {
            $cached_data = Get-Content -Raw $cache_file | ConvertFrom-Json
            $cached_json = $cached_data | ConvertTo-Json -Depth 4
            $curlCommand = "curl -s -X POST $master_url -H 'Content-Type: application/json' -d '$cached_json' --proxy $proxy $proxyAuth"
            $response = Invoke-Expression $curlCommand
            Write-Host "Cached data sent successfully at $(Get-Date)"
            Write-DebugLog "Cached device data sent successfully: $response"
            Remove-Item $cache_file
        } catch {
            Write-Host "Failed to send cached data: $_"
            Write-DebugLog "Failed to send cached device data: $_"
        }
    }

    # Send cached logs if exists
    if (Test-Path $logs_cache_file) {
        try {
            $cached_logs = Get-Content -Raw $logs_cache_file | ConvertFrom-Json
            $cached_logs_json = $cached_logs | ConvertTo-Json -Depth 4
            $curlCommand = "curl -s -X POST $logs_url -H 'Content-Type: application/json' -d '$cached_logs_json' --proxy $proxy $proxyAuth"
            $response = Invoke-Expression $curlCommand
            Write-Host "Cached logs sent successfully at $(Get-Date)"
            Write-DebugLog "Cached logs sent successfully: $response"
            Remove-Item $logs_cache_file
        } catch {
            Write-Host "Failed to send cached logs: $_"
            Write-DebugLog "Failed to send cached logs: $_"
        }
    }

    Start-Sleep -Seconds 30
}