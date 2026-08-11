@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "PYTHON_EXE="

rem Optional explicit override: set EPG_PYTHON=C:\path\to\python.exe
if defined EPG_PYTHON if exist "%EPG_PYTHON%" set "PYTHON_EXE=%EPG_PYTHON%"

if not defined PYTHON_EXE if exist ".venv\Scripts\python.exe" set "PYTHON_EXE=%CD%\.venv\Scripts\python.exe"

if not defined PYTHON_EXE (
    for /f "delims=" %%P in ('where python 2^>nul') do if not defined PYTHON_EXE set "PYTHON_EXE=%%P"
)

if not defined PYTHON_EXE (
    for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python*") do (
        if exist "%%~fD\python.exe" set "PYTHON_EXE=%%~fD\python.exe"
    )
)

rem Codex bundled Python is a safe final fallback on this machine.
if not defined PYTHON_EXE if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" set "PYTHON_EXE=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

if not defined PYTHON_EXE (
    echo [ERROR] Python was not found. Install Python 3.11+ or set EPG_PYTHON to python.exe.
    exit /b 1
)

"%PYTHON_EXE%" -X utf8 -c "import sys; assert sys.version_info.major == 3 and sys.version_info.minor in range(10, 100)" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python 3.10 or newer is required: "%PYTHON_EXE%"
    exit /b 1
)

echo [INFO] Using Python: "%PYTHON_EXE%"

"%PYTHON_EXE%" -X utf8 -c "import curl_cffi, bs4, tqdm, requests, urllib3, Crypto" >nul 2>nul
if errorlevel 1 (
    echo [INFO] Installing the generator dependencies...
    "%PYTHON_EXE%" -m pip install --disable-pip-version-check "curl_cffi[async]" beautifulsoup4 tqdm requests urllib3 pycryptodome
    if errorlevel 1 exit /b 1
)

echo [INFO] Generating the enriched XMLTV file...
"%PYTHON_EXE%" -X utf8 epg_generator.py
if errorlevel 1 (
    echo [ERROR] EPG generation failed. Nothing will be published.
    exit /b 1
)

"%PYTHON_EXE%" -X utf8 -c "import xml.etree.ElementTree as ET; r=ET.parse('epg.xml').getroot(); print('[OK] XML validated:', len(r.findall('channel')), 'channels,', len(r.findall('programme')), 'programmes')"
if errorlevel 1 (
    echo [ERROR] epg.xml is invalid. Nothing will be published.
    exit /b 1
)

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] XML generation succeeded, but Git was not found. Install Git to publish automatically.
    exit /b 1
)

rem Prepare Git automatically on a new PC without overwriting local files.
set "NEW_GIT_REPOSITORY=0"
git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
    echo [INFO] Initializing Git in this folder...
    git init -b main
    if errorlevel 1 exit /b 1
    set "NEW_GIT_REPOSITORY=1"
)

git config --local user.name "Jimmy-us1"
git config --local user.email "youssef.maher.521@hotmail.com"
git config --local credential.useHttpPath true

rem Never store an access token in this file. Git Credential Manager can authenticate the push.
git remote get-url origin >nul 2>nul
if errorlevel 1 (
    git remote add origin https://Jimmy-us1@github.com/Jimmy-us1/arbepg.git
) else (
    git remote set-url origin https://Jimmy-us1@github.com/Jimmy-us1/arbepg.git
)

echo [INFO] Synchronizing Git history without replacing generated files...
if "%NEW_GIT_REPOSITORY%"=="1" (
    rem A shallow first fetch avoids downloading every old 60 MB XML revision.
    git fetch --depth=1 origin main
) else (
    git fetch origin main
)
if errorlevel 1 (
    echo [ERROR] XML generation succeeded, but the GitHub history could not be downloaded.
    exit /b 1
)

git rev-parse --verify HEAD >nul 2>nul
if errorlevel 1 (
    rem Attach a newly initialized repository to origin/main while keeping the working files intact.
    git read-tree refs/remotes/origin/main
    if errorlevel 1 exit /b 1
    git update-ref refs/heads/main refs/remotes/origin/main
    if errorlevel 1 exit /b 1
    if not exist ".gitignore" git checkout-index -- .gitignore >nul 2>nul
)

git add -- epg.xml 1.bat
git diff --cached --quiet
if errorlevel 1 (
    git commit -m "Update enriched EPG XML"
    if errorlevel 1 exit /b 1
) else (
    echo [INFO] Generated files are already committed locally.
)

rem Another PC may have published while generation was running. Merge its history
rem while keeping this freshly generated XML, then push without force.
git fetch origin main
if errorlevel 1 exit /b 1
git merge-base --is-ancestor refs/remotes/origin/main HEAD
if errorlevel 1 (
    git merge -s ours refs/remotes/origin/main -m "Merge remote EPG history"
    if errorlevel 1 exit /b 1
)

git push origin HEAD:main
if errorlevel 1 (
    echo [ERROR] Generation succeeded, but push failed. Your local files and commit were kept safely.
    exit /b 1
)

echo [OK] Generation and publish completed successfully.
exit /b 0
