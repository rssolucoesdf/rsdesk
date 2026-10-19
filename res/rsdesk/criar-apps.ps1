# Gera os dois instaladores do RSDesk: Servidor (tecnico) e Cliente (maquina do cliente).
#
# O build Cliente embute a(s) chave(s) publica(s) do operador pela variavel RSDESK_OPERATOR_PUBKEYS,
# o que tambem o deixa em modo "so recebe". O build Servidor nao tem chave embutida.
#
# Uso (PowerShell, na pasta do repositorio):
#   .\res\rsdesk\criar-apps.ps1 -PubKey "<chave publica base64>"
# A chave publica vem do gerador: cargo run --release --features flutter,hwcodec,vram --example operator_keygen
#
# Antes de rodar, abra uma vez o ambiente de build (Rust/Flutter/vcpkg/LLVM no PATH e as variaveis
# VCPKG_ROOT e LIBCLANG_PATH definidas), como nas fases anteriores.

param(
    [Parameter(Mandatory = $true)][string]$PubKey
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$criar = Join-Path $PSScriptRoot 'criar-instalador.ps1'
$dist = 'C:\RSDesk\dist'
$cargoVer = (Select-String -Path "$repo\Cargo.toml" -Pattern '^version\s*=\s*"(.+)"').Matches[0].Groups[1].Value
$versao = (Select-String -Path "$repo\flutter\lib\consts.dart" -Pattern "kRSBuildTag = '(.+?)'").Matches[0].Groups[1].Value

function Build-Role($role, $pubkey) {
    Write-Host "==== Compilando RSDesk $role ===="
    # vazio = build Servidor (sem chave); com valor = build Cliente.
    $env:RSDESK_OPERATOR_PUBKEYS = if ($pubkey) { $pubkey } else { '' }
    # Flutter nao propaga env novas para o cargo ja iniciado; limpe a marca do crate para forcar
    # a recompilacao do option_env! ao trocar de papel.
    cargo clean -p rustdesk 2>$null
    $bw = "$repo\flutter\build\windows"
    if (Test-Path -LiteralPath $bw) { [System.IO.Directory]::Delete($bw, $true) }
    python "$repo\build.py" --portable --flutter --skip-portable-pack --hwcodec --vram
    if ($LASTEXITCODE -ne 0) { throw "build.py falhou para $role" }
    & $criar
    $src = Join-Path $dist "rsdesk-$cargoVer-x86_64.exe"
    $dst = Join-Path $dist ("rsdesk-{0}-{1}-x86_64.exe" -f $role.ToLower(), $versao)
    Move-Item -Force $src $dst
    Write-Host "Gerado: $dst"
}

Build-Role 'Servidor' $null
Build-Role 'Cliente' $PubKey
Remove-Item Env:\RSDESK_OPERATOR_PUBKEYS -ErrorAction SilentlyContinue
Write-Host "Pronto. Instaladores em $dist"
