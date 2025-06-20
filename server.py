import os
import json
import socket
from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, List
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

@app.get("/", response_class=HTMLResponse)
async def serve_ui():
    """Serve the React frontend."""
    with open("static/index.html", "r") as f:
        return HTMLResponse(content=f.read())

@app.get("/devices")
async def get_devices():
    """Return all device data from cache."""
    if os.path.exists(CACHE_FILE):
        with open(CACHE_FILE, "r") as f:
            return json.load(f)
    return []

@app.post("/devices/report")
async def receive_device_data(data: DeviceData):
    """Receive and store device data from slaves."""
    devices = []
    if os.path.exists(CACHE_FILE):
        with open(CACHE_FILE, "r") as f:
            devices = json.load(f)
    
    # Update or add device
    data_dict = data.dict()
    data_dict["last_seen"] = datetime.utcnow().isoformat() + "Z"  # UTC timestamp
    devices = [d for d in devices if d["ip_address"] != data.ip_address]
    devices.append(data_dict)
    
    with open(CACHE_FILE, "w") as f:
        json.dump(devices, f)
    return {"status": "received"}

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

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)