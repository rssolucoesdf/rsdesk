# Instala o RSDesk como servico e define a senha fixa (acesso sem supervisao).
# A senha e digitada na hora e nao fica gravada em nenhum arquivo.
$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Rode como administrador (use o instalar-rsdesk.bat).'; Read-Host 'Enter para sair'; exit 1
}

$instalador = Get-ChildItem -Path $PSScriptRoot -Filter 'rsdesk-*.exe' | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $instalador) { Write-Host "Coloque o rsdesk-<versao>-x86_64.exe na pasta $PSScriptRoot"; Read-Host 'Enter para sair'; exit 1 }
$exe = Join-Path $env:ProgramFiles 'RSDesk\RSDesk.exe'

Write-Host "Instalando $($instalador.Name)..."
Start-Process -FilePath $instalador.FullName -ArgumentList '--silent-install' -Wait
for ($i = 0; $i -lt 60 -and -not ((Test-Path $exe) -and (Get-Service -Name 'RSDesk' -ErrorAction SilentlyContinue))); $i++) { Start-Sleep 2 }
if (-not (Test-Path $exe)) { Write-Host 'A instalacao falhou: RSDesk.exe nao apareceu.'; Read-Host 'Enter para sair'; exit 1 }
Write-Host 'Instalado. Servico:' (Get-Service -Name 'RSDesk').Status

do {
    $s1 = Read-Host 'Digite a senha fixa (minimo 8 caracteres)' -AsSecureString
    $s2 = Read-Host 'Repita a senha' -AsSecureString
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
    $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
    $ok = ($p1 -eq $p2) -and ($p1.Length -ge 8)
    if (-not $ok) { Write-Host 'As senhas nao conferem ou sao curtas. Tente de novo.' }
} until ($ok)

$r = & $exe --password $p1 | Out-String
$p1 = $null; $p2 = $null
Write-Host "Senha: $($r.Trim())"
Write-Host "ID deste computador: $((& $exe --get-id | Out-String).Trim())"
Read-Host 'Pronto. Enter para sair'
