<#
- need to make it so it takes a source as an argument
  - source can be a .sql file, folder, or database
  - for a folder, concat all the files with GO between each 
  - (maybe limit it to specific file types so we're not concatenting cat pictures)
  - for a database, same, concat all definitions together with GO between each

- for now, just takes a script (call at the end with lots of examples)
- and outputs a DataTable to the console.

- need to also take output as a target
  - output to console
  - out-csv, out-xml, out-json, to pipeline or to a file
  - pass credentials to save the DataTable to a database
    - would need database, procedure, parameter name

- this now handles multiple batches, so sp_whoisactive, no problem
  - but it won't parse CREATE PROCEDURE from inside dynamic SQL
#>


Function Get-Params ($parser, $script) 
{
  try
  {
    $err = New-Object System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]
    $strReader = New-Object System.IO.StringReader($script)

    $block = $parser.Parse($strReader, [ref]$err)

    $table = New-Object System.Data.DataTable;
    $table.Columns.Add("BatchNumber")
    $table.Columns.Add("ModuleName")
    $table.Columns.Add("ParameterID")
    $table.Columns.Add("ParameterName")  
    $table.Columns.Add("DataType")
    $table.Columns.Add("HasDefaultValue")
    $table.Columns.Add("DefaultValue")
    $table.Columns.Add("IsOutput")
    $table.Columns.Add("IsReadOnly")
  
    $batchNumber = 0;

    foreach ($batch in $block.batches) 
    {
      $batchNumber += 1;
      foreach ($statement in $batch.Statements) 
      {
        if ($statement.GetType().Name -in ("CreateOrAlterProcedureStatement", "CreateOrAlterFunctionStatement", "CreateProcedureStatement", `
                        "CreateFunctionStatement", "AlterProcedureStatement", "AlterFunctionStatement"))
        {
          $thisModuleName = "";
          $seenVariable = $false;
          $seenReturns = $false;
          $p = 0;

          for ($i = $statement.FirstTokenIndex; $i -le $statement.LastTokenIndex; $i++)
          { 
            $token = $statement.ScriptTokenStream[$i];

            if ($token.TokenType -notin ("CreateOrAlter","Create","As","Or","Alter","Procedure","WhiteSpace","MultiLineComment","SingleLineComment"))
            {
              # these token types must mean we've reached the body
              # because they are invalid inside the parameter list
              if (($token.TokenType -in ("Semicolon","Set","Select","Begin","Declare","Exec","Begin","With","Print","Table")) `
                -or ($token.TokenType -eq "Identifier" -and $token.Text.ToUpper() -in ("TABLE","RETURNS")))
                                # RETURNS isn't a proper token because ¯\_(ツ)_/¯ !
              {              
                $r = $table.NewRow()
                $r["ModuleName"] = $thisModuleName;
                $r["batchNumber"] = $batchNumber;
                $r["ParameterID"] = 0;
                $table.Rows.Add($r);
                break;
              }

              if (($token.TokenType -in ("Identifier", "Dot")) -and !$seenVariable)
              {
                $thisModuleName += $token.Text;
              }

              if ($token.TokenType -eq "Variable" -and !$seenReturns)
              {
                $seenVariable = $true;
                $seenEquals = $false;
                $isOutput = $false;
                $isReadOnly = $false;
                $v = $token.Text;
                $p++;
                $dt = "";
                $hdv = 0;
                $dv = "";
                $parenCount = 0;
    
                do {
                  $i++; $token = $statement.ScriptTokenStream[$i];

                  if 
                  (
                  ($token.TokenType -notin ("Table","As","EqualsSign","WhiteSpace","Begin","Variable","MultiLineComment","SingleLineComment","Print"))`
                  -and !($token.TokenType -eq "Identifier" -and $token.Text.ToUpper() -in ("RETURNS","TABLE"))`
                  )
                  {
                    if ($token.TokenType -eq "EqualsSign")
                    {
                        $seenEquals = $true;
                    }

                    # if we see AS *after* assignment, it must be marking end of param list
                    if (!$seenEquals -and $tokenType -eq "As") { break; }
                    # edge case where (a) last parameter does *not* have a default value
                    #         (b) parameter list is surrounded by parentheses
                    #       means (c) that paren was added to type name of last param 
                    if  ($token.TokenType -eq "LeftParenthesis")  {$parenCount++;}
                    if  ($token.TokenType -eq "RightParenthesis") {$parenCount--;}
                    if (($token.TokenType -ne "RightParenthesis") -or ($parenCount % 2 -eq 0))
                    {
                        if (!($token.Text.ToUpper() -in ("OUTPUT","READONLY","WITH","SCHEMABINDING")))
                        {
                            $dt += $token.Text;
                        }
                    }
                  }
                  if (($dt -gt "") -and ($token.TokenType -eq "As")) { break; }
                  if (($seenEquals -and $token.TokenType -eq "Identifier")) { break; }

                  if ($token.TokenType -eq "Identifier")
                  {
                    if ($token.Text.ToUpper() -eq "OUTPUT")   { $isOutput   = $true; }
                    if ($token.Text.ToUpper() -eq "READONLY") { $isReadOnly = $true; }
                  }
                
                } while (($token.TokenType -notin ("Begin","EqualsSign","Variable")))
                
                # hacky, ugly "clean the last comma because we didn't know it wasn't part of a precision,scale"
                if ($dt.substring($dt.length-1, 1) -eq ",") { $dt = $dt.substring(0, $dt.length-1); }
                $r = $table.NewRow()
                $r["ModuleName"] = $thisModuleName;
                $r["batchNumber"] = $batchNumber;
                $r["ParameterID"] = $p;
                $r["ParameterName"] = $v;
                $r["DataType"] = $dt;

                if ($token.TokenType -eq "EqualsSign")
                {
                  $hdv = 1;
                  do {

                    $i++;
                    $token = $statement.ScriptTokenStream[$i];
                    if ($token.Text -gt "" -and $token.TokenType -in ("AsciiStringLiteral", "HexLiteral", "Identifier",
                                              "Integer", "Minus", "Money", "Null", "Numeric",
                                              "Real", "UnicodeStringLiteral"))
                    { 
                      $dv += $token.Text; 
                    }
                  } until ($token.TokenType -in ("AsciiStringLiteral", "HexLiteral", "Identifier",
                                  "Integer", "Money", "Null", "Numeric",
                                  "Real", "UnicodeStringLiteral"))
                  $r["DefaultValue"] = $dv;


                  do {
                    $i++;
                    $token = $statement.ScriptTokenStream[$i];
                    if ($token.TokenType -eq "Identifier")
                    {
                        if ($token.Text.ToUpper() -eq "OUTPUT")   { $isOutput   = $true; }
                        if ($token.Text.ToUpper() -eq "READONLY") { $isReadOnly = $true; }
                        if ($token.Text.ToUpper() -eq "RETURNS") { $seenReturns = $true; }
                    }
                  } until ($token.TokenType -in ("Comma","Begin","EqualsSign","Variable",
                                  "AsciiStringLiteral", "HexLiteral", "Identifier",
                                  "Integer", "Money", "Null", "Numeric",
                                  "Real", "UnicodeStringLiteral"))
                }
                $r["IsReadOnly"] = $isReadOnly;
                $r["IsOutput"] = $isOutput;
                $r["HasDefaultValue"] = $hdv;
                $table.Rows.Add($r);
              }
            }
          }
        }
      }
    }
  }
  catch
  {
    Write-Host "Some bad things happened: $PSItem" -ForegroundColor Yellow
  }

  Write-Host $script;

  $table  | Sort-Object   BatchNumber, ModuleName, ParameterID `
          | Format-Table  ModuleName, ParameterID, ParameterName, DataType, HasDefaultValue, `
                          DefaultValue, IsReadOnly, IsOutput, BatchNumber 
                          #| Where-Object("ParameterID > 0");

  if($err.Count -eq 0) {
    Write-Host "We're good!" -ForegroundColor DarkGreen
  }
  else {
    Write-Host "Some bad things happened: $($parseErrors.Count) parsing error(s): $(($parseErrors | ConvertTo-Json))" -ForegroundColor Yellow
  }
}

