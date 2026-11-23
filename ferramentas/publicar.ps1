# Publica uma versão do jogo para Windows numa Release do GitHub, numa etapa só:
# confere tudo → grava application/config/version → commit "Bump version to X.Y.Z" + push
# → exporta o .exe → pede as notas → uma confirmação → gh release create.
# Pode ser rodado de novo: com a versão já commitada e sem Release, retoma no export.
# Uso: powershell -ExecutionPolicy Bypass -File ferramentas\publicar.ps1 [0.1.2]
param(
    [string]$Versao,
    [string]$Godot = "C:\codiguinhos\Godot_app_4.71\Godot_v4.7.1-stable_win64_console.exe",
    # O nome do arquivo tem que ser o da constante NOME_ASSET do scripts/geral/atualizador.gd
    [string]$Exe = "C:\codiguinhos\builds\windows\lorax-deforestationders.exe"
)
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$projeto = Join-Path $raiz "project.godot"
$branch = "boss-battle"

# Diz se a Release vX.Y.Z já existe no GitHub (gh escreve no stderr quando não existe)
function Existe-Release($v) {
    $ErrorActionPreference = "Continue"
    gh release view "v$v" *> $null
    return $LASTEXITCODE -eq 0
}

# Para o script se o último comando externo falhou
function Conferir($oQue) { if ($LASTEXITCODE -ne 0) { throw "$oQue falhou." } }

# Roda o exe novo só para ele gravar a própria versão. APPDATA temporário: o Godot cria a pasta
# do user:// e gira os logs antes de qualquer script, e isso não pode tocar nos dados reais
function Conferir-Versao-Exe {
    $pasta = Join-Path ([IO.Path]::GetTempPath()) ("lorax-conferir-" + [guid]::NewGuid())
    New-Item -ItemType Directory $pasta | Out-Null
    $arquivo = Join-Path $pasta "versao.txt"
    $appdata = $env:APPDATA
    try {
        $env:APPDATA = $pasta
        $p = Start-Process -FilePath $Exe -ArgumentList "--headless", "--gravar-versao=`"$arquivo`"" -WindowStyle Hidden -PassThru
        $null = $p.Handle # sem guardar o handle, o PowerShell 5.1 perde o ExitCode
        if (-not $p.WaitForExit(30000)) { $p.Kill(); throw "O exe não respondeu à conferência de versão." }
        if ($p.ExitCode -ne 0) { throw "A conferência de versão saiu com código $($p.ExitCode)." }
        if (-not (Test-Path -LiteralPath $arquivo)) { throw "O exe não gravou a versão." }
        $gravada = [IO.File]::ReadAllText($arquivo)
        if ($gravada -cne $Versao) { throw "O exe é da versão '$gravada', esperava '$Versao'." }
    } finally {
        $env:APPDATA = $appdata
        Remove-Item -LiteralPath $pasta -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Get-Process | Where-Object { $_.ProcessName -like "Godot*" }) { throw "Feche o Godot antes." }
Set-Location $raiz
# O Godot lê o override.cfg da pasta do projeto e da pasta do exe: mudaria o export ou falsearia a conferência
foreach ($pasta in $raiz, (Split-Path $Exe)) {
    if (Test-Path -LiteralPath (Join-Path $pasta "override.cfg")) { throw "Existe override.cfg em $pasta. Remova antes de publicar." }
}
if ((git branch --show-current) -ne $branch) { throw "A branch atual não é $branch." }
if (git status --porcelain) { throw "Há mudanças sem commit. Faça seus commits antes." }
& { $ErrorActionPreference = "Continue"; gh auth status *> $null }
Conferir "gh auth status (rode 'gh auth login')"

$texto = [IO.File]::ReadAllText($projeto)
$atual = [regex]::Match($texto, '(?m)^config/version="([^"]*)"').Groups[1].Value
if ($atual -notmatch '^\d+\.\d+\.\d+$') { throw "config/version atual ('$atual') não é X.Y.Z." }

# Sem argumento: retoma a atual se ela ainda não tem Release; senão sugere +1 no último número
if (-not $Versao) {
    $p = $atual.Split(".")
    $sugestao = if (Existe-Release $atual) { "$($p[0]).$($p[1]).$([int]$p[2] + 1)" } else { $atual }
    $resposta = Read-Host "Versão a publicar [$sugestao] (Enter = aceitar, ou digite outra)"
    $Versao = if ($resposta.Trim()) { $resposta.Trim() } else { $sugestao }
}
if ($Versao -notmatch '^\d+\.\d+\.\d+$') { throw "Versão deve ser X.Y.Z (ex.: 0.1.2)." }
if (Existe-Release $Versao) { throw "A Release v$Versao já existe." }
if ([version]$Versao -lt [version]$atual) { throw "v$Versao é menor que a atual ($atual)." }

if ([version]$Versao -gt [version]$atual) {
    $texto = [regex]::Replace($texto, '(?m)^config/version="[^"]*"', "config/version=""$Versao""")
    [IO.File]::WriteAllText($projeto, $texto, (New-Object Text.UTF8Encoding($false)))
    git commit -q -m "Bump version to $Versao" -- project.godot
    Conferir "git commit"
    Write-Host "Commit: Bump version to $Versao (era $atual)."
} else {
    Write-Host "v$Versao já está no project.godot e sem Release: retomando."
}
git push origin $branch
Conferir "git push"
$sha = (git rev-parse HEAD).Trim()

New-Item -ItemType Directory -Force (Split-Path $Exe) | Out-Null
if (Test-Path -LiteralPath $Exe) { Remove-Item -LiteralPath $Exe } # um exe antigo não pode passar por export novo
& $Godot --headless --path $raiz --export-release "Windows Release" $Exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Exe)) { throw "Export falhou." }
Conferir-Versao-Exe

$notas = Read-Host "Notas da Release (Enter = sem notas)"
Write-Host ""
Write-Host "Release:  v$Versao"
Write-Host "Commit:   $sha ($branch)"
Write-Host ("Arquivo:  {0} ({1:N1} MB)" -f $Exe, ((Get-Item $Exe).Length / 1MB))
Write-Host "Notas:    $(if ($notas) { $notas } else { '(sem notas)' })"
if ((Read-Host "Criar a Release agora? (s/n)") -ne "s") { Write-Host "Cancelado. Rode de novo para retomar."; exit 0 }
# Por arquivo: o PowerShell 5.1 estraga aspas e descarta "" quando as notas vão como argumento
$arquivoNotas = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($arquivoNotas, $notas, (New-Object Text.UTF8Encoding $false))
    gh release create "v$Versao" "$Exe" --target $sha --title "v$Versao" --notes-file $arquivoNotas
    Conferir "gh release create"
} finally {
    Remove-Item -LiteralPath $arquivoNotas -ErrorAction SilentlyContinue
}
