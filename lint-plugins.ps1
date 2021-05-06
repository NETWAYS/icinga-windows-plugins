<#
.SYNOPSIS
    Lint generated plugins, so they include all required commands
.DESCRIPTION
    The powershell framework brings various new commands, we need to test if we include them all.
#>

$plugins = @(
    'Check-UNCPath.ps1'
);

$classes = @(
    [System.Management.Automation.VerbsCommon]
    [System.Management.Automation.VerbsCommunications]
    [System.Management.Automation.VerbsData]
    [System.Management.Automation.VerbsDiagnostic]
    [System.Management.Automation.VerbsLifeCycle]
    [System.Management.Automation.VerbsSecurity]
    [System.Management.Automation.VerbsOther]
);

function Remove-Comments() {
    param(
        $content
    )

    $result = New-Object System.Collections.ArrayList;
    $inComment = $FALSE;

    foreach ($line in $content) {
        if ($inComment) {
            if ($line -match '#>') {
                $line = $line -replace '.*#>', ''
                $inComment = $FALSE;
            } else {
                continue;
            }
        } elseif ($line -match '<#') {
            $line = $line -replace '<#.*', ''
            $inComment = $TRUE;
        } elseif ($line -match '^\s*#') {
            continue;
        } else {
            # Remove trailing comment
            $line = $line -replace '\s+#.*', ''
        }

        $result += $line;
    }

    return $result;
}

function Find-CmdLets() {
    param (
        $content
    )

    $list = New-Object System.Collections.ArrayList;

    # Cleanup content
    $content = Remove-Comments $content;

    foreach ($class in $classes) {
        foreach ($field in $class.DeclaredFields) {
            $verb = $field.Name;

            $match = $content | Select-String -Pattern "((?i)${verb}-[^\s\(\);]+)";

            foreach ($m in $match.Matches) {
                foreach ($v in $m.Groups.Values) {
                    $list += $v.Value
                }
            }
        }
    }

    return $list | Sort-Object -Unique
}

foreach ($plugin in $plugins) {
    $content = Get-Content $plugin;

    $cmdlets = Find-CmdLets -content $content;
    $errors = 0;

    foreach ($c in $cmdlets) {
        if (Get-Command $c -errorAction SilentlyContinue) {
            # command exists
            continue;
        }

        $inFile = $content | Select-String -Pattern ('function\s+'+$c+'\s*\(');
        if ($inFile.Matches.Length -eq 0) {
            Write-Host "CmdLet used but not found:" $c;
            $errors++;
        }
    }
}

if ($errors -gt 0) {
    Write-Host $errors "errors found!"
    $host.SetShouldExit(1);
    exit;
} else {
    Write-Host "no errors found, checked" $cmdlets.Length "commands"
}
