# Windows Maintenance Automation

A PowerShell-based automation tool for Windows maintenance, optimization, diagnostics, updates, and report generation.

## Overview

This project automates common Windows maintenance tasks that are frequently performed by IT support teams and system administrators.

The script performs system cleanup, Windows updates, integrity checks, disk verification, and automatically generates maintenance reports in both Markdown and Microsoft Word formats.

## Features

### System Cleanup

* Remove user temporary files (`%TEMP%`)
* Remove Windows temporary files (`C:\Windows\Temp`)
* Empty Recycle Bin
* Run Windows Disk Cleanup (`cleanmgr`)

### Windows Updates

* Install and configure the PowerShell Windows Update module
* Check for available updates
* Install Windows and Microsoft Updates
* Detect if a system reboot is required

### System Health Checks

* Run DISM health restoration

```powershell
DISM /Online /Cleanup-Image /RestoreHealth
```

* Run System File Checker

```powershell
sfc /scannow
```

* Run disk verification

```powershell
chkdsk C: /scan
```

### Performance Metrics Collection

Collects system information before and after maintenance:

* Available disk space
* CPU usage
* Memory usage
* Last boot duration
* Pending updates count

### Automatic Report Generation

Generates:

* Markdown report (`.md`)
* Microsoft Word report (`.docx`)
* Maintenance log file

Reports include:

* User information
* Computer information
* Operating system details
* Maintenance execution time
* Initial diagnostics
* Cleanup operations performed
* Windows Update status
* Disk verification results
* Final diagnostics

## Requirements

### Operating System

* Windows 10
* Windows 11
* Windows Server (compatible versions)

### PowerShell

* PowerShell 5.1 or newer

### Microsoft Word

Required only for `.docx` report generation.

### Administrator Privileges

The script must be executed as Administrator.

## Dependencies

### PSWindowsUpdate

The script automatically installs the module if it is not present.

```powershell
Install-Module PSWindowsUpdate
```

## Usage

Run PowerShell as Administrator and execute:

```powershell
.\Maintenance.ps1
```

## Generated Files

### Maintenance Log

```text
%TEMP%\manutencao.log
```

### CHKDSK Results

```text
%TEMP%\chkdsk.txt
```

### Markdown Report

```text
Desktop\Relatorio_Manutencao_<COMPUTERNAME>.md
```

### Word Report

```text
Desktop\Relatorio_Manutencao_<COMPUTERNAME>.docx
```

## Report Contents

The generated report includes:

### User Information

* Username
* Computer name
* Operating system
* Technician responsible

### Execution Information

* Date
* Start time
* End time
* Total execution duration

### Initial Diagnostics

* Free disk space
* CPU usage
* RAM usage
* Boot duration

### Maintenance Actions

* Temporary files cleanup
* Recycle Bin cleanup
* Windows Update execution
* System integrity verification

### Final Diagnostics

* Free disk space after maintenance
* CPU usage after maintenance
* RAM usage after maintenance
* Improvements detected

## Security Notes

* Requires administrative privileges.
* Uses Microsoft's official update infrastructure.
* Does not modify system settings beyond maintenance and repair operations.
* Does not remove user data.

## Future Improvements

* Browser cache cleanup
* Windows Defender scan integration
* Automatic PDF report generation
* Email report delivery
* Scheduled maintenance execution
* Centralized reporting dashboard
* Other linguages

## License

This project is provided as-is for educational and administrative purposes.

Use at your own risk and always test in a controlled environment before deploying to production systems.
