# Publica uma versão do jogo para Windows numa Release do GitHub, em duas etapas:
#   1) grava application/config/version no project.godot e para (faça commit + push);
#   2) com a versão já commitada e enviada: exporta o .exe e cria a Release vX.Y.Z.
# Uso: powershell -ExecutionPolicy Bypass -File ferramentas\publicar.ps1 0.1.1
param(
    [Parameter(Mandatory = $true)][string]$Versao,
    [string]$Godot = "C:\codiguinhos\Godot_app_4.71\Godot_v4.7.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
# Mesmo nome da constante NOME_ASSET do scripts/geral/atualizador.gd
$exe = "C:\codiguinhos\builds\windows\lorax-deforestationders.exe"
$projeto = Join-Path $raiz "project.godot"

if ($Versao -notmatch '^\d+\.\d+\.\d+$') { throw "Versão deve ser X.Y.Z (ex.: 0.1.1)." }
if (Get-Process | Where-Object { $_.ProcessName -like "Godot*" }) { throw "Feche o Godot antes." }
Set-Location $raiz

# Etapa 1: versão diferente no project.godot = grava e para
$texto = [IO.File]::ReadAllText($projeto)
$atual = [regex]::Match($texto, '(?m)^config/version="([^"]*)"').Groups[1].Value
if ($atual -ne $Versao) {
    $texto = [regex]::Replace($texto, '(?m)^config/version="[^"]*"', "config/version=""$Versao""")
    [IO.File]::WriteAllText($projeto, $texto, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Gravei config/version = $Versao (era '$atual'). Faça commit + push e rode de novo."
    exit 0
}

# Etapa 2: árvore limpa e HEAD já no remoto
if (git status --porcelain) { throw "Há mudanças sem commit." }
git fetch origin --quiet
$sha = (git rev-parse HEAD).Trim()
if (-not (git branch -r --contains $sha)) { throw "HEAD ($sha) ainda não foi enviado ao GitHub." }
if (git tag -l "v$Versao") { throw "A tag v$Versao já existe." }

New-Item -ItemType Directory -Force (Split-Path $exe) | Out-Null
& $Godot --headless --path $raiz --export-release "Windows Release" $exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw "Export falhou." }

$notas = Read-Host "Notas da Release (Enter = sem notas)"
Write-Host "gh release create v$Versao `"$exe`" --target $sha --title v$Versao"
if ((Read-Host "Criar a Release agora? (s/n)") -ne "s") { Write-Host "Cancelado."; exit 0 }
gh release create "v$Versao" "$exe" --target $sha --title "v$Versao" --notes "$notas"