$s1 = @"
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

$s2 = @"
CREATE PROCEDURE dbo.x1
@foo int output
AS PRINT 1; 
GO

CREATE PROCEDURE dbo.x2
@foo int = 1 OUTPUT 
AS PRINT 1
GO

CREATE PROCEDURE dbo.x3
@foo AS int output
AS PRINT 1
GO

CREATE PROCEDURE dbo.x4
@foo AS int = 3 OUTPUT
AS PRINT 1
GO

CREATE PROCEDURE dbo.x5
@foo AS int = 7 READONLY
AS PRINT 1
GO
"@

$s3 = @"
CREATE PROCEDURE dbo.flabber AS SELECT 1;
GO
SET NOCOUNT ON; -- testing stub-style .sql scripts
IF EXISTS (SELECT 1 FROM sys.objects)
BEGIN
  EXEC sys.sp_executesql N'CREATE dbo.empty_body;';
END
GO

CREATE OR ALTER PROCEDURE dbo.foo /* blfdf */ -- yo
(  @param1 varchar(32) = 'blat',
  @param2 dbo.[bad /* name */] READONLY,
  @param3 int = -64,
  @x varchar(32)
)  AS 
  SELECT @param1 = 'splunge'; SELECT @param2 = 34;
GO

CREATE PROCEDURE dbo.blat
  @param4 datetime = getdate OUTPUT,
  @param5 varchar(32)
