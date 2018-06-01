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
        Add-Member -MemberType NoteProperty -Name Sessions -Value $null -PassThru |
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

    # async requests
    $session.Sessions = New-Object System.Collections.ArrayList

    # pode module path
    $modulePath = (Get-Module -Name Pode).Path

    # session state
    $state = [initialsessionstate]::CreateDefault()
    $variables = @(
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'timers', $session.Timers, $null),
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sessions', $session.Sessions, $null),
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'module', $modulePath, $null),
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'currentdir', $session.CurrentPath, $null)
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

function Start-SessionRunspace
{
    $script = {
        Import-Module $module
        Set-Location $currentdir

        while ($true)
        {
            if (($sessions | Measure-Object).Count -eq 0) {
                Start-Sleep -Seconds 1
                continue
            }

            $s = $sessions[0]
            $sessions.RemoveAt(0) | Out-Null

            $PodeSession = @{
                'Web' = $s;
                'ViewEngine' = $s.ViewEngine;
            }

            Write-ToResponseFromFile -Path $s.FilePath

            if ($s.Response.OutputStream) {
                $s.Response.OutputStream.Close()
            }
        }
    }

    Add-PodeRunspace $script
}