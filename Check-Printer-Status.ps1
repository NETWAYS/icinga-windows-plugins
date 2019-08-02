<#
Icinga Check Printer Status

(c) 2019 NETWAYS GmbH <info@netways.de>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

Microsoft Documentation:
  - https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-service
  - https://docs.microsoft.com/en-us/powershell/module/printmanagement/get-printer
  - https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/cim-printer
  - https://docs.microsoft.com/en-us/previous-versions/aa394288(v%3Dvs.85)
#>
Param(
    [String[]] $Ignore = @("Fax"),
    [int] $WarnJobs = 1,
    [int] $CritJobs = 10,
    [switch] $NoneIsError,
    [switch] $UseCIM
)

$ErrorActionPreference = "Stop"
$StateMap = @("OK", "WARNING", "CRITICAL", "UNKNOWN")

function Exit-Icinga([int] $State, [string] $Output, [string[]] $LongOutput) {
    if ($State -gt 3 -Or $State -lt 0) {
        $State = 3
    }
    $StateName = $StateMap[$State]
    Write-Output "${StateName} - ${Output}"
    if ($LongOutput) {
        Write-Output $LongOutput
    }
    if ($Error) {
        Write-Output "Powershell Error: ${Error}"
    }
    exit $State
}

function main() {
    try {
        $Service = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    } catch {
        Exit-Icinga 3 "Could not find service: Spooler"
    }

    if ($Service.Status -ne "Running") {
        Exit-Icinga 2 ("Service Spooler is not running: " + $Service.Status)
    }

    if (-not $UseCIM -and (Get-Command "Get-Printer" -ErrorAction SilentlyContinue)) {
        Invoke-ModernCheck
    } else {
        $Error.Clear() # clear Get-Command error
        Invoke-CIMCheck
    }
}

function Invoke-ModernCheck() {
    $LongOutput = @()
    $Criticals = 0
    $Warnings = 0
    $Oks = 0

    $Printers = Get-Printer

    # see the enum for all states:
    # [enum]::GetValues([type] "Microsoft.PowerShell.Cmdletization.GeneratedTypes.Printer.PrinterStatus")
    $NormalStates = @("Normal", "ManualFeed", "IoActive", "Busy", "Printing", "Waiting", "Processing", "Initializing", "WarmingUp", "PowerSave")
    $WarningStates = @("Paused", "PendingDeletion", "TonerLow")

    foreach($printer in $Printers) {
        if ($Ignore.Contains($printer.Name)) {
            continue
        }
        $printerStatus = [string] $printer.PrinterStatus
        $jobCount = $printer.JobCount

        if ($NormalStates.Contains($printerStatus) -and ($jobCount -lt $WarnJobs) -and ($jobCount -lt $CritJobs)) {
            $state = 0
            $Oks++
        } elseif ($WarningStates.Contains($printerStatus) -and ($jobCount -ge $WarnJobs) -and $($jobCount -lt $CritJobs)) {
            $state = 1
            $Warnings++
        } else {
            $state = 2
            $Criticals++
        }
        $LongOutput += "[{0}] {1} - Status={2} JobCount={3}" -f $StateMap[$state], $printer.Name, $printer.PrinterStatus, $jobCount
    }

    Exit-Summary $Oks $Warnings $Criticals $LongOutput
}

function Invoke-CIMCheck() {
    $LongOutput = @()
    $Criticals = 0
    $Warnings = 0
    $Oks = 0

    $Printers = Get-CimInstance Win32_Printer
    $PrintQueue = Get-CimInstance Win32_PerfFormattedData_Spooler_PrintQueue
    $PrintQueueMap = @{}
    foreach($queue in $PrintQueue) {
        $PrintQueueMap[$queue.Name] = $queue
    }

    # Derived from PrinterStatus
    $States = @("NOSTATE", "Other", "Unknown", "Idle", "Printing", "Warmup", "Stopped Printing", "Offline")
    $NormalStates = @("Idle", "Printing", "Warmup")

    # Derived from StatusInfo
    $Infos = @("(noinfo)", "Other", "Unknown", "Enabled", "Disabled", "Not Applicable")
    $NormalInfo = @("Enabled", "Not Applicable")

    foreach($printer in $Printers) {
        if ($Ignore.Contains($printer.Name)) {
            continue
        }
        $printerStatus = $States[$printer.PrinterStatus]
        $infoCode = $printer.StatusInfo
        if (-not $infoCode) {
            $infoCode = 5 # Not Applicable
        }
        $printerInfo = $Infos[$infoCode]
        $jobCount = ($PrintQueueMap[$printer.Name]).Jobs

        if ($NormalStates.Contains($printerStatus) -and $NormalInfo.Contains($printerInfo) -and ($jobCount -lt $WarnJobs) -and ($jobCount -lt $CritJobs)) {
            $state = 0
            $Oks++
        } elseif (($jobCount -ge $WarnJobs) -and $($jobCount -lt $CritJobs)) {
            $state = 1
            $Warnings++
        } else {
            $state = 2
            $Criticals++
        }
        $LongOutput += "[{0}] {1} - Status={2} Info={3} JobCount={4}" -f $StateMap[$state], $printer.Name, $printerStatus, $printerInfo, $jobCount
    }

    Exit-Summary $Oks $Warnings $Criticals $LongOutput
}

function Exit-Summary([int] $Oks, [int] $Warnings, [int] $Criticals, [String[]] $LongOutput) {
    if ($Criticals -gt 0) {
        $State = 2
        $Summary = "${Criticals} printers are in critical state"
    } elseif ($Warnings -gt 0) {
        $State = 1
        $Summary = "${Warnings} printers are in warning state"
    } elseif ($Oks -gt 0) {
        $State = 0
        $Summary = "All ${Oks} printers are fine"
    } else {
        if ($NoneIsError) {
            $State = 2
        } else {
            $State = 0
        }
        $Summary = "No Printers found"
    }

    Exit-Icinga $State $Summary $LongOutput
}

main