# SSPL Central Network Monitoring System

![DRDO Logo](static/drdo_logo.png)

A central network monitoring system for collecting and visualizing hardware and software inventory from multiple Windows and Linux machines. Built with FastAPI (Python backend) and a React-based frontend.

---

## Features
- Collects detailed hardware and software info from Windows and Linux clients
- Centralized dashboard for device inventory
- Download device data as CSV or PDF
- Simple login-protected web UI
- Agents for Windows (PowerShell) and Linux (Bash)

---

## Prerequisites
- Python 3.8+
- pip (Python package manager)
- (For Linux agent) curl, lsb_release, dmidecode, lsblk, awk, etc.
- (For Windows agent) PowerShell 5+

---

## Installation & Setup

### 1. Clone the Repository
```sh
git clone <repo-url>
cd Network_Monitor
```

### 2. Install Python Dependencies
It is recommended to use a virtual environment:
```sh
python -m venv venv
venv\Scripts\activate  # On Windows
# or
source venv/bin/activate  # On Linux/Mac
pip install -r requirements.txt
```

### 3. Run the Server
```sh
python server.py
```
The server will start at `http://0.0.0.0:8000/` (default port 8000).

---

## Web Dashboard
- Open your browser and go to `http://<server-ip>:8000/`
- Login with:
  - **Username:** `sspl`
  - **Password:** `password`
- View all reported devices, sort columns, and download device data as CSV or PDF.

---

## Deploying Agents

### Windows Agent
1. Download `agent.ps1` and `run_agent.bat` from the dashboard or from `static/`.
2. Run the agent:
   - With PowerShell:
     ```sh
     powershell -ExecutionPolicy Bypass -File agent.ps1
     ```
   - Or double-click `run_agent.bat` (which runs the above command).

### Linux Agent
1. Download `agent.sh` from the dashboard or from `static/`.
2. Make it executable:
   ```sh
   chmod +x agent.sh
   ./agent.sh
   ```

**Note:** Both agents will cache data locally and retry if the server is unreachable.

---

## File Structure
- `server.py` — FastAPI backend
- `static/` — Frontend (React), agents, and assets
- `device_data.json` — Device data cache (auto-created)
- `requirements.txt` — Python dependencies

---

## Customization
- **Change login credentials:** Edit `LOCAL_USERNAME` and `LOCAL_PASSWORD` in `static/app.js`.
- **Branding:** Replace `static/drdo_logo.png` with your own logo if desired.

---

## License
This project is for internal use at SSPL/DRDO. 