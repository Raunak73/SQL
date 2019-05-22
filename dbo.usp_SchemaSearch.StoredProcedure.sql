GO
IF OBJECT_ID('dbo.usp_SchemaSearch') IS NOT NULL DROP PROCEDURE dbo.usp_SchemaSearch;
GO
-- =============================================
-- Author:		Chad Baldwin
-- Create date: 2015-04-13
-- Description:	Searches Proc names, proc contents (whole word and partial), Table names, Column Names and Job Step code
-- =============================================
CREATE PROCEDURE dbo.usp_SchemaSearch (
	@Search				VARCHAR(200),
	@DBName				VARCHAR(50)		= NULL,
	@ANDSearch			VARCHAR(200)	= NULL,
	@ANDSearch2			VARCHAR(200)	= NULL,
	@WholeOnly			BIT				= 0,
	@SearchObjContents	BIT				= 1,
	@FindReferences		BIT				= 1,
	@Debug				BIT				= 0
)
AS
BEGIN
	/*
		DECLARE
			@Search				VARCHAR(200)	= 'TestTest',
			@DBName				VARCHAR(50)		= NULL,
			@ANDSearch			VARCHAR(200)	= NULL,
			@ANDSearch2			VARCHAR(200)	= NULL,
			@WholeOnly			BIT				= 0,
			@SearchObjContents	BIT				= 1,
			@FindReferences		BIT				= 1,
			@Debug				BIT				= 0
	--*/
	
	SET NOCOUNT ON

	IF (@Search = '')
		THROW 51000, 'Must Provide a Search Criteria', 1;

	SET @DBName		= NULLIF(@DBName,'')
	SET @Search		= REPLACE(@Search					,'_','[_]')
	SET @ANDSearch	= REPLACE(NULLIF(@ANDSearch,'')		,'_','[_]')
	SET @ANDSearch2	= REPLACE(NULLIF(@ANDSearch2,'')	,'_','[_]')

	SELECT 'SearchCriteria: ', CONCAT('''', @Search, '''', ' AND ''' + @ANDSearch + '''', ' AND ''' + @ANDSearch2 + '''')

	--Populate table with a list of all databases user has access to
	DECLARE @DBs TABLE (ID INT IDENTITY(1,1) NOT NULL, DBName VARCHAR(100) NOT NULL, HasAccess BIT NOT NULL, DBOnline BIT NOT NULL)
	INSERT INTO @DBs
	SELECT DBName	= [name]
		, HasAccess	= HAS_PERMS_BY_NAME([name], 'DATABASE', 'ANY')
		, DBOnline	= IIF([state] = 0, 1, 0) --IIF([status] & 512 <> 512, 1, 0)
	FROM [master].sys.databases
	WHERE database_id > 4	--Filter out system databases
		AND ([name] = @DBName OR @DBName IS NULL)
	--	AND [name] NOT LIKE '%[_]New'
	--	AND [name] NOT LIKE '%[_]Old'
	--	AND [name] NOT LIKE '%JATO%'
	ORDER BY HasAccess DESC, DBOnline DESC

	SELECT * FROM @DBs db

	IF (@@ROWCOUNT > 50)
	BEGIN
		RAISERROR('That''s a lot of databases....Might not be a good idea to run this',0,1) WITH NOWAIT;
	END

	SELECT 'Only databases with access are scanned'
	SELECT DBName, HasAccess, DBOnline FROM @DBs ORDER BY DBName

	DECLARE	@PartSearch			VARCHAR(512)	=			 '%' + @Search     + '%',
			@ANDPartSearch		VARCHAR(512)	=			 '%' + @ANDSearch  + '%',
			@ANDPartSearch2		VARCHAR(512)	=			 '%' + @ANDSearch2 + '%',
			@WholeSearch		VARCHAR(512)	=  '%[^0-9A-Z_]' + @Search     + '[^0-9A-Z_]%',
			@ANDWholeSearch		VARCHAR(512)	=  '%[^0-9A-Z_]' + @ANDSearch  + '[^0-9A-Z_]%',
			@ANDWholeSearch2	VARCHAR(512)	=  '%[^0-9A-Z_]' + @ANDSearch2 + '[^0-9A-Z_]%',
			@CRLF				CHAR(2)			= CHAR(13)+CHAR(10)

	IF OBJECT_ID('tempdb..#ObjNames')		IS NOT NULL DROP TABLE #ObjNames		--SELECT * FROM #ObjNames
	CREATE TABLE #ObjNames		(ID INT IDENTITY(1,1) NOT NULL, [Database] NVARCHAR(128) NOT NULL, SchemaName NVARCHAR(32) NOT NULL, ObjectName VARCHAR(512) NOT NULL, [Type_Desc] VARCHAR(100) NOT NULL)

	IF OBJECT_ID('tempdb..#ObjectContents')	IS NOT NULL DROP TABLE #ObjectContents	--SELECT * FROM #ObjectContents
	CREATE TABLE #ObjectContents(ID INT IDENTITY(1,1) NOT NULL, ObjectID INT NOT NULL, [Database] NVARCHAR(128) NOT NULL, SchemaName NVARCHAR(32) NOT NULL, ObjectName VARCHAR(512) NOT NULL, [Type_Desc] VARCHAR(100) NOT NULL, MatchQuality VARCHAR(100) NOT NULL)

	IF OBJECT_ID('tempdb..#Objects')		IS NOT NULL DROP TABLE #Objects			--SELECT * FROM #Objects
	CREATE TABLE #Objects		(ID INT IDENTITY(1,1) NOT NULL, [Database] NVARCHAR(128) NOT NULL, SchemaName NVARCHAR(32) NOT NULL, ObjectName VARCHAR(512) NOT NULL, [Type_Desc] VARCHAR(100) NOT NULL, [Definition] VARCHAR(MAX) NULL)

	IF OBJECT_ID('tempdb..#Columns')		IS NOT NULL DROP TABLE #Columns			--SELECT * FROM #Columns
	CREATE TABLE #Columns		(ID INT IDENTITY(1,1) NOT NULL, [Database] NVARCHAR(128) NOT NULL, SchemaName NVARCHAR(32) NOT NULL, Table_Name SYSNAME NOT NULL, Column_Name SYSNAME NOT NULL, Data_Type NVARCHAR(128) NOT NULL, Character_Maximum_Length INT NULL)

	IF OBJECT_ID('tempdb..#SQL')			IS NOT NULL DROP TABLE #SQL				--SELECT * FROM #SQL
	CREATE TABLE #SQL			(ID INT IDENTITY(1,1) NOT NULL, [Database] NVARCHAR(128) NOT NULL, SQLCode VARCHAR(MAX) NOT NULL)

	RAISERROR('',0,1) WITH NOWAIT;
	------------------------------------------------------------------------------
	
	------------------------------------------------------------------------------
		IF OBJECT_ID('tempdb..#JobStepContents') IS NOT NULL DROP TABLE #JobStepContents --SELECT * FROM #JobStepContents
		SELECT DBName	= s.[database_name]
			, JobName	= j.[name]
			, StepID	= s.step_id
			, StepName	= s.step_name
			, [Enabled]	= j.[enabled]
			, StepCode	= s.command
			, JobID		= j.job_id
		INTO #JobStepContents
		FROM msdb.dbo.sysjobs j
			JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
	------------------------------------------------------------------------------
	
	------------------------------------------------------------------------------
		IF OBJECT_ID('tempdb..#JobStepNames_Results') IS NOT NULL DROP TABLE #JobStepNames_Results --SELECT * FROM #JobStepNames_Results
		SELECT DBName, JobName, StepID, StepName, [Enabled], JobID
		INTO #JobStepNames_Results
		FROM #JobStepContents
		WHERE (	   (JobName		LIKE @PartSearch AND JobName	LIKE COALESCE(@ANDPartSearch, JobName)	AND JobName		LIKE COALESCE(@ANDPartSearch2, JobName))
				OR (StepName	LIKE @PartSearch AND StepName	LIKE COALESCE(@ANDPartSearch, StepName)	AND StepName	LIKE COALESCE(@ANDPartSearch2, StepName))
			)
			AND (DBName = @DBName OR @DBName IS NULL)

		IF (@@ROWCOUNT > 0)
		BEGIN
			SELECT 'Job/Step - Names'
			SELECT DBName, JobName, StepID, StepName, [Enabled], JobID FROM #JobStepNames_Results ORDER BY JobName, StepID
		END
		ELSE SELECT 'Job/Step - Names', 'NO RESULTS FOUND'

		RAISERROR('',0,1) WITH NOWAIT;
	------------------------------------------------------------------------------
	
	------------------------------------------------------------------------------
		IF OBJECT_ID('tempdb..#JobStepContents_Results') IS NOT NULL DROP TABLE #JobStepContents_Results --SELECT * FROM #JobStepContents_Results
		SELECT s.DBName, s.JobName, s.StepID, s.StepName, s.[Enabled], s.JobID
			, StepCode = TRY_CONVERT(XML, '<?query --'+@CRLF+s.StepCode+@CRLF+'--?>')
		INTO #JobStepContents_Results
		FROM #JobStepContents s
		WHERE s.StepCode LIKE @PartSearch
			AND (s.StepCode LIKE @ANDPartSearch  OR @ANDPartSearch  IS NULL)
			AND (s.StepCode LIKE @ANDPartSearch2 OR @ANDPartSearch2 IS NULL)
			AND (s.DBName = @DBName OR @DBName IS NULL)

		IF (@@ROWCOUNT > 0)
		BEGIN
			SELECT 'Job step - Contents'
			SELECT DBName, JobName, StepID, StepName, [Enabled], StepCode, JobID FROM #JobStepContents_Results ORDER BY JobName, StepID
		END
		ELSE SELECT 'Job step - Contents', 'NO RESULTS FOUND'

		RAISERROR('',0,1) WITH NOWAIT;
	------------------------------------------------------------------------------
	
	------------------------------------------------------------------------------
		--Loop through each database to grab objects
		--TODO: Maybe in the future use sp_MSforeachdb or BrentOzar's sp_foreachdb
		DECLARE @i INT = 1, @SQL VARCHAR(MAX) = '', @DB VARCHAR(100)
		WHILE (1=1)
		BEGIN
			SELECT @DB = DBName FROM @DBs WHERE ID = @i AND HasAccess = 1 AND DBOnline = 1
			IF @@ROWCOUNT = 0 BREAK;

			PRINT @DB

			SELECT @SQL = '
				USE ' + @DB

			IF (@SearchObjContents = 1)
			SELECT @SQL	= @SQL + '
				INSERT INTO #Objects ([Database], SchemaName, ObjectName, [Type_Desc], [Definition])
				SELECT DB_NAME(), SCHEMA_NAME(o.[schema_id]), o.[name], o.[type_desc], m.[definition]
				FROM sys.objects o
					JOIN sys.sql_modules m ON m.[object_id] = o.[object_id]'

			SELECT @SQL = @SQL + '
				INSERT INTO #ObjNames ([Database], SchemaName, ObjectName, [Type_Desc])
				SELECT DB_NAME(), SCHEMA_NAME([schema_id]), [name], [type_desc]
				FROM sys.objects
				WHERE [type_desc] <> ''SYSTEM_TABLE''
					AND [name] LIKE '''+@PartSearch+''''
					+ IIF(@ANDPartSearch  IS NOT NULL, ' AND [name] LIKE '''+@ANDPartSearch +'''', '')
					+ IIF(@ANDPartSearch2 IS NOT NULL, ' AND [name] LIKE '''+@ANDPartSearch2+'''', '')

			SELECT @SQL	= @SQL + '
				INSERT INTO #Columns ([Database], SchemaName, Table_Name, Column_Name, Data_Type, Character_Maximum_Length)
				SELECT TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, UPPER(DATA_TYPE), CHARACTER_MAXIMUM_LENGTH
				FROM INFORMATION_SCHEMA.COLUMNS
				WHERE COLUMN_NAME LIKE '''+@PartSearch+''''
					+ IIF(@ANDPartSearch  IS NOT NULL, ' AND COLUMN_NAME LIKE '''+@ANDPartSearch +'''', '')
					+ IIF(@ANDPartSearch2 IS NOT NULL, ' AND COLUMN_NAME LIKE '''+@ANDPartSearch2+'''', '')

			EXEC sys.sp_sqlexec @p1 = @SQL

			INSERT INTO #SQL ([Database], SQLCode) SELECT @DB, @SQL
			SELECT @i += 1

			RAISERROR('',0,1) WITH NOWAIT;
		END
	------------------------------------------------------------------------------
	
	------------------------------------------------------------------------------
		IF (EXISTS(SELECT * FROM #Columns))
		BEGIN
			SELECT 'Columns'
		
			SELECT [Database], SchemaName, Table_Name, Column_Name, Data_Type, Character_Maximum_Length
			FROM #Columns
			ORDER BY [Database], SchemaName, Table_Name, Column_Name
		END
		ELSE SELECT 'Columns', 'NO RESULTS FOUND'

		RAISERROR('',0,1) WITH NOWAIT;
	------------------------------------------------------------------------------
	
	------------------------------------------------------------------------------
		--Covers all objects - Views, Procs, Functions, Triggers, Tables, Constraints
		IF (EXISTS(SELECT * FROM #ObjNames))
		BEGIN
			SELECT 'Object - Names'

			SELECT [Database], SchemaName, ObjectName, [Type_Desc]
			FROM #ObjNames
			ORDER BY [Database], SchemaName, [Type_Desc], ObjectName
		END
		ELSE SELECT 'Object - Names', 'NO RESULTS FOUND'

		RAISERROR('',0,1) WITH NOWAIT;
	------------------------------------------------------------------------------
	
	------------------------------------------------------------------------------
	IF (@SearchObjContents = 1)
	BEGIN
		INSERT INTO #ObjectContents (ObjectID, [Database], SchemaName, ObjectName, [Type_Desc], MatchQuality)
		SELECT o.ID, o.[Database], o.SchemaName, o.ObjectName, o.[Type_Desc]
			, 'Whole Match'
		FROM #Objects o
		WHERE    '#'+o.[Definition]+'#' LIKE @WholeSearch
			AND ('#'+o.[Definition]+'#' LIKE @ANDWholeSearch  OR @ANDWholeSearch  IS NULL)
			AND ('#'+o.[Definition]+'#' LIKE @ANDWholeSearch2 OR @ANDWholeSearch2 IS NULL)

		IF (@WholeOnly = 0)
			INSERT INTO #ObjectContents (ObjectID, [Database], SchemaName, ObjectName, [Type_Desc], MatchQuality)
			SELECT o.ID, o.[Database], o.SchemaName, o.ObjectName, o.[Type_Desc]
				, 'Partial Word Match'
			FROM #Objects o
			WHERE    o.[Definition] LIKE @PartSearch
				AND (o.[Definition] LIKE @ANDPartSearch  OR @ANDPartSearch  IS NULL)
				AND (o.[Definition] LIKE @ANDPartSearch2 OR @ANDPartSearch2 IS NULL)

		IF OBJECT_ID('tempdb..#ObjectContentsResults') IS NOT NULL DROP TABLE #ObjectContentsResults --SELECT * FROM #ObjectContentsResults
		SELECT ID = IDENTITY(INT,1,1), w.ObjectID, w.[Database], w.SchemaName, w.ObjectName, w.[Type_Desc], w.MatchQuality
		INTO #ObjectContentsResults
		FROM (
			SELECT ObjectID, [Database], SchemaName, ObjectName, [Type_Desc], MatchQuality
				, RN = ROW_NUMBER() OVER (PARTITION BY [Database], ObjectName, [Type_Desc] ORDER BY IIF(MatchQuality = 'Whole Match', 1, 0) DESC) --If a whole match is found, prefer that over partial match
			FROM #ObjectContents
		) w
		WHERE w.RN = 1
			AND w.ObjectName NOT LIKE @Search

		--Name match - if you search for something and we find an exact match for that name, separate it out
		IF (EXISTS (SELECT * FROM #Objects o WHERE ObjectName LIKE @Search))
		BEGIN
			SELECT 'Object - Exact Name match'
			SELECT [Database], SchemaName, ObjectName, [Type_Desc], CompleteObjectContents = CONVERT(XML, CONCAT('<?query --', @CRLF, REPLACE(REPLACE([Definition],'<?','/*'),'?>','*/'), @CRLF, '--?>'))
			FROM #Objects
			WHERE ObjectName LIKE @Search
			ORDER BY [Database], [Type_Desc], ObjectName
		END
		------------------------------------------------------------------------------
		
		------------------------------------------------------------------------------
			IF (EXISTS(SELECT * FROM #ObjectContentsResults WHERE ObjectName NOT LIKE @Search))
			BEGIN
				SELECT 'Object - Contents' --Covers all objects - Views, Procs, Functions, Triggers

				IF OBJECT_ID('tempdb..#ObjectContentsResults2') IS NOT NULL DROP TABLE #ObjectContentsResults2 --SELECT * FROM #ObjectContentsResults2
				SELECT r.ID, r.ObjectID, r.[Database], r.SchemaName, r.ObjectName, r.[Type_Desc], r.MatchQuality
					, QuickScript = CASE r.[Type_Desc] --This is mainly just to get a quick parsable snippet so that RedGate SQL Prompt will give you the hover popup to view its contents
										WHEN 'SQL_STORED_PROCEDURE'				THEN CONCAT('-- EXEC ', r.[Database], '.', r.SchemaName, '.', r.ObjectName)
										WHEN 'VIEW'								THEN CONCAT('-- SELECT TOP(100) * FROM ', r.[Database], '.', r.SchemaName, '.', r.ObjectName)
										WHEN 'SQL_TABLE_VALUED_FUNCTION'		THEN CONCAT('-- SELECT TOP(100) * FROM ', r.[Database], '.', r.SchemaName, '.', r.ObjectName, '() x')
										WHEN 'SQL_INLINE_TABLE_VALUED_FUNCTION'	THEN CONCAT('-- SELECT TOP(100) * FROM ', r.[Database], '.', r.SchemaName, '.', r.ObjectName, '() x')
										WHEN 'SQL_SCALAR_FUNCTION'				THEN CONCAT('-- EXEC ', r.[Database], '.', r.SchemaName, '.', r.ObjectName, '() x')
										WHEN 'SQL_TRIGGER'						THEN NULL --No action for triggers for now
										ELSE NULL
									END
					, SVNPath = CONCAT('%SVNPath%\Schema\',r.[Database],'\' --TODO: may change to be an input parameter where the base path is supplied rather than hardcoded as an env variable
									, CASE r.[Type_Desc]
										WHEN 'SQL_STORED_PROCEDURE'				THEN 'StoredProcedures\'					+ r.SchemaName + '.' + r.ObjectName + '.StoredProcedure.sql'
										WHEN 'VIEW'								THEN 'Views\'								+ r.SchemaName + '.' + r.ObjectName + '.View.sql'
										WHEN 'SQL_TABLE_VALUED_FUNCTION'		THEN 'Functions\Table-valued Functions\'	+ r.SchemaName + '.' + r.ObjectName + '.UserDefinedFunction.sql'
										WHEN 'SQL_INLINE_TABLE_VALUED_FUNCTION'	THEN 'Functions\Table-valued Functions\'	+ r.SchemaName + '.' + r.ObjectName + '.UserDefinedFunction.sql'
										WHEN 'SQL_SCALAR_FUNCTION'				THEN 'Functions\Scalar-valued Functions\'	+ r.SchemaName + '.' + r.ObjectName + '.UserDefinedFunction.sql'
										WHEN 'SQL_TRIGGER'						THEN 'Triggers\'							+ r.SchemaName + '.' + r.ObjectName + '.Trigger.sql'
										ELSE NULL
									END
								)
				INTO #ObjectContentsResults2
				FROM #ObjectContentsResults r
				WHERE r.ObjectName NOT LIKE @Search

				IF (@FindReferences = 1)
				BEGIN
					IF OBJECT_ID('tempdb..#ObjectReferences') IS NOT NULL DROP TABLE #ObjectReferences --SELECT * FROM #ObjectReferences
					SELECT r.ID
						, Label = IIF(x.CombName IS NOT NULL, '--- mentioned in --->>', NULL)
						, Ref_Name = x.CombName
						, Ref_Type = x.[Type_Desc]
					INTO #ObjectReferences
					FROM #ObjectContentsResults r
						--TODO: Change mentioned in / called by code to use referening entities dm query as a "whole match" so that it's more accurate as to which instance of the object is being referenced, but contintue to also do string matching as a "partial match"
						CROSS APPLY (SELECT SecondarySearch = '%EXEC%[^0-9A-Z_]' + REPLACE(r.ObjectName,'_','[_]') + '[^0-9A-Z_]%') ss --Whole search name, preceded by"EXEC" --Not perfect because it can match procs that have same name in multiple databases
						OUTER APPLY ( --Find all likely called by references, exact matches only
							SELECT x.CombName, x.[Type_Desc]
							FROM (
								--Procs/Triggers
								SELECT CombName = o.[Database]+'.'+o.SchemaName+'.'+o.ObjectName, o.[Type_Desc]
								FROM #Objects o
								WHERE '#'+[Definition]+'#' LIKE ss.SecondarySearch
									AND o.ObjectName <> r.ObjectName							--Dont include self
									AND r.[Type_Desc] = 'SQL_STORED_PROCEDURE'					--Reference
									AND o.[Type_Desc] IN ('SQL_STORED_PROCEDURE','SQL_TRIGGER')	--Referenced By
								UNION
								--Jobs
								SELECT CombName = CONCAT(JobName,' - ',StepID,') ', COALESCE(NULLIF(StepName,''),'''''')), 'JOB_STEP'
								FROM #JobStepContents
								WHERE '#'+StepCode+'#' LIKE ss.SecondarySearch
							) x
							WHERE r.MatchQuality = 'Whole Match'
						) x

					SELECT o.[Database], o.SchemaName, o.ObjectName, o.[Type_Desc], o.MatchQuality
						 , r.Label, r.Ref_Name, r.Ref_Type
						 , o.QuickScript
						 , CompleteObjectContents = CONVERT(XML, CONCAT('<?query --', @CRLF, REPLACE(REPLACE(o2.[Definition],'<?','/*'),'?>','*/'), @CRLF, '--?>'))
						 , o.SVNPath
					FROM #ObjectContentsResults2 o
						JOIN #Objects o2 ON o2.ID = o.ObjectID
						JOIN #ObjectReferences r ON o.ID = r.ID
					ORDER BY o.[Database], o.SchemaName, o.[Type_Desc], o.ObjectName
				END ELSE
				BEGIN
					SELECT o.[Database], o.SchemaName, o.ObjectName, o.[Type_Desc], o.MatchQuality
						, o.QuickScript
						, CompleteObjectContents = CONVERT(XML, CONCAT('<?query --', @CRLF, REPLACE(REPLACE(o2.[Definition],'<?','/*'),'?>','*/'), @CRLF, '--?>'))
						, o.SVNPath
					FROM #ObjectContentsResults2 o
						JOIN #Objects o2 ON o2.ID = o.ObjectID
					ORDER BY o.[Database], o.SchemaName, o.[Type_Desc], o.ObjectName
				END
			END
			ELSE SELECT 'Object - Contents', 'NO RESULTS FOUND'

			RAISERROR('',0,1) WITH NOWAIT;
		------------------------------------------------------------------------------
		
		------------------------------------------------------------------------------
	END

	IF (@Debug = 1)
	BEGIN
		SELECT 'DEBUG'
		SELECT [Database], SQLCode FROM #SQL
	END
END
GO