CREATE PROCEDURE dbo.do_the_thing
  @foo dbo.ya = /*what */ 5 READONLY,
  @bar int = 32 OUTPUT
AS
  SELECT 1;
GO
CREATE OR ALTER FUNCTION dbo./* yo */x--ya
(@a int /*dfdf*/ = --
2) RETURNS int AS BEGIN
  RETURN (SELECT @a + 1);
END
GO
CREATE FUNCTION dbo.do_less_than_nothing() 
RETURNS int AS BEGIN RETURN 1; END;
GO
CREATE PROCEDURE dbo.do_nothing AS PRINT 1;
GO
CREATE PROCEDURE [dbo].what
(
@p1 AS [int] = /* 1 */ 1 READONLY,
@p2 datetime = getdate OUTPUT,-- comment
@p3 dbo.tabletype = {t '2020-02-01 13:15:17'} READONLY
)
AS SELECT 5
GO
CREATE PROCEDURE dbo.whatnow AS PRINT 1;
GO
CREATE FUNCTION dbo.getstuff(@r int = 5)
RETURNS char(5)
AS
BEGIN
  RETURN ('hi');
END
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
  @i sysname = N'汉🤦‍学中',
  @j xml = N'<foo></bar>',
  @k dbo.[Email Address] = 'foo@bar.com',
  @l geography,
  @m decimal(12,4) = 3.45,
  @n nvarchar(max) = /* @not_a_param int = 5 AS BEGIN */ N'splungemort',
  @o nvarchar(17) = N'folab',
  /* @not_a_param int = 5 AS BEGIN */
  @p datetime2(6) = getdate,
  @q numeric(18,2) = 5,
  @r datetime = '20200101',
  @s float ( 53 ) = 54,
  @t float(25) = 75, -- becomes float(53) -- metadata problem, not me
  @u float(23) = 90, -- becomes real    -- again, metadata problem, not me
  @读🤦‍文 decimal(12,2) = 16.54,
  @w real = 5.678  
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