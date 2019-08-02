<#
Icinga Check DHCP Server

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
  - https://docs.microsoft.com/en-us/powershell/module/dhcpserver/?view=win10-ps
#>
Param(
    [int] $WarnFreeLeases = 100,
    [int] $CritFreeLeases = 200,
    [int] $WarnUsage = $null,
    [int] $CritUsage = $null
)

$ErrorActionPreference = "Stop"
$Error.Clear()
$StateMap = @("OK", "WARNING", "CRITICAL", "UNKNOWN")

function Exit-Icinga([int] $State, [string] $Output, [string[]] $LongOutput, [String[]] $PerfData) {
    if ($State -gt 3 -Or $State -lt 0) {
        $State = 3
    }
    $StateName = $StateMap[$State]
    Write-Host "${StateName} - ${Output}"
    if ($LongOutput) {
        foreach ($line in $LongOutput) {
            Write-Host $line
        }
    }
    if ($Error) {
        Write-Host "Powershell Error: ${Error}"
    }
    if ($PerfData) {
        Write-Host ("| " + $PerfData)
    }
    return $state
}

function main() {
    try {
        $Service = Get-Service -Name DHCPServer
    } catch {
        return Exit-Icinga 3 "Could not find service: DHCPServer"
    }

    if ($Service.Status -ne "Running") {
        return Exit-Icinga 2 ("Service DHCPServer is not running: " + $Service.Status)
    }

    if (-not (Get-Module -ListAvailable -Name DHCPServer)) {
        return Exit-Icinga 3 "PowerShell Module DHCPServer is not available!"
    }

    if ($WarnFreeLeases -and $CritFreeLeases -and $WarnFreeLeases -le $CritFreeLeases) {
        return Exit-Icinga 3 "WarnFreeLeases must be greater than CritFreeLeases"
    }

    if ($WarnUsage -and $CritUsage -and $WarnUsage -gt $CritUsage) {
        return Exit-Icinga 3 "WarnUsage must be lower than CritUsage"
    }

    return Invoke-ScopeCheck
}

function Invoke-ScopeCheck() {
    $LongOutput = @()
    $PerfData = @()
    $Criticals = 0
    $Warnings = 0
    $Oks = 0

    $Scopes = Get-DhcpServerv4Scope

    foreach($scope in $Scopes) {
        if ($scope.State -ne "Active") {
            continue
        }

        $state = 0
        $Oks++

        $stats = Get-DhcpServerv4ScopeStatistics -ScopeId $scope.ScopeId

        $free = $stats.Free
        $usage = [math]::round($stats.PercentageInUse)

        if ($stats.InUse -eq 0 -or (
            (-not $WarnFreeLeases -or $free -gt $WarnFreeLeases) -and `
            (-not $CritFreeLeases -or $free -gt $CritFreeLeases) -and `
            (-not $WarnUsage -or $usage -lt $WarnUsage) -and `
            (-not $CritUsage -or $usage -lt $CritUsage) `
        )) {
            $state = 0
            $Oks++
        } elseif (
            ($WarnFreeLeases -and $CritFreeLeases -and $free -gt $CritFreeLeases) -or `
            ($WarnUsage -and $CritUsage -and $usage -lt $CritUsage)
        ) {
            $state = 1
            $Warnings++
        } else {
            $state = 2
            $Criticals++
        }

        $LongOutput += "[{0}] {1} ({2}) InUse={3} ({4}%) Free={5} Reserved={6}" -f $StateMap[$state], $scope.Name, $scope.ScopeId, `
            $stats.InUse, $usage, $free, $stats.Reserved

        $PerfPrefix = Convert-Performance-Label $scope.Name
        $PerfData += "{0}_{1}={2}" -f $PerfPrefix, "inuse", $stats.InUse
        $PerfData += "{0}_{1}={2}" -f $PerfPrefix, "free", $free
        $PerfData += "{0}_{1}={2}" -f $PerfPrefix, "reserved", $stats.Reserved

    }

    return Exit-Summary $Oks $Warnings $Criticals $LongOutput $PerfData
}

function Convert-Performance-Label([string] $name) {
    return $name -replace "[^\w]+", "_"
}

function Exit-Summary([int] $Oks, [int] $Warnings, [int] $Criticals, [String[]] $LongOutput, [String[]] $PerfData) {
    if ($Criticals -gt 0) {
        $State = 2
        $Summary = "${Criticals} DHCP scopes are in critical state"
    } elseif ($Warnings -gt 0) {
        $State = 1
        $Summary = "${Warnings} DHCP scopes are in warning state"
    } elseif ($Oks -gt 0) {
        $State = 0
        $Summary = "All ${Oks} DHCP scopes are fine"
    } else {
        $State = 2
        $Summary = "No active DHCP scopes found"
    }

    return Exit-Icinga $State $Summary $LongOutput $PerfData
}

$rc = main
if ($host.name -notmatch 'ISE') {
    exit $rc
} else {
    Write-Host "Would exit with code: ", $rc
}