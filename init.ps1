#region executable code
# set the nuget download uri
$downloadLink = "https://www.nuget.org/api/v2/package/Microsoft.SqlServer.TransactSql.ScriptDom/150.4573.2"

# set our expected dll path
$dllPath = "$($PSScriptRoot)/Microsoft.SqlServer.TransactSql.ScriptDom.dll"
if (-not (Test-Path $dllPath)) {
    Write-Verbose "Detected missing ScriptDom binary, downloading from nuget..."
    $outputFile = "$($PSScriptRoot)/Microsoft.SqlServer.TransactSql.ScriptDom.zip"
    Invoke-WebRequest -UseBasicParsing -Uri $downloadLink -OutFile $outputFile -ErrorAction Stop
    # extract the zip
    $unzipPath = "$($PSScriptRoot)/Microsoft.SqlServer.TransactSql.ScriptDom"
    Expand-Archive -Path $outputFile -DestinationPath $unzipPath -Force -ErrorAction Stop
    # copy the dll we just expanded into our root path
    Copy-Item -Path "$($unzipPath)/lib/netstandard2.0/Microsoft.SqlServer.TransactSql.ScriptDom.dll" -Destination $PSScriptRoot -Force

    # clean up
    Remove-Item -Path $outputFile
    Remove-Item -Path $unzipPath -Force -Recurse
}

# now we can scope in the dll for usage in the module
try {
    Write-Verbose "Importing dll from path '$($dllPath)'"
    Add-Type -Path $dllPath -ErrorAction Stop
}
catch {
    throw "An error occured during dll import.`nFull Error: $($_ | Out-String)" # we want to terminate any further process
}
#endregion