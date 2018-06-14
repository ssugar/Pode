function Server
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [scriptblock]
        $ScriptBlock,

        [Parameter()]
        [ValidateNotNull()]
        [int]
        $Port = 0,

        [Parameter()]
        [ValidateNotNull()]
        [int]
        $Interval = 0,

        [switch]
        $Smtp,

        [switch]
        $Tcp,

        [switch]
        $Https,

        [switch]
        $Log
    )

    # if smtp is passed, and no port - force port to 25
    if ($Port -eq 0 -and $Smtp) {
        $Port = 25
    }

    # validate port passed
    if ($Port -le 0) {
        throw "Port cannot be negative: $($Port)"
    }

    try {
        # create session object
        $PodeSession = New-PodeSession -Port $Port

        # set it so ctrl-c can terminate
        [Console]::TreatControlCAsInput = $true

        # run the logic
        & $ScriptBlock

        # start runspace for timers
        Start-TimerRunspace

        # run logic for a smtp server
        if ($Smtp) {
            Start-SmtpServer
        }

        # run logic for a tcp server
        elseif ($Tcp) {
            Start-TcpServer
        }

        # if there's a port, run a web server
        elseif ($Port -gt 0) {
            if($Log){
                Start-WebServer -Https:$Https -Log
            } else {
                Start-WebServer -Https:$Https
            }
        }

        # otherwise, run logic
        else {
            # are we running this logic in an interval loop?
            if ($Interval -gt 0) {
                Write-Host "Looping logic every $($Interval)secs" -ForegroundColor Yellow

                while ($true) {
                    Test-CtrlCPressed
                    Start-Sleep -Seconds $Interval
                    & $ScriptBlock
                }
            }
        }
    }
    finally {
        # clean the runspaces
        Close-PodeRunspaces

        # clean the session
        $PodeSession = $null
    }
}