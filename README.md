# ParamParser

You're here because you want to know the default values defined for your stored procedures, but SQL Server makes this next to impossible using native functionality. I started this little project to make it easier. It's a simple Powershell script that parses parameter information out of modules stored in a database, database scripts stored in files, or raw scripts inline.

### Background

Since SQL Server first supported parameters to stored procedures and functions, we've had access to metadata about those parameters, but this metadata has never been complete:

- [x] parameter name
- [x] data type
- [x] ordinal position
- [x] direction (input / output)
- [x] read only
- [ ] ~whether it has a default value~
- [ ] ~the actual default value~

The last two are not in the metadata anywhere, in any version up to and including SQL Server 2019. [The `sys.parameters` catalog view](https://docs.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-parameters-transact-sql) contains the columns `has_default_value` and `default_value`, which sound promising, but these are only ever populated for CLR objects. Management Studio tells you about the _presence_ of a default value, but it doesn't get that from the system catalog; it gets that by parsing the module's definition. And it doesn't tell you the default value when there is one. 

Parsing these default values out of the module definition with T-SQL seems like a fun idea (even [the docs](https://docs.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-parameters-transact-sql) suggest it), until you get beyond the simplest case. I tried back in 2006 ([after complaining about it to no avail](https://feedback.azure.com/forums/908035-sql-server/suggestions/32891455-populate-has-default-value-in-sys-parameters)), and again in 2009, and gave up both times. There are so many edge cases that make even finding the start and end of the parameter list difficult:

- You can’t rely on the presence of (open and close parentheses) surrounding the parameter list, since they are optional (and may be found throughout the parameter list also).
- You can't easily parse for the first AS to mark the beginning of the body, since it can appear for other reasons.
- You can't rely on the presence of BEGIN to mark the beginning of the body, since it is optional.
- It is hard to split on commas, since they can appear inside comments, string literals, and data type declarations (think (precision, scale)).
- It is very hard to parse away both types of comments, which can appear anywhere, including inside string literals, and even inside other comments.
- You can inadvertently find important keywords inside string literals and comments.

Take this (intentionally ridiculous) example:

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

My first action on discovering that procedure would be to have the developer fix it. Barring that, I'd love to see T-SQL that will reliably parse it, returning only the input parameters and their default values, and not the local variables. If you don't believe me, give it a try. **It's hard.**

After answering a [recent question on Stack Overflow](https://stackoverflow.com/q/63581531/61305) about this, and tracing my steps back ~15 years, I came across [this great post](https://michaeljswart.com/2014/04/removing-comments-from-sql/) by Michael Swart. In that post, Michael uses the ScriptDom's [TSqlParser](https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.transactsql.scriptdom.tsqlparser) to remove both single-line and multi-line comments from a block of T-SQL. This gave me all the motivation I needed to take this a few steps further; I started with C#, but quickly determined that Powershell would be more flexible, more robust. And after several attempts at parsing through _every single token_ in a block of T-SQL, I found [Dan Guzman's post on ScriptDom](https://www.dbdelta.com/microsoft-sql-server-script-dom/), which talked about `TSqlFragmentVisitor`, and quickly changed directions.

The resulting code is being shared here, and this is what it was able to parse out of that small monstrosity:

![](https://sqlblog.org/wp-content/uploads/2020/09/param-parser-output-0.96.png)

### Dependencies / How to Start

This solution was developed using Visual Studio Code on a Mac. In order to debug and build, I had to install the Powershell extension, brew, and update the ScriptDom package to the latest version. If you're on Windows, you probably won't need any of this help, but please reach out if you have issues. 

- Install the [Powershell extension for VS Code](https://code.visualstudio.com/docs/languages/powershell)
- Install brew from [brew.sh](https://brew.sh/)
  - `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"`
- Install Powershell ([Microsoft instructions](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-macos?view=powershell-6))
  - `brew cask install powershell`
  - If pwsh is already available, make sure you have the latest version:
    - `brew update`
    - `brew cask upgrade powershell`
- Update ScriptDom
  - Download sqlpackage from [here](https://docs.microsoft.com/en-us/sql/tools/sqlpackage-download) (or the NuGet package from [here](https://www.nuget.org/packages/Microsoft.SqlServer.TransactSql.ScriptDom/))
  - Extract `Microsoft.SqlServer.TransactSql.ScriptDom.dll` from the package and copy it to the same folder as the .ps1 file
    - If you want to point elsewhere, update the `Add-Type` reference to point to that file location instead of `$($PSScriptRoot)`.
- Install Pester
  - `Install-Module Pester`
  - This will allow you to execute unit tests for validation during development efforts.
  - Execute tests: `Invoke-Pester -Path ./tests/*`

### What does it do

For now, it just takes a script (call at the end with lots of examples) and outputs a `PSCustomObject` to the console using `Write-Output`. I showed an abbreviated sample above, but the elements in the output are, perhaps not in the most logical order at present:

- **`Id`**: 
  - Simply a row number incremented for every fragment visited.
- **`ModuleId`**: 
  - A counter that increments for every new procedure or function body we encounter.
- **`ObjectName`**: 
  - The name of the object.
- **`ParamId`**: 
  - A counter that increments for every new parameter we encounter inside a module. (Currently 0-based but this should be 1-based.)
- **`StatementType`**: 
  - Whether it's create/alter/create or alter | procedure/function. Inside the body it's going to show `ProcedureParameter` but this should arguably show blank.
- **`DataType`**: 
  - Properly defined data type _as written_ - e.g. this will show `float(23)` if that's what the module defines, even if that isn't the data type stored in `sys.parameters`.
- **`DefaultValue`**: 
  - The literal text supplied by default, whether it's a string or numeric literal, an ODBC literal, or an identifier.
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

- need to make it so it takes a source as an argument
  - source can be a .sql file, array of files, folder, array of folders, or a database, array of databases, all user databases
    - for one or more folders, concat all the files with GO between each 
    - (maybe limit it to specific file types so we're not concatenting cat pictures)
    - for a database, same, concat all definitions together with GO between each
    - but inject metadata so output can reflect source 
      - (say if two different files (or even different batches in the same file) contain procedures with same name but different interface)
- fix `ParamId` to be 1-based
- should also accept path to ScriptDom.dll as an optional argument
- for now, just:
  - takes a raw script pasted in (call at the end with lots of examples)
  - and outputs a PSCustom object to the console usng Write-Output.
- need to also take an argument to define output target
  - output to console
  - out-csv, out-xml, out-json, to pipeline, or to a file
  - pass credentials to save the DataTable to a database
    - would need database, procedure, parameter name or database, TVP type name (give a definition for this), table name
- this now handles multiple batches, so sp_whoisactive, no problem
  - but it won't parse CREATE PROCEDURE from inside dynamic SQL
- Maybe it could be an ADS extension, too (see [this post](https://cloudblogs.microsoft.com/sqlserver/2020/09/02/the-release-of-the-azure-data-studio-extension-generator-is-now-available/?_lrsc=85b3aad6-1627-46a6-bf7c-b7e16efb7e6a)) and/or a web-based offering (Azure function)
