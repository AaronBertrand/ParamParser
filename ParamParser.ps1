<#
- need to make it so it takes a source as an argument
  - source can be a .sql file, array of files, folder, array of folders, or a database, array of databases, all user databases
    - for one or more folders, concat all the files with GO between each 
    - (maybe limit it to specific file types so we're not concatenting cat pictures)
    - for a database, same, concat all definitions together with GO between each
    - but inject metadata so output can reflect source 
      - (say if two different files (or even different batches in the same file) contain procedures with same name but different interface)
      
- should also accept path to ScriptDom.dll as an optional argument

- for now, just:
  - takes a raw script pasted in (call at the end with lots of examples)
  - and outputs a PSCustom object to the console usng Write-Output.

- need to also take an input argument to define output target
  - output to console
  - out-csv, out-xml, out-json, to pipeline, or to a file
  - pass credentials to save the DataTable to a database
    - would need database, procedure, parameter name or database, TVP type name (give a definition for this), table name

- this now handles multiple batches, so sp_whoisactive, no problem
  - but it won't parse CREATE PROCEDURE from inside dynamic SQL
  
  # Visitor code lifted from Dan Guzman
  # https://www.dbdelta.com/microsoft-sql-server-script-dom/
#>

try 
{
    Add-Type -Path "$($PSScriptRoot)/Microsoft.SqlServer.TransactSql.ScriptDom.dll";
}
catch {
    throw "Please update ScriptDom.dll and verify the path."; # we want to terminate any further process
}


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
    hidden [int]$ParamId = 0;

    [void]Visit ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment] $fragment)
    {
        $fragmentType = $fragment.GetType().Name;

        if ($fragmentType -iin ($this.ProcedureStatements + $this.FunctionStatements + $this.ModuleTokenTypes))
        {
            # if body of procedure or function, increase the module # and reset param count
            if ($fragmentType -iin ($this.ProcedureStatements + $this.FunctionStatements))
            {
                $this.ModuleId++;
                $this.ParamId = 0;
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

Function Get-ParsedParams
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $false)]
        [ValidateScript( {Test-Path $PSItem -PathType Leaf} )]
        [Parameter(Position = 1, Mandatory = $false, ParameterSetName = "ScriptData")]
        [ValidateNotNullOrEmpty()]
        [string]$Script,
        [Parameter(Position = 1, Mandatory = $false, ParameterSetName = "File")]
        [ValidateScript({$PSItem | ForEach-Object {
                ((Test-Path $_ -PathType Leaf) -and ([System.IO.Path]::GetExtension($_) -ieq ".sql"))
            }
        })]
        [string[]]$File,
        [Parameter(Position = 1, Mandatory = $false, ParameterSetName = "Directory")]
        [ValidateScript({$PSItem | ForEach-Object {
                (Test-Path $_ -PathType Container)
            }
        })]
        [string[]]$Directory
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

$script = @"
CREATE PROCEDURE dbo.do_the_thing
  @foo dbo.ya = /*what */ 5 READONLY,
  @bar int = 32 OUTPUT
AS
  SELECT 1;
GO
CREATE OR ALTER FUNCTION dbo./* yo */x--ya
(@a int /*dfdf*/ = --
2) RETURNS int AS BEGIN
  RETURN (SELECT @a + 1);
END
GO
CREATE FUNCTION dbo.do_less_than_nothing() 
RETURNS int AS BEGIN RETURN 1; END;
GO
CREATE PROCEDURE dbo.do_nothing AS PRINT 1;
GO
CREATE PROCEDURE [dbo].what
(
@p1 AS [int] = /* 1 */ 1 READONLY,
@p2 datetime = getdate OUTPUT,-- comment
@p3 dbo.tabletype = {t '2020-02-01 13:15:17'} READONLY
)
AS SELECT 5
GO
CREATE PROCEDURE dbo.whatnow AS PRINT 1;
GO
CREATE FUNCTION dbo.getstuff(@r int = 5)
RETURNS char(5)
AS
BEGIN
  RETURN ('hi');
END
GO
CREATE OR ALTER PROCEDURE dbo.p3
(
  @a int = 5,
  /* @not_a_param int = 5 AS BEGIN */
  @b varchar(32) = '/* @not_a_param int = 5 AS BEGIN */',
  @c datetime = sysdatetime,
  @d AS datetime = getdate,
  @e binary(8) = 0x000000FF,
  @f datetime,
  @g int OUTPUT,
  @h dbo.tabletype READONLY,
  /* @not_a_param int = 5 AS BEGIN */
  @i sysname = N'汉🤦‍学中',
  @j xml = N'<foo></bar>',
  @k dbo.[Email Address] = 'foo@bar.com',
  @l geography,
  @m decimal(12,4) = 3.45,
  @n nvarchar(max) = /* @not_a_param int = 5 AS BEGIN */ N'splungemort',
  @o nvarchar(17) = N'folab',
  /* @not_a_param int = 5 AS BEGIN */
  @p datetime2(6) = getdate,
  @q numeric(18,2) = 5,
  @r datetime = '20200101',
  @s float ( 53 ) = 54,
  @t float(25) = 75, -- becomes float(53) -- metadata problem, not me
  @u float(23) = 90, -- becomes real    -- again, metadata problem, not me
  @读🤦‍文 decimal(12,2) = 16.54,
  @w real = 5.678  
  /* @not_a_param int = 5 AS BEGIN */
)
AS
  /* @not_a_param int = 5 AS BEGIN */
  DECLARE @foo int = 6
  IF @foo = 5
  BEGIN
  PRINT 'BEGIN';
  END
GO
/* AS BEGIN , @a int = 7, comments can appear anywhere */
CREATE PROCEDURE dbo.some_procedure 
    -- AS BEGIN, @a int = 7 'blat' AS =
    /* AS BEGIN, @a int = 7 'blat' AS = */
    @a AS /* comment here because -- chaos */ int = 5,
    @b AS varchar(64) = 'AS = /* BEGIN @a, int = 7 */ ''blat'''
  AS
    -- @b int = 72,
    DECLARE @c int = 5;
    SET @c = 6;
"@

#Get-ParsedParams -Script $script;
#Get-ParsedParams -File @("$PSScriptRoot/dirDemo/dir1/sample1.sql", "$PSScriptRoot/dirDemo/dir2/sample2.sql")
#Get-ParsedParams -Directory "$PSScriptRoot/dirDemo"
#Get-ParsedParams -Directory @("$PSScriptRoot/dirDemo/dir1", "$PSScriptRoot/dirDemo/dir2")
