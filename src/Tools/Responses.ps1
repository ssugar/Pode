# write data to main http response
function Write-ToResponse
{
    param (
        [Parameter()]
        $Value,

        [Parameter()]
        [string]
        $ContentType = $null
    )

    if (Test-Empty $Value) {
        return
    }

    $res = $PodeSession.Web.Response

    #put estimated response size into an aproxsize variable for logging
    $PodeSession.ResponseSize = [System.Text.Encoding]::UTF8.GetByteCount($Value)

    if ($res -eq $null -or $res.OutputStream -eq $null -or !$res.OutputStream.CanWrite) {
        return
    }

    if (!(Test-Empty $ContentType)) {
        $res.ContentType = $ContentType
    }

    try {
        if ((Get-Type $Value).Name -ieq 'string') {
            $writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList $res.OutputStream
            $writer.WriteLine([string]$Value)
            $writer.Flush()
        }
        else {
            $memory = New-Object -TypeName System.IO.MemoryStream
            $memory.Write($Value, 0, $Value.Length)
            $memory.WriteTo($res.OutputStream)
            $memory.Flush()
        }
    }
    catch [exception] {
        if (Test-ValidNetworkFailure $_.Exception) {
            return
        }

        throw $_.Exception
    }
}

function Write-ToResponseFromFile
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path
    )

    # if the file doesnt exist then just fail on 404
    if (!(Test-Path $Path)) {
        status 404
        return
    }

    # are we dealing with a dynamic file for the view engine?
    $ext = Get-FileExtension -Path $Path -TrimPeriod
    if ((Test-Empty $ext) -or $ext -ine $PodeSession.ViewEngine.Extension) {
        if (Test-IsPSCore) {
            $content = Get-Content -Path $Path -Raw -AsByteStream
        }
        else {
            $content = Get-Content -Path $Path -Raw -Encoding byte
        }

        Write-ToResponse -Value $content -ContentType (Get-PodeContentType -Extension $ext)
        return
    }

    # generate dynamic content
    $content = [string]::Empty

    switch ($ext.ToLowerInvariant())
    {
        'pode' {
            $content = Get-Content -Path $Path -Raw -Encoding utf8
            $content = ConvertFrom-PodeFile -Content $content
        }

        default {
            if ($PodeSession.ViewEngine.Script -ne $null) {
                $content = Invoke-Command -ScriptBlock $PodeSession.ViewEngine.Script -ArgumentList $Path
            }
        }
    }

    $ext = Get-FileExtension -Path (Get-FileName -Path $Path -WithoutExtension) -TrimPeriod
    Write-ToResponse -Value $content -ContentType (Get-PodeContentType -Extension $ext)
}

function Status
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [int]
        $Code,

        [Parameter()]
        [string]
        $Description
    )

    $PodeSession.Web.Response.StatusCode = $Code
    $PodeSession.Web.Response.StatusDescription = $Description
}

function Write-JsonResponse
{
    [obsolete("Use 'json' instead")]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $NoConvert
    )

    json -Value $Value
}

function Write-JsonResponseFromFile
{
    [obsolete("Use 'json' instead")]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path
    )

    json -Value $Path -File
}

function Json
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $File
    )

    if ($File) {
        if (!(Test-Path $Value)) {
            status 404
            return
        }
        else {
            $Value = Get-Content -Path $Value -Encoding utf8
        }
    }
    elseif ((Get-Type $Value).Name -ine 'string') {
        $Value = ($Value | ConvertTo-Json -Depth 10 -Compress)
    }

    Write-ToResponse -Value $Value -ContentType 'application/json; charset=utf-8'
}

function Csv
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $File
    )

    if ($File) {
        if (!(Test-Path $Value)) {
            status 404
            return
        }
        else {
            $Value = Get-Content -Path $Value -Encoding utf8
        }
    }
    elseif ((Get-Type $Value).Name -ine 'string') {
        $Value = ($Value | ConvertTo-Csv -Delimiter ',')
    }

    Write-ToResponse -Value $Value -ContentType 'text/csv; charset=utf-8'
}

function Write-XmlResponse
{
    [obsolete("Use 'xml' instead")]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $NoConvert
    )

    xml -Value $Value
}

function Write-XmlResponseFromFile
{
    [obsolete("Use 'xml' instead")]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path
    )

    xml -Value $Path -File
}

function Xml
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $File
    )

    if ($File) {
        if (!(Test-Path $Value)) {
            status 404
            return
        }
        else {
            $Value = Get-Content -Path $Value -Encoding utf8
        }
    }
    elseif ((Get-Type $Value).Name -ine 'string') {
        $Value = ($Value | ConvertTo-Xml -Depth 10)
    }

    Write-ToResponse -Value $Value -ContentType 'application/xml; charset=utf-8'
}

function Write-HtmlResponse
{
    [obsolete("Use 'html' instead")]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $NoConvert
    )

    html -Value $Value
}

