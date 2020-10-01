CREATE TYPE dbo.ParameterSetTVP AS TABLE
(
	ModuleId int,
	ObjectName nvarchar(515),
	StatementType nvarchar(255),
	ParamId int,
	ParamName nvarchar(255),
	DataType nvarchar(255),
	DefaultValue nvarchar(max),
	IsOutput bit,
	IsReadOnly bit
);
GO

CREATE SEQUENCE dbo.ParameterLogBatchID AS bigint START WITH 1;
GO

CREATE TABLE dbo.ParameterLog
(
    BatchID bigint,
	EventTime datetime2 NOT NULL DEFAULT sysdatetime(),
    ModuleId int,
	ObjectName nvarchar(515),
	StatementType nvarchar(255),
	ParamId int,
	ParamName nvarchar(255),
	DataType nvarchar(255),
	DefaultValue nvarchar(max),
	IsOutput bit,
	IsReadOnly bit,
	INDEX cix_ParameterLog CLUSTERED(BatchID, EventTime)
);
GO

CREATE PROCEDURE dbo.LogParameters
	@ParameterSet dbo.ParameterSetTVP READONLY
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @BatchID bigint = NEXT VALUE FOR dbo.ParameterBatchID;

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
	  IsReadOnly
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
	  IsReadOnly
	FROM @ParameterSet 
	ORDER BY ModuleId, ParamId, ParamName;
END
GO