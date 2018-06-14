function New-PodeSession
{
    param (
        [int]
        $Port = 0
    )

    # basic session object
    $session = New-Object -TypeName psobject |
        Add-Member -MemberType NoteProperty -Name Routes -Value $null -PassThru |
        Add-Member -MemberType NoteProperty -Name Handlers -Value $null -PassThru |
        Add-Member -MemberType NoteProperty -Name Port -Value $Port -PassThru | 
        Add-Member -MemberType NoteProperty -Name ViewEngine -Value $null -PassThru | 
        Add-Member -MemberType NoteProperty -Name Web -Value @{} -PassThru | 
        Add-Member -MemberType NoteProperty -Name Smtp -Value @{} -PassThru | 
        Add-Member -MemberType NoteProperty -Name Tcp -Value @{} -PassThru |
        Add-Member -MemberType NoteProperty -Name Timers -Value $null -PassThru |
        Add-Member -MemberType NoteProperty -Name RunspacePool -Value $null -PassThru |
        Add-Member -MemberType NoteProperty -Name Runspaces -Value $null -PassThru |
        Add-Member -MemberType NoteProperty -Name CurrentPath -Value $pwd -PassThru

    # session engine for rendering views
    $session.ViewEngine = @{
        'Extension' = 'html';
        'Script' = $null;
    }

    # routes for pages and api
    $session.Routes = @{
        'delete' = @{};
        'get' = @{};
        'head' = @{};
        'merge' = @{};
        'options' = @{};
        'patch' = @{};
        'post' = @{};
        'put' = @{};
        'trace' = @{};
    }

    # handlers for tcp
    $session.Handlers = @{
        'tcp' = $null;
        'smtp' = $null;
    }

    # async timers
    $session.Timers = @{}

    # pode module path
    $modulePath = (Get-Module -Name Pode).Path

    # session state
    $state = [initialsessionstate]::CreateDefault()
    $state.ImportPSModule($modulePath)
    $counter = 0

    $variables = @(
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'timers', $session.Timers, $null),
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'currentdir', $session.CurrentPath, $null),
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'counter', $counter, $null)
    )

    $variables | ForEach-Object {
        $state.Variables.Add($_)
    }

    # runspace and pool
    $session.Runspaces = @()
    $session.RunspacePool = [runspacefactory]::CreateRunspacePool(1, 2, $state, $Host)
    $session.RunspacePool.Open()

    return $session
}

function Add-ContentResponseRunspace
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Session
    )

    $script = {
        param (
            [Parameter(Mandatory=$true)]
            $Session
        )

        Set-Location $currentdir

        $PodeSession = @{
            'Web' = $Session;
            'ViewEngine' = $Session.ViewEngine;
        }

        Write-ToResponseFromFile -Path $Session.FilePath
        dispose $Session.Response.OutputStream -Close -CheckNetwork
    }

    Add-PodeRunspace -ScriptBlock $script -Parameters @{ 'Session' = $Session; }
}

function Add-ServerLogRunspace
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Session
    )

    $script = {
        param (
            [Parameter(Mandatory=$true)]
            $Session
        )

        $logEntry = New-Object -TypeName PSCustomObject
        $logEntry | Add-Member -MemberType NoteProperty -Name "clientIP" -Value ($Session.Web.Request.RemoteEndPoint.ToString().Split(':'))[0]
        $logEntry | Add-Member -MemberType NoteProperty -Name "rfcUserIdentifier" -Value "-"
        $logEntry | Add-Member -MemberType NoteProperty -Name "userId" -Value "-"
        $logEntry | Add-Member -MemberType NoteProperty -Name "dateTime" -Value "[$(Get-Date -UFormat "%d/%b/%Y:%H:%M:%S %Z")]"
        $logEntry | Add-Member -MemberType NoteProperty -Name "requestLine" -Value "`"$($Session.Web.Request.HttpMethod) $($Session.Web.Request.RawUrl) HTTP/$($Session.Web.Request.ProtocolVersion)`""
        $logEntry | Add-Member -MemberType NoteProperty -Name "responseStatus" -Value "$($Session.Web.Response.StatusCode)"
        $logEntry | Add-Member -MemberType NoteProperty -Name "responseLength" -Value "$($Session.Web.Response.ContentLength64)"
        $logEntry | Add-Member -MemberType NoteProperty -Name "requestUrlReferrer" -Value "`"$($Session.Web.Request.UrlReferrer)`""
        $logEntry | Add-Member -MemberType NoteProperty -Name "userAgent" -Value "`"$($Session.Web.Request.UserAgent)`""

        write-host "$($logEntry.clientIP) $($logEntry.rfcUserIdentifier) $($logEntry.userId) $($logEntry.dateTime) $($logEntry.requestLine) $($logEntry.responseStatus) $($logEntry.responseLength) $($logEntry.requestUrlReferrer) $($logEntry.userAgent)"
    }
    Add-PodeRunspace -ScriptBlock $script -Parameters @{ 'Session' = $Session; }
}