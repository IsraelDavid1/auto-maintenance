$ErrorActionPreference = "Stop"

$admin = (
    New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator
)

if (-not $admin) {
    throw "Execute o script como ADMINISTRADOR!"
}

if (-not (Test-NetConnection download.windowsupdate.com -Port 443).TcpTestSucceeded) {
    throw "Sem acesso à internet"
}

Start-Transcript -Path "$env:TEMP\manutencao.log" -Append

$starttime = Get-Date
$endtime = $null
$DiskBefore = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$FreeSpaceBefore = [math]::Round($DiskBefore.FreeSpace / 1GB, 2)
$OS = Get-CimInstance Win32_OperatingSystem
$OSName = $OS.Caption
$script:SfcStatus = "Não executado"
$script:ChkStatus = "Não executado"

function Get-PendingUpdatesCount {

    try {
        if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {

            Install-Module PSWindowsUpdate `
                -Force `
                -AllowClobber `
                -Confirm:$false
        }

        Import-Module PSWindowsUpdate

        return (
            Get-WindowsUpdate -MicrosoftUpdate -ErrorAction SilentlyContinue
        ).Count
    }
    catch {
        return "Não foi possível verificar"
    }
}

Function Get-BootTime {
    $BootEvent = Get-WinEvent `
        -FilterHashtable @{
            LogName='Microsoft-Windows-Diagnostics-Performance/Operational'
            ID=100
        } `
        -MaxEvents 1

    [xml]$xml = $BootEvent.ToXml()

    $BootTimeMs = ($xml.Event.EventData.Data |
        Where-Object {$_.Name -eq "BootTime"}).'#text'

    $BootSeconds = [math]::Round($BootTimeMs / 1000,2)

    return $BootSeconds
}

function Get-RamUsage {
    $OS = Get-CimInstance Win32_OperatingSystem
    $TotalRAM = [math]::Round($OS.TotalVisibleMemorySize / 1MB,2)
    $FreeRAM = [math]::Round($OS.FreePhysicalMemory / 1MB,2)
    $UsedRAM = [math]::Round($TotalRAM - $FreeRAM,2)
    $RamPercent = [math]::Round(($UsedRAM / $TotalRAM) * 100,2)

    return "$RamPercent %"
}

function Get-CpuUsage {
    try {
        $cpuSamples = @()

        1..5 | ForEach-Object {
            $cpuSamples += (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples.CookedValue
            Start-Sleep 1
        }

        $CpuAverage = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 2)
        return "$CpuAverage %"
    }
    catch {
        # Fallback via CIM caso o contador de performance esteja indisponível
        try {
            $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
            return "$([math]::Round($cpu, 2)) % (via CIM)"
        }
        catch {
            return "Não foi possível verificar"
        }
    }
}

function Update-Progress {
    param(
        [int]$Percent,
        [string]$Status
    )

    Write-Progress `
        -Activity "Manutenção Windows" `
        -Status $Status `
        -PercentComplete $Percent
}

function Clear-TempFiles {
    try {
        Write-Output "==== INÍCIO LIMPEZA ===="
        Update-Progress 5 "Limpando %temp%"
        Get-ChildItem $env:TEMP -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Update-Progress 10 "Limpando arquivos temporários"
        
        Update-Progress 15 "Limpando Temp"
        Get-ChildItem "C:\Windows\Temp" -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Update-Progress 20 "Limpando arquivos temporários"
        # Retirei a proxima etapa pós não é mais recomendado apagar o prefetch, caso necessário descomentar
        # Remove-Item "C:\Windows\Prefetch\*" -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning $_.Exception.Message
        Write-Host "Falha ao limpar arquivos"
    }
}

function Start-DiskCleaner {
    try {
        $p = Start-Process cleanmgr -ArgumentList "/sagerun:1" -PassThru -Wait
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Update-Progress 30 "Limpando disco C:"
    }
    catch {
        Write-Warning $_.Exception.Message
        Write-Host "Erro na limpeza de disco"
    }
}

function Update-System {
    try {
        Write-Output "==== INÍCIO WINDOWS UPDATE ===="
        Set-PSRepository PSGallery -InstallationPolicy Trusted
        [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12
        if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
            Install-Module PSWindowsUpdate `
                -Force `
                -AllowClobber `
                -Confirm:$false
        }
        Import-Module PSWindowsUpdate
        Update-Progress 40 "Atualizando sistema e drivers"
        
        Add-WUServiceManager `
            -MicrosoftUpdate `
            -Confirm:$false `
            -ErrorAction SilentlyContinue
        Get-WindowsUpdate -MicrosoftUpdate
        Update-Progress 55 "Atualizando sistema e drivers"
        
        Install-WindowsUpdate `
            -AcceptAll `
            -IgnoreReboot
        if (Get-WURebootStatus -Silent) {
            Write-Host "Reinicialização necessária" -ForegroundColor Yellow
        }
        Update-Progress 70 "Atualizando sistema e drivers"
    }
    catch {
        Write-Warning $_.Exception.Message
        Write-Host "Erro na atualização"
    }
}

function Repair-SystemFiles {
    try {
        Write-Output "==== INÍCIO CHECAGEM DE DISCO ===="
        Update-Progress 75 "Executando DISM"
        DISM /online /Cleanup-Image /RestoreHealth
        Update-Progress 80 "Reparando arquivos"
        
        Update-Progress 85 "Executando SFC"
        $SfcResult = sfc /scannow
        if ($SfcResult -match "não encontrou nenhuma violação" -or $SfcResult -match "did not find any integrity violations") {
            $script:SfcStatus = "Nenhuma violação encontrada"
        }
        elseif ($SfcResult -match "A Proteção de Recursos do Windows encontrou arquivos" -or $SfcResult -match "Windows Resource Protection found corrupt files") {
            $script:SfcStatus = "Arquivos corrompidos encontrados e corrigidos"
        }
        else {
            $script:SfcStatus = "Necessária análise manual"
        }
        Update-Progress 90 "Reparando arquivos"
        
        Update-Progress 95 "Executando chkdsk"
        $script:ChkDskResult = chkdsk C: /scan
        $ChkDskResult | Out-File "$env:TEMP\chkdsk.txt"
        if ($ChkDskResult -match "não encontrou problemas" -or $ChkDskResult -match "found no problems") {
            $script:ChkStatus = "Nenhum problema encontrado"
        }
        else {
            $script:ChkStatus = "Verificar log completo"
        }
        Update-Progress 100 "Reparando arquivos"
    }
    catch {
        Write-Warning $_.Exception.Message
        Write-Host "Falha na verificação e reparo de disco"
    }
}


function main {
    Write-Host "$starttime"
    Write-Host "Espaço livre: $FreeSpaceBefore GB"
    Write-Progress `
        -Activity "Manutenção Windows" `
        -Status "Inicio" `
        -PercentComplete 0

    try {
        Clear-TempFiles
        Start-DiskCleaner
        Update-System
        Repair-SystemFiles

        Write-Progress -Activity "Manutenção Windows" -Completed

        $script:endtime = Get-Date

        Write-Host ""
        Write-Host "Manutenção concluída."
        Write-Host "Início : $starttime"
        Write-Host "Fim    : $endtime"
        Write-Host "Tempo  : $($endtime - $starttime)"
    }
    catch {
        Write-Host "ERROR:" -ForegroundColor Red
        Write-Host $_.Exception.Message
        Write-Host $_.ScriptStackTrace
    }
}

$CpuBefore = Get-CpuUsage
$RamBefore = Get-RamUsage
$BootTimeBefore = Get-BootTime

try {
    main
}
finally {
    
    try { Stop-Transcript } catch { <# ignora se não há transcript ativo #> }

    $CpuAfter = Get-CpuUsage
    $RamAfter = Get-RamUsage
    $DiskAfter = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $FreeSpaceAfter = [math]::Round($DiskAfter.FreeSpace / 1GB, 2)
    $PendingCount = Get-PendingUpdatesCount

    $Report = @"
## Registro de Limpeza e Otimização de Computador

### 1. Identificação do Usuário

- Nome do usuário: $env:USERNAME
- Departamento: 
- Nome do computador: $env:COMPUTERNAME
- Sistema operacional: $OSName
- Responsável pela execução:

---

### 2. Controle de Execução

- Data: $($starttime.ToString("dd/MM/yyyy"))
- Hora de início: $($starttime.ToString("HH:mm:ss"))
- Hora de término: $(if ($endtime) { $endtime.ToString("HH:mm:ss") } else { "N/A" })
- Duração total: $(if ($endtime) { $endtime - $starttime } else { "N/A" })

---

### 3. Diagnóstico Inicial

- Espaço em disco (antes): $FreeSpaceBefore
- Uso de CPU em repouso: $CpuBefore
- Uso de memória (RAM): $RamBefore
- Tempo de inicialização (estimado): $BootTimeBefore segundos

---

### 4. Limpeza Realizada

### 4.1 Arquivos temporários

- Limpeza de pasta TEMP: (x) Sim ( ) Não
- Limpeza de Windows Temp: (x) Sim ( ) Não
- Limpeza de Prefetch: ( ) Sim (x) Não

### 4.2 Lixeira

- Lixeira esvaziada: (x) Sim ( ) Não

### 4.3 Cache de navegadores

- Google Chrome: ( ) Sim (x) Não
- Microsoft Edge: ( ) Sim (x) Não
- Mozilla Firefox: ( ) Sim (x) Não

### 4.4 Programas

- Programas desinstalados:
    - 
    -
    -

### 4.5 Inicialização do sistema

- Programas desativados na inicialização:
    - 
    -
    -

---

### 5. Verificações de Segurança

- Antivírus executado: ( ) Sim ( ) Não
- Ameaças encontradas:
- Ações tomadas:

---

### 6. Atualizações

- Windows Update realizado: (x) Sim ( ) Não
- Atualizações pendentes: $PendingCount
- Drivers atualizados: (x) Sim ( ) Não

---

### 7. Verificação de Disco

- CHKDSK executado: (x) Sim ( ) Não
- Problemas encontrados: $ChkStatus
- SFC /scannow executado: (x) Sim ( ) Não
- Problemas encontrados: $SfcStatus

---

### 8. Diagnóstico Final

- Espaço em disco (depois): $FreeSpaceAfter
- Uso de CPU em repouso: $CpuAfter
- Uso de memória (RAM):  $RamAfter
- Tempo de inicialização (estimado):
- Melhorias observadas:

---

### 9. Observações Gerais

- 
-
-

---

### 10. Ações Futuras / Recomendações

- 
- 
- 

---
"@

    $ReportPath = "$env:USERPROFILE\Desktop\Relatorio_Manutencao_$env:COMPUTERNAME.md"

    $Report | Out-File $ReportPath -Encoding UTF8

    try {
        if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
            winget install --source winget --exact --id JohnMacFarlane.Pandoc --silent
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        }
        
        $DocxPath = "$env:USERPROFILE\Desktop\Relatorio_Manutencao_$env:COMPUTERNAME.docx"

        pandoc $ReportPath -o $DocxPath
    }
    catch {
        Write-Warning $_.Exception.Message
        Write-Host "Falha na criação do arquivo word"
    }
}
