# Gera o instalador do RSDesk (EXE autoextraivel), como o workflow oficial do RustDesk.
# Uso (PowerShell, na pasta do repositorio): .\res\rsdesk\criar-instalador.ps1
# Antes: rode o build (python .\build.py --portable --flutter --skip-portable-pack --hwcodec --vram).
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$release = "$repo\flutter\build\windows\x64\runner\Release"
$pasta = "$repo\rustdesk"
$saida = 'C:\RSDesk\dist'
$versao = (Select-String -Path "$repo\Cargo.toml" -Pattern '^version\s*=\s*"(.+)"').Matches[0].Groups[1].Value

if (-not (Test-Path "$release\rsdesk.exe")) { throw "Build nao encontrado em $release" }
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"

if (Test-Path $pasta) { Remove-Item -Recurse -Force -LiteralPath $pasta }
Copy-Item -Recurse $release $pasta

# Driver de tela virtual (mesmo arquivo que o release oficial inclui).
$zip = "$env:TEMP\usbmmidd_v2.zip"
Invoke-WebRequest -Uri https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip -OutFile $zip
Expand-Archive $zip -DestinationPath "$env:TEMP\usbmmidd" -Force
Remove-Item -Recurse -Force "$env:TEMP\usbmmidd\usbmmidd_v2\Win32"
Remove-Item -Force "$env:TEMP\usbmmidd\usbmmidd_v2\deviceinstaller64.exe", "$env:TEMP\usbmmidd\usbmmidd_v2\deviceinstaller.exe", "$env:TEMP\usbmmidd\usbmmidd_v2\usbmmidd.bat"
Move-Item "$env:TEMP\usbmmidd\usbmmidd_v2" "$pasta\usbmmidd_v2"

$res = Get-ChildItem -Recurse -Filter Runner.res "$repo\flutter\build" | Select-Object -First 1
if ($res) { Copy-Item $res.FullName "$repo\libs\portable\Runner.res" -Force }

Push-Location "$repo\libs\portable"
try {
    python -m pip install -q -r requirements.txt
    python .\generate.py -f ..\..\rustdesk\ -o . -e ..\..\rustdesk\rsdesk.exe
    if ($LASTEXITCODE -ne 0) { throw "generate.py falhou" }
} finally { Pop-Location }

New-Item -ItemType Directory -Force $saida | Out-Null
$exe = "$saida\rsdesk-$versao-x86_64.exe"
Copy-Item "$repo\target\release\rustdesk-portable-packer.exe" $exe -Force
Remove-Item -Recurse -Force -LiteralPath $pasta
Write-Output "Instalador: $exe"
