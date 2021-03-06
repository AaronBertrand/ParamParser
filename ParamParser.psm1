#region classes
class Visitor: Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragmentVisitor 
{
    $Results = [System.Collections.ArrayList]@();

    $ProcedureStatements = @("CreateOrAlterProcedureStatement",
        "CreateProcedureStatement", "AlterProcedureStatement");

    $FunctionStatements = @("CreateOrAlterFunctionStatement",
        "CreateFunctionStatement", "AlterFunctionStatement");

    $ModuleTokenTypes = (@("ProcedureParameter", "ProcedureReference"));

    $CommentTokenTypes = (@("MultilineComment", "SingleLineComment"));

    [PSCustomObject]GetResultObject ([string]$StatementType) {
      return ([PSCustomObject]@{
          Id            = $this.Counter
          ModuleId      = $this.ModuleId
          ObjectName    = $this.ObjectName
          StatementType = $StatementType
          ParamId       = $this.ParamId
          ParamName     = [string]::Empty
          DataType      = [string]::Empty
          DefaultValue  = [string]::Empty
          IsOutput      = $false
          IsReadOnly    = $false
          Source        = [string]::Empty
      })
    }

    hidden [int]$Counter  = 0;
    hidden [int]$ModuleId = 0;
    hidden [int]$ParamId  = 1;
    hidden [string]$Source = [string]::Empty

    [void]Visit ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment] $fragment)
    {
        $fragmentType = $fragment.GetType().Name;

        # if this is an injected PRINT statement, it contains the source for this statement
        if ($fragmentType -eq "StringLiteral")
        {
            $token = $fragment.ScriptTokenStream[$fragment.FirstTokenIndex]
            if ($token.Text -like "'ParamParser.Source*")
            {
                $this.Source = $token.Text.Substring(21, $token.Text.Length-22)
            }
        }

        if ($fragmentType -iin ($this.ProcedureStatements + $this.FunctionStatements + $this.ModuleTokenTypes))
        {
            $result = $this.GetResultObject($fragmentType);

            # if body of procedure or function, increase the module # and reset param count
            if ($fragmentType -iin ($this.ProcedureStatements + $this.FunctionStatements))
            {
                $this.ModuleId++;
                $this.ParamId      = 1;
                $result.ParamId    = $null;
                $result.IsOutput   = $null;
                $result.IsReadOnly = $null;
                $result.Source = $this.Source;
            }

            # for any parameter or procedure name, need to loop through all the tokens
            # in the fragment to build up the name, data type, default, etc.
            if ($fragmentType -iin $this.ModuleTokenTypes)
            {
                $seenEquals = $false;
                $isOutputOrReadOnly = $false;

                for ($i = $fragment.FirstTokenIndex; $i -le $fragment.LastTokenIndex; $i++)
                {
                    $token = $fragment.ScriptTokenStream[$i];
                    if ($token.TokenType -notin (@("As") + $this.CommentTokenTypes))
                    {
                        if ($fragmentType -eq "ProcedureParameter")
                        {
                            if ($token.TokenType -eq "Identifier" -and ($token.Text -iin ("OUT", "OUTPUT", "READONLY")))
                            {
                                $isOutputOrReadOnly = $true;
                                if ($token.Text -ieq "READONLY")
                                {
                                    $result.IsReadOnly = $true;
                                }
                                else 
                                {
                                    $result.IsOutput = $true;
                                }
                            }

                            if (!$seenEquals)
                            {
                                if ($token.TokenType -eq "EqualsSign") 
                                { 
                                    $seenEquals = $true; 
                                }
                                else 
                                { 
                                    if ($token.TokenType -eq "Variable") 
                                    {
                                      $this.ParamId++;
                                      $result.ParamName = $token.Text; 
                                    }
                                    else
                                    {
                                        if (!$isOutputOrReadOnly)
                                        {
                                            $result.DataType += $token.Text; 
                                        }
                                    }
                                }
                            }
                            else
                            { 
                                if ($token.TokenType -ne "EqualsSign" -and !$isOutputOrReadOnly)
                                {
                                    $result.DefaultValue += $token.Text;
                                }
                            }
                        }
                        else 
                        {
                            $result.ObjectName += $token.Text.Trim(); 
                        }
                    }
                }
            }

            # tedious: need to loop through function to build the object name
            # no FunctionReference but there will be multiple identifiers
            if ($fragmentType -iin ($this.FunctionStatements)) 
            {
                $seenObject = $false;
                $seenEndOfFirstObject = $false;
                for ($i = $fragment.FirstTokenIndex; $i -le $fragment.LastTokenIndex; $i++)
                {
                    $token = $fragment.ScriptTokenStream[$i];
                    if ($token.TokenType -notin (@("WhiteSpace") + $this.CommentTokenTypes))
                    {
                        if ($seenObject -and $token.TokenType -notin ("Dot","Identifier","QuotedIdentifier"))
                        {
                            $seenEndOfFirstObject = $true;
                        }
                        if ($token.TokenType -in ("Dot","Identifier","QuotedIdentifier") -and !$seenEndOfFirstObject)
                        {
                            $seenObject = $true;
                            $result.ObjectName += $token.Text.Trim();
                        }
                    } 
                } 
            }            
            $result.DataType = $result.DataType.TrimStart();
            $result.DefaultValue = $result.DefaultValue.TrimStart();
            $this.Results.Add($result);
            $this.Counter++;
        }
    }
}
#endregion

