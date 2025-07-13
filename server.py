import os
import json
import socket
from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, List, Any
import uvicorn

app = FastAPI()

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods
    allow_headers=["*"],  # Allows all headers
)

# Mount static files with proper MIME types
app.mount("/static", StaticFiles(directory="static", html=True), name="static")

# Cache file for device data
CACHE_FILE = "device_data.json"
LOGS_CACHE_FILE = "device_logs.json"

# Pydantic model for device data
class DeviceData(BaseModel):
    hostname: str
    os: str
    os_version: str
    cpu: str
    cpu_cores: int
    memory_total: float
    disks: List[Dict]
    serial_number: str
    hwid: str
    mac_address: str
    ip_address: str
    bios_version: str = ""
    installed_software: List[str] = []
    last_seen: str = ""  # ISO format timestamp
    usb_last_connected: str = ""  # ISO format timestamp

class DeviceLogs(BaseModel):
    hostname: str
    ip_address: str
    logs: List[dict]

# Helper function to safely load JSON data from a file
def safe_load_json(filename):
    try:
        with open(filename, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, FileNotFoundError):
        return []

@app.get("/", response_class=HTMLResponse)
async def serve_ui():
    """Serve the React frontend."""
    with open("static/index.html", "r") as f:
        return HTMLResponse(content=f.read())

@app.get("/devices")
async def get_devices():
    """Return all device data from cache."""
    if os.path.exists(CACHE_FILE):
        return safe_load_json(CACHE_FILE)
    return []

@app.post("/devices/report")
async def receive_device_data(data: DeviceData):
    """Receive and store device data from slaves."""
    devices = safe_load_json(CACHE_FILE) if os.path.exists(CACHE_FILE) else []
    # Update or add device
    data_dict = data.model_dump()
    from datetime import timezone
    data_dict["last_seen"] = datetime.now(timezone.utc).isoformat()
    devices = [d for d in devices if d["ip_address"] != data.ip_address]
    devices.append(data_dict)
    with open(CACHE_FILE, "w") as f:
        json.dump(devices, f)
    return {"status": "received"}

@app.post("/devices/logs")
async def receive_device_logs(data: DeviceLogs):
    logs = safe_load_json(LOGS_CACHE_FILE) if os.path.exists(LOGS_CACHE_FILE) else []
    data_dict = data.model_dump()
    logs = [l for l in logs if l["ip_address"] != data.ip_address]
    logs.append(data_dict)
    with open(LOGS_CACHE_FILE, "w") as f:
        json.dump(logs, f)
    return {"status": "received"}

@app.get("/devices/logs/{ip_address}")
async def get_device_logs(ip_address: str):
    logs = safe_load_json(LOGS_CACHE_FILE) if os.path.exists(LOGS_CACHE_FILE) else []
    for log in logs:
        if log["ip_address"] == ip_address:
            return log
    return {"hostname": "Unknown", "ip_address": ip_address, "logs": []}

@app.get("/download/windows")
async def download_windows_agent():
    """Serve Windows PowerShell agent."""
    if os.path.exists("static/agent.ps1"):
        return FileResponse("static/agent.ps1", filename="agent.ps1")
    raise HTTPException(status_code=404, detail="Agent not found")

@app.get("/download/linux")
async def download_linux_agent():
    """Serve Linux Bash agent."""
    if os.path.exists("static/agent.sh"):
        return FileResponse("static/agent.sh", filename="agent.sh")
    raise HTTPException(status_code=404, detail="Agent not found")

@app.get("/download/windows-bat")
async def download_windows_bat():
    """Serve Windows batch wrapper."""
    if os.path.exists("static/run_agent.bat"):
        return FileResponse("static/run_agent.bat", filename="run_agent.bat")
    raise HTTPException(status_code=404, detail="Batch file not found")

@app.get("/download/windows-proxy")
async def download_windows_proxy():
    """Serve Windows Proxy Agent."""
    if os.path.exists("static/agent_with_proxy.ps1"):
        return FileResponse("static/agent_with_proxy.ps1", filename="agent_with_proxy.ps1")
    raise HTTPException(status_code=404, detail="Proxy agent not found")

@app.get("/download/windows-proxy-bat")
async def download_windows_proxy_bat():
    """Serve Windows Proxy Agent."""
    if os.path.exists("static/run_proxy.bat"):
        return FileResponse("static/run_proxy.bat", filename="run_proxy.bat")
    raise HTTPException(status_code=404, detail="Proxy agent not found")

@app.get("/download/clear_usb_history_windows")
async def download_clear_usb_history_windows():
    """Serve Windows batch wrapper."""
    if os.path.exists("static/clear_usb_history.bat"):
        return FileResponse("static/clear_usb_history.bat", filename="clear_usb_history.bat")
    raise HTTPException(status_code=404, detail="Batch file not found")

@app.get("/download/clear_usb_history_linux")
async def download_clear_usb_history_linux():
    """Serve Linux Bash wrapper."""
    if os.path.exists("static/clear_usb_history.sh"):
        return FileResponse("static/clear_usb_history.sh", filename="clear_usb_history.sh")
    raise HTTPException(status_code=404, detail="Bash file not found")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)