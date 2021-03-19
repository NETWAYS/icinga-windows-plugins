<#
.SYNOPSIS
    Checks a given path / unc path and determines the size of the volume including free space
.DESCRIPTION
    Invoke-IcingaCheckUNCPath uses a path or unc path to fetch information about the volume this
    path is set to. This includes the total and free space of the share but also the total free share size.

    You can monitor the share size itself by using % and byte values, while the total free share size only supports byte values.

    In case you are checking very long path entries, you can short them with a display name alias.
.ROLE
    ### Path Permissions

    The user running this plugin requires read access to the given path. In case authentication is required, it has to be mapped to a user
    who can authenticate without a prompt
.PARAMETER Path
    The path to a volume or network share you want to monitor, like "\\example.com\Home" or "C:\ClusterSharedVolume\Volume1"
.PARAMETER DisplayAlias
    Modifies the plugin output to not display the value provided within the `-Path` argument but to use this string value
    instead of shorten the output and make it more visual appealing.
.PARAMETER Warning
    A warning threshold for the shares free space in either % or byte units, like "20%:" or "50GB:"
    Please note that this value is decreasing over time, therefor you will have to use the plugin handler and add ":" at the end
    of your input to check for "current value < threshold" like in the previous example

    Allowed units: %, B, KB, MB, GB, TB, PB, KiB, MiB, GiB, TiB, PiB
.PARAMETER Critical
    A critical threshold for the shares free space in either % or byte units, like "20%:" or "50GB:"
    Please note that this value is decreasing over time, therefor you will have to use the plugin handler and add ":" at the end
    of your input to check for "current value < threshold" like in the previous example

    Allowed units: %, B, KB, MB, GB, TB, PB, KiB, MiB, GiB, TiB, PiB
.PARAMETER WarningTotal
    A warning threshold for the shares total free space in byte units, like "50GB:"
    Please note that this value is decreasing over time, therefor you will have to use the plugin handler and add ":" at the end
    of your input to check for "current value < threshold" like in the previous example

    Allowed units: B, KB, MB, GB, TB, PB, KiB, MiB, GiB, TiB, PiB
.PARAMETER CriticalTotal
    A warning threshold for the shares total free space in byte units, like "50GB:"
    Please note that this value is decreasing over time, therefor you will have to use the plugin handler and add ":" at the end
    of your input to check for "current value < threshold" like in the previous example

    Allowed units: B, KB, MB, GB, TB, PB, KiB, MiB, GiB, TiB, PiB
.PARAMETER NoPerfData
    Disables the performance data output of this plugin. Default to FALSE.
.PARAMETER Verbosity
    Changes the behavior of the plugin output which check states are printed:
    0 (default): Only service checks/packages with state not OK will be printed
    1: Only services with not OK will be printed including OK checks of affected check packages including Package config
    2: Everything will be printed regardless of the check state
.EXAMPLE
    icinga { Invoke-IcingaCheckUNCPath -Path '\\example.com\Shares\Icinga' -Critical '20TB:' }

    [CRITICAL] Check package "\\example.com\Shares\Icinga Share" (Match All) - [CRITICAL] Free Space
        \_ [CRITICAL] Free Space: Value "5105899364352B" is lower than threshold "20000000000000B"
    | 'share_free_bytes'=5105899364352B;;20000000000000: 'total_free_bytes'=5105899364352B;; 'share_size'=23016091746304B;; 'share_free_percent'=22.18%;;;0;100
.EXAMPLE
    icinga { Invoke-IcingaCheckUNCPath -Path '\\example.com\Shares\Icinga' -Critical '40%:' }

    [CRITICAL] Check package "\\example.com\Shares\Icinga Share" - [CRITICAL] Free %
        \_ [CRITICAL] Free %: Value "22.18%" is lower than threshold "40%"
    | 'share_free_bytes'=5105899343872B;; 'total_free_bytes'=5105899343872B;; 'share_size'=23016091746304B;; 'share_free_percent'=22.18%;;40:;0;100
.EXAMPLE
    icinga { Invoke-IcingaCheckUNCPath -Path '\\example.com\Shares\Icinga' -CriticalTotal '20TB:' }

    [CRITICAL] Check package "\\example.com\Shares\Icinga Share" - [CRITICAL] Total Free
        \_ [CRITICAL] Total Free: Value "5105899315200B" is lower than threshold "20000000000000B"
    | 'share_free_bytes'=5105899315200B;; 'total_free_bytes'=5105899315200B;;20000000000000: 'share_size'=23016091746304B;; 'share_free_percent'=22.18%;;;0;100
.EXAMPLE
    icinga { Invoke-IcingaCheckUNCPath -Path '\\example.com\Shares\Icinga' -DisplayAlias 'IcingaExample' -CriticalTotal '20TB:' }

    [CRITICAL] Check package "IcingaExample Share" - [CRITICAL] Total Free
        \_ [CRITICAL] Total Free: Value "5105899069440B" is lower than threshold "20000000000000B"
    | 'share_free_bytes'=5105899069440B;; 'total_free_bytes'=5105899069440B;;20000000000000: 'share_size'=23016091746304B;; 'share_free_percent'=22.18%;;;0;100
.LINK
    https://github.com/Icinga/icinga-powershell-framework
    https://github.com/Icinga/icinga-powershell-plugins
#>

<#
Assembled plugin based on plugins\Invoke-IcingaCheckUNCPath.psm1 from
https://github.com/Icinga/icinga-powershell-plugins

icinga-powershell-framework: 1.4.1
icinga-powershell-plugins: 1.4.0
#>

    param (
        [string]$Path         = '',
        [string]$DisplayAlias = '',
        $Warning              = $null,
        $Critical             = $null,
        $WarningTotal         = $null,
        $CriticalTotal        = $null,
        [switch]$NoPerfData   = $FALSE,
        [ValidateSet(0, 1, 2)]
        $Verbosity            = 0
    );

# Tell the script the daemon is not running
$global:IcingaDaemonData = @{ FrameworkRunningAsDaemon = $FALSE }


# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\core\tools\New-StringTree.psm1
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

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\core\tools\Format-IcingaPerfDataLabel.psm1
function Format-IcingaPerfDataLabel()
{
    param(
        $PerfData
    );

    $Output = ((($PerfData) -Replace ' ', '_') -Replace '[\W]', '');

    while ($Output.Contains('__')) {
        $Output = $Output.Replace('__', '_');
    }
    # Remove all special characters and spaces on label names
    return $Output;
}

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\core\tools\Format-IcingaPerfDataValue.psm1
function Format-IcingaPerfDataValue()
{
    param(
        $PerfValue
    );

    if ((Test-Numeric $PerfValue) -eq $FALSE) {
        return $PerfValue;
    }

    # Convert our value to a string and replace ',' with a '.' to allow Icinga to parse the output
    # In addition, round every output to 6 digits
    return (([string]([math]::round([decimal]$PerfValue, 6))).Replace(',', '.'));
}

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\core\tools\Convert-IcingaPluginThresholds.psm1
<#
.SYNOPSIS
    Converts any kind of Icinga threshold with provided units
    to the lowest base of the unit which makes sense. It does
    support the Icinga plugin language, like ~:30, @10:40, 15:30,
    ...

    The conversion does currently support the following units:

    Size: B, KB, MB, GB, TB, PT, KiB, MiB, GiB, TiB, PiB
    Time: ms, s, m, h, d w, M, y
.DESCRIPTION
    Converts any kind of Icinga threshold with provided units
    to the lowest base of the unit. It does support the Icinga
    plugin language, like ~:30, @10:40, 15:30, ...

    The conversion does currently support the following units:

    Size: B, KB, MB, GB, TB, PT, KiB, MiB, GiB, TiB, PiB
    Time: ms, s, m, h, d w, M, y
.FUNCTIONALITY
    Converts values with units to the lowest unit of this category.
    Accepts Icinga Thresholds.
.EXAMPLE
    PS>Convert-IcingaPluginThresholds -Threshold '20d';

    Name                           Value
    ----                           -----
    Value                          1728000
    Unit                           s
.EXAMPLE
    PS>Convert-IcingaPluginThresholds -Threshold '5GB';

    Name                           Value
    ----                           -----
    Value                          5000000000
    Unit                           B
.EXAMPLE
    PS>Convert-IcingaPluginThresholds -Threshold '10MB:20MB';

    Name                           Value
    ----                           -----
    Value                          10000000:20000000
    Unit                           B
.EXAMPLE
    PS>Convert-IcingaPluginThresholds -Threshold '10m:1h';

    Name                           Value
    ----                           -----
    Value                          600:3600
    Unit                           s
.EXAMPLE
    PS>Convert-IcingaPluginThresholds -Threshold '@10m:1h';

    Name                           Value
    ----                           -----
    Value                          @600:3600
    Unit                           s
.EXAMPLE
    Convert-IcingaPluginThresholds -Threshold '~:1M';

    Name                           Value
    ----                           -----
    Value                          ~:2592000
    Unit                           s
.INPUTS
   System.String
.OUTPUTS
    System.Hashtable
.LINK
   https://github.com/Icinga/icinga-powershell-framework
#>

function Convert-IcingaPluginThresholds()
{
    param (
        [string]$Threshold = $null
    );

    [hashtable]$RetValue = @{
        'Unit'  = '';
        'Value' =  $null;
    };

    if ($null -eq $Threshold) {
        return $RetValue;
    }

    # Always ensure we are using correct digits
    $Threshold = $Threshold.Replace(',', '.');

    [array]$Content    = @();

    if ($Threshold.Contains(':')) {
        $Content = $Threshold.Split(':');
    } else {
        $Content += $Threshold;
    }

    [array]$ConvertedValue = @();

    foreach ($ThresholdValue in $Content) {

        [bool]$HasTilde = $FALSE;
        [bool]$HasAt    = $FALSE;
        $Value          = '';
        $WorkUnit       = '';

        if ($ThresholdValue.Contains('~')) {
            $ThresholdValue = $ThresholdValue.Replace('~', '');
            $HasTilde = $TRUE;
        } elseif ($ThresholdValue.Contains('@')) {
            $HasAt = $TRUE;
            $ThresholdValue = $ThresholdValue.Replace('@', '');
        }

        If (($ThresholdValue -Match "(^[\d\.]*) ?(B|KB|MB|GB|TB|PT|KiB|MiB|GiB|TiB|PiB)")) {
            $WorkUnit = 'B';
            if ([string]::IsNullOrEmpty($RetValue.Unit) -eq $FALSE -And $RetValue.Unit -ne $WorkUnit) {
                Exit-IcingaThrowException -ExceptionType 'Input' -ExceptionThrown $IcingaExceptions.Inputs.MultipleUnitUsage -Force;
            }
            $Value         = (Convert-Bytes -Value $ThresholdValue -Unit $WorkUnit).Value;
            $RetValue.Unit = $WorkUnit;
        } elseif (($ThresholdValue -Match "(^[\d\.]*) ?(ms|s|m|h|d|w|M|y)")) {
            $WorkUnit = 's';
            if ([string]::IsNullOrEmpty($RetValue.Unit) -eq $FALSE -And $RetValue.Unit -ne $WorkUnit) {
                Exit-IcingaThrowException -ExceptionType 'Input' -ExceptionThrown $IcingaExceptions.Inputs.MultipleUnitUsage -Force;
            }
            $Value         = (ConvertTo-Seconds -Value $ThresholdValue);
            $RetValue.Unit = $WorkUnit;
        } elseif (($ThresholdValue -Match "(^[\d\.]*) ?(%)")) {
            $WorkUnit      = '%';
            $Value         = ([string]$ThresholdValue).Replace(' ', '').Replace('%', '');
            $RetValue.Unit = $WorkUnit;
        } else {
            $Value = $ThresholdValue;
        }

        if ($HasTilde) {
            $ConvertedValue += [string]::Format('~{0}', $Value);
        } elseif ($HasAt) {
            $ConvertedValue += [string]::Format('@{0}', $Value);
        } else {
            $ConvertedValue += $Value;
        }
    }

    [string]$Value = [string]::Join(':', $ConvertedValue);

    if ([string]::IsNullOrEmpty($Value) -eq $FALSE -And $Value.Contains(':') -eq $FALSE) {
        if ((Test-Numeric $Value)) {
            $RetValue.Value = $Value;
            return $RetValue;
        }
    }

    # Always ensure we are using correct digits
    $Value = ([string]$Value).Replace(',', '.');
    $RetValue.Value = $Value;

    return $RetValue;
}

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\core\tools\Test-Numeric.psm1
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

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\core\tools\ConvertTo-Integer.psm1
<#
.SYNOPSIS
   Helper function to convert values to integer if possible
