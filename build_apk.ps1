# build_apk.ps1 - One script to build APK for any constituency
# Usage: .\build_apk.ps1
# For other constituency: .\build_apk.ps1 -DbPath "output\kurnool.db"

param([string]$DbPath = "output\dhone_full.db")

# Fix PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")
$pyPath = "C:\Users\azadmin\AppData\Local\Programs\Python\Python311"
$env:Path = "$env:Path;$pyPath;$pyPath\Scripts"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  AP Voter Search - APK Builder" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Step 1: Read config from DB using a temp Python file (avoids quote issues)
Write-Host "`n[1/6] Reading constituency info from DB..." -ForegroundColor Yellow

$dbPathClean = $DbPath -replace '\\','/'

@"
import sqlite3, json
conn = sqlite3.connect('$dbPathClean')
try:
    cfg = {r[0]:r[1] for r in conn.execute('SELECT key,value FROM config').fetchall()}
    total = conn.execute('SELECT COUNT(*) FROM voters').fetchone()[0]
    print(cfg.get('const_name','Voter Search'))
    print(cfg.get('ac_number','000'))
    print(cfg.get('year','2002'))
    print(total)
except Exception as e:
    print('Voter Search')
    print('000')
    print('2002')
    print(0)
conn.close()
"@ | Out-File -FilePath "read_config.py" -Encoding UTF8

$pyOut     = python read_config.py
$lines     = $pyOut -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
$constName = $lines[0]
$acNumber  = $lines[1]
$year      = $lines[2]
$total     = $lines[3]

Remove-Item "read_config.py" -Force

$appName     = "$constName SIR $year"
$safeName    = $constName -replace '[^\w]','_'
$apkFileName = "${safeName}_AC${acNumber}_SIR${year}.apk"

Write-Host "  Constituency : $constName" -ForegroundColor White
Write-Host "  AC Number    : $acNumber"  -ForegroundColor White
Write-Host "  Year         : $year"      -ForegroundColor White
Write-Host "  Total Voters : $total"     -ForegroundColor White
Write-Host "  App Name     : $appName"   -ForegroundColor Green
Write-Host "  APK File     : $apkFileName" -ForegroundColor Green

# Step 2: Update AndroidManifest.xml
Write-Host "`n[2/6] Setting app name in AndroidManifest.xml..." -ForegroundColor Yellow
$manifestPath = "flutter_app\android\app\src\main\AndroidManifest.xml"
$manifest = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
$manifest = $manifest -replace 'android:label="[^"]*"', "android:label=`"$appName`""
[System.IO.File]::WriteAllText((Resolve-Path $manifestPath), $manifest, [System.Text.Encoding]::UTF8)
Write-Host "  Done: android:label = $appName" -ForegroundColor Green

# Step 3: Create/Update strings.xml
Write-Host "`n[3/6] Updating strings.xml..." -ForegroundColor Yellow
$stringsDir  = "flutter_app\android\app\src\main\res\values"
$stringsPath = "$stringsDir\strings.xml"
New-Item -ItemType Directory -Force -Path $stringsDir | Out-Null
$stringsXml = "<?xml version=""1.0"" encoding=""utf-8""?>`r`n<resources>`r`n    <string name=""app_name"">$appName</string>`r`n</resources>"
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($stringsPath),
    $stringsXml,
    [System.Text.Encoding]::UTF8
)
Write-Host "  Done: app_name = $appName" -ForegroundColor Green

# Step 4: Copy DB to Flutter assets
Write-Host "`n[4/6] Copying database to Flutter assets..." -ForegroundColor Yellow
$dbSize = [math]::Round((Get-Item $DbPath).Length / 1MB, 1)
Copy-Item $DbPath "flutter_app\assets\voters.db" -Force
Write-Host "  Done: $DbPath ($dbSize MB) -> assets\voters.db" -ForegroundColor Green

# Step 5: Build APK
Write-Host "`n[5/6] Building release APK (3-5 mins)..." -ForegroundColor Yellow
Set-Location flutter_app
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    Set-Location ..
    exit 1
}
Set-Location ..
Write-Host "  Build complete!" -ForegroundColor Green

# Step 6: Copy APK to output with proper name
Write-Host "`n[6/6] Saving APK as $apkFileName..." -ForegroundColor Yellow
$apkSource = "flutter_app\build\app\outputs\flutter-apk\app-release.apk"
$apkDest   = "output\$apkFileName"
Copy-Item $apkSource $apkDest -Force
$apkSize = [math]::Round((Get-Item $apkDest).Length / 1MB, 1)
Write-Host "  Done!" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  BUILD SUCCESSFUL!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  App Name  : $appName"            -ForegroundColor White
Write-Host "  AC        : $constName AC-$acNumber" -ForegroundColor White
Write-Host "  Voters    : $total"              -ForegroundColor White
Write-Host "  APK Size  : $apkSize MB"         -ForegroundColor White
Write-Host "  APK       : output\$apkFileName" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next constituency:" -ForegroundColor Yellow
Write-Host "  .\build_apk.ps1 -DbPath output\kurnool.db" -ForegroundColor Gray
Write-Host ""