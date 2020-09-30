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
          Id = $this.Counter
          ModuleId = $this.ModuleId
          ObjectName = $this.ObjectName
          ParamId = $this.ParamId
          StatementType = $StatementType
          DataType = [string]::Empty
          DefaultValue = [string]::Empty
          IsOutput = $false
          IsReadOnly = $false
          ParamName = [string]::Empty
      })
    }

    hidden [int]$Counter = 0;
    hidden [int]$ModuleId = 0;
    hidden [int]$ParamId = 1;

    [void]Visit ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment] $fragment)
    {
        $fragmentType = $fragment.GetType().Name;

        if ($fragmentType -iin ($this.ProcedureStatements + $this.FunctionStatements + $this.ModuleTokenTypes))
        {
            # if body of procedure or function, increase the module # and reset param count
            if ($fragmentType -iin ($this.ProcedureStatements + $this.FunctionStatements))
            {
                $this.ModuleId++;
                $this.ParamId = 1;
            }

            $result = $this.GetResultObject($fragmentType);

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
                      if ($seenObject -and $token.TokenType -notin ("Dot","Identifier"))
                        {
                            $seenEndOfFirstObject = $true;
                        }
                        if ($token.TokenType -in ("Dot", "Identifier") -and !$seenEndOfFirstObject)
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
Function Get-ParsedParams
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $false, ParameterSetName = "ScriptData")]
        [ValidateNotNullOrEmpty()]
        [string]$Script,

        [Parameter(Position = 0, Mandatory = $false, ParameterSetName = "File")]
        [ValidateScript({$PSItem | ForEach-Object {
                ((Test-Path $_ -PathType Leaf) -and ([System.IO.Path]::GetExtension($_) -ieq ".sql"))
            }
        })]
        [string[]]$File,

        [Parameter(Position = 0, Mandatory = $false, ParameterSetName = "Directory")]
        [ValidateScript({$PSItem | ForEach-Object {
                (Test-Path $_ -PathType Container)
            }
        })]
        [string[]]$Directory,

        [Parameter(Position = 0, Mandatory = $false, ParameterSetName = "SQLServer")]
        [ValidateNotNullOrEmpty()]
        [string]$ServerInstance,
        [Parameter(Position = 1, Mandatory = $false, ParameterSetName = "SQLServer")]
        [ValidateNotNullOrEmpty()]
        [string]$Database,
        [Parameter(Position = 2, Mandatory = $false, ParameterSetName = "SQLServer")]
        [ValidateNotNullOrEmpty()]
        [string]$AuthenticationMode = "Windows", # Or SQL
        #[Parameter(Mandatory = $false, ParameterSetName = "SQLServer")]
        #[switch]$Prompt, # to specify _alternate_ Windows auth credentials

        # if SQL - can I make this mandator _if_ SQL is specified?
        [Parameter(Mandatory = $false, ParameterSetName = "SQLServer")]
        [string]$Username,
        [Parameter(Mandatory = $false, ParameterSetName = "SQLServer")]
        [SecureString]$SecurePassword,
        #NotRecommended!:
        [Parameter(Mandatory = $false, ParameterSetName = "SQLServer")]
        [string]$InsecurePassword
    )
    begin {
        $parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql150Parser]($true)::New(); 
        $errors = [System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]]::New();

        # if user called with script data, nothing to do... otherwise we need to preprocess into common format
        switch ($psCmdlet.ParameterSetName) {
            "File" {
                foreach ($item in $File) {
                    $data = (Get-Content -Path $item -Raw)
                    if (-not $data.EndsWith("GO")) {
                        $data += "`nGO"
                    }
                    $Script += ($data + "`n`n")
                }
            }
            "Directory" {
                foreach ($item in $Directory) {
                    Get-ChildItem -Path $item -Filter "*.sql" -Recurse | ForEach-Object {
                        $data = (Get-Content -Path $_.FullName -Raw)
                        if (-not $data.EndsWith("GO")) {
                            $data += "`nGO"
                        }
                        $Script += ($data + "`n`n")
                    }
                }
            }
            "SQLServer" {
                $connstring = "Server=$ServerInstance; Database=$Database;"
                $connection = New-Object System.Data.SqlClient.SqlConnection;
                switch ($AuthenticationMode)
                {
                    "SQL" { 
                        if ($InsecurePassword -gt "") {
                            $PlainPassword = $InsecurePassword # ConvertTo-SecureString $InsecurePassword -AsPlainText -Force
                            # $PlainPassword.MakeReadOnly()
                        }
                        else {
                            $BSTR =  [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
                            $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                        }
                        # $connection.Credential = New-Object System.Data.SqlClient.SqlCredential($Username, $PlainPassword)
                        $connstring += "User ID=$Username; Password=$PlainPassword;"
                    }
                    "Windows" {
                        $connstring += "Trusted_Connection=Yes; Integrated Security=SSPI;"
                        # if ($Prompt) { # if we can add _alternate_ Windows Auth credentials
                                         # this may need Invoke-SqlCmd vs. SqlConnection?
                            # $cred = Get-Credential -Message "Enter Windows Auth credentials:" # -UserName $Username
                            # $cred.Password.MakeReadOnly()
                            # $SQLCred = New-Object System.Data.SqlClient.SqlCredential($cred.UserName, $cred.Password)
                            # $connection.Credential = $SQLCred
                        # }
                    }
                }
                $connection.ConnectionString = $connstring;    

                try {
                    $connection.Open()
                    $command = $connection.CreateCommand()
                    $command.CommandText = @"
                        SELECT script = OBJECT_DEFINITION(object_id) 
                            FROM sys.objects 
                            WHERE type IN (N'P',N'IF',N'FN',N'TF');
"@
                    $reader = $command.ExecuteReader()
                    while ($reader.Read()) {
                        $data = $reader.GetValue(0).ToString()
                        $Script += ($data + "`nGO`n`n")
                    }
                }
                catch {
                    Write-Host "Database connection failed."
                }
            }
        }
    }

    process {
        $fragment = $parser.Parse([System.IO.StringReader]::New($script), [ref]$errors);
        if ($errors.Count -gt 0) {
            throw "$($errors.Count) parsing error(s): $(($errors | ConvertTo-Json))";
        }
        $visitor = [Visitor]::New();
        $fragment.Accept($visitor);
        # collapse rows
        $idsToExclude = @();
        for ($i = 1; $i -le $visitor.Results.Count; $i++) {
            $thisObject = $visitor.Results[$i];
            $prevObject = $visitor.Results[$i-1];

            if ($visitor.ProcedureStatements -icontains $prevObject.StatementType -and 
                $prevObject.ModuleId -eq $thisObject.ModuleId) {
                $prevObject.ObjectName = $thisObject.ObjectName;
                $idsToExclude += ($i);
            }
        }
    }
    end {
        Write-Output ($visitor.Results | Where-Object {$_.Id -notin $idsToExclude});
    }
}
#endregion
