class Visitor: Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragmentVisitor 
{
    [void]Visit ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment] $fragment)
    {
        if ($fragment.GetType().Name -eq "ProcedureParameter")
        {
            $output = "";  
            $hasDefault = "  -- no default";
            for ($i = $fragment.FirstTokenIndex; $i -le $fragment.LastTokenIndex; $i++)
            {
                $token = $fragment.ScriptTokenStream[$i];
                if ($token.TokenType -notin ("MultiLineComment", "SingleLineComment"))
                {
                    $output += $token.Text;
                }
                if ($token.TokenType -eq "EqualsSign")
                {
                    $hasDefault = " -- <-- has a default!";
                }
            }
            Write-Host "$output $hasDefault" -ForegroundColor Yellow;
        }
    }
}

Function Get-ParsedParams ($script) 
{
    try { Add-Type -Path "$($PSScriptRoot)/Microsoft.SqlServer.TransactSql.ScriptDom.dll"; }
    catch {
        $sb = [System.Text.StringBuilder]::New()
        $msg = $sb.AppendLine('Download sqlpackage 18.5.1 or better from:').
            Append([System.Environment]::NewLine).
            AppendLine('  https://docs.microsoft.com/en-us/sql/tools/sqlpackage-download').
            Append([System.Environment]::NewLine).
            AppendLine('Extract Microsoft.SqlServer.TransactSql.ScriptDom.dll and place').
            AppendLine('it in the same folder as this file (or update -Path above):')
        $sb.ToString();
        Write-Host $msg -ForegroundColor Magenta;
    }
    $parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql150Parser]($true)::New(); 
    $fragment = $parser.Parse([System.IO.StringReader]::New($script), 
      [ref][System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]]::New());
    $visitor = [Visitor]::New();
    $fragment.Accept($visitor);
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
"@

Get-ParsedParams -script $script;
