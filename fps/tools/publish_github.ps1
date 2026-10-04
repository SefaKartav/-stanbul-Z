# GitHub vitrin deposunu gunceller: oynanabilir oyunu (fps/) temiz bir yayin
# klasorune aynalar, commit atar ve gonderir. Yerel calisma klasoru DEGISMEZ.
#
#   powershell -ExecutionPolicy Bypass -File fps\tools\publish_github.ps1 -Message "aciklama"
#
# Yayinda OLMAYANLAR (yerelde kalir): promptlar ve gorev belgeleri (game\docs),
# _yedek, build\ (EXE), turkey-*.osm.pbf, tools\cache (OSM onbellegi),
# .godot onbellegi, __pycache__, kok dizindeki eski Python prototipi ve kopya
# asset klasoru (Istanbul-Z_600_..._soft_expansion; oyun fps\assets'ten okur).
param(
    [string]$Message = "Guncelleme",
    [string]$Target = "$env:USERPROFILE\OneDrive\Masaüstü\istanbul-z-github",
    [string]$Remote = "https://github.com/SefaKartav/-stanbul-Z.git"
)
$ErrorActionPreference = "Stop"
$env:Path = "$env:ProgramFiles\Git\cmd;$env:Path"
$fps = Split-Path $PSScriptRoot -Parent

New-Item -ItemType Directory -Force $Target | Out-Null
# /MIR: hedefteki fps\ kaynakla birebir; .git ve vitrin dosyalari fps\ disinda oldugu icin dokunulmaz.
robocopy $fps (Join-Path $Target "fps") /MIR /NFL /NDL /NJH /NJS /NP `
    /XD ".godot" "cache" "__pycache__" "saves_fps" `
    /XF "*.pyc" "*.tmp" "*.log" | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy basarisiz ($LASTEXITCODE)" }

Push-Location $Target
try {
    if (-not (Test-Path ".git")) {
        git init -b main | Out-Null
        git remote add origin $Remote
    }
    git add -A
    $changes = git status --porcelain
    if (-not $changes) { Write-Output "Degisiklik yok."; return }
    git commit -m $Message | Out-Null
    git push -u origin main
} finally {
    Pop-Location
}