AS
  PRINT 1;
GO

ALTER FUNCTION dbo.bar(@paramA int = 5, @paramB varchar) RETURNS int AS BEGIN RETURN(@param3) END;
GO
CREATE PROCEDURE dbo.flabber AS SELECT 1;
GO

"@

$s4 = @"
CREATE PROCEDURE dbo.p2
/* @bar AS varchar(32) = 'AS' */ -- @bar AS varchar(32) = 'AS'
  @bar AS varchar(32) = 'AS',
  @d datetime = sysdatetime,
  --@x dbo.whatever READONLY,
  @splunge int = NULL,
/* @bar AS varchar(32) = 'AS' */ -- @bar AS varchar(32) = 'AS'
  @mort int = 5,
  @qwerty varbinary(8) = 0x000000FF
/* @bar AS varchar(32) = 'AS' */ -- @bar AS varchar(32) = 'AS'
AS
/* @bar AS varchar(32) = 'AS' */ -- @bar AS varchar(32) = 'AS'
  /* @bar AS varchar(32) = 'AS' */ 
  PRINT 1;
  -- @bar AS varchar(32) = 'AS'
GO

-- a couple of different types to make sure those show up properly
CREATE TYPE dbo.tabletype AS TABLE(id int);
GO
CREATE TYPE dbo.EmailAddress FROM varchar(320);
GO

-- one of each type of function, with some Unicode in there too
CREATE FUNCTION dbo.GetWeek_IF(@StartDate date = /* 🤦‍♂️ */ getdate)
RETURNS table
WITH SCHEMABINDING
AS
  RETURN (SELECT x = 1 WHERE @StartDate = GETDATE());
GO

CREATE FUNCTION dbo.GetWeek_FN(@StartDate date = /* 🤦‍♂️ */ getdate)
RETURNS date
WITH SCHEMABINDING
AS
BEGIN
  RETURN (@StartDate);
END
GO

CREATE FUNCTION dbo.GetWeek_TF(@StartDate AS date = /* 🤦‍♂️ */ getdate)
RETURNS @x TABLE(i int)
WITH SCHEMABINDING
AS
BEGIN
  INSERT @x SELECT 1;
  RETURN;
END
GO
-- another procedure with some Unicode and all kinds of types
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
  @k dbo.EmailAddress = 'foo@bar.com',
  @l geography,
  @m decimal(12,4) = 3.45,
  @n nvarchar(max) = /* @not_a_param int = 5 AS BEGIN */ N'splungemort',
  @o nvarchar(17) = N'folab',
  /* @not_a_param int = 5 AS BEGIN */
  @p datetime2(6) = getdate,
  @q numeric(18,2) = 5,
  @r datetime = '20200101',
  @s float(53) = 54,
  @t float(25) = 75, -- becomes float(53) -- metadata problem, not me
  @u float(23) = 90, -- becomes real    -- again, metadata problem, not me
  @读写汉🤦‍♂️学中文 decimal(12,2) = 16.54,
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

Add-Type -Path "Microsoft.SqlServer.TransactSql.ScriptDom.dll";
$parser = New-Object Microsoft.SqlServer.TransactSql.ScriptDom.TSql150Parser($true)

#Get-Params -parser $parser -script $s1
#Get-Params -parser $parser -script $s2
#Get-Params -parser $parser -script $s3
Get-Params -parser $parser -script $s4