#region functions
<#
.SYNOPSIS


.DESCRIPTION
Long description

.PARAMETER Script
Parameter description

.PARAMETER File
Parameter description

.PARAMETER Directory
Parameter description

.PARAMETER ServerInstance
Parameter description

.PARAMETER Database
Parameter description

.PARAMETER AuthenticationMode
Parameter description

.PARAMETER GridView
Parameter description

.PARAMETER Console
Parameter description

.PARAMETER LogToDatabase
Parameter description

.PARAMETER LogToDBAuthenticationMode
Parameter description

.EXAMPLE
$password = ConvertTo-SecureString -AsPlainText -Force -String 'secret123'
$creds = New-Object -TypeName PSCredential -ArgumentList 'myUsername', $password
Get-ParsedParams -ServerInstance "localhost" -Database "msdb" -AuthenticationMode SQL -SqlCredential $creds

.EXAMPLE
Get-ParsedParams -ServerInstance "localhost" -Database "msdb" -AuthenticationMode SQL -SqlCredential (Get-Credential -Username 'myUsername')

.NOTES
General notes
#>
Function Get-ParsedParams
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "Script")]
        [ValidateNotNullOrEmpty()]
        [string]$Script,
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "File")]
        [ValidateScript({$PSItem | ForEach-Object {
                ((Test-Path $_ -PathType Leaf) -and ([System.IO.Path]::GetExtension($_) -ieq ".sql"))
            }
        })]
        [string[]]$File,
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "Directory")]
        [ValidateScript({$PSItem | ForEach-Object {
                (Test-Path $_ -PathType Container)
            }
        })]
        [string[]]$Directory,
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "SQLServer")]
        [ValidateNotNullOrEmpty()]
        [string[]]$ServerInstance,
        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "SQLServer")]
        [ValidateNotNullOrEmpty()]
        [string[]]$Database,
        [Parameter(Position = 2, Mandatory = $false, ParameterSetName = "SQLServer")]
        [ValidateSet("SQL", "Windows")]
        [string]$AuthenticationMode = "Windows",
        [Parameter(Position = 3, Mandatory = $false)]
        [switch]$GridView,
        [Parameter(Position = 4, Mandatory = $false)]
        [switch]$Console, # currently logs to console whether you like it or not
        [Parameter(Position = 5, Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [switch]$LogToDatabase,
        [Parameter(Position = 6, Mandatory = $false)]
        [ValidateSet("SQL", "Windows")]
        [string]$LogToDBAuthenticationMode = "Windows"
    )

    #region dynamic params
    DynamicParam {
        $runtimeDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        # here we inject a dynamic parameter based on whether SQL auth was specified or not.
        # we use a PSCredential object and set to mandatory. If the user doesn't supply, this has the nice
        # behavior of prompting them with a nice dialog box
        if ($AuthenticationMode -eq "SQL") {  
            $parameterName = 'SqlCredential'
            $attributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $paramAttribute = New-Object System.Management.Automation.ParameterAttribute
            $paramAttribute.Mandatory = $true
            $paramAttribute.Position = 7
            $attributeCollection.Add($paramAttribute)
            $validateAttribute = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute
            $attributeCollection.Add($validateAttribute)
            $runtimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter($parameterName, [PSCredential], $attributeCollection)
            $runtimeDictionary.Add($parameterName, $runtimeParam)
        }
        # we also inject the requirements for the logto database and instance
        if ($LogToDatabase.IsPresent) {
            $parameterName = 'LogToDBServerInstance'
            $attributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $paramAttribute = New-Object System.Management.Automation.ParameterAttribute
            $paramAttribute.Mandatory = $true
            $paramAttribute.Position = 8
            $attributeCollection.Add($paramAttribute)
            $validateAttribute = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute
            $attributeCollection.Add($validateAttribute)
            $runtimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter($parameterName, [string], $attributeCollection)
            $runtimeDictionary.Add($parameterName, $runtimeParam)
            $parameterName = 'LogToDBDatabase'
            $attributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $paramAttribute = New-Object System.Management.Automation.ParameterAttribute
            $paramAttribute.Mandatory = $true
            $paramAttribute.Position = 9
            $attributeCollection.Add($paramAttribute)
            $validateAttribute = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute
            $attributeCollection.Add($validateAttribute)
            $runtimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter($parameterName, [string], $attributeCollection)
            $runtimeDictionary.Add($parameterName, $runtimeParam)
        }
        # below we force credential input for database based login but only if mode is SQL
        if ($LogToDatabase.IsPresent -and $LogToDBAuthenticationMode -eq "SQL") {
            $parameterName = 'LogToDBSqlCredential'
            $attributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $paramAttribute = New-Object System.Management.Automation.ParameterAttribute
            $paramAttribute.Mandatory = $true
            $paramAttribute.Position = 10
            $attributeCollection.Add($paramAttribute)
            $validateAttribute = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute
            $attributeCollection.Add($validateAttribute)
            $runtimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter($parameterName, [PSCredential], $attributeCollection)
            $runtimeDictionary.Add($parameterName, $runtimeParam)
        }

        return $runtimeDictionary
    }
    #endregion
    begin {
        # bind the dynamic params to expected var names
        $SqlCredential = $PSBoundParameters["SqlCredential"]
        $LogToDBServerInstance = $PSBoundParameters["LogToDBServerInstance"]
        $LogToDBDatabase = $PSBoundParameters["LogToDBDatabase"]
        $LogToDBSqlCredential = $PSBoundParameters["LogToDBSqlCredential"]

        $parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql150Parser]($true)::New(); 
        $errors = [System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]]::New();

        # if user called with script data, nothing to do... otherwise we need to preprocess into common format
        switch ($psCmdlet.ParameterSetName) {
            "File" {
                foreach ($item in $File) {
                    $data = (Get-Content -Path $item -Raw)
                    $Script += ("PRINT 'ParamParser.Source: $($item)'`nGO`n`n$($data)`nGO`n`n" )
                }
            }
            "Directory" {
                foreach ($item in $Directory) {
                    Get-ChildItem -Path $item -Filter "*.sql" -Recurse | ForEach-Object {
                        $data = (Get-Content -Path $_.FullName -Raw)
                        $Script += ("PRINT 'ParamParser.Source: $($_.FullName)'`nGO`n`n$($data)`nGO`n`n" )
                    }
                }
            }
            "SQLServer" {
                $connectionParams = @{
                    AuthMode = $AuthenticationMode
                }
                if ($SqlCredential) {
                    $connectionParams.SqlCredential = $SqlCredential
                }
                foreach ($ServerInstanceName in $ServerInstance) {
                    $connectionParams.ServerInstance = $ServerInstanceName
                    foreach ($DatabaseName in $Database) {
                        $connectionParams.Database = $DatabaseName
                        $Connection = Get-DBConnection @connectionParams
                        try {
                            $Connection.Open()
                            $Command = $Connection.CreateCommand()
                            $Command.CommandText = @"
                                SELECT script = OBJECT_DEFINITION(object_id) 
                                    FROM sys.objects 
                                    WHERE type IN (N'P',N'IF',N'FN',N'TF');
"@
                            $Reader = $Command.ExecuteReader()
                            while ($Reader.Read()) {
                                $Data = $Reader.GetValue(0).ToString()
                                $Script += ("PRINT 'ParamParser.Source: [$($ServerInstanceName)].[$($DatabaseName)]'`nGO`n`n$($data)`nGO`n`n" )
                            }
                        }
                        catch {
                            Write-Host "Database connection failed ($($ServerInstanceName), $($DatabaseName)).`n$PSItem" -ForegroundColor Yellow
                        }
                        finally {
                            $Connection.Close()
                        }        
                    }
                }
            }
        }
    }

    process {
        $fragment = $parser.Parse([System.IO.StringReader]::New($Script), [ref]$errors);
        if ($errors.Count -gt 0) {
            throw "$($errors.Count) parsing error(s): $(($errors | ConvertTo-Json))";
        }
        $visitor = [Visitor]::New();
        $fragment.Accept($visitor);
        # collapse rows and correct ModuleId assignments
        $idsToExclude = @();

        for ($i = 1; $i -le $visitor.Results.Count; $i++) {
            $thisObject = $visitor.Results[$i];
            $prevObject = $visitor.Results[$i-1];

            if ($prevObject.ModuleId -eq 0) { $prevObject.ModuleId = 1 }

            if ($visitor.ProcedureStatements -icontains $prevObject.StatementType -and 
                $prevObject.ModuleId -eq $thisObject.ModuleId) {
                    $prevObject.ObjectName = $thisObject.ObjectName;
                    $idsToExclude += $i;
            }

            if ($thisObject.StatementType -eq "ProcedureReference") {
                if ($visitor.ProcedureStatements -icontains $prevObject.StatementType) {
                    $prevObject.ObjectName = $thisObject.ObjectName;
                }
                $idsToExclude += $i;
            }

            if (($visitor.ProcedureStatements + $visitor.FunctionStatements) -icontains $prevObject.StatementType) {
                $prevObject.ModuleId = $thisObject.ModuleId
            }
        }
    }
    end {
        if (($GridView -eq $false -and $LogToDatabase -eq $false) -or ($Console -eq $true)) {
            # list all properties for all *important* fragments - longer output:
            Write-Output ($visitor.Results) | Where-Object {$_.Id -notin $idsToExclude};
        }

        if ($GridView -eq $true) {
            # spawn a new GridView window instead, much more concise:        
            $visitor.Results | Where-Object {$_.Id -notin $idsToExclude} | Out-GridView -Title "ParamParser Output"           
        }

        if ($LogToDatabase -eq $true) {
            # log to database -- requires database-side objects to be created
            # see .\database\DatabaseSupportObjects.sql
            $connectionParams = @{
                ServerInstance = $LogToDBServerInstance
                Database = $LogToDBDatabase
                AuthMode = $LogToDBAuthenticationMode
            }
            if ($LogToDBSqlCredential) {
                $connectionParams.SqlCredential = $LogToDBSqlCredential
            }
            $WriteConnection = Get-DBConnection @connectionParams

            try {
                $WriteConnection.Open()
                $WriteCommand = $WriteConnection.CreateCommand()
                $WriteCommand.CommandType = [System.Data.CommandType]::StoredProcedure
                $WriteCommand.CommandText = "dbo.LogParameters"

                $dt = New-Object System.Data.DataTable;
                $dt.Columns.Add("ModuleId",      [int])            > $null
                $dt.Columns.Add("ObjectName",    [string])         > $null
                $dt.Columns.Add("StatementType", [string])         > $null
                $dt.Columns.Add("ParamId",       [int])            > $null
                $dt.Columns.Add("ParamName",     [string])         > $null
                $dt.Columns.Add("DataType",      [string])         > $null
                $dt.Columns.Add("DefaultValue",  [string])         > $null
                $dt.Columns.Add("IsOutput",      [System.Boolean]) > $null
                $dt.Columns.Add("IsReadOnly",    [System.Boolean]) > $null
                $dt.Columns.Add("Source",        [string])         > $null

                $visitor.Results | Where-Object Id -notin $idsToExclude | ForEach-Object {
                    $dr                = $dt.NewRow()
                    $dr.ModuleId       = $_.ModuleId
                    $dr.ObjectName     = $_.ObjectName
                    $dr.StatementType  = $_.StatementType
                    if ($null -ne $_.ParamId) {
                        $dr.ParamId    = $_.ParamId
                    }
                    $dr.ParamName      = $_.ParamName
                    $dr.DataType       = $_.DataType
                    $dr.DefaultValue   = $_.DefaultValue
                    if ($null -ne $_.IsOutput) {
                        $dr.IsOutput   = $_.IsOutput
                    }
                    if ($null -ne $_.IsReadOnly) {
                        $dr.IsReadOnly = $_.IsReadOnly
                    }
                    $dr.Source         = $_.Source
                    $dt.Rows.Add($dr) > $null
                }

                $tvp = New-Object System.Data.SqlClient.SqlParameter
                $tvp.ParameterName = "ParameterSet"
                $tvp.SqlDBtype = [System.Data.SqlDbType]::Structured
                $tvp.Value = $dt
                $WriteCommand.Parameters.Add($tvp) > $null
                try {
                    $WriteCommand.ExecuteNonQuery() > $null
                    Write-Host "Wrote to database successfully." -ForegroundColor Green
                }
                catch {
                    Write-Host "Database write failed. $PSItem" -ForegroundColor Yellow
                }
                finally {
                    $WriteConnection.Close()
                }
            }
            catch {
                Write-Host "Write database connection failed ($($LogToDBServerInstance), $($LogToDBDatabase))`n$PSItem." -ForegroundColor Yellow
            }
        }
    }
}

Function Get-DBConnection
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerInstance, 
        [Parameter(Position = 1, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Database,
        [Parameter(Position = 2, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AuthMode,
        [Parameter(Position = 3, Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$SqlCredential
    )
    begin {
        $Conn = New-Object System.Data.SqlClient.SqlConnection
        $ConnectionString = "Server=$($ServerInstance); Database=$($Database);"
        if ($AuthMode -eq "SQL" -and $null -eq $SqlCredential) {
            throw "You must supply SqlCredential parameter if using SQL authentication mode."
        }
        if ($AuthMode -eq "SQL") {
            $ConnectionString += "User ID=$($SqlCredential.UserName); Password=$($SqlCredential.GetNetworkCredential().Password);"
        }
        if ($AuthMode -eq "Windows") {
            $ConnectionString += "Trusted_Connection=Yes; Integrated Security=SSPI;"
        }
    }
    process {
        $Conn.ConnectionString = $ConnectionString; 
    }
    end {
        return $Conn
    }
}
#endregion