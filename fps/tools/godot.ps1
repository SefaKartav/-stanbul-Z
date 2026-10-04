# Godot'u zaman asimi korumasiyla calistirir ve ciktiyi dondurur.
#
#   .\tools\godot.ps1 tests                 # GDScript testleri (basliksiz)
#   .\tools\godot.ps1 tests -Filter voxel   # yalnizca adinda 'voxel' gecenler
#   .\tools\godot.ps1 import                # varliklari ice aktar
#   .\tools\godot.ps1 check                 # betikleri derle, hata raporla
#   .\tools\godot.ps1 run                   # oyunu pencerede ac
#   .\tools\godot.ps1 scene res://x.tscn    # belirli sahneyi pencerede ac
#
# Neden bir sarmalayici? Betikte derleme hatasi olan bir sahne quit()'e hic
# ulasamaz ve Godot sonsuza kadar bekler. Zaman asimi olmadan otomatik
# testler "takildi" ile "gecti" arasini ayirt edemez.
param(
    [Parameter(Position = 0)][string]$Mode = "tests",
    [Parameter(Position = 1)][string]$Target = "",
    [string]$Filter = "",
    [int]$Timeout = 300,
    [string]$Extra = ""
)

$ErrorActionPreference = "Stop"
$godotDir = Join-Path $env:LOCALAPPDATA "Programs\Godot\4.7.2"
$godot = Join-Path $godotDir "Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { throw "Godot bulunamadi: $godot" }
$project = Split-Path $PSScriptRoot -Parent

switch ($Mode) {
    "tests"  { $argsList = @("--headless", "--path", $project, "res://tests/test_runner.tscn", "--"); if ($Filter) { $argsList += "--filter=$Filter" } }
    "import" { $argsList = @("--headless", "--path", $project, "--import") }
    "check"  { $argsList = @("--headless", "--path", $project, "--import", "--check-only") }
    "run"    { $argsList = @("--path", $project) }
    "scene"  { $argsList = @("--path", $project, $Target) }
    default  { throw "Bilinmeyen kip: $Mode" }
}
if ($Extra) { $argsList += $Extra.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries) }

# Yeni `class_name` tanimlari yalnizca ice aktarma taramasinda global sinif
# onbellegine yazilir. Testten/calistirmadan once hizli bir tarama yapilmazsa
# yeni eklenen siniflar "tanimsiz" gorunur.
if ($Mode -in @("tests", "run", "scene")) {
    $scan = Start-Process -FilePath $godot -ArgumentList @("--headless", "--path", $project, "--import") `
        -NoNewWindow -PassThru -RedirectStandardOutput ([System.IO.Path]::GetTempFileName()) `
        -RedirectStandardError ([System.IO.Path]::GetTempFileName())
    if (-not $scan.WaitForExit(240000)) {
        Get-Process | Where-Object { $_.ProcessName -like "Godot_v4.7.2*" } | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output "ICE AKTARMA ZAMAN ASIMI"
        exit 124
    }
}

$out = [System.IO.Path]::GetTempFileName()
$err = [System.IO.Path]::GetTempFileName()
$proc = Start-Process -FilePath $godot -ArgumentList $argsList -NoNewWindow -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
if (-not $proc.WaitForExit($Timeout * 1000)) {
    # Konsol sarmalayicisi asil sureci (GUI exe) baslatir; ikisini de kapat.
    Get-Process | Where-Object { $_.ProcessName -like "Godot_v4.7.2*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Content $out, $err -Encoding UTF8 | Where-Object { $_ -notmatch "^\s*$" } | Select-Object -Last 60
    Write-Output "ZAMAN ASIMI ($Timeout sn) -- surec durduruldu"
    exit 124
}
$proc.WaitForExit()
$lines = Get-Content $out, $err -Encoding UTF8 | Where-Object { $_ -notmatch "^\s*$" -and $_ -notmatch "^\[\s*\d+% \]" }
$lines
Remove-Item $out, $err -ErrorAction SilentlyContinue
$code = $proc.ExitCode
# GDScript calisma hatalari cikis kodunu degistirmez; testte gorulen her
# SCRIPT ERROR basarisizlik sayilir.
if ($Mode -eq "tests" -and $code -eq 0 -and ($lines | Where-Object { $_ -match "SCRIPT ERROR" })) {
    Write-Output "BETIK HATASI GORULDU -- basarisiz sayildi"
    $code = 1
}
exit $code
