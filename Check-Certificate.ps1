<#
.SYNOPSIS
   Check whether a certificate is still trusted and when it runs out or starts.
.DESCRIPTION
   Invoke-IcingaCheckCertificate returns either 'OK', 'WARNING' or 'CRITICAL', based on the thresholds set.
   e.g a certificate will run out in 30 days, WARNING is set to '20d:', CRITICAL is set to '50d:'. In this case the check will return 'WARNING'.
   
   More Information on https://github.com/Icinga/icinga-powershell-plugins
.FUNCTIONALITY
   This module is intended to be used to check if a certificate is still valid or about to become valid.
.EXAMPLE
   You can check certificates in the local certificate store of Windows:

   PS> Invoke-IcingaCheckCertificate -CertStore 'LocalMachine' -CertStorePath 'My' -CertSubject '*' -WarningEnd '30d:' -CriticalEnd '10d:'
   [OK] Check package "Certificates" (Match All)
   \_ [OK] Certificate 'test.example.com' (valid until 2033-11-19 : 4993d) valid for: 431464965.59
.EXAMPLE
   Also a directory with a file name pattern is possible:

   PS> Invoke-IcingaCheckCertificate -CertPaths "C:\ProgramData\icinga2\var\lib\icinga2\certs" -CertName '*.crt' -WarningEnd '10000d:'
   [WARNING] Check package "Certificates" (Match All) - [WARNING] Certificate 'test.example.com' (valid until 2033-11-19 : 4993d) valid for, Certificate 'Icinga CA' (valid until 2032-09-18 : 4566d) valid for
   \_ [WARNING] Certificate 'test.example.com' (valid until 2033-11-19 : 4993d) valid for: Value "431464907.76" is lower than threshold "864000000"
   \_ [WARNING] Certificate 'Icinga CA' (valid until 2032-09-18 : 4566d) valid for: Value "394583054.72" is lower than threshold "864000000"
.EXAMPLE
   The checks can be combined into a single check:

   PS> Invoke-IcingaCheckCertificate -CertStore 'LocalMachine' -CertStorePath 'My' -CertThumbprint '*'-CertPaths "C:\ProgramData\icinga2\var\lib\icinga2\certs" -CertName '*.crt' -Trusted
   [CRITICAL] Check package "Certificates" (Match All) - [CRITICAL] Certificate 'test.example.com' trusted, Certificate 'Icinga CA' trusted 
   \_ [CRITICAL] Check package "Certificate 'test.example.com'" (Match All)
      \_ [OK] Certificate 'test.example.com' (valid until 2033-11-19 : 4993d) valid for: 431464853.88
      \_ [CRITICAL] Certificate 'test.example.com' trusted: Value "False" is not matching threshold "True"
   \_ [CRITICAL] Check package "Certificate 'Icinga CA'" (Match All)
      \_ [OK] Certificate 'Icinga CA' (valid until 2032-09-18 : 4566d) valid for: 394583000.86
      \_ [CRITICAL] Certificate 'Icinga CA' trusted: Value "False" is not matching threshold "True"

.PARAMETER Trusted
   Used to switch on trusted behavior. Whether to check, If the certificate is trusted by the system root.
   Will return Critical in case of untrust.

   Note: it is currently required that the root and intermediate CA is known and trusted by the local system.

.PARAMETER CriticalStart
   Used to specify a date. The start date of the certificate has to be past the date specified, otherwise the check results in critical. Use carefully.
   Use format like: 'yyyy-MM-dd'
   
.PARAMETER WarningEnd
   Used to specify a Warning range for the end date of an certificate. In this case a string.
   Allowed units include: ms, s, m, h, d, w, M, y

.PARAMETER CriticalEnd
   Used to specify a Critical range for the end date of an certificate. In this case a string.
   Allowed units include: ms, s, m, h, d, w, M, y
   
.PARAMETER CertStore
   Used to specify which CertStore to check. Valid choices are '*', 'LocalMachine', 'CurrentUser', ''
   
 .PARAMETER CertThumbprint
   Used to specify an array of Thumbprints, which are used to determine what certificate to check, within the CertStore.

.PARAMETER CertSubject
   Used to specify an array of Subjects, which are used to determine what certificate to check, within the CertStore.
   
.PARAMETER CertStorePath
   Used to specify which path within the CertStore should be checked.
   
.PARAMETER CertPaths
   Used to specify an array of paths on your system, where certificate files are. Use with CertName.
   
.PARAMETER CertName
   Used to specify an array of certificate names of certificate files to check. Use with CertPaths.
   
.INPUTS
   System.String
.OUTPUTS
   System.String
.LINK
   https://github.com/Icinga/icinga-powershell-plugins
.NOTES
#>

<# Assembled plugin based on Invoke-IcingaCheckCertificate from https://github.com/Icinga/icinga-powershell-plugins #>

   param(
      #Checking
      [switch]$Trusted,
      $CriticalStart         = $null,
      $WarningEnd            = '30d:',
      $CriticalEnd           = '10d:',
      #CertStore-Related Param
      [ValidateSet('*', 'LocalMachine', 'CurrentUser', $null)]
      [string]$CertStore     = $null,
      [array]$CertThumbprint = $null,
      [array]$CertSubject    = $null,
      $CertStorePath         = '*',
      #Local Certs
      [array]$CertPaths      = $null,
      [array]$CertName       = $null,
      #Other
      [ValidateSet(0, 1, 2, 3)]
      [int]$Verbosity        = 3
   );

# Tell the script the daemon is not running
$global:IcingaDaemonData = @{ FrameworkRunningAsDaemon = $FALSE }


# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-framework\lib\core\tools\New-StringTree.psm1
function New-StringTree()
{
    param(
        [int]$Spacing
    )
    
    if ($Spacing -eq 0) {
        return '';
    }

    [string]$spaces = '\_ ';
    
    while ($Spacing -gt 1) {
        $Spacing -= 1;
        $spaces = '   ' + $spaces;
    }

    return $spaces;
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-framework\lib\core\tools\Format-IcingaPerfDataValue.psm1
function Format-IcingaPerfDataValue()
{
    param(
        $PerfValue
    );

    if ((Test-Numeric $PerfValue) -eq $FALSE) {
        return $PerfValue;
    }

    # Convert our value to a string and replace ',' with a '.' to allow Icinga to parse the output
    # In addition, round every output to 2 digits
    return (([string]([math]::round($PerfValue, 2))).Replace(',', '.'));
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-framework\lib\core\tools\Test-Numeric.psm1
<#
.SYNOPSIS
   Tests whether a value is numeric
.DESCRIPTION
   This module tests whether a value is numeric

   More Information on https://github.com/Icinga/icinga-powershell-framework
.EXAMPLE
   PS> Test-Numeric 32
   True
.LINK
   https://github.com/Icinga/icinga-powershell-framework
.NOTES
#>
function Test-Numeric ($number) {
    return $number -Match "^[\d\.]+$";
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-framework\lib\core\tools\ConvertTo-Seconds.psm1
<#
.SYNOPSIS
   Converts unit to seconds.
.DESCRIPTION
   This module converts a given time unit to seconds.
   e.g hours to seconds.

   More Information on https://github.com/Icinga/icinga-powershell-framework

.PARAMETER Value
   Specify unit to be converted to seconds. Allowed units: ms, s, m, h, d, w, M, y
   ms = miliseconds; s = seconds; m = minutes; h = hours; d = days; w = weeks; M = months; y = years;

   Like 20d for 20 days.
.EXAMPLE
   PS> ConvertTo-Seconds 30d
   2592000
.LINK
   https://github.com/Icinga/icinga-powershell-framework
.NOTES
#>

function ConvertTo-Seconds()
{
    param(
        [string]$Value
    );

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value;
    }

    [string]$NumberPart = '';
    [string]$UnitPart   = '';
    [bool]$Negate       = $FALSE;
    [bool]$hasUnit      = $FALSE;

    foreach($char in $Value.ToCharArray()) {
        if ((Test-Numeric $char)) {
            $NumberPart += $char;
        } else {
            if ($char -eq '-') {
                $Negate = $TRUE;
            } elseif ($char -eq '.' -Or $char -eq ',') {
                $NumberPart += '.';
            } else {
                $UnitPart += $char;
                $hasUnit = $TRUE;
            }
        }
    }

    if (-Not $hasUnit) {
        return $Value;
    }

    [single]$ValueSplitted = $NumberPart;
    $result             = 0;

    if ($Negate) {
        $ValueSplitted *= -1;
    }

    [string]$errorMsg   = (
        [string]::Format('Invalid unit type "{0}" specified for convertion. Allowed units: ms, s, m, h, d, w, M, y', $UnitPart)
    );

    if ($UnitPart -Match 'ms') {
        $result = ($ValueSplitted / [math]::Pow(10, 3));
    } else {
        if ($UnitPart.Length -gt 1) {
            Throw $errorMsg;
        }

        switch ([int][char]$UnitPart) {
            { 115 -contains $_ } { $result = $ValueSplitted; break; } # s
            { 109 -contains $_ } { $result = $ValueSplitted * 60; break; } # m
            { 104 -contains $_ } { $result = $ValueSplitted * 3600; break; } # h
            { 100 -contains $_ } { $result = $ValueSplitted * 86400; break; } # d
            { 119 -contains $_ } { $result = $ValueSplitted * 604800; break; } # w
            { 77  -contains $_ } { $result = $ValueSplitted * 2592000; break; } # M
            { 121 -contains $_ } { $result = $ValueSplitted * 31536000; break; } # y
            default { 
                Throw $errorMsg;
                break;
            }
        }
    }

    return $result;
}

function ConvertTo-SecondsFromIcingaThresholds()
{
    param(
        [string]$Threshold
    );

    [array]$Content    = $Threshold.Split(':');
    [array]$NewContent = @();

    foreach ($entry in $Content) {
        $NewContent += (Get-IcingaThresholdsAsSeconds -Value $entry)
    }

    return [string]::Join(':', $NewContent);
}

function Get-IcingaThresholdsAsSeconds()
{
    param(
        [string]$Value
    );

    if ($Value.Contains('~')) {
        $Value = $Value.Replace('~', '');
        return [string]::Format('~{0}', (ConvertTo-Seconds $Value));
    } elseif ($Value.Contains('@')) {
        $Value = $Value.Replace('@', '');
        return [string]::Format('@{0}', (ConvertTo-Seconds $Value));
    }

    return (ConvertTo-Seconds $Value);
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-framework\lib\icinga\enums\Icinga_IcingaEnums.psm1
<#
 # This script will provide 'Enums' we can use within our module to
 # easier access constants and to maintain a better overview of the
 # entire components
 #>

[hashtable]$IcingaExitCode = @{
    Ok        = 0;
    Warning   = 1;
    Critical  = 2;
    Unknown   = 3;
};

[hashtable]$IcingaExitCodeText = @{
    0 = '[OK]';
    1 = '[WARNING]';
    2 = '[CRITICAL]';
    3 = '[UNKNOWN]';
};

[hashtable]$IcingaMeasurementUnits = @{
    's'  = 'seconds';
    'ms' = 'milliseconds';
    'us' = 'microseconds';
    '%'  = 'percent';
    'B'  = 'bytes';
    'KB' = 'Kilobytes';
    'MB' = 'Megabytes';
    'GB' = 'Gigabytes';
    'TB' = 'Terabytes';
    'c'  = 'counter';
};

<#
 # Once we defined a new enum hashtable above, simply add it to this list
 # to make it available within the entire module.
 #
 # Example usage:
 # $IcingaEnums.IcingaExitCode.Ok
 #>
[hashtable]$IcingaEnums = @{
    IcingaExitCode         = $IcingaExitCode;
    IcingaExitCodeText     = $IcingaExitCodeText;
    IcingaMeasurementUnits = $IcingaMeasurementUnits;
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-framework\lib\icinga\plugin\New-IcingaCheck.psm1
function New-IcingaCheck()
{
    param(
        [string]$Name       = '',
        $Value              = $null,
        $Unit               = $null,
        [string]$Minimum    = '',
        [string]$Maximum    = '',
        $ObjectExists       = -1,
        $Translation        = $null,
        [switch]$NoPerfData
    );

    $Check = New-Object -TypeName PSObject;
    $Check | Add-Member -membertype NoteProperty -name 'name'           -value $Name;
    $Check | Add-Member -membertype NoteProperty -name 'verbose'        -value 0;
    $Check | Add-Member -membertype NoteProperty -name 'messages'       -value @();
    $Check | Add-Member -membertype NoteProperty -name 'oks'            -value @();
    $Check | Add-Member -membertype NoteProperty -name 'warnings'       -value @();
    $Check | Add-Member -membertype NoteProperty -name 'criticals'      -value @();
    $Check | Add-Member -membertype NoteProperty -name 'unknowns'       -value @();
    $Check | Add-Member -membertype NoteProperty -name 'okchecks'       -value @();
    $Check | Add-Member -membertype NoteProperty -name 'warningchecks'  -value @();
    $Check | Add-Member -membertype NoteProperty -name 'criticalchecks' -value @();
    $Check | Add-Member -membertype NoteProperty -name 'unknownchecks'  -value @();
    $Check | Add-Member -membertype NoteProperty -name 'value'          -value $Value;
    $Check | Add-Member -membertype NoteProperty -name 'exitcode'       -value -1;
    $Check | Add-Member -membertype NoteProperty -name 'unit'           -value $Unit;
    $Check | Add-Member -membertype NoteProperty -name 'spacing'        -value 0;
    $Check | Add-Member -membertype NoteProperty -name 'compiled'       -value $FALSE;
    $Check | Add-Member -membertype NoteProperty -name 'perfdata'       -value (-Not $NoPerfData);
    $Check | Add-Member -membertype NoteProperty -name 'warning'        -value '';
    $Check | Add-Member -membertype NoteProperty -name 'critical'       -value '';
    $Check | Add-Member -membertype NoteProperty -name 'minimum'        -value $Minimum;
    $Check | Add-Member -membertype NoteProperty -name 'maximum'        -value $Maximum;
    $Check | Add-Member -membertype NoteProperty -name 'objectexists'   -value $ObjectExists;
    $Check | Add-Member -membertype NoteProperty -name 'translation'    -value $Translation;
    $Check | Add-Member -membertype NoteProperty -name 'checks'         -value $null;
    $Check | Add-Member -membertype NoteProperty -name 'completed'      -value $FALSE;
    $Check | Add-Member -membertype NoteProperty -name 'checkcommand'   -value '';
    $Check | Add-Member -membertype NoteProperty -name 'checkpackage'   -value $FALSE;

    $Check | Add-Member -membertype ScriptMethod -name 'HandleDaemon' -value {
        # Only apply this once the checkcommand is set
        if ([string]::IsNullOrEmpty($this.checkcommand) -Or $global:IcingaDaemonData.FrameworkRunningAsDaemon -eq $FALSE) {
            return;
        }

        if ($global:IcingaDaemonData.ContainsKey('BackgroundDaemon') -eq $FALSE) {
            return;
        }

        if ($global:IcingaDaemonData.BackgroundDaemon.ContainsKey('ServiceCheckScheduler') -eq $FALSE) {
            return;
        }

        if ($global:IcingaDaemonData.BackgroundDaemon.ServiceCheckScheduler.ContainsKey($this.checkcommand)) {
            if ($global:IcingaDaemonData.BackgroundDaemon.ServiceCheckScheduler[$this.checkcommand]['results'].ContainsKey($this.name) -eq $FALSE) {
                $global:IcingaDaemonData.BackgroundDaemon.ServiceCheckScheduler[$this.checkcommand]['results'].Add(
                    $this.name,
                    [hashtable]::Synchronized(@{})
                );
            }
            $global:IcingaDaemonData.BackgroundDaemon.ServiceCheckScheduler[$this.checkcommand]['results'][$this.name].Add(
                (Get-IcingaUnixTime),
                $this.value
            );
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AddSpacing' -value {
        $this.spacing += 1;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AssignCheckCommand' -value {
        param($CheckCommand);

        $this.checkcommand = $CheckCommand;
        $this.HandleDaemon();
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetWarnings' -value {
        return $this.warningchecks;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetCriticals' -value {
        return $this.criticalchecks;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetUnknowns' -value {
        return $this.unknownchecks;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnOutOfRange' -value {
        param($warning);

        if ([string]::IsNullOrEmpty($warning)) {
            return $this;
        }

        if ((Test-Numeric $warning)) {
            $this.WarnIfGreaterThan($warning).WarnIfLowerThan(0) | Out-Null;
        } else {
            [array]$thresholds = $warning.Split(':');
            [string]$rangeMin = $thresholds[0];
            [string]$rangeMax = $thresholds[1];
            $negate = $rangeMin.Contains('@');
            $rangeMin = $rangeMin.Replace('@', '');
            if (-Not $negate -And (Test-Numeric $rangeMin) -And (Test-Numeric $rangeMax)) {
                $this.WarnIfLowerThan($rangeMin).WarnIfGreaterThan($rangeMax) | Out-Null;
            } elseif ((Test-Numeric $rangeMin) -And [string]::IsNullOrEmpty($rangeMax) -eq $TRUE) {
                $this.WarnIfLowerThan($rangeMin) | Out-Null;
            } elseif ($rangeMin -eq '~' -And (Test-Numeric $rangeMax)) {
                $this.WarnIfGreaterThan($rangeMax) | Out-Null;
            } elseif ($negate -And (Test-Numeric $rangeMin) -And (Test-Numeric $rangeMax)) {
                $this.WarnIfBetweenAndEqual($rangeMin, $rangeMax) | Out-Null;
            } else {
                $this.AddMessage(
                    [string]::Format(
                        'Invalid range specified for Warning argument: "{0}" of check {1}',
                        $warning,
                        $this.name
                    ),
                    $IcingaEnums.IcingaExitCode.Unknown
                )
                $this.exitcode = $IcingaEnums.IcingaExitCode.Unknown;
                return $this;
            }
        }

        $this.warning = $warning;

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfLike' -value {
        param($warning);

        if ($this.value -Like $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'like'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfNotLike' -value {
        param($warning);

        if (-Not ($this.value -Like $warning)) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'not like'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfMatch' -value {
        param($warning);

        if ($this.value -eq $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'matching'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfNotMatch' -value {
        param($warning);

        if ($this.value -ne $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'not matching'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfBetweenAndEqual' -value {
        param($min, $max);

        if ($this.value -ge $min -And $this.value -le $max) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                [string]::Format('{0}:{1}', $min, $max),
                'between'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfBetween' -value {
        param($min, $max);

        if ($this.value -gt $min -And $this.value -lt $max) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                [string]::Format('{0}:{1}', $min, $max),
                'between'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfLowerThan' -value {
        param($warning);

        if ($this.value -lt $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'lower than'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfLowerEqualThan' -value {
        param($warning);

        if ($this.value -le $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'lower or equal than'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfGreaterThan' -value {
        param($warning);

        if ($this.value -gt $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'greater than'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WarnIfGreaterEqualThan' -value {
        param($warning);

        if ($this.value -ge $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'greater or equal than'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritOutOfRange' -value {
        param($critical);

        if ([string]::IsNullOrEmpty($critical)) {
            return $this;
        }

        if ((Test-Numeric $critical)) {
            $this.CritIfGreaterThan($critical).CritIfLowerThan(0) | Out-Null;
        } else {
            [array]$thresholds = $critical.Split(':');
            [string]$rangeMin = $thresholds[0];
            [string]$rangeMax = $thresholds[1];
            $negate = $rangeMin.Contains('@');
            $rangeMin = $rangeMin.Replace('@', '');
            if (-Not $negate -And (Test-Numeric $rangeMin) -And (Test-Numeric $rangeMax)) {
                $this.CritIfLowerThan($rangeMin).CritIfGreaterThan($rangeMax) | Out-Null;
            } elseif ((Test-Numeric $rangeMin) -And [string]::IsNullOrEmpty($rangeMax) -eq $TRUE) {
                $this.CritIfLowerThan($rangeMin) | Out-Null;
            } elseif ($rangeMin -eq '~' -And (Test-Numeric $rangeMax)) {
                $this.CritIfGreaterThan($rangeMax) | Out-Null;
            } elseif ($negate -And (Test-Numeric $rangeMin) -And (Test-Numeric $rangeMax)) {
                $this.CritIfBetweenAndEqual($rangeMin, $rangeMax) | Out-Null;
            } else {
                $this.AddMessage(
                    [string]::Format(
                        'Invalid range specified for Critical argument: "{0}" of check {1}',
                        $critical,
                        $this.name
                    ),
                    $IcingaEnums.IcingaExitCode.Unknown
                )
                $this.exitcode = $IcingaEnums.IcingaExitCode.Unknown;
                return $this;
            }
        }

        $this.critical = $critical;

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfLike' -value {
        param($critical);

        if ($this.value -Like $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'like'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfNotLike' -value {
        param($critical);

        if (-Not ($this.value -Like $critical)) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'not like'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfMatch' -value {
        param($critical);

        if ($this.value -eq $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'matching'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfNotMatch' -value {
        param($critical);

        if ($this.value -ne $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'not matching'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfBetweenAndEqual' -value {
        param($min, $max);

        if ($this.value -ge $min -And $this.value -le $max) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                [string]::Format('{0}:{1}', $min, $max),
                'between'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfBetween' -value {
        param($min, $max);

        if ($this.value -gt $min -And $this.value -lt $max) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                [string]::Format('{0}:{1}', $min, $max),
                'between'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfLowerThan' -value {
        param($critical);

        if ($this.value -lt $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'lower than'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfLowerEqualThan' -value {
        param($critical);

        if ($this.value -le $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'lower or equal than'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfGreaterThan' -value {
        param($critical);

        if ($this.value -gt $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'greater than'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CritIfGreaterEqualThan' -value {
        param($critical);

        if ($this.value -ge $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'greater or equal than'
            );
        }

        return $this;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'TranslateValue' -value {
        param($value);

        $value = Format-IcingaPerfDataValue $value;

        if ($null -eq $this.translation -Or $null -eq $value) {
            return $value;
        }

        $checkValue = $value;

        if ((Test-Numeric $checkValue)) {
            $checkValue = [int]$checkValue;
        } else {
            $checkValue = [string]$checkValue;
        }

        if ($this.translation.ContainsKey($checkValue)) {
            return $this.translation[$checkValue];
        }

        return $value;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AddInternalCheckMessage' -value {
        param($state, $value, $type);

        if ($this.objectexists -ne -1 -And $null -eq $this.objectexists) {
            $this.SetExitCode($IcingaEnums.IcingaExitCode.Unknown);
            $this.AddMessage([string]::Format(
                '{0} does not exist', $this.name
            ), $IcingaEnums.IcingaExitCode.Unknown);
            return;
        }

        $this.SetExitCode($state);
        $this.AddMessage(
            [string]::Format(
                '{0}: Value "{1}{4}" is {2} threshold "{3}{4}"',
                $this.name,
                $this.TranslateValue($this.value),
                $type,
                $this.TranslateValue($value),
                $this.unit
            ),
            $state
        );

        switch ($state) {
            $IcingaEnums.IcingaExitCode.Warning {
                $this.warning = $value;
                break;
            };
            $IcingaEnums.IcingaExitCode.Critical {
                $this.critical = $value;
                break;
            };
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AddMessage' -value {
        param($message, [int]$exitcode);

        [string]$outputMessage = [string]::Format(
            '{0} {1}',
            $IcingaEnums.IcingaExitCodeText[$exitcode],
            $message
        );
        $this.messages += $outputMessage;

        switch ([int]$exitcode) {
            $IcingaEnums.IcingaExitCode.Ok {
                $this.oks += $outputMessage;
                break;
            };
            $IcingaEnums.IcingaExitCode.Warning {
                $this.warnings += $outputMessage;
                break;
            };
            $IcingaEnums.IcingaExitCode.Critical {
                $this.criticals += $outputMessage;
                break;
            };
            $IcingaEnums.IcingaExitCode.Unknown {
                $this.unknowns += $outputMessage;
                break;
            };
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AddCheckStateArrays' -value {
        switch ([int]$this.exitcode) {
            $IcingaEnums.IcingaExitCode.Ok {
                $this.okchecks += $this.name;
                break;
            };
            $IcingaEnums.IcingaExitCode.Warning {
                $this.warningchecks += $this.name;
                break;
            };
            $IcingaEnums.IcingaExitCode.Critical {
                $this.criticalchecks += $this.name;
                break;
            };
            $IcingaEnums.IcingaExitCode.Unknown {
                $this.unknownchecks += $this.name;
                break;
            };
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintOkMessages' -value {
        param([string]$spaces);
        $this.OutputMessageArray($this.oks, $spaces);
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintWarningMessages' -value {
        param([string]$spaces);
        $this.OutputMessageArray($this.warnings, $spaces);
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintCriticalMessages' -value {
        param([string]$spaces);
        $this.OutputMessageArray($this.criticals, $spaces);
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintUnknownMessages' -value {
        param([string]$spaces);
        $this.OutputMessageArray($this.unknowns, $spaces);
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintAllMessages' -value {
        [string]$spaces = New-StringTree $this.spacing;
        $this.OutputMessageArray($this.unknowns, $spaces);
        $this.OutputMessageArray($this.criticals, $spaces);
        $this.OutputMessageArray($this.warnings, $spaces);
        $this.OutputMessageArray($this.oks, $spaces);
    }

    $Check | Add-Member -membertype ScriptMethod -name 'OutputMessageArray' -value {
        param($msgArray, [string]$spaces);

        foreach ($msg in $msgArray) {
            Write-IcingaPluginOutput ([string]::Format('{0}{1}', $spaces, $msg));
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintOutputMessages' -value {
        [string]$spaces = New-StringTree $this.spacing;
        if ($this.unknowns.Count -ne 0) {
            $this.PrintUnknownMessages($spaces);
        } elseif ($this.criticals.Count -ne 0) {
            $this.PrintCriticalMessages($spaces);
        } elseif ($this.warnings.Count -ne 0) {
            $this.PrintWarningMessages($spaces);
        } else {
            if ($this.oks.Count -ne 0) {
                $this.PrintOkMessages($spaces);
            }
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'SetExitCode' -value {
        param([int]$code);

        # Only overwrite the exit code in case our new value is greater then
        # the current one Ok > Warning > Critical
        if ([int]$this.exitcode -gt $code) {
            return $this;
        }

        switch ($code) {
            0 { break; };
            1 {
                $this.oks = @();
                break;
            };
            2 {
                $this.oks = @();
                $this.warnings = @();
                break;
            };
            3 {
                $this.oks = @();
                $this.warnings = @();
                $this.criticals = @();
                break;
            };
        }

        $this.exitcode = $code;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'ValidateUnit' -value {
        if ($null -ne $this.unit -And (-Not $IcingaEnums.IcingaMeasurementUnits.ContainsKey($this.unit))) {
            $this.AddMessage(
                    [string]::Format(
                        'Error on check "{0}": Usage of invalid plugin unit "{1}". Allowed units are: {2}',
                        $this.name,
                        $this.unit,
                        (($IcingaEnums.IcingaMeasurementUnits.Keys | Sort-Object name)  -Join ', ')
                    ),
                    $IcingaEnums.IcingaExitCode.Unknown
            )
            $this.unit = '';
            $this.exitcode = $IcingaEnums.IcingaExitCode.Unknown;
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AddOkOutput' -value {
        if ([int]$this.exitcode -eq -1) {
            $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
            $this.AddMessage(
                [string]::Format(
                    '{0}: {1}{2}',
                    $this.name,
                    $this.TranslateValue($this.value),
                    $this.unit
                ),
                $IcingaEnums.IcingaExitCode.Ok
            );
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'SilentCompile' -value {
        if ($this.compiled) {
            return;
        }

        $this.AddOkOutput();
        $this.compiled = $TRUE;
        $this.AddCheckStateArrays();
    }

    $Check | Add-Member -membertype ScriptMethod -name 'Compile' -value {
        param([bool]$Verbose = $FALSE);

        if ($this.compiled) {
            return;
        }

        $this.AddOkOutput();
        $this.compiled = $TRUE;

        if ($Verbose) {
            $this.PrintOutputMessages();
        }

        $this.AddCheckStateArrays();

        return $this.exitcode;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetPerfData' -value {

        if ($this.completed -Or -Not $this.perfdata) {
            return $null;
        }

        $this.AutodiscoverMinMax();

        $this.completed    = $TRUE;
        [string]$LabelName = (Format-IcingaPerfDataLabel $this.name);

        $perfdata = @{
            'label'    = $LabelName;
            'perfdata' = '';
            'unit'     = $this.unit;
            'value'    = (Format-IcingaPerfDataValue $this.value);
            'warning'  = (Format-IcingaPerfDataValue $this.warning);
            'critical' = (Format-IcingaPerfDataValue $this.critical);
            'minimum'  = (Format-IcingaPerfDataValue $this.minimum);
            'maximum'  = (Format-IcingaPerfDataValue $this.maximum);
            'package'  = $FALSE;
        };

        return $perfdata;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AutodiscoverMinMax' -value {
        if ([string]::IsNullOrEmpty($this.minimum) -eq $FALSE -Or [string]::IsNullOrEmpty($this.maximum) -eq $FALSE) {
            return;
        }

        switch ($this.unit) {
            '%' {
                $this.minimum = '0';
                $this.maximum = '100';
                if ($this.value -gt $this.maximum) {
                    $this.maximum = $this.value
                }
                break;
            }
        }
    }

    $Check.ValidateUnit();
    $Check.HandleDaemon();

    return $Check;
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-framework\lib\icinga\plugin\New-IcingaCheckPackage.psm1
function New-IcingaCheckPackage()
{
    param(
        [string]$Name,
        [switch]$OperatorAnd,
        [switch]$OperatorOr,
        [switch]$OperatorNone,
        [int]$OperatorMin      = -1,
        [int]$OperatorMax      = -1,
        [array]$Checks         = @(),
        [int]$Verbose          = 0,
        [switch]$Hidden        = $FALSE
    );

    $Check = New-Object -TypeName PSObject;
    $Check | Add-Member -membertype NoteProperty -name 'name'           -value $Name;
    $Check | Add-Member -membertype NoteProperty -name 'exitcode'       -value -1;
    $Check | Add-Member -membertype NoteProperty -name 'verbose'        -value $Verbose;
    $Check | Add-Member -membertype NoteProperty -name 'hidden'         -value $Hidden;
    $Check | Add-Member -membertype NoteProperty -name 'checks'         -value $Checks;
    $Check | Add-Member -membertype NoteProperty -name 'opand'          -value $OperatorAnd;
    $Check | Add-Member -membertype NoteProperty -name 'opor'           -value $OperatorOr;
    $Check | Add-Member -membertype NoteProperty -name 'opnone'         -value $OperatorNone;
    $Check | Add-Member -membertype NoteProperty -name 'opmin'          -value $OperatorMin;
    $Check | Add-Member -membertype NoteProperty -name 'opmax'          -value $OperatorMax;
    $Check | Add-Member -membertype NoteProperty -name 'spacing'        -value 0;
    $Check | Add-Member -membertype NoteProperty -name 'compiled'       -value $FALSE;
    $Check | Add-Member -membertype NoteProperty -name 'perfdata'       -value $FALSE;
    $Check | Add-Member -membertype NoteProperty -name 'checkcommand'   -value '';
    $Check | Add-Member -membertype NoteProperty -name 'headermsg'      -value '';
    $Check | Add-Member -membertype NoteProperty -name 'checkpackage'   -value $TRUE;
    $Check | Add-Member -membertype NoteProperty -name 'warningchecks'  -value @();
    $Check | Add-Member -membertype NoteProperty -name 'criticalchecks' -value @();
    $Check | Add-Member -membertype NoteProperty -name 'unknownchecks'  -value @();

    $Check | Add-Member -membertype ScriptMethod -name 'HasChecks' -value {
        if ($this.checks -ne 0) {
            return $TRUE
        }

        return $FALSE;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'Initialise' -value {
        foreach ($check in $this.checks) {
            $this.InitCheck($check);
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'InitCheck' -value {
        param($check);

        if ($null -eq $check) {
            return;
        }

        $check.verbose = $this.verbose;
        $check.AddSpacing();
        $check.SilentCompile();
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AddSpacing' -value {
        $this.spacing += 1;
        foreach ($check in $this.checks) {
            $check.spacing = $this.spacing;
            $check.AddSpacing();
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AddCheck' -value {
        param($check);

        if ($null -eq $check) {
            return;
        }

        $this.InitCheck($check);
        $this.checks += $check;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetWarnings' -value {
        foreach ($check in $this.checks) {
            $this.warningchecks += $check.GetWarnings();
        }

        return $this.warningchecks;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetCriticals' -value {
        foreach ($check in $this.checks) {
            $this.criticalchecks += $check.GetCriticals();
        }

        return $this.criticalchecks;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetUnknowns' -value {
        foreach ($check in $this.checks) {
            $this.unknownchecks += $check.GetUnknowns();
        }

        return $this.unknownchecks;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AssignCheckCommand' -value {
        param($CheckCommand);

        $this.checkcommand = $CheckCommand;

        foreach ($check in $this.checks) {
            $check.AssignCheckCommand($CheckCommand);
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'Compile' -value {
        param([bool]$Verbose);

        if ($this.compiled) {
            return;
        }

        $this.compiled = $TRUE;

        if ($this.checks.Count -ne 0) {
            if ($this.opand) {
                if ($this.CheckAllOk() -eq $FALSE) {
                    $this.GetWorstExitCode();
                }
            } elseif($this.opor) {
                if ($this.CheckOneOk() -eq $FALSE) {
                    $this.GetWorstExitCode();
                }
            } elseif($this.opnone) {
                if ($this.CheckOneOk() -eq $TRUE) {
                    $this.GetWorstExitCode();
                    $this.exitcode = $IcingaEnums.IcingaExitCode.Critical;
                } else {
                    $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
                }
            } elseif([int]$this.opmin -ne -1) {
                if ($this.CheckMinimumOk() -eq $FALSE) {
                    $this.GetWorstExitCode();
                } else {
                    $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
                }
            } elseif([int]$this.opmax -ne -1) {
                if ($this.CheckMaximumOk() -eq $FALSE) {
                    $this.GetWorstExitCode();
                } else {
                    $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
                }
            }
        } else {
            $this.exitcode = $IcingaEnums.IcingaExitCode.Unknown;
        }

        if ([int]$this.exitcode -eq -1) {
            $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
        }

        if ($Verbose -eq $TRUE) {
            $this.PrintOutputMessages();
        }

        return $this.exitcode;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'SilentCompile' -value {
        $this.Compile($FALSE) | Out-Null;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetOkCount' -value {
        [int]$okCount = 0;
        foreach ($check in $this.checks) {
            if ([int]$check.exitcode -eq [int]$IcingaEnums.IcingaExitCode.Ok) {
                $okCount += 1;
            }
        }

        return $okCount;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CheckMinimumOk' -value {
        if ($this.opmin -gt $this.checks.Count) {
            Write-IcingaPluginOutput ([string]::Format(
                'Unknown: The minimum argument ({0}) is exceeding the amount of assigned checks ({1}) to this package "{2}"',
                $this.opmin, $this.checks.Count, $this.name
            ));
            $this.exitcode = $IcingaEnums.IcingaExitCode.Unknown;
            return $FALSE;
        }

        [int]$okCount = $this.GetOkCount();

        if ($this.opmin -le $okCount) {
            return $TRUE;
        }

        return $FALSE;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CheckMaximumOk' -value {
        if ($this.opmax -gt $this.checks.Count) {
            Write-IcingaPluginOutput ([string]::Format(
                'Unknown: The maximum argument ({0}) is exceeding the amount of assigned checks ({1}) to this package "{2}"',
                $this.opmax, $this.checks.Count, $this.name
            ));
            $this.exitcode = $IcingaEnums.IcingaExitCode.Unknown;
            return $FALSE;
        }

        [int]$okCount = $this.GetOkCount();

        if ($this.opmax -ge $okCount) {
            return $TRUE;
        }

        return $FALSE;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CheckAllOk' -value {
        foreach ($check in $this.checks) {
            if ([int]$check.exitcode -ne [int]$IcingaEnums.IcingaExitCode.Ok) {
                return $FALSE;
            }
        }

        return $TRUE;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'CheckOneOk' -value {
        foreach ($check in $this.checks) {
            if ([int]$check.exitcode -eq [int]$IcingaEnums.IcingaExitCode.Ok) {
                $this.exitcode = $check.exitcode;
                return $TRUE;
            }
        }

        return $FALSE;
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetPackageConfigMessage' -value {
        if ($this.opand) {
            return 'Match All';
        } elseif ($this.opor) {
            return 'Match Any';
        } elseif ($this.opnone) {
            return 'Match None';
        } elseif ([int]$this.opmin -ne -1) {
            return [string]::Format('Minimum {0}', $this.opmin)
        } elseif ([int]$this.opmax -ne -1) {
            return [string]::Format('Maximum {0}', $this.opmax)
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintOutputMessageSorted' -value {
        param($skipHidden, $skipExitCode);

        if ($this.hidden -And $skipHidden) {
            return;
        }

        [hashtable]$MessageOrdering = @{};
        foreach ($check in $this.checks) {
            if ([int]$check.exitcode -eq $skipExitCode -And $skipExitCode -ne -1) {
                continue;
            }

            if ($MessageOrdering.ContainsKey($check.Name) -eq $FALSE) {
                $MessageOrdering.Add($check.name, $check);
            } else {
                [int]$DuplicateKeyIndex = 1;
                while ($TRUE) {
                    $newCheckName = [string]::Format('{0}[{1}]', $check.Name, $DuplicateKeyIndex);
                    if ($MessageOrdering.ContainsKey($newCheckName) -eq $FALSE) {
                        $MessageOrdering.Add($newCheckName, $check);
                        break;
                    }
                    $DuplicateKeyIndex += 1;
                }
            }
        }

        $SortedArray = $MessageOrdering.GetEnumerator() | Sort-Object name;

        foreach ($entry in $SortedArray) {
            $entry.Value.PrintAllMessages();
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WriteAllOutput' -value {
        $this.PrintOutputMessageSorted($TRUE, -1);
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintAllMessages' -value {
        $this.WritePackageOutputStatus();
        $this.WriteAllOutput();
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WriteCheckErrors' -value {
        $this.PrintOutputMessageSorted($FALSE, $IcingaEnums.IcingaExitCode.Ok);
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintNoChecksConfigured' -value {
        if ($this.checks.Count -eq 0) {
            Write-IcingaPluginOutput (
                [string]::Format(
                    '{0}{1} No checks configured for package "{2}"',
                    (New-StringTree ($this.spacing + 1)),
                    $IcingaEnums.IcingaExitCodeText.($this.exitcode),
                    $this.name
                )
            )
            return;
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'WritePackageOutputStatus' -value {
        if ($this.hidden) {
            return;
        }

        [string]$outputMessage = '{0}{1} Check package "{2}"';
        if ($this.verbose -ne 0) {
            $outputMessage += ' ({3})';
        }

        if ($this.exitcode -ne 0 -And $this.spacing -eq 0) {
            $outputMessage += ' - {4}';
        }

        Write-IcingaPluginOutput (
            [string]::Format(
                $outputMessage,
                (New-StringTree $this.spacing),
                $IcingaEnums.IcingaExitCodeText.($this.exitcode),
                $this.name,
                $this.GetPackageConfigMessage(),
                $this.headermsg
            )
        );
    }

    $Check | Add-Member -membertype ScriptMethod -name 'PrintOutputMessages' -value {
        [bool]$printAll = $FALSE;

        switch ($this.verbose) {
            0 { 
                # Default value. Only print a package but not the services include
                break; 
            };
            1 { 
                # Include the Operator into the check package result
                break;
            };
            Default {
                $printAll = $TRUE;
                break;
            }
        }

        $this.WritePackageOutputStatus();

        if ($printAll) {
            $this.WriteAllOutput();
            $this.PrintNoChecksConfigured();
        } else {
            if ([int]$this.exitcode -ne $IcingaEnums.IcingaExitCode.Ok) {
                $this.WriteCheckErrors();
                $this.PrintNoChecksConfigured();
            }
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'AddUniqueSortedChecksToHeader' -value {
        param($checkarray, $state);

        [hashtable]$CheckHash = @{};

        foreach ($entry in $checkarray) {
            if ($CheckHash.ContainsKey($entry) -eq $FALSE) {
                $CheckHash.Add($entry, $TRUE);
            }
        }

        [array]$SortedCheckArray = $CheckHash.GetEnumerator() | Sort-Object name;

        if ($SortedCheckArray.Count -ne 0) {
            $this.headermsg += [string]::Format(
                '{0} {1} ',
                $IcingaEnums.IcingaExitCodeText[$state],
                [string]::Join(', ', $SortedCheckArray.Key)
            );           
        }
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetWorstExitCode' -value {
        if ([int]$this.exitcode -eq [int]$IcingaEnums.IcingaExitCode.Unknown) {
            return;
        }

        foreach ($check in $this.checks) {
            if ([int]$this.exitcode -lt $check.exitcode) {
                $this.exitcode = $check.exitcode;
            }

            $this.criticalchecks += $check.GetCriticals();
            $this.warningchecks  += $check.GetWarnings();
            $this.unknownchecks  += $check.GetUnknowns();
        }

        # Only apply this to our top package
        if ($this.spacing -ne 0) {
            return;
        }

        $this.AddUniqueSortedChecksToHeader(
            $this.criticalchecks, $IcingaEnums.IcingaExitCode.Critical
        );
        $this.AddUniqueSortedChecksToHeader(
            $this.warningchecks, $IcingaEnums.IcingaExitCode.Warning
        );
        $this.AddUniqueSortedChecksToHeader(
            $this.unknownchecks, $IcingaEnums.IcingaExitCode.Unknown
        );
    }

    $Check | Add-Member -membertype ScriptMethod -name 'GetPerfData' -value {
        [string]$perfData             = '';
        [hashtable]$CollectedPerfData = @{};

        # At first lets collect all perf data, but ensure we only add possible label duplication only once
        foreach ($check in $this.checks) {
            $data = $check.GetPerfData();

            if ($null -eq $data -Or $null -eq $data.label) {
                continue;
            }

            if ($CollectedPerfData.ContainsKey($data.label)) {
                continue;
            }

            $CollectedPerfData.Add($data.label, $data);
        }

        # Now sort the label output by name
        $SortedArray = $CollectedPerfData.GetEnumerator() | Sort-Object name;

        # Buold the performance data output based on the sorted result
        foreach ($entry in $SortedArray) {
            $perfData += $entry.Value;
        }

        return @{
            'label'    = $this.name;
            'perfdata' = $CollectedPerfData;
            'package'  = $TRUE;
        }
    }

    $Check.Initialise();

    return $Check;
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-framework\lib\icinga\plugin\New-IcingaCheckResult.psm1
function New-IcingaCheckresult()
{
    param(
        $Check,
        [bool]$NoPerfData,
        [switch]$Compile
    );

    $CheckResult = New-Object -TypeName PSObject;
    $CheckResult | Add-Member -membertype NoteProperty -name 'check'      -value $Check;
    $CheckResult | Add-Member -membertype NoteProperty -name 'noperfdata' -value $NoPerfData;

    $CheckResult | Add-Member -membertype ScriptMethod -name 'Compile' -value {
        if ($null -eq $this.check) {
            return $IcingaEnums.IcingaExitCode.Unknown;
        }

        $CheckCommand = (Get-PSCallStack)[2].Command;

        # Compile the check / package if not already done
        $this.check.AssignCheckCommand($CheckCommand);
        $this.check.Compile($TRUE) | Out-Null;

        if ([int]$this.check.exitcode -ne [int]$IcingaEnums.IcingaExitCode.Unknown -And -Not $this.noperfdata) {
            Write-IcingaPluginPerfData -PerformanceData ($this.check.GetPerfData()) -CheckCommand $CheckCommand;
        }

        return $this.check.exitcode;
    }

    if ($Compile) {
        return $CheckResult.Compile();
    }

    return $CheckResult;
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-framework\lib\icinga\plugin\Write-IcingaPluginOutput.psm1
function Write-IcingaPluginOutput()
{
    param(
        $Output
    );

    if ($global:IcingaDaemonData.FrameworkRunningAsDaemon -eq $FALSE) {
        Write-Host $Output;
    } else {
        if ($global:IcingaDaemonData.IcingaThreadContent.ContainsKey('Scheduler')) {
            $global:IcingaDaemonData.IcingaThreadContent['Scheduler']['PluginCache'] += $Output;
        }
    }
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-plugins\provider\certificate\Icinga_ProviderCertificate.psm1
function Get-IcingaCertificateData()
{
   param(
      #CertStore-Related Param
      [ValidateSet('*', 'LocalMachine', 'CurrentUser', $null)]
      [string]$CertStore     = $null,
      [array]$CertThumbprint = $null,
      [array]$CertSubject    = $null,
      $CertStorePath         = '*',
      #Local Certs
      [array]$CertPaths      = $null,
      [array]$CertName       = $null
   );


   if ([string]::IsNullOrEmpty($CertStore) -eq $FALSE){
      $CertData = Get-IcingaCertStoreCertificates -CertStore $CertStore -CertThumbprint $CertThumbprint -CertSubject $CertSubject -CertStorePath $CertStorePath;
   } else {
      [hashtable]$CertData = @{};
   }

   if (($null -ne $CertPaths) -or ($null -ne $CertName)) {
      $CertDataFile = Get-IcingaDirectoryRecurse -Path $CertPaths -FileNames $CertName;
   }

  if ($null -ne $CertDataFile) {
     foreach ($Cert in $CertDataFile) {
        $CertConverted = New-Object Security.Cryptography.X509Certificates.X509Certificate2 $Cert.FullName;
        $CertData = Add-IcingaCertificateToHashtable -Certificate $CertConverted -CertCache $CertData;
     }
  }

   return $CertData;
}

function Get-IcingaCertStoreCertificates()
{
   param(
      #CertStore-Related Param
      [ValidateSet('*', 'LocalMachine', 'CurrentUser')]
      [string]$CertStore = '*',
      [array]$CertThumbprint = @(),
      [array]$CertSubject    = @(),
      $CertStorePath         = '*'
   );

   $CertStoreArray = @{};
   $CertStorePath  = [string]::Format('Cert:\{0}\{1}', $CertStore, $CertStorePath);
   $CertStoreCerts = Get-ChildItem -Path $CertStorePath -Recurse;

   if ($CertSubject.Count -eq 0 -And $CertThumbprint.Count -eq 0) {
      foreach ($Cert in $CertStoreCerts) {
         $CertStoreArray = Add-IcingaCertificateToHashtable -Certificate $Cert -CertCache $CertStoreArray;
      }
      return $CertStoreCerts;
   }

   foreach ($Cert in $CertStoreCerts) {
      foreach ($Subject in $CertSubject) {
	     if (($Cert.Subject -Like $Subject) -Or $Subject -eq '*') {
            $CertStoreArray = Add-IcingaCertificateToHashtable -Certificate $Cert -CertCache $CertStoreArray;
         }
      }
      if (($CertThumbprint -Contains $Cert.Thumbprint) -Or ($CertThumbprint -Contains '*')) {
         $CertStoreArray = Add-IcingaCertificateToHashtable -Certificate $Cert -CertCache $CertStoreArray;
      }
   }

   return $CertStoreArray;
}

function Add-IcingaCertificateToHashtable()
{
   param(
      $Certificate,
      [hashtable]$CertCache = @{}
   );

   if ($null -eq $CertCache -or $null -eq $Certificate) {
      return $CertCache;
   }

   if ($CertCache.ContainsKey($Certificate.Subject)) {
      if ($CertCache[$Certificate.Subject].ContainsKey($Certificate.Thumbprint) -eq $FALSE) {
         $CertCache[$Certificate.Subject].Add(
            $Certificate.Thumbprint,
            $Certificate
         );
      }
   } else {
      $CertCache.Add(
         $Certificate.Subject,
         @{
            $Certificate.Thumbprint = $Certificate
         }
      );
   }

   return $CertCache;
}

# Content from: C:\Program Files\WindowsPowershell\Modules\icinga-powershell-plugins\provider\directory\Icinga_Provider_Directory.psm1
function Get-IcingaDirectoryAll()
{
    param(
        [string]$Path,
        [array]$FileNames,
        [bool]$Recurse,
        [string]$ChangeTimeEqual,
        [string]$ChangeYoungerThan,
        [string]$ChangeOlderThan,
        [string]$CreationTimeEqual,
        [string]$CreationOlderThan,
        [string]$CreationYoungerThan,
        [string]$FileSizeGreaterThan,
        [string]$FileSizeSmallerThan
    );

    if ($Recurse -eq $TRUE) {
        $DirectoryData = Get-IcingaDirectoryRecurse -Path $Path -FileNames $FileNames;
    } else {
        $DirectoryData = Get-IcingaDirectory -Path $Path -FileNames $FileNames;
    }

    if ([string]::IsNullOrEmpty($ChangeTimeEqual) -eq $FALSE) {
        $DirectoryData = Get-IcingaDirectoryChangeTimeEqual -ChangeTimeEqual $ChangeTimeEqual -DirectoryData $DirectoryData;
    }

    if ([string]::IsNullOrEmpty($CreationTimeEqual) -eq $FALSE) {
        $DirectoryData = Get-IcingaDirectoryCreationTimeEqual -CreationTimeEqual $CreationTimeEqual -DirectoryData $DirectoryData;
    }

    If ([string]::IsNullOrEmpty($ChangeTimeEqual) -eq $TRUE -Or [string]::IsNullOrEmpty($CreationTimeEqual) -eq $TRUE) {
        if ([string]::IsNullOrEmpty($ChangeOlderThan) -eq $FALSE) {
            $DirectoryData = Get-IcingaDirectoryChangeOlderThan -ChangeOlderThan $ChangeOlderThan -DirectoryData $DirectoryData;
        } 
        if ([string]::IsNullOrEmpty($ChangeYoungerThan) -eq $FALSE) {
            $DirectoryData = Get-IcingaDirectoryChangeYoungerThan -ChangeYoungerThan $ChangeYoungerThan -DirectoryData $DirectoryData;
        }
        if ([string]::IsNullOrEmpty($CreationOlderThan) -eq $FALSE) {
            $DirectoryData = Get-IcingaDirectoryCreationOlderThan -CreationOlderThan $CreationOlderThan -DirectoryData $DirectoryData;
        } 
        if ([string]::IsNullOrEmpty($CreationYoungerThan) -eq $FALSE) {
            $DirectoryData = Get-IcingaDirectoryCreationYoungerThan -CreationYoungerThan $CreationYoungerThan -DirectoryData $DirectoryData;
        } 
    }
    if ([string]::IsNullOrEmpty($FileSizeGreaterThan) -eq $FALSE) {
        $DirectoryData = (Get-IcingaDirectorySizeGreaterThan -FileSizeGreaterThan $FileSizeGreaterThan -DirectoryData $DirectoryData);
    }
    if ([string]::IsNullOrEmpty($FileSizeSmallerThan) -eq $FALSE) {
        $DirectoryData = (Get-IcingaDirectorySizeSmallerThan -FileSizeSmallerThan $FileSizeSmallerThan -DirectoryData $DirectoryData);
    }

    return $DirectoryData;
}



# RECURSE

function Get-IcingaDirectory()
{
    param(
        [string]$Path,
        [array]$FileNames
    );

    $DirectoryData = Get-ChildItem -Include $FileNames -Path $Path;

    return $DirectoryData;
}

function Get-IcingaDirectoryRecurse()
{
    param(
        [string]$Path,
        [array]$FileNames
    );

    $DirectoryData = Get-ChildItem -Recurse -Include $FileNames -Path $Path;

    return $DirectoryData;
}

# FILE SIZE

function Get-IcingaDirectorySizeGreaterThan()
{
    param(
        [string]$FileSizeGreaterThan,
        $DirectoryData
    );
    $FileSizeGreaterThanValue = (Convert-Bytes $FileSizeGreaterThan -Unit B).value
    $DirectoryData = ($DirectoryData | Where-Object {$_.Length -gt $FileSizeGreaterThanValue})

    return $DirectoryData;
}

function Get-IcingaDirectorySizeSmallerThan()
{
    param(
        [string]$FileSizeSmallerThan,
        $DirectoryData
    );
    $FileSizeSmallerThanValue = (Convert-Bytes $FileSizeSmallerThan -Unit B).value
    $DirectoryData = ($DirectoryData | Where-Object {$_.Length -gt $FileSizeSmallerThanValue})

    return $DirectoryData;
}

# TIME BASED CHANGE

function Get-IcingaDirectoryChangeOlderThan()
{
    param (
        [string]$ChangeOlderThan,
        $DirectoryData
    )
    $ChangeOlderThan = Set-NumericNegative (ConvertTo-Seconds $ChangeOlderThan);
    $DirectoryData = ($DirectoryData | Where-Object {$_.LastWriteTime -lt (Get-Date).AddSeconds($ChangeOlderThan)})

    return $DirectoryData;
}

function Get-IcingaDirectoryChangeYoungerThan()
{
    param (
        [string]$ChangeYoungerThan,
        $DirectoryData
    )
    $ChangeYoungerThan = Set-NumericNegative (ConvertTo-Seconds $ChangeYoungerThan);
    $DirectoryData = ($DirectoryData | Where-Object {$_.LastWriteTime -gt (Get-Date).AddSeconds($ChangeYoungerThan)})

    return $DirectoryData;
}

function Get-IcingaDirectoryChangeTimeEqual()
{
    param (
        [string]$ChangeTimeEqual,
        $DirectoryData
    )
    $ChangeTimeEqual = Set-NumericNegative (ConvertTo-Seconds $ChangeTimeEqual);
    $ChangeTimeEqual = (Get-Date).AddSeconds($ChangeTimeEqual);
    $DirectoryData = ($DirectoryData | Where-Object {$_.LastWriteTime.Day -eq $ChangeTimeEqual.Day -And $_.LastWriteTime.Month -eq $ChangeTimeEqual.Month -And $_.LastWriteTime.Year -eq $ChangeTimeEqual.Year})

    return $DirectoryData;
}

# TIME BASED CREATION

function Get-IcingaDirectoryCreationYoungerThan()
{
    param (
        [string]$CreationYoungerThan,
        $DirectoryData
    )
    $CreationYoungerThan = Set-NumericNegative (ConvertTo-Seconds $CreationYoungerThan);
    $DirectoryData = ($DirectoryData | Where-Object {$_.CreationTime -gt (Get-Date).AddSeconds($CreationYoungerThan)})

    return $DirectoryData;
}

function Get-IcingaDirectoryCreationOlderThan()
{
    param (
        [string]$CreationOlderThan,
        $DirectoryData
    )
    $CreationOlderThan = Set-NumericNegative (ConvertTo-Seconds $CreationOlderThan);
    $DirectoryData = ($DirectoryData | Where-Object {$_.CreationTime -lt (Get-Date).AddSeconds($CreationOlderThan)})

    return $DirectoryData;
}

function Get-IcingaDirectoryCreationTimeEqual()
{
    param (
        [string]$CreationTimeEqual,
        $DirectoryData
    )
    $CreationTimeEqual = Set-NumericNegative (ConvertTo-Seconds $CreationTimeEqual);
    $CreationTimeEqual = (Get-Date).AddSeconds($CreationTimeEqual);
    $DirectoryData = ($DirectoryData | Where-Object {$_.CreationTime.Day -eq $CreationTimeEqual.Day -And $_.CreationTime.Month -eq $CreationTimeEqual.Month -And $_.CreationTime.Year -eq $CreationTimeEqual.Year})

    return $DirectoryData;
}

# Content from: plugins\Invoke-IcingaCheckCertificate.psm1

   $CertData         = (Get-IcingaCertificateData -CertStore $CertStore -CertThumbprint $CertThumbprint -CertSubject $CertSubject -CertPaths $CertPaths -CertName $CertName -CertStorePath $CertStorePath);
   $CertPackage      = New-IcingaCheckPackage -Name 'Certificates' -OperatorAnd -Verbose $Verbosity;

   if ($null -ne $CriticalStart) {
      try {
         [datetime]$CritDateTime = $CriticalStart
      } catch {
         Write-Host "[UNKNOWN] CriticalStart ${CriticalStart} can not be parsed!"
         return 3
      }
   }

   foreach ($Subject in $CertData.Keys) {
      $Thumbprints = $CertData[$Subject];
      foreach ($cert in $Thumbprints.Keys) {
         $cert = $Thumbprints[$cert];

         $SpanTilAfter = (New-TimeSpan -Start (Get-Date) -End $Cert.NotAfter);
         if ($Cert.Subject.Contains(',')) {
            [string]$CertName = $Cert.Subject.Split(",")[0];
         } else {
            [string]$CertName = $Cert.Subject;
         }

         $CertName = $CertName -ireplace '(cn|ou)=', '';
         $CheckNamePrefix = "Certificate '${CertName}'";

         $checks = @();

         if ($Trusted) {
            $CertValid = Test-Certificate $cert -ErrorAction SilentlyContinue -WarningAction SilentlyContinue;

            $IcingaCheck = New-IcingaCheck -Name "${CheckNamePrefix} trusted" -Value $CertValid;
            $IcingaCheck.CritIfNotMatch($TRUE) | Out-Null;
            $checks += $IcingaCheck;
         }

         if ($null -ne $CriticalStart) {
            $CritStart = ((New-TimeSpan -Start $Cert.NotBefore -End $CritDateTime) -gt 0)
            $IcingaCheck = New-IcingaCheck -Name "${CheckNamePrefix} already valid" -Value $CritStart;
            $IcingaCheck.CritIfNotMatch($TRUE) | Out-Null;
            $checks += $IcingaCheck;
         }

         if(($null -ne $WarningEnd) -Or ($null -ne $CriticalEnd)) {
            $ValidityInfo = ([string]::Format('valid until {0} : {1}d', $Cert.NotAfter.ToString('yyyy-MM-dd'), $SpanTilAfter.Days));

            $IcingaCheck = New-IcingaCheck -Name "${CheckNamePrefix} ($ValidityInfo) valid for" -Value (New-TimeSpan -End $Cert.NotAfter.DateTime).TotalSeconds;
            $IcingaCheck.WarnOutOfRange((ConvertTo-SecondsFromIcingaThresholds -Threshold $WarningEnd)).CritOutOfRange((ConvertTo-SecondsFromIcingaThresholds -Threshold $CriticalEnd)) | Out-Null;
            $checks += $IcingaCheck;
         }

         if ($checks.Length -eq 1) {
            # Only add one check instead of the package
            # TODO: this should be a feature of the framework (collapsing packages)
            $CertPackage.AddCheck($checks[0])
         } else {
            $CertCheck = New-IcingaCheckPackage -Name $CheckNamePrefix -OperatorAnd;
            foreach ($check in $checks) {
               $CertCheck.AddCheck($check)
            }
            $CertPackage.AddCheck($CertCheck)
         }
      }
   }

   return (New-IcingaCheckResult -Name 'Certificates' -Check $CertPackage -NoPerfData $TRUE -Compile);

