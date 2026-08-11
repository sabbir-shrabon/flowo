# 🚀 Life Agent - Local Development Guide

This guide explains how to run the Life Agent full-stack application (FastAPI backend + Flutter web frontend) on your local machine.

---

## 1️⃣ Backend Setup (FastAPI)

The backend runs on **Port 8000** and connects to your Supabase database.

### First-Time Setup
If this is your first time, you need to create a Python virtual environment and install dependencies:
```powershell
python -m venv backend\venv
.\backend\venv\Scripts\Activate.ps1
pip install -r backend\requirements.txt
```

### Starting the Backend (Every Time)
Open a terminal in the root directory of the project and run:
```powershell
.\backend\venv\Scripts\Activate.ps1
uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000
```
*The backend API will now be available at `http://127.0.0.1:8000`*

---

## 2️⃣ Frontend Setup (Flutter Web)

The Flutter web app runs on **Port 5000** and connects to the backend API.

### Starting the Frontend (Every Time)
Open a **new, separate terminal** in the root directory and run the provided helper script:
```powershell
cd life_agent_flutter
.\run_web.ps1
```

This script automatically launches Flutter Web on `localhost:5000` with the correct environment variables (it passes `--dart-define` flags to connect to the backend on port 8000).

### Flutter Run Commands
While the Flutter app is running in the terminal, you can press these keys:
*   `r` : Hot reload (applies UI changes instantly)
*   `R` : Hot restart (restarts the app state)
*   `h` : List all available interactive commands
*   `d` : Detach (leaves the app running in Chrome but frees up the terminal)
*   `q` : Quit (stops the app)

---

## ⚙️ Environment Variables (.env)

Make sure you have your `.env` files set up correctly before starting!

**1. Backend:** `backend/.env`
Requires your Supabase keys (URL and Service Role Key) and a master encryption key.
*Note: Make sure `DEV_MODE=False` unless you specifically want to bypass authentication.*

**2. Frontend:** `life_agent_flutter/.env`
Requires your Supabase Anon Key and URL. 
*Note: Make sure `API_BASE_URL=http://localhost:8000` so it can talk to your local backend.*

---

## 🛠️ Troubleshooting

**Port Conflicts?**
If port 8000 is already in use by another app, you can start the backend on a different port (e.g., 8001):
```powershell
uvicorn backend.main:app --reload --port 8001
```
*If you do this, remember to update `API_BASE_URL` in `life_agent_flutter/.env` to match the new port, then restart the Flutter app.*

**Dangling Processes?**
If you close a terminal but the app is still running in the background, you can kill processes on specific ports using PowerShell:
```powershell
# Kill whatever is running on port 8000 (Backend)
Stop-Process -Id (Get-NetTCPConnection -LocalPort 8000).OwningProcess -Force

# Kill whatever is running on port 5000 (Frontend)
Stop-Process -Id (Get-NetTCPConnection -LocalPort 5000).OwningProcess -Force
```