# we have to make sure our module is imported
Import-Module "$(Split-Path -Path $PSScriptRoot -Parent)/ParamParser.psd1" -Force -Verbose

Describe -Tag "Visitor" -Name "Visitor" {
    Context "String Input Tests" {
        It "Provided a varchar param should yield predicted result" {
            $parsedData = Get-ParsedParams -Script "
            CREATE PROCEDURE dbo.do_the_thing
              @bar varchar(32)
            AS
              SELECT 1;
            GO"

            $parsedData.Count | Should -Be 2

            $parsedData[0].StatementType | Should -Be "CreateProcedureStatement"
            $parsedData[0].ObjectName | Should -Be "dbo.do_the_thing"
            $parsedData[0].DataType | Should -Be ''
            $parsedData[0].ParamName | Should -Be ''
            
            $parsedData[1].StatementType | Should -Be "ProcedureParameter"
            $parsedData[1].ObjectName | Should -Be $null
            $parsedData[1].DataType | Should -Be "varchar(32)"
            $parsedData[1].ParamName | Should -Be "@bar"
        }
    }
}