.DESCRIPTION
   Converts an input value to integer if possible in any way. Otherwise it will return the object unmodified

   More Information on https://github.com/Icinga/icinga-powershell-framework
.FUNCTIONALITY
   Converts an input value to integer if possible in any way. Otherwise it will return the object unmodified
.PARAMETER Value
   Any value/object is analysed and if possible converted to an integer
.INPUTS
   System.Object
.OUTPUTS
   System.Integer

.LINK
   https://github.com/Icinga/icinga-powershell-framework
.NOTES
#>

function ConvertTo-Integer()
{
    param (
        $Value,
        [switch]$NullAsEmpty
    );

    if ($null -eq $Value) {
        if ($NullAsEmpty) {
            return '';
        }

        return 0;
    }

    if ([string]::IsNullOrEmpty($Value)) {
        if ($NullAsEmpty) {
            return '';
        }

        return 0;
    }

    if ((Test-Numeric $Value)) {
        return $Value;
    }

    $Type = $value.GetType().Name;

    if ($Type -eq 'GpoBoolean' -Or $Type -eq 'Boolean' -Or $Type -eq 'SwitchParameter') {
        return [int]$Value;
    }

    if ($Type -eq 'String') {
        if ($Value.ToLower() -eq 'true' -Or $Value.ToLower() -eq 'yes' -Or $Value.ToLower() -eq 'y') {
            return 1;
        }
        if ($Value.ToLower() -eq 'false' -Or $Value.ToLower() -eq 'no' -Or $Value.ToLower() -eq 'n') {
            return 0;
        }
    }

    return $Value;
}

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\core\cache\Get-IcingaCacheData.psm1
<#
.SYNOPSIS
    Reads data from a cache file of the Framework and returns its content
.DESCRIPTION
    Allows a developer to read data from certain cache files to either speed up
    loading procedures, to store content to not lose data on restarts of a daemon
    or to build data tables over time
.FUNCTIONALITY
    Returns cached data for specific content
.EXAMPLE
    PS>Get-IcingaCacheData -Space 'sc_daemon' -CacheStore 'checkresult_store' -KeyName 'Invoke-IcingaCheckCPU';
.PARAMETER Space
    The individual space to read from. This is targeted to a folder the cache data is written to under icinga-powershell-framework/cache/
.PARAMETER CacheStore
    This is targeted to a sub-folder under icinga-powershell-framework/cache/<space>/
.PARAMETER KeyName
    This is the actual cache file located under icinga-powershell-framework/cache/<space>/<CacheStore>/<KeyName>.json
    Please note to only provide the name without the '.json' apendix. This is done by the module itself
.INPUTS
    System.String
.OUTPUTS
    System.Object
.LINK
    https://github.com/Icinga/icinga-powershell-framework
.NOTES
#>
function Get-IcingaCacheData()
{
    param(
        [string]$Space,
        [string]$CacheStore,
        [string]$KeyName
    );

    $CacheFile       = Join-Path -Path (Join-Path -Path (Join-Path -Path (Get-IcingaCacheDir) -ChildPath $Space) -ChildPath $CacheStore) -ChildPath ([string]::Format('{0}.json', $KeyName));
    [string]$Content = '';
    $cacheData       = @{ };

    if ((Test-Path $CacheFile) -eq $FALSE) {
        return $null;
    }

    $Content = Read-IcingaFileContent -File $CacheFile;

    if ([string]::IsNullOrEmpty($Content)) {
        return $null;
    }

    $cacheData = ConvertFrom-Json -InputObject ([string]$Content);

    if ([string]::IsNullOrEmpty($KeyName)) {
        return $cacheData;
    } else {
        return $cacheData.$KeyName;
    }
}

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\icinga\enums\Icinga_IcingaEnums.psm1
<#
 # This script will provide 'Enums' we can use within our module to
 # easier access constants and to maintain a better overview of the
 # entire components
 #>

[hashtable]$IcingaExitCode = @{
    Ok       = 0;
    Warning  = 1;
    Critical = 2;
    Unknown  = 3;
};

[hashtable]$IcingaExitCodeText = @{
    0 = '[OK]';
    1 = '[WARNING]';
    2 = '[CRITICAL]';
    3 = '[UNKNOWN]';
};

