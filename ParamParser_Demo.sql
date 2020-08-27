/*
  This script is destructive. It drops the database and re-creates it.

  These are just demos that show ParamParser results out of the box.
  Feel free to try extracting the parameter default values with T-SQL.
*/

USE master;
GO

IF DB_ID(N'ParamParser_Demo') IS NOT NULL
BEGIN
  EXEC master.sys.sp_executesql N'
    ALTER DATABASE ParamParser_Demo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE IF EXISTS ParamParser_Demo;
    CREATE DATABASE ParamParser_Demo;';
END
GO

USE ParamParser_Demo;
GO
-- two procedures with really messed up parameter lists
GO
/* AS BEGIN , @a int = 7, comments can appear anywhere */
CREATE PROCEDURE dbo.p1
    -- AS BEGIN, @a int = 7 'blat' AS =
    /* AS BEGIN, @a int = 7 'blat' AS = */
    @a AS /* comment here because -- chaos */ int = 5,
    @b AS varchar(64) = 'AS = /* BEGIN @a, int = 7 */ ''blat'''
  AS
    -- @b int = 72,
    DECLARE @c int = 5;
    SET @c = 6;
GO

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

CREATE FUNCTION dbo.GetWeek_TF(@StartDate date = /* 🤦‍♂️ */ getdate)
RETURNS @x TABLE(i int)
WITH SCHEMABINDING
AS
BEGIN
  INSERT @x SELECT 1;
  RETURN;
END
GO

CREATE FUNCTION dbo.GetWeek_FN(@StartDate date = /* 🤦‍♂️ */ getdate)
RETURNS date
WITH SCHEMABINDING
AS
BEGIN
  RETURN (@StartDate);
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
  @u float(23) = 90, -- becomes real      -- again, metadata problem, not me
  @v real = 5.678  
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

-- now run ParamParser, and then:

/*
SELECT 
    [object] = QUOTENAME(s.name) + N'.' + QUOTENAME(o.name), 
    [object_type] = o.type, 
    [param] = mp.name, 
    mp.friendly_type_name, 
    mp.has_default_value, 
    mp.default_value,
    mp.parameter_id
  FROM sys.objects AS o
  INNER JOIN sys.schemas AS s
    ON o.[schema_id] = s.[schema_id]
  INNER JOIN ParamParser_Central.dbo.ModuleParams AS mp
    ON o.[object_id] = mp.[object_id]
  WHERE o.type IN (N'P', N'FN', N'IF', N'TF')
  ORDER BY [object], mp.parameter_id;
*/

/*
Results:

object              object_type  param       friendly_type_name    has_default_value    default_value                             parameter_id
[dbo].[GetWeek_FN]  FN           @StartDate	 date                  1                    getdate                                   1
[dbo].[GetWeek_IF]	IF	         @StartDate  date                  1                    getdate                                   1
[dbo].[GetWeek_TF]	TF           @StartDate  date                  1                    getdate                                   1
[dbo].[p1]          P            @a          int                   1                    5                                         1
[dbo].[p1]          P            @b          varchar(64)           1                    'AS = /* BEGIN @a, int = 7 */ ''blat'''   2
[dbo].[p2]          P            @bar        varchar(32)           1                    'AS'                                      1
[dbo].[p2]          P            @d          datetime              1                    sysdatetime                               2
[dbo].[p2]          P            @splunge    int                   1                    NULL                                      3
[dbo].[p2]          P          	 @mort       int                   1                    5                                         4
[dbo].[p2]          P          	 @qwerty     varbinary(8)          1                    1                                         5
[dbo].[p3]          P          	 @a          int                   1                    5                                         1
[dbo].[p3]          P          	 @b          varchar(32)           1                    '/* @not_a_param int = 5 AS BEGIN */'     2
[dbo].[p3]          P          	 @c          datetime              1                    sysdatetime                               3
[dbo].[p3]          P          	 @d          datetime              1                    getdate                                   4
[dbo].[p3]          P          	 @e          binary(8)             1                    0x000000FF                                5
[dbo].[p3]          P          	 @f          datetime              0                                                              6
[dbo].[p3]          P          	 @g          int                   0                                                              7
[dbo].[p3]          P          	 @h          dbo.tabletype         0                                                              8
[dbo].[p3]          P          	 @i          sysname               1                    N'fl读写汉oo🤦‍♂️fl学中文oo'                   9
[dbo].[p3]          P          	 @j          xml                   1                    N'<foo></bar>'                            10
[dbo].[p3]          P          	 @k          dbo.EmailAddress      1                    'foo@bar.com'                             11
[dbo].[p3]          P          	 @l          geography             0	                                                          12
[dbo].[p3]          P          	 @m          decimal(12,4)         1                    3.45                                      13
[dbo].[p3]          P          	 @n          nvarchar(max)         1                    N'splungemort'                            14
[dbo].[p3]          P          	 @o          nvarchar(17)          1                    N'folab'                                  15
[dbo].[p3]          P          	 @p          datetime2(6)          1                    getdate                                   16
[dbo].[p3]          P          	 @q          numeric(18,2)         1                    5                                         17
[dbo].[p3]          P          	 @r          datetime              1                    '20200101'                                18
[dbo].[p3]          P          	 @s          float(53)             1                    54                                        19
[dbo].[p3]          P          	 @t          float(53)             1                    75                                        20
[dbo].[p3]          P          	 @u          real                  1                    90                                        21
[dbo].[p3]          P          	 @v          real                  1                    5.678                                     22
*/