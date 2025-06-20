$ErrorActionPreference = "SilentlyContinue"
$master_url = "http://192.168.29.2:8000/devices/report"  # Replace with master IP

# Collect system information
$computer = Get-CimInstance -ClassName Win32_ComputerSystem
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$cpu = Get-CimInstance -ClassName Win32_Processor
$bios = Get-CimInstance -ClassName Win32_BIOS
$disks = Get-CimInstance -ClassName Win32_DiskDrive
$network = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
$software = Get-CimInstance -ClassName Win32_Product | Select-Object -ExpandProperty Name
$system_product = Get-CimInstance -ClassName Win32_ComputerSystemProduct

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
    last_seen = ""  # Server will set this
}

# Convert to JSON
$json_data = $data | ConvertTo-Json -Depth 4

# Send to master
try {
    Invoke-RestMethod -Uri $master_url -Method Post -Body $json_data -ContentType "application/json"
} catch {
    # Cache locally if master unreachable
    $json_data | Out-File -FilePath "$env:TEMP\device_data.json"
}