[hashtable]$IcingaExitCodeColor = @{
    0 = 'Green';
    1 = 'Yellow';
    2 = 'Red';
    3 = 'Magenta';
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

<##################################################################################################
################# Service Enums ##################################################################
##################################################################################################>

[hashtable]$ServiceStartupTypeName = @{
    0 = 'Boot';
    1 = 'System';
    2 = 'Automatic';
    3 = 'Manual';
    4 = 'Disabled';
    5 = 'Unknown'; # Custom
}

[hashtable]$ServiceWmiStartupType = @{
    'Boot'     = 0;
    'System'   = 1;
    'Auto'     = 2;
    'Manual'   = 3;
    'Disabled' = 4;
    'Unknown'  = 5; # Custom
}

<#
 # Once we defined a new enum hashtable above, simply add it to this list
 # to make it available within the entire module.
 #
 # Example usage:
 # $IcingaEnums.IcingaExitCode.Ok
 #>
 if ($null -eq $IcingaEnums) {
    [hashtable]$IcingaEnums = @{
        IcingaExitCode         = $IcingaExitCode;
        IcingaExitCodeText     = $IcingaExitCodeText;
        IcingaExitCodeColor    = $IcingaExitCodeColor;
        IcingaMeasurementUnits = $IcingaMeasurementUnits;
        #services
        ServiceStartupTypeName = $ServiceStartupTypeName;
        ServiceWmiStartupType  = $ServiceWmiStartupType;
    }
}

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\icinga\plugin\New-IcingaCheckPackage.psm1
function New-IcingaCheckPackage()
{
    param(
        [string]$Name,
        [switch]$OperatorAnd,
        [switch]$OperatorOr,
        [switch]$OperatorNone,
        [int]$OperatorMin           = -1,
        [int]$OperatorMax           = -1,
        [array]$Checks              = @(),
        [int]$Verbose               = 0,
        [switch]$IgnoreEmptyPackage = $FALSE,
        [switch]$Hidden             = $FALSE
    );

    $Check = New-Object -TypeName PSObject;
    $Check | Add-Member -MemberType NoteProperty -Name 'name'               -Value $Name;
    $Check | Add-Member -MemberType NoteProperty -Name 'exitcode'           -Value -1;
    $Check | Add-Member -MemberType NoteProperty -Name 'verbose'            -Value $Verbose;
    $Check | Add-Member -MemberType NoteProperty -Name 'hidden'             -Value $Hidden;
    $Check | Add-Member -MemberType NoteProperty -Name 'ignoreemptypackage' -Value $IgnoreEmptyPackage;
    $Check | Add-Member -MemberType NoteProperty -Name 'checks'             -Value $Checks;
    $Check | Add-Member -MemberType NoteProperty -Name 'opand'              -Value $OperatorAnd;
    $Check | Add-Member -MemberType NoteProperty -Name 'opor'               -Value $OperatorOr;
    $Check | Add-Member -MemberType NoteProperty -Name 'opnone'             -Value $OperatorNone;
    $Check | Add-Member -MemberType NoteProperty -Name 'opmin'              -Value $OperatorMin;
    $Check | Add-Member -MemberType NoteProperty -Name 'opmax'              -Value $OperatorMax;
    $Check | Add-Member -MemberType NoteProperty -Name 'spacing'            -Value 0;
    $Check | Add-Member -MemberType NoteProperty -Name 'compiled'           -Value $FALSE;
    $Check | Add-Member -MemberType NoteProperty -Name 'perfdata'           -Value $FALSE;
    $Check | Add-Member -MemberType NoteProperty -Name 'checkcommand'       -Value '';
    $Check | Add-Member -MemberType NoteProperty -Name 'headermsg'          -Value '';
    $Check | Add-Member -MemberType NoteProperty -Name 'checkpackage'       -Value $TRUE;
    $Check | Add-Member -MemberType NoteProperty -Name 'warningchecks'      -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'criticalchecks'     -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'unknownchecks'      -Value @();

    $Check | Add-Member -MemberType ScriptMethod -Name 'HasChecks' -Value {
        if ($this.checks -ne 0) {
            return $TRUE
        }

        return $FALSE;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'Initialise' -Value {
        foreach ($check in $this.checks) {
            $this.InitCheck($check);
        }
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'InitCheck' -Value {
        param($check);

        if ($null -eq $check) {
            return;
        }

        $check.verbose = $this.verbose;
        $check.AddSpacing();
        $check.SilentCompile();
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'AddSpacing' -Value {
        $this.spacing += 1;
        foreach ($check in $this.checks) {
            $check.spacing = $this.spacing;
            $check.AddSpacing();
        }
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'AddCheck' -Value {
        param($check);

        if ($null -eq $check) {
            return;
        }

        $this.InitCheck($check);
        $this.checks += $check;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetWarnings' -Value {
        foreach ($check in $this.checks) {
            $this.warningchecks += $check.GetWarnings();
        }

        return $this.warningchecks;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetCriticals' -Value {
        foreach ($check in $this.checks) {
            $this.criticalchecks += $check.GetCriticals();
        }

        return $this.criticalchecks;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetUnknowns' -Value {
        foreach ($check in $this.checks) {
            $this.unknownchecks += $check.GetUnknowns();
        }

        return $this.unknownchecks;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'AssignCheckCommand' -Value {
        param($CheckCommand);

        $this.checkcommand = $CheckCommand;

        foreach ($check in $this.checks) {
            $check.AssignCheckCommand($CheckCommand);
        }
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'Compile' -Value {
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
            } elseif ($this.opor) {
                if ($this.CheckOneOk() -eq $FALSE) {
                    $this.GetWorstExitCode();
                }
            } elseif ($this.opnone) {
                if ($this.CheckOneOk() -eq $TRUE) {
                    $this.GetWorstExitCode();
                    $this.exitcode = $IcingaEnums.IcingaExitCode.Critical;
                } else {
                    $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
                }
            } elseif ([int]$this.opmin -ne -1) {
                if ($this.CheckMinimumOk() -eq $FALSE) {
                    $this.GetWorstExitCode();
                } else {
                    $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
                }
            } elseif ([int]$this.opmax -ne -1) {
                if ($this.CheckMaximumOk() -eq $FALSE) {
                    $this.GetWorstExitCode();
                } else {
                    $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
                }
            }
        } else {
            if ($this.ignoreemptypackage) {
                $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
            } else {
                $this.exitcode = $IcingaEnums.IcingaExitCode.Unknown;
            }
        }

        if ([int]$this.exitcode -eq -1) {
            $this.exitcode = $IcingaEnums.IcingaExitCode.Ok;
        }

        if ($Verbose -eq $TRUE) {
            $this.PrintOutputMessages();
        }

        return $this.exitcode;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'SilentCompile' -Value {
        $this.Compile($FALSE) | Out-Null;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetOkCount' -Value {
        [int]$okCount = 0;
        foreach ($check in $this.checks) {
            if ([int]$check.exitcode -eq [int]$IcingaEnums.IcingaExitCode.Ok) {
                $okCount += 1;
            }
        }

        return $okCount;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CheckMinimumOk' -Value {
        if ($this.opmin -gt $this.checks.Count) {
            Write-IcingaPluginOutput (
                [string]::Format(
                    'Unknown: The minimum argument ({0}) is exceeding the amount of assigned checks ({1}) to this package "{2}"',
                    $this.opmin, $this.checks.Count, $this.name
                )
            );
            $this.exitcode = $IcingaEnums.IcingaExitCode.Unknown;
            return $FALSE;
        }

        [int]$okCount = $this.GetOkCount();

        if ($this.opmin -le $okCount) {
            return $TRUE;
        }

        return $FALSE;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CheckMaximumOk' -Value {
        if ($this.opmax -gt $this.checks.Count) {
            Write-IcingaPluginOutput (
                [string]::Format(
                    'Unknown: The maximum argument ({0}) is exceeding the amount of assigned checks ({1}) to this package "{2}"',
                    $this.opmax, $this.checks.Count, $this.name
                )
            );
            $this.exitcode = $IcingaEnums.IcingaExitCode.Unknown;
            return $FALSE;
        }

        [int]$okCount = $this.GetOkCount();

        if ($this.opmax -ge $okCount) {
            return $TRUE;
        }

        return $FALSE;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CheckAllOk' -Value {
        foreach ($check in $this.checks) {
            if ([int]$check.exitcode -ne [int]$IcingaEnums.IcingaExitCode.Ok) {
                return $FALSE;
            }
        }

        return $TRUE;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CheckOneOk' -Value {
        foreach ($check in $this.checks) {
            if ([int]$check.exitcode -eq [int]$IcingaEnums.IcingaExitCode.Ok) {
                $this.exitcode = $check.exitcode;
                return $TRUE;
            }
        }

        return $FALSE;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetPackageConfigMessage' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintOutputMessageSorted' -Value {
        param($skipHidden, $skipExitCode);

        if ($this.hidden -And $skipHidden) {
            return;
        }

        [hashtable]$MessageOrdering = @{};
        foreach ($check in $this.checks) {
            if ($this.verbose -eq 0) {
                if ([int]$check.exitcode -eq $skipExitCode) {
                    continue;
                }
            } elseif ($this.verbose -eq 1) {
                if ([int]$check.exitcode -eq $skipExitCode -And $check.checkpackage) {
                    continue;
                }
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'WriteAllOutput' -Value {
        $this.PrintOutputMessageSorted($TRUE, $IcingaEnums.IcingaExitCode.Ok);
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintAllMessages' -Value {
        $this.WritePackageOutputStatus();
        $this.WriteAllOutput();
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WriteCheckErrors' -Value {
        $this.PrintOutputMessageSorted($FALSE, $IcingaEnums.IcingaExitCode.Ok);
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintNoChecksConfigured' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'WritePackageOutputStatus' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintOutputMessages' -Value {
        [bool]$printAll = $FALSE;

        switch ($this.verbose) {
            0 {
                # Default value. Only print a package but not the services include
                break;
            };
            1 {
                # Include the Operator into the check package result and OK checks of package
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'AddUniqueSortedChecksToHeader' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetWorstExitCode' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetPerfData' -Value {
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

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\icinga\plugin\New-IcingaCheck.psm1
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
        [string]$LabelName  = $null,
        [switch]$NoPerfData
    );

    $Check = New-Object -TypeName PSObject;
    $Check | Add-Member -MemberType NoteProperty -Name 'name'           -Value $Name;
    $Check | Add-Member -MemberType NoteProperty -Name 'verbose'        -Value 0;
    $Check | Add-Member -MemberType NoteProperty -Name 'messages'       -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'oks'            -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'warnings'       -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'criticals'      -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'unknowns'       -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'okchecks'       -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'warningchecks'  -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'criticalchecks' -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'unknownchecks'  -Value @();
    $Check | Add-Member -MemberType NoteProperty -Name 'value'          -Value $Value;
    $Check | Add-Member -MemberType NoteProperty -Name 'exitcode'       -Value -1;
    $Check | Add-Member -MemberType NoteProperty -Name 'unit'           -Value $Unit;
    $Check | Add-Member -MemberType NoteProperty -Name 'spacing'        -Value 0;
    $Check | Add-Member -MemberType NoteProperty -Name 'compiled'       -Value $FALSE;
    $Check | Add-Member -MemberType NoteProperty -Name 'perfdata'       -Value (-Not $NoPerfData);
    $Check | Add-Member -MemberType NoteProperty -Name 'warning'        -Value '';
    $Check | Add-Member -MemberType NoteProperty -Name 'critical'       -Value '';
    $Check | Add-Member -MemberType NoteProperty -Name 'minimum'        -Value $Minimum;
    $Check | Add-Member -MemberType NoteProperty -Name 'maximum'        -Value $Maximum;
    $Check | Add-Member -MemberType NoteProperty -Name 'objectexists'   -Value $ObjectExists;
    $Check | Add-Member -MemberType NoteProperty -Name 'translation'    -Value $Translation;
    $Check | Add-Member -MemberType NoteProperty -Name 'labelname'      -Value $LabelName;
    $Check | Add-Member -MemberType NoteProperty -Name 'checks'         -Value $null;
    $Check | Add-Member -MemberType NoteProperty -Name 'completed'      -Value $FALSE;
    $Check | Add-Member -MemberType NoteProperty -Name 'checkcommand'   -Value '';
    $Check | Add-Member -MemberType NoteProperty -Name 'checkpackage'   -Value $FALSE;

    $Check | Add-Member -MemberType ScriptMethod -Name 'HandleDaemon' -Value {
        # Only apply this once the checkcommand is set
        if ([string]::IsNullOrEmpty($this.checkcommand) -Or $global:IcingaDaemonData.FrameworkRunningAsDaemon -eq $FALSE) {
            return;
        }

        if ($null -eq $global:Icinga -Or $global:Icinga.ContainsKey('CheckData') -eq $FALSE) {
            return;
        }

        if ($global:Icinga.CheckData.ContainsKey($this.checkcommand)) {
            if ($global:Icinga.CheckData[$this.checkcommand]['results'].ContainsKey($this.name) -eq $FALSE) {
                $global:Icinga.CheckData[$this.checkcommand]['results'].Add(
                    $this.name,
                    @{ }
                );
            }

            # Fix possible error for identical time stamps due to internal exceptions
            # and check execution within the same time slot because of this
            [string]$TimeIndex = Get-IcingaUnixTime;

            if ($global:Icinga.CheckData[$this.checkcommand]['results'][$this.name].ContainsKey($TimeIndex)) {
                return;
            }

            $global:Icinga.CheckData[$this.checkcommand]['results'][$this.name].Add(
                $TimeIndex,
                $this.value
            );
        }
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'AddSpacing' -Value {
        $this.spacing += 1;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'AssignCheckCommand' -Value {
        param($CheckCommand);

        $this.checkcommand = $CheckCommand;
        $this.HandleDaemon();
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetWarnings' -Value {
        return $this.warningchecks;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetCriticals' -Value {
        return $this.criticalchecks;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetUnknowns' -Value {
        return $this.unknownchecks;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'SetUnknown' -Value {
        $this.AddInternalCheckMessage(
            $IcingaEnums.IcingaExitCode.Unknown,
            $null,
            $null
        );

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'SetWarning' -Value {
        $this.AddInternalCheckMessage(
            $IcingaEnums.IcingaExitCode.Warning,
            $null,
            $null
        );

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnOutOfRange' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfLike' -Value {
        param($warning);

        if ($this.value -Like $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'like'
            );
        }

        $this.warning = $warning;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfNotLike' -Value {
        param($warning);

        if (-Not ($this.value -Like $warning)) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'not like'
            );
        }

        $this.warning = $warning;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfMatch' -Value {
        param($warning);

        if ($this.value -eq $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'matching'
            );
        }

        $this.warning = $warning;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfNotMatch' -Value {
        param($warning);

        if ($this.value -ne $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'not matching'
            );
        }

        $this.warning = $warning;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfBetweenAndEqual' -Value {
        param($min, $max);

        if ($this.value -ge $min -And $this.value -le $max) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                [string]::Format('{0}:{1}', $min, $max),
                'between'
            );
        }

        $this.warning = [string]::Format('{0}:{1}', $min, $max);

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfBetween' -Value {
        param($min, $max);

        if ($this.value -gt $min -And $this.value -lt $max) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                [string]::Format('{0}:{1}', $min, $max),
                'between'
            );
        }

        $this.warning = [string]::Format('{0}:{1}', $min, $max);

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfLowerThan' -Value {
        param($warning);

        if ($this.value -lt $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'lower than'
            );
        }

        $this.warning = $warning;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfLowerEqualThan' -Value {
        param($warning);

        if ($this.value -le $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'lower or equal than'
            );
        }

        $this.warning = $warning;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfGreaterThan' -Value {
        param($warning);

        if ($this.value -gt $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'greater than'
            );
        }

        $this.warning = $warning;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'WarnIfGreaterEqualThan' -Value {
        param($warning);

        if ($this.value -ge $warning) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Warning,
                $warning,
                'greater or equal than'
            );
        }

        $this.warning = $warning;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'SetCritical' -Value {
        $this.AddInternalCheckMessage(
            $IcingaEnums.IcingaExitCode.Critical,
            $null,
            $null
        );

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritOutOfRange' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfLike' -Value {
        param($critical);

        if ($this.value -Like $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'like'
            );
        }

        $this.critical = $critical;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfNotLike' -Value {
        param($critical);

        if (-Not ($this.value -Like $critical)) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'not like'
            );
        }

        $this.critical = $critical;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfMatch' -Value {
        param($critical);

        if ($this.value -eq $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'matching'
            );
        }

        $this.critical = $critical;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfNotMatch' -Value {
        param($critical);

        if ($this.value -ne $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'not matching'
            );
        }

        $this.critical = $critical;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfBetweenAndEqual' -Value {
        param($min, $max);

        if ($this.value -ge $min -And $this.value -le $max) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                [string]::Format('{0}:{1}', $min, $max),
                'between'
            );
        }

        $this.critical = [string]::Format('{0}:{1}', $min, $max);

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfBetween' -Value {
        param($min, $max);

        if ($this.value -gt $min -And $this.value -lt $max) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                [string]::Format('{0}:{1}', $min, $max),
                'between'
            );
        }

        $this.critical = [string]::Format('{0}:{1}', $min, $max);

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfLowerThan' -Value {
        param($critical);

        if ($this.value -lt $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'lower than'
            );
        }

        $this.critical = $critical;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfLowerEqualThan' -Value {
        param($critical);

        if ($this.value -le $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'lower or equal than'
            );
        }

        $this.critical = $critical;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfGreaterThan' -Value {
        param($critical);

        if ($this.value -gt $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'greater than'
            );
        }

        $this.critical = $critical;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'CritIfGreaterEqualThan' -Value {
        param($critical);

        if ($this.value -ge $critical) {
            $this.AddInternalCheckMessage(
                $IcingaEnums.IcingaExitCode.Critical,
                $critical,
                'greater or equal than'
            );
        }

        $this.critical = $critical;

        return $this;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'TranslateValue' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'AddInternalCheckMessage' -Value {
        param($state, $value, $type);

        if ($this.objectexists -ne -1 -And $null -eq $this.objectexists) {
            $this.SetExitCode($IcingaEnums.IcingaExitCode.Unknown);
            $this.AddMessage(
                [string]::Format(
                    '{0} does not exist', $this.name
                ),
                $IcingaEnums.IcingaExitCode.Unknown
            );
            return;
        }

        $this.SetExitCode($state);

        if ($null -eq $value -And $null -eq $type) {
            $this.AddMessage(
                $this.name,
                $state
            );
        } else {
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
        }

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

    $Check | Add-Member -MemberType ScriptMethod -Name 'AddMessage' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'AddCheckStateArrays' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintOkMessages' -Value {
        param([string]$spaces);
        $this.OutputMessageArray($this.oks, $spaces);
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintWarningMessages' -Value {
        param([string]$spaces);
        $this.OutputMessageArray($this.warnings, $spaces);
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintCriticalMessages' -Value {
        param([string]$spaces);
        $this.OutputMessageArray($this.criticals, $spaces);
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintUnknownMessages' -Value {
        param([string]$spaces);
        $this.OutputMessageArray($this.unknowns, $spaces);
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintAllMessages' -Value {
        [string]$spaces = New-StringTree $this.spacing;
        $this.OutputMessageArray($this.unknowns, $spaces);
        $this.OutputMessageArray($this.criticals, $spaces);
        $this.OutputMessageArray($this.warnings, $spaces);
        $this.OutputMessageArray($this.oks, $spaces);
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'OutputMessageArray' -Value {
        param($msgArray, [string]$spaces);

        foreach ($msg in $msgArray) {
            Write-IcingaPluginOutput ([string]::Format('{0}{1}', $spaces, $msg));
        }
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'PrintOutputMessages' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'SetExitCode' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'ValidateUnit' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'AddOkOutput' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'SilentCompile' -Value {
        if ($this.compiled) {
            return;
        }

        $this.AddOkOutput();
        $this.compiled = $TRUE;
        $this.AddCheckStateArrays();
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'Compile' -Value {
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

    $Check | Add-Member -MemberType ScriptMethod -Name 'GetPerfData' -Value {

        if ($this.completed -Or -Not $this.perfdata) {
            return $null;
        }

        $this.AutodiscoverMinMax();

        $this.completed    = $TRUE;
        [string]$LabelName = (Format-IcingaPerfDataLabel $this.name);
        $value             = ConvertTo-Integer -Value $this.value -NullAsEmpty;
        $warning           = ConvertTo-Integer -Value $this.warning -NullAsEmpty;
        $critical          = ConvertTo-Integer -Value $this.critical -NullAsEmpty;

        if ([string]::IsNullOrEmpty($this.labelname) -eq $FALSE) {
            $LabelName = $this.labelname;
        }

        $perfdata = @{
            'label'    = $LabelName;
            'perfdata' = '';
            'unit'     = $this.unit;
            'value'    = (Format-IcingaPerfDataValue $value);
            'warning'  = (Format-IcingaPerfDataValue $warning);
            'critical' = (Format-IcingaPerfDataValue $critical);
            'minimum'  = (Format-IcingaPerfDataValue $this.minimum);
            'maximum'  = (Format-IcingaPerfDataValue $this.maximum);
            'package'  = $FALSE;
        };

        return $perfdata;
    }

    $Check | Add-Member -MemberType ScriptMethod -Name 'AutodiscoverMinMax' -Value {
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

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\icinga\plugin\New-IcingaCheckResult.psm1
function New-IcingaCheckresult()
{
    param(
        $Check,
        [bool]$NoPerfData,
        [switch]$Compile
    );

    $CheckResult = New-Object -TypeName PSObject;
    $CheckResult | Add-Member -MemberType NoteProperty -Name 'check'      -Value $Check;
    $CheckResult | Add-Member -MemberType NoteProperty -Name 'noperfdata' -Value $NoPerfData;

    $CheckResult | Add-Member -MemberType ScriptMethod -Name 'Compile' -Value {
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

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\icinga\plugin\New-IcingaPerformanceDataEntry.psm1
function New-IcingaPerformanceDataEntry()
{
    param (
        $PerfDataObject,
        $Label          = $null,
        $Value          = $null
    );

    if ($null -eq $PerfDataObject) {
        return '';
    }

    [string]$LabelName = $PerfDataObject.label;
    [string]$PerfValue = $PerfDataObject.value;

    if ([string]::IsNullOrEmpty($Label) -eq $FALSE) {
        $LabelName = $Label;
    }
    if ([string]::IsNullOrEmpty($Value) -eq $FALSE) {
        $PerfValue = $Value;
    }

    $minimum = '';
    $maximum = '';

    if ([string]::IsNullOrEmpty($PerfDataObject.minimum) -eq $FALSE) {
        $minimum = [string]::Format(';{0}', $PerfDataObject.minimum);
    }
    if ([string]::IsNullOrEmpty($PerfDataObject.maximum) -eq $FALSE) {
        $maximum = [string]::Format(';{0}', $PerfDataObject.maximum);
    }

    return (
        [string]::Format(
            "'{0}'={1}{2};{3};{4}{5}{6} ",
            $LabelName.ToLower(),
            (Format-IcingaPerfDataValue $PerfValue),
            $PerfDataObject.unit,
            (Format-IcingaPerfDataValue $PerfDataObject.warning),
            (Format-IcingaPerfDataValue $PerfDataObject.critical),
            (Format-IcingaPerfDataValue $minimum),
            (Format-IcingaPerfDataValue $maximum)
        )
    );
}

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\icinga\plugin\Write-IcingaPluginOutput.psm1
function Write-IcingaPluginOutput()
{
    param(
        $Output
    );

    if ($global:IcingaDaemonData.FrameworkRunningAsDaemon -eq $FALSE) {
        Write-IcingaConsolePlain $Output;
    } else {
        # New behavior with local thread separated results
        $global:Icinga.CheckResults += $Output;
    }
}

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-framework\1.4.1\lib\icinga\plugin\Write-IcingaPluginPerfData.psm1
function Write-IcingaPluginPerfData()
{
    param(
        $PerformanceData,
        $CheckCommand
    );

    if ($PerformanceData.package -eq $FALSE) {
        $PerformanceData = @{
            $PerformanceData.label = $PerformanceData;
        }
    } else {
        $PerformanceData = $PerformanceData.perfdata;
    }

    $CheckResultCache = Get-IcingaCacheData -Space 'sc_daemon' -CacheStore 'checkresult' -KeyName $CheckCommand;

    if ($global:IcingaDaemonData.FrameworkRunningAsDaemon -eq $FALSE) {
        [string]$PerfDataOutput = (Get-IcingaPluginPerfDataContent -PerfData $PerformanceData -CheckResultCache $CheckResultCache);
        Write-IcingaConsolePlain ([string]::Format('| {0}', $PerfDataOutput));
    } else {
        [void](Get-IcingaPluginPerfDataContent -PerfData $PerformanceData -CheckResultCache $CheckResultCache -AsObject $TRUE);
    }
}

function Get-IcingaPluginPerfDataContent()
{
    param(
        $PerfData,
        $CheckResultCache,
        [bool]$AsObject = $FALSE
    );

    [string]$PerfDataOutput = '';

    foreach ($package in $PerfData.Keys) {
        $data = $PerfData[$package];
        if ($data.package) {
            $PerfDataOutput += (Get-IcingaPluginPerfDataContent -PerfData $data.perfdata -CheckResultCache $CheckResultCache -AsObject $AsObject);
        } else {
            foreach ($checkresult in $CheckResultCache.PSobject.Properties) {
                $SearchPattern = [string]::Format('{0}_', $data.label);
                $SearchEntry   = $checkresult.Name;
                if ($SearchEntry -like "$SearchPattern*") {
                    $cachedresult = (New-IcingaPerformanceDataEntry -PerfDataObject $data -Label $SearchEntry -Value $checkresult.Value);

                    if ($AsObject) {
                        # New behavior with local thread separated results
                        $global:Icinga.PerfData += $cachedresult;
                    }
                    $PerfDataOutput += $cachedresult;
                }
            }

            $compiledPerfData = (New-IcingaPerformanceDataEntry $data);

            if ($AsObject) {
                # New behavior with local thread separated results
                $global:Icinga.PerfData += $compiledPerfData;
            }
            $PerfDataOutput += $compiledPerfData;
        }
    }

    return $PerfDataOutput;
}

# Content from: C:\Users\marku\Documents\PowerShell\Modules\icinga-powershell-plugins\1.4.0\provider\certificate\Icinga_ProviderCertificate.psm1
function Get-IcingaCertificateData()
{
   param(
      #CertStore-Related Param
      [ValidateSet('*', 'LocalMachine', 'CurrentUser')]
      [string]$CertStore     = '*',
      [array]$CertThumbprint = $null,
      [array]$CertSubject    = $null,
      $CertStorePath         = '*',
      #Local Certs
      [array]$CertPaths      = $null,
      [array]$CertName       = $null,
      [bool]$Recurse         = $FALSE
   );

   [array]$CertData = @();

   if ([string]::IsNullOrEmpty($CertStore) -eq $FALSE){
      $CertData += Get-IcingaCertStoreCertificates -CertStore $CertStore -CertThumbprint $CertThumbprint -CertSubject $CertSubject -CertStorePath $CertStorePath;
   }

   if (($null -ne $CertPaths) -or ($null -ne $CertName)) {
      $CertDataFile = @();

      foreach ($path in $CertPaths) {
         foreach ($name in $CertName) {
            $searchPath   = $path;
            [array]$files = Get-ChildItem -Recurse:$Recurse -Filter $name -Path $searchPath;

            if ($null -ne $files) {
               $CertDataFile += $files;
            } else {
               # Remember that pattern didn't match
               if ($CertPaths.length -eq 1) {
                  $certPath = $name;
               } else {
                  $certPath = "${path}\${name}";
               }
               $CertData += @{
                  Path = $certPath;
                  Cert = $null;
               };   
            }
         }
      }
   }

   if ($null -ne $CertDataFile) {
      foreach ($Cert in $CertDataFile) {
         $path = $Cert.FullName;

         if ($CertPaths.length -eq 1) {
            $path = $path.Replace("${CertPaths}\", '');
         }

         try {
            $CertConverted = New-Object Security.Cryptography.X509Certificates.X509Certificate2 $Cert.FullName; 
            $CertData += @{
               Path = $path;
               Cert = $CertConverted;
            }; 
         } catch {
            # Not a valid certificate
            $CertData += @{
               Path = $path;
               Cert = $null;
            }; 
         }
      }
   }

   return $CertData;
}

function Get-IcingaCertStoreCertificates()
{
   param (
      #CertStore-Related Param
      [ValidateSet('*', 'LocalMachine', 'CurrentUser')]
      [string]$CertStore     = '*',
      [array]$CertThumbprint = @(),
      [array]$CertSubject    = @(),
      $CertStorePath         = '*'
   );

   $CertStoreArray = @();
   $CertStorePath  = [string]::Format('Cert:\{0}\{1}', $CertStore, $CertStorePath);
   $CertStoreCerts = Get-ChildItem -Path $CertStorePath -Recurse;

   if ($CertSubject.Count -eq 0 -And $CertThumbprint.Count -eq 0) {
      $CertSubject += '*';
   }

   foreach ($Cert in $CertStoreCerts) {
      $data = @{
         Thumbprint = $Cert.Thumbprint;
         Cert       = $Cert;
      }
      if (($CertThumbprint -Contains '*') -Or ($CertThumbprint -Contains $Cert.Thumbprint)) {
         $CertStoreArray += $data;
         continue;
      }

      foreach ($Subject in $CertSubject) {
        if ($Subject -eq '*' -Or ($Cert.Subject -Like $Subject)) {
            $CertStoreArray += $data;
            break;
         }
      }
   }

   return $CertStoreArray;
}

# Content from: plugins\Invoke-IcingaCheckUNCPath.psm1

    [string]$DisplayName = $Path;

    if ([string]::IsNullOrEmpty($DisplayAlias) -eq $FALSE) {
        $DisplayName = $DisplayAlias;
    }

    $Warning       = Convert-IcingaPluginThresholds $Warning;
    $Critical      = Convert-IcingaPluginThresholds $Critical;
    $WarningTotal  = Convert-IcingaPluginThresholds $WarningTotal;
    $CriticalTotal = Convert-IcingaPluginThresholds $CriticalTotal;
    $PathData      = Get-IcingaUNCPathSize -Path $Path;
    $CheckPackage  = New-IcingaCheckPackage -Name ([string]::Format('{0} Share', $DisplayName)) -OperatorAnd -Verbose $Verbosity;

    $ShareFree = New-IcingaCheck `
        -Name ([string]::Format('Free Space', $DisplayName)) `
        -Value $PathData.ShareFree `
        -Unit 'B' `
        -LabelName ([string]::Format('share_free_bytes', $PathData.ShareFree));

    $ShareSize = New-IcingaCheck `
        -Name ([string]::Format('Size', $DisplayName)) `
        -Value $PathData.ShareSize `
        -Unit 'B' `
        -LabelName ([string]::Format('share_size', $PathData.ShareSize));

    if ($Warning.Unit -ne '%') {
        $ShareFree.WarnOutOfRange($Warning.Value) | Out-Null;
    }
    if ($Critical.Unit -ne '%') {
        $ShareFree.CritOutOfRange($Critical.Value) | Out-Null;
    }

    $ShareFreePercent = New-IcingaCheck `
        -Name ([string]::Format('Free %', $DisplayName)) `
        -Value $PathData.ShareFreePercent `
        -Unit '%' `
        -LabelName ([string]::Format('share_free_percent', $PathData.ShareFreePercent));

    if ($Warning.Unit -eq '%') {
        $ShareFreePercent.WarnOutOfRange($Warning.Value) | Out-Null;
    }
    if ($Critical.Unit -eq '%') {
        $ShareFreePercent.CritOutOfRange($Critical.Value) | Out-Null;
    }

    $TotalFree = New-IcingaCheck `
        -Name ([string]::Format('Total Free', $DisplayName)) `
        -Value $PathData.TotalFree `
        -Unit 'B' `
        -LabelName ([string]::Format('total_free_bytes', $PathData.TotalFree));

    $TotalFree.WarnOutOfRange($WarningTotal.Value).CritOutOfRange($CriticalTotal.Value) | Out-Null;

    $CheckPackage.AddCheck($ShareFree);
    $CheckPackage.AddCheck($ShareSize);
    $CheckPackage.AddCheck($ShareFreePercent);
    $CheckPackage.AddCheck($TotalFree);

    return (New-IcingaCheckResult -Name ([string]::Format('{0} Share', $DisplayName)) -Check $CheckPackage -NoPerfData $NoPerfData -Compile);

