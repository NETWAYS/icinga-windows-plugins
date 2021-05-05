$Framework = "icinga-powershell-framework"
$Plugins = "icinga-powershell-plugins"

# Make sure we are were this script lies
Set-Location $PSScriptRoot

$NEWLINE = "`r`n"

function Read-Plugin-Parts()
{
    param(
        [object[]]$Source
    );

    $inComment = $FALSE
    $inBody = $FALSE
    $inParams = $FALSE
    $comment = ''
    $params = ''
    $body = ''

    foreach($line in $Source) {
        if (!$inComment -and !$inBody) {
            if ($line -eq '<#') {
                $inComment = $TRUE
            } elseif ($line.StartsWith('function ')) {
                $inBody = $TRUE
                continue
            } elseif ($line -ne '') {
                throw ("Invalid line: " + $line.Substring(0, 15))
            }
        }

        if ($inComment) {
            $comment += $line + $NEWLINE
            if ($line -eq '#>') {
                $inComment = $FALSE
            }
        } elseif ($inParams) {
            $params += $line + $NEWLINE
            if ($line.Trim() -eq ');') {
                $inParams = $FALSE
            }
        } elseif ($inBody) {
            if ($line.Trim() -match 'param\s*\(') {
                $params += $line + $NEWLINE
                $inParams = $TRUE
            } elseif ($line -eq '{') {
                # begin of block
                continue
            } elseif ($line -eq '}') {
                $inBody = $FALSE
            } else {
                $body += $line + $NEWLINE
            }
        }
    }

    return $comment, $params, $body
}

function Find-PSModule() {
    param(
        [string]$Name
    )

    $Path = $null
    $Location = $null

    foreach ($p in ($env:PSModulePath -Split ';')) {
        if (Test-Path "${p}\${Name}") {
            $Path = "${p}\${Name}"
            $Location = $p
            break
        }
    }

    if ($null -eq $Path) {
        throw "Could not find module ${Name} in PSModulePath"
    }

    if (Test-Path "${Path}\.git") {
        $version = (git --git-dir "${Path}\.git" describe --tags);
        $version = $version -replace '^v', '';
        return $Path, $version, $Location;
    } else {
        # Find the newest version of a subdir
        $versions = [array](Get-ChildItem $Path | Select-Object -Expand Name | Sort-Object {[version] $_})
        if ($versions.Length -eq 0) {
            throw "No versions found in $Path"
        }

        $version = $versions[-1]
        return "${Path}\${version}", $version, $Location
    }
}
function Get-AssembledPlugin() {
    param(
        [string]$Source,
        [string[]]$Dependencies
    )

    $FrameworkPath, $FrameworkVersion, $FrameworkLocation = Find-PSModule $Framework
    $PluginPath, $PluginVersion, $PluginLocation = Find-PSModule $Plugins

    $comment, $params, $body = Read-Plugin-Parts -Source (Get-Content "${PluginPath}\${Source}")

    $notice = @(
        '<#'
        "Assembled plugin based on ${Source} from"
        'https://github.com/Icinga/icinga-powershell-plugins'
        ''
        "icinga-powershell-framework: ${FrameworkVersion}"
        "icinga-powershell-plugins: ${PluginVersion}"
        '#>'
    )

    $content = $comment + $NEWLINE + ($notice -join $NEWLINE) + $NEWLINE + $NEWLINE + $params + $NEWLINE

    $content += '# Tell the script the daemon is not running' + $NEWLINE
    $content += '$global:IcingaDaemonData = @{ FrameworkRunningAsDaemon = $FALSE }' + $NEWLINE + $NEWLINE

    foreach($file in $Dependencies) {
        if ($file.StartsWith('plugins:')) {
            $file = $file.Replace('plugins:', $PluginPath)
            $shortFile = $file.Replace($PluginLocation + '\', '')
        } elseif ($file.StartsWith('framework:')) {
            $file = $file.Replace('framework:', $FrameworkPath)
            $shortFile = $file.Replace($FrameworkLocation + '\', '')
        }

        $content += $NEWLINE + "# Content from: " + $shortFile + $NEWLINE
        $fileSource = Get-Content -Path $file `
            | Select-String -NotMatch -Pattern "Import-IcingaLib" `
            | Select-String -NotMatch -Pattern "Export-ModuleMember"
        $fileContent = ($fileSource -Join $NEWLINE).Trim() + $NEWLINE;

        # Remove usage of Get-IcingaCacheData
        $fileContent = $fileContent.Replace('$CheckResultCache = Get-IcingaCacheData', '$CheckResultCache = $NULL; # Get-IcingaCacheData');

        $content += $fileCOntent;
    }

    $content += $NEWLINE + "# Content from: " + $Source + $NEWLINE
    $content += $body

    return $content
}

function Write-Check-Certificates() {
    $deps = @(
        'framework:\lib\core\tools\New-StringTree.psm1'
        'framework:\lib\core\tools\Format-IcingaPerfDataValue.psm1'
        'framework:\lib\core\tools\Test-Numeric.psm1'
        'framework:\lib\core\tools\ConvertTo-Seconds.psm1'
        'framework:\lib\icinga\enums\Icinga_IcingaEnums.psm1'
        'framework:\lib\icinga\plugin\New-IcingaCheck.psm1'
        'framework:\lib\icinga\plugin\New-IcingaCheckPackage.psm1'
        'framework:\lib\icinga\plugin\New-IcingaCheckResult.psm1'
        'framework:\lib\icinga\plugin\Write-IcingaPluginOutput.psm1'
        'plugins:\provider\certificate\Icinga_ProviderCertificate.psm1'
    )

    $content = Get-AssembledPlugin -Source 'plugins\Invoke-IcingaCheckCertificate.psm1' -Dependencies $deps

    $content | Out-File "Check-Certificate.ps1"
}

function Write-Check-UNCPath() {
    $deps = @(
        'framework:\lib\core\tools\New-StringTree.psm1'
        'framework:\lib\core\tools\Format-IcingaPerfDataLabel.psm1'
        'framework:\lib\core\tools\Format-IcingaPerfDataValue.psm1'
        'framework:\lib\core\tools\Convert-IcingaPluginThresholds.psm1'
        'framework:\lib\core\tools\Test-Numeric.psm1'
        'framework:\lib\core\tools\ConvertTo-Integer.psm1'
        'framework:\lib\core\framework\Test-IcingaFrameworkConsoleOutput.psm1'
        'framework:\lib\core\logging\Write-IcingaConsolePlain.psm1'
        'framework:\lib\core\logging\Write-IcingaConsoleOutput.psm1'
        'framework:\lib\icinga\enums\Icinga_IcingaEnums.psm1'
        'framework:\lib\icinga\plugin\New-IcingaCheckPackage.psm1'
        'framework:\lib\icinga\plugin\New-IcingaCheck.psm1'
        'framework:\lib\icinga\plugin\New-IcingaCheckResult.psm1'
        'framework:\lib\icinga\plugin\New-IcingaPerformanceDataEntry.psm1'
        'framework:\lib\icinga\plugin\Write-IcingaPluginOutput.psm1'
        'framework:\lib\icinga\plugin\Write-IcingaPluginPerfData.psm1'
        'plugins:\provider\certificate\Icinga_ProviderCertificate.psm1'
        'plugins:\provider\disks\Get-IcingaUNCPathSize.psm1'
    )

    $content = Get-AssembledPlugin -Source 'plugins\Invoke-IcingaCheckUNCPath.psm1' -Dependencies $deps

    $content | Out-File "Check-UNCPath.ps1"
}

Write-Check-Certificates
Write-Check-UNCPath
