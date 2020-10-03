# ParamParser

You're here because you want to know the default values defined for your stored procedures and functions, but SQL Server makes this next to impossible using native functionality. I started this little project to make it easier. It's a simple PowerShell script that parses parameter information out of modules stored in a database, database scripts stored in files, or raw scripts inline.

### Background

I've begun writing about the journey here:

* [Parse parameter default values using PowerShell - Part 1](https://sqlperformance.com/2020/09/sql-performance/paramparser-1)
* [Parse parameter default values using PowerShell - Part 2](https://sqlperformance.com/2020/10/sql-performance/paramparser-2)

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

The code here parses through all that garbage and outputs the following to `Out-GridView`:

![](https://sqlperformance.com/wp-content/uploads/2020/10/pp-some-proc-grid-view.png)

There is also a way to log to a database table (not yet enabled), which will store data like this:

![](https://sqlperformance.com/wp-content/uploads/2020/10/pp-database-logged.png)

As another reference point, here is what a call against the most recent version of `AdventureWorks` looks like (not quite as interesting as I thought it would be, since they don't use a lot of default values for parameters):

![](https://sqlperformance.com/wp-content/uploads/2020/10/pp-advworks-output.png)

### Dependencies / How to Start

You need to have the latest ScriptDom.dll locally in order to use the related classes here, but we can't legally give you that file. After that, you can import the ParamParser module, and then run `Get-ParsedParams` with a string, a database, a file, or a directory. 

- Clone this repository
- Run `init.ps1`, which will extract the latest version of `ScriptDom.dll` from [here](https://docs.microsoft.com/en-us/sql/tools/sqlpackage-download) into the script root
- To run, in any PS session, `cd` to the repository folder, then:
  - `Import-Module ./ParamParser.psm1`
    - If testing local changes, add `-Force` to overwrite
  - **For input:**
    - To pass in a raw script:
      - `Get-ParsedParams -Script "CREATE PROCEDURE dbo.foo @bar int = 1 AS PRINT 1;"`
    - To pull from one or more files:
      - `Get-ParsedParams -File "./dirDemo/dir1/sample1.sql"`
      - `Get-ParsedParams -File "./dirDemo/dir1/sample1.sql", "./dirDemo/dir2/sample2.sql"`
    - To pull from one or more directories:
      - `Get-ParsedParams -Directory "./dirDemo/"`
      - `Get-ParsedParams -Directory "./dirDemo/dir1/", "./dirDemo/dir2/"`
    - To pull from one or more SQL Server databases:
      - Using current Windows Auth credentials:
        - `Get-ParsedParams -ServerInstance "server\instance" -Database "db" -AuthenticationMode "Windows"`
        - `Get-ParsedParams -ServerInstance "server\instance" -Database "db"` (Windows is the default)
      - To pass in a SecureString SQL Authentication password (assuming you'd get SecureString from another source):
        - `$password = "password" | ConvertTo-SecureString -AsPlainText -Force`
        - `Get-ParsedParams -ServerInstance "server" -Database "db" -AuthenticationMode "SQL" -SQLAuthUsername "username" -SecurePassword $password`
      - To pass in a plaintext SQL Authentication password:
        - `Get-ParsedParams -ServerInstance "server" -Database "db" -AuthenticationMode "SQL" -SQLAuthUsername "username" -InsecurePassword "password"`
      - For multiple instances or databases (usually you won't provide multiple of both at the same time):
        - `Get-ParsedParams -ServerInstance "server1","server2" -Database "db"`
        - `Get-ParsedParams -ServerInstance "server" -Database "db1","db2"`
  - **For output:**
    - To get the output in `Out-GridView`:
      - `Get-ParsedParams -File "./dirDemo/dir1/sample1.sql" -GridView`
    - To get the output only in the console:
      - `Get-ParsedParams -File "./dirDemo/dir1/sample1.sql" -Console`
    - To also log the output to a database, run `.\database\DatabaseSupportObjects.sql` somewhere, and then:
      - `Get-ParsedParams -File "./dirDemo/dir1/sample1.sql" -LogToDatabase -LogToDBServerInstance "server" -LogToDBDatabase "database"`
      - this will assume Windows Authentiction, but you can  by adding:
        - `-LogToDBAuthenticationMode "Windows"` 
      - if you want SQL Authentication, add: 
        - `-LogToDBAuthenticationMode "SQL" -LogToDBSQLAuthUsername "user" -LogToDBInsecurePassword "password"`
    - If you don't specify `-GridView` or `-LogToDatabase`, you get `-Console` behavior
  - **For unit testing**, install Pester:
    - `Install-Module Pester`
    - This will allow you to execute unit tests for validation during development efforts
    - Execute tests: `Invoke-Pester -Path ./tests/*`

### What does it do

For now, it just outputs a `PSCustomObject` to the console using `Write-Output`, but you can optionally (a) output to `Out-GridView` and/or (b) log to a database.

I showed abbreviated samples above, but the elements in the `Write-Output` display are:

- **`Id`**: 
  - A simple counter incremented for every fragment visited.
- **`ModuleId`**: 
  - A counter that increments for every new procedure or function body we encounter (this has no relation to `object_id`).
- **`ObjectName`**: 
  - The one- or two-part name of the object.
- **`StatementType`**: 
  - Indicates `create`/`alter`/`create or alter` | `procedure` / `function`. When pulling from a database, this will always be a `create` statement.
- **`ParamId`**: 
  - A counter that increments for every new parameter we encounter inside a module.
- **`ParamName`**: 
  - The name of the parameter.
- **`DataType`**: 
  - Properly defined data type _as written_ - e.g. this will show `float(23)` if that's what the module defines, even if that isn't the data type stored in `sys.parameters`.
- **`DefaultValue`**: 
  - The literal text supplied by default, whether it's a string or numeric literal, an ODBC literal, or a string disguised as an identifier (e.g. `GETDATE`).
- **`IsOutput`**: 
  - Whether the parameter is defined as `OUT`/`OUTPUT`.
- **`IsReadOnly`**: 
  - Whether the parameter is read only (only valid for table-valued parameters).

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
- need more output targets
  - out-csv, out-xml, out-json, to pipeline, or to a file
  - make it easier to use .\database\DatabaseSupportObjects.sql to log each parse batch - currently quite manual
- cleaner error handling (e.g. for a typo in file/folder path)
  - also make error handling for database connections optionally more verbose for diagnostics
- maybe it could be an ADS extension, too (see [this post](https://cloudblogs.microsoft.com/sqlserver/2020/09/02/the-release-of-the-azure-data-studio-extension-generator-is-now-available/?_lrsc=85b3aad6-1627-46a6-bf7c-b7e16efb7e6a)) and/or a web-based offering (e.g. Azure function)
