# Gera o instalador MSI do RSDesk (Servidor ou Cliente), via WiX.
# O MSI instala pelo Windows Installer (servico por custom action C++), SEM o .bat da Temp
# que alguns antivirus bloqueiam.
#
# Uso (PowerShell, na pasta do repositorio), com o ambiente de build aberto:
#   .\res\rsdesk\criar-msi.ps1 -Role Servidor
#   .\res\rsdesk\criar-msi.ps1 -Role Cliente -PubKey "<chave publica>"
#
# Precisa: Rust/Flutter/vcpkg/LLVM no PATH, VCPKG_ROOT e LIBCLANG_PATH definidos,
# MSBuild do Visual Studio Build Tools, e C:\RSDesk\tools\nuget.exe.

param(
    [Parameter(Mandatory = $true)][ValidateSet('Servidor', 'Cliente')][string]$Role,
    [string]$PubKey = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$release = "$repo\flutter\build\windows\x64\runner\Release"
$pasta = "$repo\rustdesk"
$saida = 'C:\RSDesk\dist'
$cargoVer = (Select-String -Path "$repo\Cargo.toml" -Pattern '^version\s*=\s*"(.+)"').Matches[0].Groups[1].Value
$ver = (Select-String -Path "$repo\flutter\lib\consts.dart" -Pattern "kRSBuildTag = '(.+?)'").Matches[0].Groups[1].Value
$vs = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
$env:Path = "$vs\MSBuild\Current\Bin;C:\RSDesk\tools;$env:Path"

# 1) Compila o Release do papel (Cliente embute a chave; Servidor nao).
$env:RSDESK_OPERATOR_PUBKEYS = if ($Role -eq 'Cliente') { $PubKey } else { '' }
cargo clean -p rustdesk 2>$null
if (Test-Path -LiteralPath "$release\..\..\..\windows") {
    $bw = "$repo\flutter\build\windows"
    if (Test-Path -LiteralPath $bw) { [System.IO.Directory]::Delete($bw, $true) }
}
python "$repo\build.py" --portable --flutter --skip-portable-pack --hwcodec --vram
if ($LASTEXITCODE -ne 0) { throw "build.py falhou" }

# 2) Prepara a pasta com o app + driver de tela virtual.
if (Test-Path -LiteralPath $pasta) { [System.IO.Directory]::Delete($pasta, $true) }
Copy-Item -Recurse $release $pasta
$zip = "$env:TEMP\usbmmidd_v2.zip"
if (-not (Test-Path $zip)) {
    Invoke-WebRequest -Uri https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip -OutFile $zip
}
if (Test-Path -LiteralPath "$env:TEMP\usbmmidd") { [System.IO.Directory]::Delete("$env:TEMP\usbmmidd", $true) }
New-Item -ItemType Directory -Force "$env:TEMP\usbmmidd" | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zip, "$env:TEMP\usbmmidd")
Remove-Item -Recurse -Force "$env:TEMP\usbmmidd\usbmmidd_v2\Win32"
Remove-Item -Force "$env:TEMP\usbmmidd\usbmmidd_v2\deviceinstaller64.exe", "$env:TEMP\usbmmidd\usbmmidd_v2\deviceinstaller.exe", "$env:TEMP\usbmmidd\usbmmidd_v2\usbmmidd.bat"
Move-Item "$env:TEMP\usbmmidd\usbmmidd_v2" "$pasta\usbmmidd_v2"
$res = Get-ChildItem -Recurse -Filter Runner.res "$repo\flutter\build" | Select-Object -First 1
if ($res) { Copy-Item $res.FullName "$repo\libs\portable\Runner.res" -Force }

# 3) Monta e compila o MSI. Cliente = so recebe; Servidor = recebe e conecta.
Push-Location "$repo\res\msi"
try {
    git checkout -- . 2>$null
    $connArg = if ($Role -eq 'Cliente') { @('--conn-type', 'incoming') } else { @() }
    # Mostra a nossa versao no Windows: 4o numero = nosso build (ex.: 1.5.0.4).
    $rev = [int]($ver.Split('.')[3])
    python preprocess.py -d ../../rustdesk --app-name RSDesk -m "RS Solucoes" -v $cargoVer --revision-version $rev @connArg
    if ($LASTEXITCODE -ne 0) { throw "preprocess.py falhou" }
    & C:\RSDesk\tools\nuget.exe restore msi.sln
    msbuild msi.sln -t:clean -p:Configuration=Release -p:Platform=x64 | Out-Null
    msbuild msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10
    if ($LASTEXITCODE -ne 0) { throw "msbuild falhou" }
}
finally { Pop-Location }

New-Item -ItemType Directory -Force $saida | Out-Null
$msi = Get-ChildItem "$repo\res\msi\Package\bin\*\Release\en-us\Package.msi" | Select-Object -First 1
$dst = Join-Path $saida ("rsdesk-{0}-{1}.msi" -f $Role.ToLower(), $ver)
Copy-Item $msi.FullName $dst -Force
[System.IO.Directory]::Delete($pasta, $true)
Write-Output "MSI gerado: $dst"
