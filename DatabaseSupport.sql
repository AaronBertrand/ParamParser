USE master;
GO

/*
ALTER DATABASE Utility SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS Utility;
GO
CREATE DATABASE Utility;
GO
*/

USE Utility; -- or wherever you put central DBA-type database objects
GO

/*
DROP PROCEDURE IF EXISTS dbo.SaveModuleParams, dbo.GetAllModulesWithParams;
GO
DROP TYPE IF EXISTS dbo.ParamsWithDefaults;
GO
DROP TABLE IF EXISTS dbo.ModuleParams;
GO
*/

CREATE TYPE dbo.ParamsWithDefaults
AS TABLE
(
    object_id      int,
    name           nvarchar(128),
    default_value  nvarchar(4000),
    INDEX CIX_tvp CLUSTERED (object_id, name)
);
GO

CREATE TABLE dbo.ModuleParams
(
    database_id        int,
    object_id          int,
    name               nvarchar(128),
    friendly_type_name sysname,
    has_default_value  AS (CONVERT(bit, CASE WHEN default_value > '' THEN 1 ELSE 0 END)),
    default_value      nvarchar(4000),
    parameter_id       int,
    capture_time       datetime2 NOT NULL DEFAULT sysutcdatetime(),
    INDEX CIX_ModuleParams CLUSTERED (database_id, object_id, name)
);
GO

CREATE PROCEDURE dbo.SaveModuleParams
  @dbname sysname = N'tempdb',
  @params AS dbo.ParamsWithDefaults READONLY
AS
BEGIN
  SET NOCOUNT ON;
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

  -- sadly can't pass TVP into a database where that type doesn't exist, so:
  SELECT * INTO #params FROM @params;

  BEGIN TRANSACTION;

  DELETE dbo.ModuleParams WHERE database_id = DB_ID(@dbname);

  -- arguably you don't need to copy data from sys.parameters,
  -- but this gives a snapshot as close as possible to when
  -- you parsed the parameter default values

  DECLARE @sql  nvarchar(max), 
          @exec nvarchar(max) = QUOTENAME(@dbname) + N'.sys.sp_executesql';

  -- This is really awful code that makes a presentable type name for the 
  -- data type of each parameter. It might have been easier to parse them.
  SET @sql = N'SELECT DB_ID(@dbname),
    mp.object_id, 
    mp.name, 
    friendly_type_name = CASE t.schema_id WHEN 4 THEN N'''' ELSE ts.name + N''.'' END + t.name
        + CASE WHEN (t.system_type_id < 41 OR t.system_type_id BETWEEN 44 AND 61)
              OR t.user_type_id   >= 256
              OR t.system_type_id IN (98,99,104,122,127,240,189,241)
          THEN N''''
        WHEN t.system_type_id IN (35,99,165,167,173,175,231,239,173)
          THEN N''('' + CASE WHEN p.max_length = -1 THEN N''max'' ELSE CONVERT(varchar(11), p.max_length 
               / CASE WHEN t.system_type_id IN (231,239) THEN 2 ELSE 1 END) END + N'')''
        WHEN t.system_type_id IN (41,42,43) 
          THEN N''('' + CONVERT(varchar(11), p.scale) + N'')''
        WHEN t.system_type_id = 62 
          THEN N''('' + CONVERT(varchar(11), p.precision) + N'')''
        WHEN t.system_type_id IN (106, 108) 
          THEN N''('' + CONVERT(varchar(2), p.precision) + N'','' + CONVERT(varchar(2), p.scale) + N'')''
        ELSE N'''' END,
    default_value = COALESCE(mp.default_value, N''''),
    p.parameter_id
  FROM #params AS mp
  INNER JOIN sys.parameters AS p
    ON mp.[object_id] = p.[object_id]
    AND mp.name = p.name
  LEFT OUTER JOIN sys.types AS t
    ON (p.system_type_id = t.system_type_id)
    AND (p.system_type_id <> t.system_type_id
    OR p.user_type_id = t.user_type_id)
  LEFT OUTER JOIN sys.schemas AS ts
    ON t.schema_id = ts.schema_id;';

  INSERT dbo.ModuleParams(database_id, object_id, name, friendly_type_name, default_value, parameter_id)
  EXEC @exec @sql, N'@dbname sysname', @dbname;

  COMMIT TRANSACTION;
END
GO

CREATE PROCEDURE dbo.GetAllModulesThatHaveParams
  @dbname sysname = N'tempdb'
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @sql  nvarchar(max), 
          @exec nvarchar(max) = QUOTENAME(@dbname) + N'.sys.sp_executesql';

  SET @sql = N'SELECT object_id, definition = OBJECT_DEFINITION(object_id)
    FROM sys.objects AS o 
    WHERE type IN (N''P'', N''FN'', N''IF'', N''TF'')
      AND EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = o.object_id);';

  EXEC @exec @sql;
END
GO