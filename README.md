# ParamParser

You're here because you want to know the default values defined for your stored procedures, but SQL Server makes this next to impossible using native functionality. I started this little project to make it easier. It's a simple C# console app that parses parameter default values and stores them in a table.

### Background

Since SQL Server first supported parameters to stored procedures and functions, we've had access to metadata about those parameters, but this metadata has never been complete:

- [x] parameter name
- [x] data type
- [x] ordinal position
- [x] direction (input / output)
- [x] nullable
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

After answering a [recent question on Stack Overflow](https://stackoverflow.com/q/63581531/61305) about this, and tracing my steps back ~15 years, I came across [this great post](https://michaeljswart.com/2014/04/removing-comments-from-sql/) by Michael Swart. In that post, Michael uses the ScriptDom's [TSqlParser](https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.transactsql.scriptdom.tsqlparser) to remove both single-line and multi-line comments from a block of T-SQL. This gave me all the motivation I needed to take this a few steps further.

What I ended up with is here, and this is what it was able to parse out of the above monstrosity:

![Example result](https://sqlblog.org/wp-content/uploads/2020/08/param-parser-example.png)

### Dependencies / How to Start

I developed this solution using Visual Studio Code on a Mac. In order to debug and build, I had to install the OmniSharp C# extension, and update both SqlClient and ScriptDom packages.

- Install the [OmniSharp C# extension for VS Code](https://github.com/OmniSharp/omnisharp-vscode)
- Add the SqlClient and ScriptDom packages. At a Terminal in VS Code:
  - `dotnet add package System.Data.SqlClient --version 4.8.2`
  - `dotnet add package Microsoft.SqlServer.TransactSql.ScriptDom --version 150.4573.2`
  - _Note that when you read this there may be newer versions of these packages available._
- Create the supporting database by running **ParamParser_Central.sql** (this creates a database called ParamParser_Central)
- Update the code to use your connection string particulars
- Build **ParamParser.cs** as part of a new console application
  - The shortest path is to build a Hello World console app following [these easy steps](https://docs.microsoft.com/en-us/dotnet/core/tutorials/with-visual-studio-code) and then just replace the code in **Program.cs** with my code in **ParamParser.cs**.
- Test it out:
  - To test the demo I've provided, run **ParamParser_Demo.sql** (this creates a database called ParamParser_Demo), the code references this as the target database by default
  - To test against your own database, just pass the target database in as the first argument (`ParamParser "targetDB"`) or change the `targetDB` variable in the code at runtime
  - In either case, inspect the contents of ParamParser_Central.dbo.ModuleParams

### Future Enhancements

- Break database objects into separate files
- More robust logic in the DatabaseSupport.sql script to handle changes
- Command line arguments to support multiple target databases, all databases, all user databases
- Connection info off in appconfig / JSON instead of within the app code
