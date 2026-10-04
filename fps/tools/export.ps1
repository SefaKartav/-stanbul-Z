# Istanbul-Z Windows surumu: test -> ice aktar -> disa aktar -> duman testi -> kisayol.
#
#   powershell -ExecutionPolicy Bypass -File fps\tools\export.ps1
#
# Cikti: build\fps\IstanbulZ.exe (tek dosya; PCK gomulu).
# Masaustundeki "Istanbul-Z" kisayolu bu EXE'yi acar. Kaynak kod degisikligi
# EXE yeniden disa aktarilmadan kullaniciya ULASMAZ; is paketinin son adimi
# her zaman bu betiktir.
param([switch]$SkipTests)

$ErrorActionPreference = "Stop"
$project = Split-Path $PSScriptRoot -Parent
$repo = Split-Path $project -Parent
$godot = Join-Path $env:LOCALAPPDATA "Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
$out = Join-Path $repo "build\fps"
$exe = Join-Path $out "IstanbulZ.exe"

if (-not $SkipTests) {
    Write-Output "== Testler"
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "godot.ps1") tests -Timeout 300 | Select-Object -Last 3
    if ($LASTEXITCODE -ne 0) { throw "Testler basarisiz; disa aktarilmadi." }
}

Write-Output "== Disa aktarim"
New-Item -ItemType Directory -Force $out | Out-Null
# Once yan dosyaya aktarilir; eski EXE yalnizca yeni EXE duman testini
# gectikten sonra degistirilir. (Eskiden once silinirdi: aktarim ya da duman
# testi basarisiz olursa masaustu kisayolu hicbir sey acmazdi.)
$candidate = Join-Path $out "IstanbulZ_yeni.exe"
if (Test-Path $candidate) { Remove-Item $candidate -Force }
$log = [System.IO.Path]::GetTempFileName()
# Start-Process argumanlari bosluktan boler: on ayar adi ve yollar tirnakli verilir.
$proc = Start-Process -FilePath $godot -ArgumentList @("--headless", "--path", "`"$project`"", "--export-release", "`"Windows Desktop`"", "`"$candidate`"") `
    -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
if (-not $proc.WaitForExit(600000)) { $proc.Kill(); throw "Disa aktarim zaman asimi" }
Get-Content $log, "$log.err" | Where-Object { $_ -match "ERROR|error|WARN" } | Select-Object -First 20
if (-not (Test-Path $candidate)) { throw "EXE uretilmedi (eski surum yerinde birakildi)" }
"{0} ({1:N1} MB)" -f $candidate, ((Get-Item $candidate).Length / 1MB)

Write-Output "== Duman testi (paketlenmis EXE: dunya yuklenir, ekran goruntusu alinir, kapanir)"
$shot = Join-Path $env:TEMP "istanbulz_smoke.png"
if (Test-Path $shot) { Remove-Item $shot }
$smoke = Start-Process -FilePath $candidate -ArgumentList @("--windowed", "--resolution", "1280x720", "--", "--shot=$shot", "--shot-delay=1.5", "--zombies=4") `
    -PassThru -RedirectStandardOutput "$log.smoke" -RedirectStandardError "$log.smoke.err"
if (-not $smoke.WaitForExit(180000)) { $smoke.Kill(); throw "Duman testi zaman asimi" }
Get-Content "$log.smoke" | Where-Object { $_ -match "Icerik|Ekran|FPS|HAZIR|ERROR" }
if (-not (Test-Path $shot)) { throw "Duman testi: ekran goruntusu alinamadi (oyun dunyayi yukleyemedi; eski surum yerinde birakildi)" }
Write-Output "Duman testi gecti: $shot"
Move-Item -Force $candidate $exe
"yeni surum yerinde: {0} ({1:N1} MB)" -f $exe, ((Get-Item $exe).Length / 1MB)

Write-Output "== Kisayol"
$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath("Desktop")
foreach ($path in @((Join-Path $desktop "Istanbul-Z.lnk"), (Join-Path $repo "Istanbul-Z.lnk"))) {
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = $exe
    $link.WorkingDirectory = $out
    $link.IconLocation = "$exe,0"
    $link.Description = "Istanbul-Z (voxel FPS)"
    $link.Save()
    "kisayol -> $path"
}