function Write-HtmlResponseFromFile
{
    [obsolete("Use 'html' instead")]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path
    )

    html -Value $Path -File
}

function Html
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $File
    )

    if ($File) {
        if (!(Test-Path $Value)) {
            status 404
            return
        }
        else {
            $Value = Get-Content -Path $Value -Encoding utf8
        }
    }
    elseif ((Get-Type $Value).Name -ine 'string') {
        $Value = ($Value | ConvertTo-Html)
    }

    Write-ToResponse -Value $Value -ContentType 'text/html; charset=utf-8'
}

# include helper to import the content of a view into another view
function Include
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter()]
        $Data = @{}
    )

    # add view engine extension
    $ext = Get-FileExtension -Path $Path
    $hasExt = ![string]::IsNullOrWhiteSpace($ext)
    if (!$hasExt) {
        $Path += ".$($PodeSession.ViewEngine.Extension)"
    }

    # only look in the view directory
    $Path = (Join-Path 'views' $Path)
    if (!(Test-Path $Path)) {
        throw "File not found at path: $($Path)"
    }

    # run any engine logic
    $engine = $PodeSession.ViewEngine.Extension
    if ($hasExt) {
        $engine = $ext.Trim('.')
    }

    $content = [string]::Empty

    switch ($engine.ToLowerInvariant())
    {
        'html' {
            $content = Get-Content -Path $Path -Raw -Encoding utf8
        }

        'pode' {
            $content = Get-Content -Path $Path -Raw -Encoding utf8
            $content = ConvertFrom-PodeFile -Content $content -Data $Data
        }

        default {
            if ($PodeSession.ViewEngine.Script -ne $null) {
                $content = Invoke-Command -ScriptBlock $PodeSession.ViewEngine.Script -ArgumentList $Path, $Data
            }
        }
    }

    return $content
}

function  Write-ViewResponse
{
    [obsolete("Use 'view' instead")]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path,

        [Parameter()]
        $Data = @{}
    )

    view -Path $Path -Data $Data
}

function View
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path,

        [Parameter()]
        $Data = @{}
    )

    # default data if null
    if ($Data -eq $null) {
        $Data = @{}
    }

    # add path to data as "pagename" - unless key already exists
    if (!$Data.ContainsKey('pagename')) {
        $Data['pagename'] = $Path
    }

    # add view engine extension
    $ext = Get-FileExtension -Path $Path
    $hasExt = ![string]::IsNullOrWhiteSpace($ext)
    if (!$hasExt) {
        $Path += ".$($PodeSession.ViewEngine.Extension)"
    }

    # only look in the view directory
    $Path = (Join-Path 'views' $Path)
    if (!(Test-Path $Path)) {
        status 404
        return
    }

    # run any engine logic
    $engine = $PodeSession.ViewEngine.Extension
    if ($hasExt) {
        $engine = $ext.Trim('.')
    }

    $content = [string]::Empty

    switch ($engine.ToLowerInvariant())
    {
        'html' {
            $content = Get-Content -Path $Path -Raw -Encoding utf8
        }

        'pode' {
            $content = Get-Content -Path $Path -Raw -Encoding utf8
            $content = ConvertFrom-PodeFile -Content $content -Data $Data
        }

        default {
            if ($PodeSession.ViewEngine.Script -ne $null) {
                $content = Invoke-Command -ScriptBlock $PodeSession.ViewEngine.Script -ArgumentList $Path, $Data
            }
        }
    }

    html -Value $content
}

# write data to tcp stream
function Write-ToTcpStream
{
    [obsolete("Use 'tcp write <msg>' instead")]
    param (
        [Parameter()]
        [ValidateNotNull()]
        [string]
        $Message,

        [Parameter()]
        $Client
    )

    if ($Client -eq $null) {
        $Client = $PodeSession.Tcp.Client
    }

    tcp write $Message -Client $Client
}

function Read-FromTcpStream
{
    [obsolete("Use 'tcp read' instead")]
    param (
        [Parameter()]
        $Client
    )

    if ($Client -eq $null) {
        $Client = $PodeSession.Tcp.Client
    }

    return (tcp read -Client $Client)
}

function Tcp
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet('write', 'read')]
        [string]
        $Action,

        [Parameter()]
        [string]
        $Message,

        [Parameter()]
        $Client
    )

    if ($client -eq $null) {
        $client = $PodeSession.Tcp.Client
    }

    switch ($Action.ToLowerInvariant())
    {
        'write' {
            $stream = $client.GetStream()
            $encoder = New-Object System.Text.ASCIIEncoding
            $buffer = $encoder.GetBytes("$($Message)`r`n")
            $stream.Write($buffer, 0, $buffer.Length)
            $stream.Flush()
        }

        'read' {
            $bytes = New-Object byte[] 8192
            $stream = $client.GetStream()
            $encoder = New-Object System.Text.ASCIIEncoding
            $bytesRead = $stream.Read($bytes, 0, 8192)
            $message = $encoder.GetString($bytes, 0, $bytesRead)
            return $message
        }
    }
}