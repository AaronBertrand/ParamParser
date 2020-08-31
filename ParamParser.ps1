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


class Visitor: Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragmentVisitor 
{
    [void]Visit ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment] $frag)
    {
        $fragType = $frag.GetType().Name;
        if ($fragType -in ("ProcedureParameter", "SchemaObjectName") -or $global:CreateStatements.Contains($fragType))
        {
            $seenEquals = $false;
            $dataTypeOrName = "";
            $defaultValue = "";
            $isOutput = 0;
            $isReadOnly = 0;
            if ($fragType -eq "ProcedureParameter" -or ($frag.FirstTokenIndex -lt $frag.LastTokenIndex))       
            {   
                $r = $global:dt.NewRow();
                for ($i = $frag.FirstTokenIndex; $i -le $frag.LastTokenIndex; $i++)
                { 
                    $token = $frag.ScriptTokenStream[$i];
                    if ($token.TokenType -eq "Variable" -and $fragType -eq "ProcedureParameter") { $r["ParamName"] = $token.Text; }
                    if ($token.TokenType -eq "EqualsSign") { $seenEquals = $true; }
                    if (!$seenEquals -and $token.TokenType -notin ("Variable","WhiteSpace","MultiLineComment","SingleLineComment","As"))
                    {
                        if     ($token.TokenType -eq "Identifier" -and $token.Text.ToUpper() -eq "Output") { $isOutput = 1; }   
                        elseif ($token.TokenType -eq "Identifier" -and $token.Text.ToUpper() -eq "ReadOnly") { $isReadOnly = 1; }
                        else { $dataTypeOrName += $token.Text } # + ", $($token.Type), $($frag.FirstTokenIndex), $($frag.LastTokenIndex)"; }
                    }
                    if ($seenEquals -and $token.TokenType -notin ("EqualsSign","Output","ReadOnly","MultiLineComment","SingleLineComment","As"))
                    {
                        if     ($token.TokenType -eq "Identifier" -and $token.Text.ToUpper() -eq "Output") { $isOutput = 1; }   
                        elseif ($token.TokenType -eq "Identifier" -and $token.Text.ToUpper() -eq "ReadOnly") { $isReadOnly = 1; }
                        else { $defaultValue += $token.Text }
                    }
                }
                if ($fragType -eq "ProcedureParameter")
                { 
                    $r["DataType"]     = $dataTypeOrName;
                    $r["DefaultValue"] = $defaultValue.TrimStart();
                    $r["IsOutput"]     = $isOutput;
                    $r["isReadOnly"]   = $isReadOnly;
                }
                if ($fragType -eq "SchemaObjectName")
                {
                    $r["ObjectName"]   = $dataTypeOrName;
                }
                $r["TokenType"] = $fragType;
                $global:dt.Rows.Add($r);
            }
        }
    }
}


Function Get-ParsedParams ($script) 
{
    Add-Type -Path "Microsoft.SqlServer.TransactSql.ScriptDom.dll"
    $parser = New-Object Microsoft.SqlServer.TransactSql.ScriptDom.TSql150Parser($true)
    $err = New-Object System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]
    $stringReader = New-Object System.IO.StringReader($script)
    $frag = $parser.Parse($stringReader, [ref]$err)
    if($err.Count -gt 0) 
    {
        throw "$($err.Count) parsing error(s): $(($err | ConvertTo-Json))"
    }
    $global:dt = New-Object System.Data.DataTable;
    $id = New-Object System.Data.DataColumn RowID,([int]);
    $id.AutoIncrement = $true;
    $id.AutoIncrementSeed = 1;
    $global:dt.Columns.Add($id);
    [void]$global:dt.Columns.Add("TokenType");
    [void]$global:dt.Columns.Add("ObjectName");
    [void]$global:dt.Columns.Add("ParamName");
    [void]$global:dt.Columns.Add("DataType");
    [void]$global:dt.Columns.Add("DefaultValue");
    [void]$global:dt.Columns.Add("IsOutput");
    [void]$global:dt.Columns.Add("IsReadOnly"); 
    
    $global:CreateStatements = @("CreateOrAlterFunctionStatement", "CreateOrAlterProcedureStatement", `
    "CreateFunctionStatement", "CreateProcedureStatement", "AlterFunctionStatement", "AlterProcedureStatement");
    $visitor = [Visitor]::new();
    $frag.Accept($visitor);


    for ($i = 1; $i -le $global:dt.Rows.Count; $i++)
    {
        $thisToken = $global:dt.Rows[$i].TokenType;
        $prevToken = $global:dt.Rows[$i-1].TokenType;

        # delete any row that has a SchemaObjectName but isn't the name of the procedure
        # because this gets pulled out in a visit even if it's part of a data type declaration (e.g. @param dbo.UserType)
        # also flatten the first two rows for any object - one is type of statement, two is object name
        if ($thisToken -eq "SchemaObjectName")
        {
            if (!$global:CreateStatements.Contains($prevToken))
            {
                $global:dt.Rows[$i].Delete();
            }
            if ($global:CreateStatements.Contains($prevToken))
            {  
                $global:dt.Rows[$i].TokenType = $prevToken;
                $global:dt.Rows[$i-1].Delete();
            }
        }
        $global:dt.AcceptChanges();
    }
    $global:dt | Select-Object | Sort-Object RowID | Format-Table;
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
  @i sysname = N'fl读写汉oo🤦‍♂️fl学中文oo',
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
  @读🤦‍♂️文 decimal(12,2) = 16.54,
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

Get-ParsedParams -script $script;
