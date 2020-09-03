<#
- need to make it so it takes a source as an argument
  - source can be a .sql file, array of files, folder, array of folders, or a database, array of databases, all user databases
    - for one or more folders, concat all the files with GO between each 
    - (maybe limit it to specific file types so we're not concatenting cat pictures)
    - for a database, same, concat all definitions together with GO between each
    - but inject metadata so output can reflect source 
      - (say if two different files with the same name contain procedures with same name but different interface)

- for now, just:
  - takes a script (call at the end with lots of examples)
  - and outputs a DataTable to the console.

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


class Visitor: Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragmentVisitor {
    # below is used for collecting results within Visit method
    $Results = [System.Collections.ArrayList]@()

    # define all known create statements
    $CreateStatements = @("CreateOrAlterFunctionStatement", "CreateOrAlterProcedureStatement", 
    "CreateFunctionStatement", "CreateProcedureStatement", 
    "AlterFunctionStatement", "AlterProcedureStatement")

    # comment token types
    $CommentTokenTypes = @("MultiLineComment", "SingleLineComment")

    # we only process items in the below
    $FragementsToProcess = (@("ProcedureParameter", "SchemaObjectName") + $this.CreateStatements)

    # nice easy way to get a standard object for our results collection
    [PSCustomObject]GetResultObject ([string]$TokenType) {
        return ([PSCustomObject]@{
            Id = $this.Counter
            TokenType = $TokenType
            DataType = [string]::Empty
            DefaultValue = [string]::Empty
            IsOutput = $false
            isReadOnly = $false
            ParamName = [string]::Empty
            ObjectName = $null
        })
    }

    # for internal use only
    hidden [int]$Counter = 0

    # our visit implementation
    [void]Visit ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment] $frag) {
        $fragType = $frag.GetType().Name
        if ($fragType -iin $this.FragementsToProcess) {
            # get a new result object
            $result = $this.GetResultObject($fragType)

            # store whether equals has been seen outside of loop
            $seenEquals = $false

            if ($fragType -eq "ProcedureParameter" -or ($frag.FirstTokenIndex -lt $frag.LastTokenIndex)) {   
                for ($i = $frag.FirstTokenIndex; $i -le $frag.LastTokenIndex; $i++) { 
                    $token = $frag.ScriptTokenStream[$i]
                    if ($token.TokenType -eq "Variable" -and $fragType -eq "ProcedureParameter") { 
                        $result.ParamName = $token.Text
                    }
                    if ($token.TokenType -eq "EqualsSign") { 
                        $seenEquals = $true
                    }
                    if (-not $seenEquals -and $token.TokenType -notin (@("Variable", "WhiteSpace", "As") + $this.CommentTokenTypes)) {
                        if ($token.TokenType -eq "Identifier" -and $token.Text -ieq "Output") {
                            $result.IsOutput = $true
                        }   
                        elseif ($token.TokenType -eq "Identifier" -and $token.Text -ieq "ReadOnly") {
                            $result.IsReadOnly = $true
                        }
                        else {
                            $result.DataType += $token.Text
                        }
                    }
                    if ($seenEquals -and $token.TokenType -notin (@("EqualsSign", "Output", "ReadOnly", "As") + $this.CommentTokenTypes)) {
                        if ($token.TokenType -eq "Identifier" -and $token.Text -ieq "Output") {
                            $result.IsOutput = $true
                        }   
                        elseif ($token.TokenType -eq "Identifier" -and $token.Text -ieq "ReadOnly") { 
                            $result.IsReadOnly = $true
                        }
                        else {
                            $result.DefaultValue += $token.Text 
                        }
                    }
                }
                # override the object name if appropriate
                if ($fragType -eq "SchemaObjectName") {
                    $result.ObjectName = $result.DataType
                    $result.DataType = $null
                }
                # tidy the value
                $result.DefaultValue = $result.DefaultValue.TrimStart()

                # append result to output collection
                $this.Results.Add($result)

                # increment the counter
                $this.Counter++
            }
        }
    }
}


Function Get-ParsedParams ($script) {

    try { 
        Add-Type -Path "Microsoft.SqlServer.TransactSql.ScriptDom.dll"
    }
    catch {
        $msg = @"
Download sqlpackage 18.5.1 or better from:

  https://docs.microsoft.com/en-us/sql/tools/sqlpackage-download

Extract Microsoft.SqlServer.TransactSql.ScriptDom.dll and place
it in the same folder as this file (or update -Path above
"@
        Write-Host $msg -ForegroundColor Magenta;
    }

    $parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql150Parser]($true)::New(); 
    $err = [System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]]::New();
    $frag = $parser.Parse([System.IO.StringReader]::New($script), [ref]$err);
 
    if ($err.Count -gt 0) {
        throw "$($err.Count) parsing error(s): $(($err | ConvertTo-Json))"
    }

    $visitor = [Visitor]::new();
    $frag.Accept($visitor);
    
    $idsToExclude = @()
    for ($i = 0; $i -le $visitor.Results.Count; $i++) {
        $thisObject = $visitor.Results[$i];
        $prevObject = $visitor.Results[$i-1];

        # delete any row that has a SchemaObjectName but isn't the name of the procedure
        # because this gets pulled out in a visit even if it's part of a data type declaration (e.g. @param dbo.UserType)
        # also flatten the first two rows for any object - one is type of statement, two is object name
        if ($thisObject.TokenType -eq "SchemaObjectName") {
            if ($visitor.CreateStatements -inotcontains $prevObject.TokenType) {
                $idsToExclude += $thisObject.Id
            }
            else {  
                $thisObject.TokenType = $prevObject.TokenType;
                $idsToExclude += $prevObject.Id
            }
        }
    }
    Write-Output ($visitor.Results | Where-Object {$_.Id -notin $idsToExclude})
}

$script = @"
/* AS BEGIN , @a int = 7, comments can appear anywhere */
CREATE PROCEDURE dbo.some_procedure 
  -- AS BEGIN, @a int = 7 'blat' AS =
  /* AS BEGIN, @a int = 7 'blat' AS = */
  @a AS /* comment here because -- chaos */ int = 5,
  @b AS varchar(64) /* = 'AS = /* BEGIN @a, int = 7 */ ''blat''' */ 
  AS
  -- @b int = 72,
  DECLARE @c int = 5;
  SET @c = 6;
GO
"@

$sd2 = @"
CREATE PROCEDURE [dbo].what
(
@p1 AS [int] = /* 1 */ 1 READONLY,
@p2 datetime = getdate OUTPUT,-- comment
@p3 dbo.tabletype = {t '5:45'} READONLY
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
"@

Get-ParsedParams -script $sd2
