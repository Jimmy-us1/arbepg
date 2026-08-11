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

if not exist ".git" (
    echo [OK] epg.xml was generated. This folder is not a Git repository, so publish was skipped.
    exit /b 0
)

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] XML generation succeeded, but Git was not found. Nothing was published.
    exit /b 1
)

rem Never store an access token in this file. Git Credential Manager can authenticate the push.
git remote set-url origin https://github.com/Jimmy-us1/arbepg.git >nul 2>nul
git add -- epg.xml 1.bat
git diff --cached --quiet
if not errorlevel 1 (
    echo [OK] No changes to publish.
    exit /b 0
)

git commit -m "Update enriched EPG XML"
if errorlevel 1 exit /b 1

git push origin HEAD:main
if errorlevel 1 (
    echo [ERROR] Generation succeeded, but push failed. Your local files and commit were kept safely.
    exit /b 1
)

echo [OK] Generation and publish completed successfully.
exit /b 0
