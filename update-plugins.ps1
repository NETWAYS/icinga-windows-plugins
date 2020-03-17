param(
    $ModulePath = 'C:\Program Files\WindowsPowershell\Modules',
    $Framework = "${ModulePath}\icinga-powershell-framework",
    $Plugins = "${ModulePath}\icinga-powershell-plugins"
)

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
            if ($line.Trim() -eq 'param(') {
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

function Write-Check-Certificates() {
    $plugin = 'plugins\Invoke-IcingaCheckCertificate.psm1'
    $source = Get-Content "${plugins}\${plugin}"

    $files = @(
        $Framework + '\lib\core\tools\New-StringTree.psm1'
        $Framework + '\lib\core\tools\Format-IcingaPerfDataValue.psm1'
        $Framework + '\lib\core\tools\Test-Numeric.psm1'
        $Framework + '\lib\core\tools\ConvertTo-Seconds.psm1'
        $Framework + '\lib\icinga\enums\Icinga_IcingaEnums.psm1'
        $Framework + '\lib\icinga\plugin\New-IcingaCheck.psm1'
        $Framework + '\lib\icinga\plugin\New-IcingaCheckPackage.psm1'
        $Framework + '\lib\icinga\plugin\New-IcingaCheckResult.psm1'
        $Framework + '\lib\icinga\plugin\Write-IcingaPluginOutput.psm1'
        $Plugins + '\provider\certificate\Icinga_ProviderCertificate.psm1'
        $Plugins + '\provider\directory\Icinga_Provider_Directory.psm1'
    )

    $comment, $params, $body = Read-Plugin-Parts -Source $source

    $notice = '<# Assembled plugin based on Invoke-IcingaCheckCertificate from https://github.com/Icinga/icinga-powershell-plugins #>' + $NEWLINE + $NEWLINE

    $content = $comment + $NEWLINE + $notice + $params + $NEWLINE

    $content += '# Tell the script the daemon is not running' + $NEWLINE
    $content += '$global:IcingaDaemonData = @{ FrameworkRunningAsDaemon = $FALSE }' + $NEWLINE + $NEWLINE

    foreach($file in $files) {
        $content += $NEWLINE + "# Content from: " + $file + $NEWLINE
        $fileSource = Get-Content -Path $file `
            | Select-String -NotMatch -Pattern "Import-IcingaLib" `
            | Select-String -NotMatch -Pattern "Export-ModuleMember"
        $content += ($fileSource -Join $NEWLINE).Trim() + $NEWLINE
    }

    $content += $NEWLINE + "# Content from: " + $plugin + $NEWLINE
    $content += $body

    $content | Out-File "Check-Certificate.ps1"
}

Write-Check-Certificates