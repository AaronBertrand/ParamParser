CREATE TYPE dbo.ParameterSetTVP AS TABLE
(
    ModuleId      int,
    ObjectName    nvarchar(515),
    StatementType nvarchar(255),
    ParamId       int,
    ParamName     nvarchar(255),
    DataType      nvarchar(255),
    DefaultValue  nvarchar(max),
    IsOutput      bit,
    IsReadOnly    bit,
    Source        nvarchar(max)
);
GO

CREATE SEQUENCE dbo.ParameterLogBatchID AS bigint START WITH 1;
GO

CREATE TABLE dbo.ParameterLog
(
    BatchID       bigint,
    EventTime     datetime2 NOT NULL DEFAULT sysdatetime(),
    ModuleId      int,
    ObjectName    nvarchar(515),
    StatementType nvarchar(255),
    ParamId       int,
    ParamName     nvarchar(255),
    DataType      nvarchar(255),
    DefaultValue  nvarchar(max),
    IsOutput      bit,
    IsReadOnly    bit,
    Source        nvarchar(max)
);
GO
CREATE CLUSTERED INDEX cix_ParameterLog ON dbo.ParameterLog(BatchID, EventTime, ModuleId, ParamId);
GO
CREATE PROCEDURE dbo.LogParameters
	@ParameterSet dbo.ParameterSetTVP READONLY
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @BatchID bigint = NEXT VALUE FOR dbo.ParameterLogBatchID;

	INSERT dbo.ParameterLog
	(
	  BatchId, 
	  ModuleId, 
	  ObjectName, 
	  StatementType, 
	  ParamId, 
	  ParamName, 
	  DataType, 
	  DefaultValue, 
	  IsOutput, 
	  IsReadOnly,
	  Source
	)
	SELECT 
	  @BatchId, 
	  ModuleId, 
	  ObjectName, 
	  StatementType, 
	  ParamId, 
	  ParamName, 
	  DataType, 
	  DefaultValue, 
	  IsOutput, 
	  IsReadOnly,
	  Source
	FROM @ParameterSet 
	ORDER BY ModuleId, ParamId;
END
GO