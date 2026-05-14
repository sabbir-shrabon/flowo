setup.ps1 (first-time only)
    python -m venv backend\venv
    .\backend\venv\Scripts\Activate.ps1
    pip install -r backend\requirements.txt


start_server.ps1 (every time)
for backend:
    .\backend\venv\Scripts\Activate.ps1
    uvicorn backend.main:app --reload


test_api.ps1 (test the API)
    .\backend\venv\Scripts\Activate.ps1  (if not already activated)
    python test_api.py


Port conflict?
    uvicorn backend.main:app --reload --port 8001


for frontend:
    cd frontend
    npm run dev

for flutter:
    cd life_agent_flutter
    .\run_web.ps1

Flutter web runs in Chrome at:
    http://localhost:5000

for now try this:
    .\life_agent_flutter\run_web.ps1

Flutter run key commands.
    r Hot reload. 
    R Hot restart.
    h List all available interactive commands.
    d Detach (terminate "flutter run" but leave application running).
    c Clear the screen
    q Quit (terminate the application on the device).


how to push changes to GitHub:
    git add .
    git commit -m "your commit message"
    git push

