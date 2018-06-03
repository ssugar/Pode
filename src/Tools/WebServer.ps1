function Engine
{
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Engine,

        [Parameter()]
        [scriptblock]
        $ScriptBlock = $null
    )

    $PodeSession.ViewEngine = @{
        'Extension' = $Engine.ToLowerInvariant();
        'Script' = $ScriptBlock;
    }
}

function Start-WebServer
{
    param (
        [switch]
        $Https
    )

    try
    {
        # create the listener on http and/or https
        $listener = New-Object System.Net.HttpListener
        $protocol = 'http'
        if ($Https) {
            $protocol = 'https'
        }

        $listener.Prefixes.Add("$($protocol)://*:$($PodeSession.Port)/")

        # start listener
        $listener.Start()

        # state where we're running
        Write-Host "Listening on $($protocol)://localhost:$($PodeSession.Port)/" -ForegroundColor Yellow

        # loop for http request
        while ($listener.IsListening)
        {
            # get request and response
            $task = $listener.GetContextAsync()
            while (!$task.IsCompleted) {
                Test-CtrlCPressed
            }

            $context = $task.Result
            $session = @{
                'Request' = $context.Request;
                'Response' = $context.Response;
                'Data' = $null;
                'Query' = $null;
                'Parameters' = $null;
                'ViewEngine' = $null;
                'FilePath' = $null;
            }

            # get url path and method
            $close = $true
            $path = ($session.Request.RawUrl -isplit "\?")[0]
            $method = $session.Request.HttpMethod.ToLowerInvariant()

            # check to see if the path is a file, so we can check the public folder
            if ((Get-PodeContentType -Extension (Get-FileExtension -Path $path) -DefaultIsNull) -ne $null) {
                $close = $false
                $session.ViewEngine = $PodeSession.ViewEngine
                $session.FilePath = (Join-Path 'public' $path)
                Add-SessionRunspace -Session $session
            }

            else {
                $PodeSession.Web = $session

                # ensure the path has a route
                $route = Get-PodeRoute -HttpMethod $method -Route $path
                if ($route -eq $null -or $route.Logic -eq $null) {
                    status 404
                }

                # run the scriptblock
                else {
                    # read and parse any post data
                    $stream = $session.Request.InputStream
                    $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList $stream, $session.Request.ContentEncoding
                    $data = $reader.ReadToEnd()
                    $reader.Close()

                    switch ($session.Request.ContentType) {
                        { $_ -ilike '*/json' } {
                            $data = ($data | ConvertFrom-Json)
                        }

                        { $_ -ilike '*/xml' } {
                            $data = ($data | ConvertFrom-Xml)
                        }

                        { $_ -ilike '*/csv' } {
                            $data = ($data | ConvertFrom-Csv)
                        }
                    }

                    # set session data
                    $PodeSession.Web.Data = $data
                    $PodeSession.Web.Query = $session.Request.QueryString
                    $PodeSession.Web.Parameters = $route.Parameters

                    # invoke route
                    Invoke-Command -ScriptBlock $route.Logic -ArgumentList $PodeSession.Web
                }
            }

            # close response stream (check if exists, as closing the writer closes this stream on unix)
            if ($close -and $session.Response.OutputStream) {
                try {
                    $session.Response.OutputStream.Close()
                }
                catch [exception] {
                    if (Test-ValidNetworkFailure $_.Exception) {
                        return
                    }

                    throw $_.Exception
                }
                finally {
                    $session.Response.OutputStream.Dispose()
                }
            }
        }
    }
    finally {
        if ($listener -ne $null) {
            $listener.Stop()
        }
    }
}