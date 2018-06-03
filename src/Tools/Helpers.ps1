
# read in the content from a dynamic pode file and invoke its content
function ConvertFrom-PodeFile
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Content,

        [Parameter()]
        $Data = @{}
    )

    # if we have data, then setup the data param
    if (!(Test-Empty $Data)) {
        $Content = "param(`$data)`nreturn `"$($Content -replace '"', '``"')`""
    }
    else {
        $Content = "return `"$($Content -replace '"', '``"')`""
    }

    # invoke the content as a script to generate the dynamic content
    $Content = (Invoke-Command -ScriptBlock ([scriptblock]::Create($Content)) -ArgumentList $Data)
    return $Content
}

function Get-Type
{
    param (
        [Parameter()]
        $Value
    )

    if ($Value -eq $null) {
        return $null
    }

    return @{
        'Name' = $Value.GetType().Name.ToLowerInvariant();
        'BaseName' = $Value.GetType().BaseType.Name.ToLowerInvariant();
    }
}

function Test-Empty
{
    param (
        [Parameter()]
        $Value
    )

    $type = Get-Type $Value
    if ($type -eq $null) {
        return $true
    }

    if ($type.Name -ieq 'string') {
        return [string]::IsNullOrWhiteSpace($Value)
    }

    if ($type.Name -ieq 'hashtable') {
        return $Value.Count -eq 0
    }

    switch ($type.BaseName) {
        'valuetype' {
            return $false
        }

        'array' {
            return (($Value | Measure-Object).Count -eq 0 -or $Value.Count -eq 0)
        }
    }

    return ([string]::IsNullOrWhiteSpace($Value) -or ($Value | Measure-Object).Count -eq 0 -or $Value.Count -eq 0)
}

function Test-IsUnix
{
    return $PSVersionTable.Platform -ieq 'unix'
}

function Test-IsPSCore
{
    return $PSVersionTable.PSEdition -ieq 'core'
}

function Add-PodeRunspace
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [scriptblock]
        $ScriptBlock,

        [Parameter()]
        $Parameters
    )

    $ps = [powershell]::Create()
    $ps.RunspacePool = $PodeSession.RunspacePool
    $ps.AddScript($ScriptBlock) | Out-Null

    if (!(Test-Empty $Parameters)) {
        $Parameters.Keys | ForEach-Object {
            $ps.AddParameter($_, $Parameters[$_]) | Out-Null
        }
    }

    $PodeSession.Runspaces += @{
        'Runspace' = $ps;
        'Status' = $ps.BeginInvoke();
        'Stopped' = $false;
    }
}

function Close-PodeRunspaces
{
    $PodeSession.Runspaces | Where-Object { !$_.Stopped } | ForEach-Object {
        $_.Runspace.Dispose()
        $_.Stopped = $true
    }

    if (!$PodeSession.RunspacePool.IsDisposed) {
        $PodeSession.RunspacePool.Close()
        $PodeSession.RunspacePool.Dispose()
    }
}

function Test-CtrlCPressed
{
    if ([Console]::IsInputRedirected -or ![Console]::KeyAvailable) {
        return
    }

    $key = [Console]::ReadKey($true)

    if ($key.Key -ieq 'c' -and $key.Modifiers -band [ConsoleModifiers]::Control) {
        Write-Host 'Terminating...' -NoNewline
        Close-PodeRunspaces
        Write-Host " Done" -ForegroundColor Green
        exit 0
    }
}

function Get-FileExtension
{
    param (
        [Parameter()]
        [string]
        $Path,

        [switch]
        $TrimPeriod
    )

    $ext = [System.IO.Path]::GetExtension($Path)

    if ($TrimPeriod) {
        $ext = $ext.Trim('.')
    }

    return $ext
}

function Get-FileName
{
    param (
        [Parameter()]
        [string]
        $Path,

        [switch]
        $WithoutExtension
    )

    if ($WithoutExtension) {
        return [System.IO.Path]::GetFileNameWithoutExtension($Path)
    }

    return [System.IO.Path]::GetFileName($Path)
}

function Test-ValidNetworkFailure
{
    param (
        [Parameter()]
        $Exception
    )

    if ($Exception.Message -ilike '*name is no longer available*') {
        return $true
    }

    if ($Exception.Message -ilike '*nonexistent network connection*') {
        return $true
    }

    $Exception | Out-Default
    return $false
}

<#
# Sourced and editted from https://davewyatt.wordpress.com/2014/04/06/thread-synchronization-in-powershell/
#>
function Lock
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [object]
        $InputObject,

        [Parameter(Mandatory=$true)]
        [scriptblock]
        $ScriptBlock
    )

    if ($InputObject.GetType().IsValueType) {
        throw 'Cannot lock value types'
    }

    $locked = $false

    try {
        [System.Threading.Monitor]::Enter($InputObject.SyncRoot)
        $locked = $true
        . $ScriptBlock
    }
    finally {
        if ($locked) {
            [System.Threading.Monitor]::Exit($InputObject.SyncRoot)
        }
    }
}

function Stopwatch
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter(Mandatory=$true)]
        [scriptblock]
        $ScriptBlock
    )

    try {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        . $ScriptBlock
    }
    finally {
        $watch.Stop()
        Out-Default -InputObject "[Stopwatch]: $($watch.Elapsed) [$($Name)]"
    }
}