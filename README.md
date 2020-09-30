# ParamParser

You're here because you want to know the default values defined for your stored procedures and functions, but SQL Server makes this next to impossible using native functionality. I started this little project to make it easier. It's a simple PowerShell script that parses parameter information out of modules stored in a database, database scripts stored in files, or raw scripts inline.

### Background

I've begun writing about the journey here:

* [Parse parameter default values using PowerShell - Part 1](https://sqlperformance.com/2020/09/sql-performance/paramparser-1)

But to see a quick example of what the current code does, take this (intentionally ridiculous) example:

```
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
```

The code here parses through all that garbage and outputs something like this:

![](https://sqlblog.org/wp-content/uploads/2020/09/param-parser-output-0.96.png)

### Dependencies / How to Start

You need to have the latest ScriptDom.dll locally in order to use the related classes here, but we can't legally give you that file. After that, you can import the ParamParser module, and then run `Get-ParsedParams` with a string, a database, a file, or a directory. Output is not perfect yet, but we'll get there. 

- Clone this repository
- Run `init.ps1`, which will extract the latest version of `ScriptDom.dll` from [here](https://docs.microsoft.com/en-us/sql/tools/sqlpackage-download) into the script root
- To run, in any PS session, `cd` to the repository folder, then:
  - `Import-Module ./ParamParser.psm1`
    - If testing local changes, add `-Force` to overwrite
  - For a raw script:
    - `Get-ParsedParams -Script "CREATE PROCEDURE dbo.foo @bar int = 1 AS PRINT 1;"`
  - For a file or folder:
    - `Get-ParsedParams -File "./dirDemo/dir1/sample1.sql"`
    - `Get-ParsedParams -Directory "./dirDemo/"`
  - For a database:
    - Using current Windows Auth credentials:
      - `Get-ParsedParams -ServerInstance "server\instance" -Database "db" -AuthenticationMode "Windows"`
      - `Get-ParsedParams -ServerInstance "server\instance" -Database "db"` (Windows is the default)
    - To pass in a SecureString SQL Auth password (assuming you'd get securestring from another source):
      - `$password = "password" | ConvertTo-SecureString -AsPlainText -Force`
      - `Get-ParsedParams -ServerInstance "server" -Database "db" -AuthenticationMode "SQL" -Username "username" -SecurePassword $password`
    - To pass in a plaintext SQL Auth password:
      - `Get-ParsedParams -ServerInstance "server" -Database "db" -AuthenticationMode "SQL" -Username "username" -InsecurePassword "password"`
    - For multiple instances or databases (usually won't provide multiple of both at the same time):
      - `Get-ParsedParams -ServerInstance "server1","server2" -Database "db"`
      - `Get-ParsedParams -ServerInstance "server" -Database "db1","db2"`
- For unit testing, install Pester
  - `Install-Module Pester`
  - This will allow you to execute unit tests for validation during development efforts
  - Execute tests: `Invoke-Pester -Path ./tests/*`

### What does it do

For now, it just outputs a `PSCustomObject` to the console using `Write-Output`. I showed an abbreviated sample above, but the elements in the output are, ungrouped and perhaps not in the most logical order at present:

- **`Id`**: 
  - A simple counter incremented for every fragment visited.
- **`ModuleId`**: 
  - A counter that increments for every new procedure or function body we encounter (this has no relation to `object_id`).
- **`ObjectName`**: 
  - The one- or two-part name of the object.
- **`ParamId`**: 
  - A counter that increments for every new parameter we encounter inside a module.
- **`StatementType`**: 
  - Whether it's `create`/`alter`/`create or alter` | `procedure` / `function`. When pulling from a database, this will always be `create`.
- **`DataType`**: 
  - Properly defined data type _as written_ - e.g. this will show `float(23)` if that's what the module defines, even if that isn't the data type stored in `sys.parameters`.
- **`DefaultValue`**: 
  - The literal text supplied by default, whether it's a string or numeric literal, an ODBC literal, or a string disguised as an identifier (e.g. `GETDATE`).
- **`IsOutput`**: 
  - Whether the parameter is defined as `OUT`/`OUTPUT`.
- **`IsReadOnly`**: 
  - Whether the parameter is read only (only valid for table-valued parameters).
- **`ParamName`**: 
  - The name of the parameter.

### Shout-Outs

I certainly can't take much credit here; there's already a big, growing list of people who have helped or inspired:

- [Will White](https://github.com/willwhite1)
- [Michael Swart](https://michaeljswart.com/)
- [Dan Guzman](https://dbdelta.com)
- [Andy Mallon](https://am2.co)
- [Melissa Connors](https://www.sentryone.com/blog/author/melissa-connors)
- [Arvind Shyamsundar](https://github.com/arvindshmicrosoft)

### Future Enhancements

Basically, more sources, more targets, more options.

- need to make it so it takes shorthand for a subset of databases, like all user databases on an instance
- inject metadata in output so it better reflects source 
  - say, if, two different files (or even different batches in the same file) contain procedures with same name but different interface
  - or if two databases contain the same procedure name, or two instances contain similar databases, etc.
- need to define output target
  - output to console, out-csv, out-xml, out-json, to pipeline, or to a file
  - pass additional credentials (or reuse same credentials) to save the DataTable to a database
    - would need database, procedure, parameter name or database, TVP type name (give a definition for this), table name
- cleaner error handling (e.g. for a typo in file/folder path)
  - also make error handling for database connections optionally more verbose for diagnostics
- maybe it could be an ADS extension, too (see [this post](https://cloudblogs.microsoft.com/sqlserver/2020/09/02/the-release-of-the-azure-data-studio-extension-generator-is-now-available/?_lrsc=85b3aad6-1627-46a6-bf7c-b7e16efb7e6a)) and/or a web-based offering (Azure function)
