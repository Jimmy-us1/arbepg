@echo off
setlocal EnableExtensions
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python was not found in PATH.
    exit /b 1
)

python -X utf8 -c "import curl_cffi, bs4, tqdm, requests, urllib3, Crypto" >nul 2>nul
if errorlevel 1 (
    echo [INFO] Installing the generator dependencies...
    python -m pip install --disable-pip-version-check "curl_cffi[async]" beautifulsoup4 tqdm requests urllib3 pycryptodome
    if errorlevel 1 exit /b 1
)

echo [INFO] Generating the enriched XMLTV file...
python -X utf8 epg_generator.py
if errorlevel 1 (
    echo [ERROR] EPG generation failed. Nothing will be published.
    exit /b 1
)

python -X utf8 -c "import xml.etree.ElementTree as ET; r=ET.parse('epg.xml').getroot(); print('[OK] XML validated:', len(r.findall('channel')), 'channels,', len(r.findall('programme')), 'programmes')"
if errorlevel 1 (
    echo [ERROR] epg.xml is invalid. Nothing will be published.
    exit /b 1
)

if not exist ".git" (
    echo [OK] epg.xml was generated. This folder is not a Git repository, so publish was skipped.
    exit /b 0
)

rem Never store an access token in this file. Git Credential Manager or GITHUB_TOKEN tooling can authenticate the push.
git remote set-url origin https://github.com/mohamedelansary/todland.git >nul 2>nul
git add -- epg.xml epg_generator.py 1.bat
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
