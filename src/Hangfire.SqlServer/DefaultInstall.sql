﻿
-- This file is part of Hangfire.
-- Copyright © 2013-2014 Sergey Odinokov.
-- 
-- Hangfire is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Lesser General Public License as 
-- published by the Free Software Foundation, either version 3 
-- of the License, or any later version.
-- 
-- Hangfire is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Lesser General Public License for more details.
-- 
-- You should have received a copy of the GNU Lesser General Public 
-- License along with Hangfire. If not, see <http://www.gnu.org/licenses/>.

SET NOCOUNT ON
DECLARE @TARGET_SCHEMA_VERSION INT;
SET @TARGET_SCHEMA_VERSION = 6;

PRINT 'Installing Hangfire SQL objects...';

BEGIN TRANSACTION;

-- Acquire exclusive lock to prevent deadlocks caused by schema creation / version update
DECLARE @SchemaLockResult INT;
EXEC @SchemaLockResult = sp_getapplock @Resource = 'HangFire:SchemaLock', @LockMode = 'Exclusive'

-- Create the database schema if it doesn't exists
IF NOT EXISTS (SELECT [schema_id] FROM [sys].[schemas] WHERE [name] = 'HangFire')
BEGIN
    EXEC (N'CREATE SCHEMA [HangFire]');
    PRINT 'Created database schema [HangFire]';
END
ELSE
    PRINT 'Database schema [HangFire] already exists';
    
DECLARE @SCHEMA_ID int;
SELECT @SCHEMA_ID = [schema_id] FROM [sys].[schemas] WHERE [name] = 'HangFire';

-- Create the [HangFire].Schema table if not exists
IF NOT EXISTS(SELECT [object_id] FROM [sys].[tables] 
    WHERE [name] = 'Schema' AND [schema_id] = @SCHEMA_ID)
BEGIN
    CREATE TABLE [HangFire].[Schema](
        [Version] [int] NOT NULL,
        CONSTRAINT [PK_HangFire_Schema] PRIMARY KEY CLUSTERED ([Version] ASC)
    );
    PRINT 'Created table [HangFire].[Schema]';
END
ELSE
    PRINT 'Table [HangFire].[Schema] already exists';
    
DECLARE @CURRENT_SCHEMA_VERSION int;
SELECT @CURRENT_SCHEMA_VERSION = [Version] FROM [HangFire].[Schema];

PRINT 'Current Hangfire schema version: ' + CASE @CURRENT_SCHEMA_VERSION WHEN NULL THEN 'none' ELSE CONVERT(nvarchar, @CURRENT_SCHEMA_VERSION) END;

IF @CURRENT_SCHEMA_VERSION IS NOT NULL AND @CURRENT_SCHEMA_VERSION > @TARGET_SCHEMA_VERSION
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR(N'Hangfire current database schema version %d is newer than the configured SqlServerStorage schema version %d. Please update to the latest Hangfire.SqlServer NuGet package.', 11, 1,
        @CURRENT_SCHEMA_VERSION, @TARGET_SCHEMA_VERSION);
END

-- Install [HangFire] schema objects
IF @CURRENT_SCHEMA_VERSION IS NULL
BEGIN
    PRINT 'Installing schema version 1';
        
    -- Create job tables
    CREATE TABLE [HangFire].[Job] (
        [Id] [int] IDENTITY(1,1) NOT NULL,
		[StateId] [int] NULL,
		[StateName] [nvarchar](20) NULL, -- To speed-up queries.
        [InvocationData] [nvarchar](max) NOT NULL,
        [Arguments] [nvarchar](max) NOT NULL,
        [CreatedAt] [datetime] NOT NULL,
        [ExpireAt] [datetime] NULL,

        CONSTRAINT [PK_HangFire_Job] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
    PRINT 'Created table [HangFire].[Job]';

	CREATE NONCLUSTERED INDEX [IX_HangFire_Job_StateName] ON [HangFire].[Job] ([StateName] ASC);
	PRINT 'Created index [IX_HangFire_Job_StateName]';
        
    -- Job history table
        
    CREATE TABLE [HangFire].[State] (
        [Id] [int] IDENTITY(1,1) NOT NULL,
        [JobId] [int] NOT NULL,
		[Name] [nvarchar](20) NOT NULL,
		[Reason] [nvarchar](100) NULL,
        [CreatedAt] [datetime] NOT NULL,
        [Data] [nvarchar](max) NULL,
            
        CONSTRAINT [PK_HangFire_State] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
    PRINT 'Created table [HangFire].[State]';

    ALTER TABLE [HangFire].[State] ADD CONSTRAINT [FK_HangFire_State_Job] FOREIGN KEY([JobId])
        REFERENCES [HangFire].[Job] ([Id])
        ON UPDATE CASCADE
        ON DELETE CASCADE;
    PRINT 'Created constraint [FK_HangFire_State_Job]';
        
    CREATE NONCLUSTERED INDEX [IX_HangFire_State_JobId] ON [HangFire].[State] ([JobId] ASC);
    PRINT 'Created index [IX_HangFire_State_JobId]';
        
    -- Job parameters table
        
    CREATE TABLE [HangFire].[JobParameter](
        [Id] [int] IDENTITY(1,1) NOT NULL,
        [JobId] [int] NOT NULL,
        [Name] [nvarchar](40) NOT NULL,
        [Value] [nvarchar](max) NULL,
            
        CONSTRAINT [PK_HangFire_JobParameter] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
    PRINT 'Created table [HangFire].[JobParameter]';

    ALTER TABLE [HangFire].[JobParameter] ADD CONSTRAINT [FK_HangFire_JobParameter_Job] FOREIGN KEY([JobId])
        REFERENCES [HangFire].[Job] ([Id])
        ON UPDATE CASCADE
        ON DELETE CASCADE;
    PRINT 'Created constraint [FK_HangFire_JobParameter_Job]';
        
    CREATE NONCLUSTERED INDEX [IX_HangFire_JobParameter_JobIdAndName] ON [HangFire].[JobParameter] (
        [JobId] ASC,
        [Name] ASC
    );
    PRINT 'Created index [IX_HangFire_JobParameter_JobIdAndName]';
        
    -- Job queue table
        
    CREATE TABLE [HangFire].[JobQueue](
        [Id] [int] IDENTITY(1,1) NOT NULL,
        [JobId] [int] NOT NULL,
        [Queue] [nvarchar](20) NOT NULL,
        [FetchedAt] [datetime] NULL,
            
        CONSTRAINT [PK_HangFire_JobQueue] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
    PRINT 'Created table [HangFire].[JobQueue]';
        
    CREATE NONCLUSTERED INDEX [IX_HangFire_JobQueue_JobIdAndQueue] ON [HangFire].[JobQueue] (
        [JobId] ASC,
        [Queue] ASC
    );
    PRINT 'Created index [IX_HangFire_JobQueue_JobIdAndQueue]';
        
    CREATE NONCLUSTERED INDEX [IX_HangFire_JobQueue_QueueAndFetchedAt] ON [HangFire].[JobQueue] (
        [Queue] ASC,
        [FetchedAt] ASC
    );
    PRINT 'Created index [IX_HangFire_JobQueue_QueueAndFetchedAt]';
        
    -- Servers table
        
    CREATE TABLE [HangFire].[Server](
        [Id] [nvarchar](50) NOT NULL,
        [Data] [nvarchar](max) NULL,
        [LastHeartbeat] [datetime] NULL,
            
        CONSTRAINT [PK_HangFire_Server] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
    PRINT 'Created table [HangFire].[Server]';
        
    -- Extension tables
        
    CREATE TABLE [HangFire].[Hash](
        [Id] [int] IDENTITY(1,1) NOT NULL,
        [Key] [nvarchar](100) NOT NULL,
        [Name] [nvarchar](40) NOT NULL,
        [StringValue] [nvarchar](max) NULL,
        [IntValue] [int] NULL,
        [ExpireAt] [datetime] NULL,
            
        CONSTRAINT [PK_HangFire_Hash] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
    PRINT 'Created table [HangFire].[Hash]';
        
    CREATE UNIQUE NONCLUSTERED INDEX [UX_HangFire_Hash_KeyAndName] ON [HangFire].[Hash] (
        [Key] ASC,
        [Name] ASC
    );
    PRINT 'Created index [UX_HangFire_Hash_KeyAndName]';
        
    CREATE TABLE [HangFire].[List](
        [Id] [int] IDENTITY(1,1) NOT NULL,
        [Key] [nvarchar](100) NOT NULL,
        [Value] [nvarchar](max) NULL,
        [ExpireAt] [datetime] NULL,
            
        CONSTRAINT [PK_HangFire_List] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
    PRINT 'Created table [HangFire].[List]';
        
    CREATE TABLE [HangFire].[Set](
        [Id] [int] IDENTITY(1,1) NOT NULL,
        [Key] [nvarchar](100) NOT NULL,
        [Score] [float] NOT NULL,
        [Value] [nvarchar](256) NOT NULL,
        [ExpireAt] [datetime] NULL,
            
        CONSTRAINT [PK_HangFire_Set] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
    PRINT 'Created table [HangFire].[Set]';
        
    CREATE UNIQUE NONCLUSTERED INDEX [UX_HangFire_Set_KeyAndValue] ON [HangFire].[Set] (
        [Key] ASC,
        [Value] ASC
    );
    PRINT 'Created index [UX_HangFire_Set_KeyAndValue]';
        
    CREATE TABLE [HangFire].[Value](
        [Id] [int] IDENTITY(1,1) NOT NULL,
        [Key] [nvarchar](100) NOT NULL,
        [StringValue] [nvarchar](max) NULL,
        [IntValue] [int] NULL,
        [ExpireAt] [datetime] NULL,
            
        CONSTRAINT [PK_HangFire_Value] PRIMARY KEY CLUSTERED (
            [Id] ASC
        )
    );
    PRINT 'Created table [HangFire].[Value]';
        
    CREATE UNIQUE NONCLUSTERED INDEX [UX_HangFire_Value_Key] ON [HangFire].[Value] (
        [Key] ASC
    );
    PRINT 'Created index [UX_HangFire_Value_Key]';

	CREATE TABLE [HangFire].[Counter](
		[Id] [int] IDENTITY(1,1) NOT NULL,
		[Key] [nvarchar](100) NOT NULL,
		[Value] [tinyint] NOT NULL,
		[ExpireAt] [datetime] NULL,

		CONSTRAINT [PK_HangFire_Counter] PRIMARY KEY CLUSTERED ([Id] ASC)
	);
	PRINT 'Created table [HangFire].[Counter]';

	CREATE NONCLUSTERED INDEX [IX_HangFire_Counter_Key] ON [HangFire].[Counter] ([Key] ASC)
	INCLUDE ([Value]);
	PRINT 'Created index [IX_HangFire_Counter_Key]';

	SET @CURRENT_SCHEMA_VERSION = 1;
END

IF @CURRENT_SCHEMA_VERSION = 1
BEGIN
	PRINT 'Installing schema version 2';

	-- https://github.com/odinserj/HangFire/issues/83

	DROP INDEX [IX_HangFire_Counter_Key] ON [HangFire].[Counter];

	ALTER TABLE [HangFire].[Counter] ALTER COLUMN [Value] SMALLINT NOT NULL;

	CREATE NONCLUSTERED INDEX [IX_HangFire_Counter_Key] ON [HangFire].[Counter] ([Key] ASC)
	INCLUDE ([Value]);
	PRINT 'Index [IX_HangFire_Counter_Key] re-created';

	DROP TABLE [HangFire].[Value];
	DROP TABLE [HangFire].[Hash];
	PRINT 'Dropped tables [HangFire].[Value] and [HangFire].[Hash]'

	DELETE FROM [HangFire].[Server] WHERE [LastHeartbeat] IS NULL;
	ALTER TABLE [HangFire].[Server] ALTER COLUMN [LastHeartbeat] DATETIME NOT NULL;

	SET @CURRENT_SCHEMA_VERSION = 2;
END

IF @CURRENT_SCHEMA_VERSION = 2
BEGIN
	PRINT 'Installing schema version 3';

	DROP INDEX [IX_HangFire_JobQueue_JobIdAndQueue] ON [HangFire].[JobQueue];
	PRINT 'Dropped index [IX_HangFire_JobQueue_JobIdAndQueue]';

	CREATE TABLE [HangFire].[Hash](
		[Id] [int] IDENTITY(1,1) NOT NULL,
		[Key] [nvarchar](100) NOT NULL,
		[Field] [nvarchar](100) NOT NULL,
		[Value] [nvarchar](max) NULL,
		[ExpireAt] [datetime2](7) NULL,
		
		CONSTRAINT [PK_HangFire_Hash] PRIMARY KEY CLUSTERED ([Id] ASC)
	);
	PRINT 'Created table [HangFire].[Hash]';

	CREATE UNIQUE NONCLUSTERED INDEX [UX_HangFire_Hash_Key_Field] ON [HangFire].[Hash] (
		[Key] ASC,
		[Field] ASC
	);
	PRINT 'Created index [UX_HangFire_Hash_Key_Field]';

	SET @CURRENT_SCHEMA_VERSION = 3;
END

IF @CURRENT_SCHEMA_VERSION = 3
BEGIN
	PRINT 'Installing schema version 4';

	CREATE TABLE [HangFire].[AggregatedCounter] (
		[Id] [int] IDENTITY(1,1) NOT NULL,
		[Key] [nvarchar](100) NOT NULL,
		[Value] [bigint] NOT NULL,
		[ExpireAt] [datetime] NULL,

		CONSTRAINT [PK_HangFire_CounterAggregated] PRIMARY KEY CLUSTERED ([Id] ASC)
	);
	PRINT 'Created table [HangFire].[AggregatedCounter]';

	CREATE UNIQUE NONCLUSTERED INDEX [UX_HangFire_CounterAggregated_Key] ON [HangFire].[AggregatedCounter] (
		[Key] ASC
	) INCLUDE ([Value]);
	PRINT 'Created index [UX_HangFire_CounterAggregated_Key]';

	CREATE NONCLUSTERED INDEX [IX_HangFire_Hash_ExpireAt] ON [HangFire].[Hash] ([ExpireAt])
	INCLUDE ([Id]);

	CREATE NONCLUSTERED INDEX [IX_HangFire_Job_ExpireAt] ON [HangFire].[Job] ([ExpireAt])
	INCLUDE ([Id]);

	CREATE NONCLUSTERED INDEX [IX_HangFire_List_ExpireAt] ON [HangFire].[List] ([ExpireAt])
	INCLUDE ([Id]);

	CREATE NONCLUSTERED INDEX [IX_HangFire_Set_ExpireAt] ON [HangFire].[Set] ([ExpireAt])
	INCLUDE ([Id]);

	PRINT 'Created indexes for [ExpireAt] columns';

	CREATE NONCLUSTERED INDEX [IX_HangFire_Hash_Key] ON [HangFire].[Hash] ([Key] ASC)
	INCLUDE ([ExpireAt]);
	PRINT 'Created index [IX_HangFire_Hash_Key]';

	CREATE NONCLUSTERED INDEX [IX_HangFire_List_Key] ON [HangFire].[List] ([Key] ASC)
	INCLUDE ([ExpireAt], [Value]);
	PRINT 'Created index [IX_HangFire_List_Key]';

	CREATE NONCLUSTERED INDEX [IX_HangFire_Set_Key] ON [HangFire].[Set] ([Key] ASC)
	INCLUDE ([ExpireAt], [Value]);
	PRINT 'Created index [IX_HangFire_Set_Key]';

	SET @CURRENT_SCHEMA_VERSION = 4;
END

IF @CURRENT_SCHEMA_VERSION = 4
BEGIN
	PRINT 'Installing schema version 5';

	DROP INDEX [IX_HangFire_JobQueue_QueueAndFetchedAt] ON [HangFire].[JobQueue];
	PRINT 'Dropped index [IX_HangFire_JobQueue_QueueAndFetchedAt] to modify the [HangFire].[JobQueue].[Queue] column';

	ALTER TABLE [HangFire].[JobQueue] ALTER COLUMN [Queue] NVARCHAR (50) NOT NULL;
	PRINT 'Modified [HangFire].[JobQueue].[Queue] length to 50';

	CREATE NONCLUSTERED INDEX [IX_HangFire_JobQueue_QueueAndFetchedAt] ON [HangFire].[JobQueue] (
        [Queue] ASC,
        [FetchedAt] ASC
    );
    PRINT 'Re-created index [IX_HangFire_JobQueue_QueueAndFetchedAt]';

	ALTER TABLE [HangFire].[Server] DROP CONSTRAINT [PK_HangFire_Server]
    PRINT 'Dropped constraint [PK_HangFire_Server] to modify the [HangFire].[Server].[Id] column';

	ALTER TABLE [HangFire].[Server] ALTER COLUMN [Id] NVARCHAR (100) NOT NULL;
	PRINT 'Modified [HangFire].[Server].[Id] length to 100';

	ALTER TABLE [HangFire].[Server] ADD  CONSTRAINT [PK_HangFire_Server] PRIMARY KEY CLUSTERED
	(
		[Id] ASC
	);
	PRINT 'Re-created constraint [PK_HangFire_Server]';

	SET @CURRENT_SCHEMA_VERSION = 5;
END

IF @CURRENT_SCHEMA_VERSION = 5
BEGIN
	PRINT 'Installing schema version 6';

	-- Remove unnecessary indexes – there's an alternative for each.

	DROP INDEX [IX_HangFire_Hash_Key] ON [HangFire].[Hash];
	PRINT 'Dropped unnecessary index [IX_HangFire_Hash_Key], because [UX_HangFire_Hash_Key_Field] is enough';

	DROP INDEX [IX_HangFire_Set_Key] ON [HangFire].[Set];
	PRINT 'Dropped unnecessary index [IX_HangFire_Set_Key], because [UX_HangFire_Set_KeyAndValue] is enough';

	-- Dropping `IX_HangFire_XXX_ExpireAt` indexes before migrating to the BIGINT type, because all of 
	-- them include the Id columns by mistake. We'll recreate them later without the inclusion.

	DROP INDEX [IX_HangFire_Hash_ExpireAt] ON [HangFire].[Hash];
	PRINT 'Dropped index [IX_HangFire_Hash_ExpireAt] to modify the [HangFire].[Hash].[Id] column';

	DROP INDEX [IX_HangFire_Job_ExpireAt] ON [HangFire].[Job];
	PRINT 'Dropped index [IX_HangFire_Job_ExpireAt] to modify the [HangFire].[Job].[Id] column';

	DROP INDEX [IX_HangFire_List_ExpireAt] ON [HangFire].[List];
	PRINT 'Dropped index [IX_HangFire_List_ExpireAt] to modify the [HangFire].[List].[Id] column';

	DROP INDEX [IX_HangFire_Set_ExpireAt] ON [HangFire].[Set];
	PRINT 'Dropped index [IX_HangFire_Set_ExpireAt] to modify the [HangFire].[Set].[Id] column';

	-- Dropping the IX_HangFire_Job_StateName index, we'll re-create it as a filtered index.
	DROP INDEX [IX_HangFire_Job_StateName] ON [HangFire].Job;
	PRINT 'Dropped index [IX_HangFire_Job_StateName], will re-create it as a filtered one.'

	-- Dropping these indexes, because we'll remove Identity columns on these tables, and make a composite
	-- primary key for each.

	DROP INDEX [IX_HangFire_JobParameter_JobIdAndName] ON [HangFire].[JobParameter];
	PRINT 'Dropped index [IX_HangFire_JobParameter_JobIdAndName]. Unique index will be created instead';

	DROP INDEX [IX_HangFire_State_JobId] ON [HangFire].[State];
	PRINT 'Dropped index [IX_HangFire_State_JobId] to modify the [HangFire].[State].[JobId] column';

	DROP INDEX [IX_HangFire_JobQueue_QueueAndFetchedAt] ON [HangFire].[JobQueue];
	PRINT 'Dropped index [IX_HangFire_JobQueue_QueueAndFetchedAt], table structure changed';

	-- Dropping foreign key constraints based on the JobId column. We'll recreate them later in the migration.

	ALTER TABLE [HangFire].[JobParameter] DROP CONSTRAINT [FK_HangFire_JobParameter_Job];
	PRINT 'Dropped constraint [FK_HangFire_JobParameter_Job] to modify the [HangFire].[JobParameter].[JobId] column';

	ALTER TABLE [HangFire].[State] DROP CONSTRAINT [FK_HangFire_State_Job];
	PRINT 'Dropped constraint [FK_HangFire_State_Job] to modify the [HangFire].[State].[JobId] column';

	-- Dropping primary key constraints based on INT identifiers. We'll recreate them later in the migration.

	ALTER TABLE [HangFire].[AggregatedCounter] DROP CONSTRAINT [PK_HangFire_CounterAggregated];
	PRINT 'Dropped constraint [PK_HangFire_CounterAggregated] to modify the [HangFire].[AggregatedCounter].[Id] column';

	ALTER TABLE [HangFire].[Counter] DROP CONSTRAINT [PK_HangFire_Counter];
	PRINT 'Dropped constraint [PK_HangFire_Counter] to modify the [HangFire].[Counter].[Id] column';

	ALTER TABLE [HangFire].[Hash] DROP CONSTRAINT [PK_HangFire_Hash];
	PRINT 'Dropped constraint [PK_HangFire_Hash] to modify the [HangFire].[Hash].[Id] column';

	ALTER TABLE [HangFire].[Job] DROP CONSTRAINT [PK_HangFire_Job];
	PRINT 'Dropped constraint [PK_HangFire_Job] to modify the [HangFire].[Job].[Id] column';

	ALTER TABLE [HangFire].[JobParameter] DROP CONSTRAINT [PK_HangFire_JobParameter];
	PRINT 'Dropped constraint [PK_HangFire_JobParameter] to modify the [HangFire].[JobParameter].[Id] column';

	ALTER TABLE [HangFire].[JobQueue] DROP CONSTRAINT [PK_HangFire_JobQueue];
	PRINT 'Dropped constraint [PK_HangFire_JobQueue] to modify the [HangFire].[JobQueue].[Id] column';

	ALTER TABLE [HangFire].[List] DROP CONSTRAINT [PK_HangFire_List];
	PRINT 'Dropped constraint [PK_HangFire_List] to modify the [HangFire].[List].[Id] column';

	ALTER TABLE [HangFire].[Set] DROP CONSTRAINT [PK_HangFire_Set];
	PRINT 'Dropped constraint [PK_HangFire_Set] to modify the [HangFire].[Set].[Id] column';

	ALTER TABLE [HangFire].[State] DROP CONSTRAINT [PK_HangFire_State];
	PRINT 'Dropped constraint [PK_HangFire_State] to modify the [HangFire].[State].[Id] column';

	-- Remove identity columns for 

	DROP INDEX [UX_HangFire_CounterAggregated_Key] ON [HangFire].[AggregatedCounter];
	ALTER TABLE [HangFire].[AggregatedCounter] DROP COLUMN [Id];
	PRINT 'Dropped [AggregatedCounter].[Id] column, we will cluster on [Key] column';

	DROP INDEX [IX_HangFire_Counter_Key] ON [HangFire].[Counter];
	ALTER TABLE [HangFire].[Counter] DROP COLUMN [Id];
	PRINT 'Dropped [Counter].[Id] column, we will cluster on [Key] column';

	DROP INDEX [UX_HangFire_Hash_Key_Field] ON [HangFire].[Hash];
	ALTER TABLE [HangFire].[Hash] DROP COLUMN [Id];
	PRINT 'Dropped [Hash].[Id] column, we will cluster on [Key]/[Field] columns';

	DROP INDEX [IX_HangFire_List_Key] ON [HangFire].[List];
	ALTER TABLE [HangFire].[List] ALTER COLUMN [Id] BIGINT NOT NULL;
	PRINT 'Modified [HangFire].[List].[Id] type to BIGINT';

	DROP INDEX [UX_HangFire_Set_KeyAndValue] ON [HangFire].[Set];
	ALTER TABLE [HangFire].[Set] DROP COLUMN [Id];
	PRINT 'Dropped [Set].[Id] column, we will cluster on [Key]/[Value] columns';

	ALTER TABLE [HangFire].[JobParameter] DROP COLUMN [Id];
	PRINT 'Dropped [JobParameter].[Id] column, we will cluster on [JobId]/[Name] columns';

	-- Modifying all the INT identifiers to use the BIGINT type.

	ALTER TABLE [HangFire].[Job] ALTER COLUMN [Id] BIGINT NOT NULL;
	PRINT 'Modified [HangFire].[Job].[Id] type to BIGINT';

	ALTER TABLE [HangFire].[Job] ALTER COLUMN [StateId] BIGINT NULL;
	PRINT 'Modified [HangFire].[Job].[StateId] type to BIGINT to modify the [HangFire].[State].[Id] column';

	ALTER TABLE [HangFire].[JobParameter] ALTER COLUMN [JobId] BIGINT NOT NULL;
	PRINT 'Modified [HangFire].[JobParameter].[JobId] type to BIGINT to modify [HangFire].[Job].[Id] type to BIGINT';

	ALTER TABLE [HangFire].[JobQueue] ALTER COLUMN [JobId] BIGINT NOT NULL;
	PRINT 'Modified [HangFire].[JobQueue].[JobId] type to BIGINT';

	ALTER TABLE [HangFire].[State] ALTER COLUMN [Id] BIGINT NOT NULL;
	PRINT 'Modified [HangFire].[State].[Id] type to BIGINT';

	ALTER TABLE [HangFire].[State] ALTER COLUMN [JobId] BIGINT NOT NULL;
	PRINT 'Modified [HangFire].[State].[JobId] type to BIGINT to modify [HangFire].[Job].[Id] type to BIGINT';

	-- Adding back all the Primary Key constraints that were dropped earlier.

	ALTER TABLE [HangFire].[AggregatedCounter] ADD CONSTRAINT [PK_HangFire_CounterAggregated] PRIMARY KEY CLUSTERED (
		[Key] ASC
	);
	PRINT 'Re-created constraint [PK_HangFire_CounterAggregated]';

	CREATE CLUSTERED INDEX [CX_HangFire_Counter] ON [HangFire].[Counter] ([Key]);
	PRINT 'Created clustered index [CX_HangFire_Counter]';

	ALTER TABLE [HangFire].[Hash] ADD CONSTRAINT [PK_HangFire_Hash] PRIMARY KEY CLUSTERED (
		[Key] ASC,
		[Field] ASC
	);
	PRINT 'Re-created constraint [PK_HangFire_Hash]';

	ALTER TABLE [HangFire].[Job] ADD CONSTRAINT [PK_HangFire_Job] PRIMARY KEY CLUSTERED ([Id] ASC);
	PRINT 'Re-created constraint [PK_HangFire_Job]';
	
	ALTER TABLE [HangFire].[JobParameter] ADD CONSTRAINT [PK_HangFire_JobParameter] PRIMARY KEY CLUSTERED (
		[JobId] ASC,
		[Name] ASC
	);
	PRINT 'Re-created constraint [PK_HangFire_JobParameter]';

	CREATE CLUSTERED INDEX [CX_HangFire_JobQueue] ON [HangFire].[JobQueue] ([Queue]);
	CREATE NONCLUSTERED INDEX [IX_HangFire_JobQueue_FetchedAt] ON [HangFire].[JobQueue] ([FetchedAt])
	WHERE [FetchedAt] IS NOT NULL;
	CREATE NONCLUSTERED INDEX [IX_HangFire_JobQueue_Id] ON [HangFire].[JobQueue] ([Id])
	WHERE [FetchedAt] IS NOT NULL;

	ALTER TABLE [HangFire].[List] ADD CONSTRAINT [PK_HangFire_List] PRIMARY KEY CLUSTERED (
		[Key] ASC,
		[Id] ASC
	);
	PRINT 'Re-created constraint [PK_HangFire_List]';

	ALTER TABLE [HangFire].[Set] ADD CONSTRAINT [PK_HangFire_Set] PRIMARY KEY CLUSTERED (
		[Key] ASC,
		[Value] ASC
	);
	PRINT 'Re-created constraint [PK_HangFire_Set]';

	ALTER TABLE [HangFire].[State] ADD CONSTRAINT [PK_HangFire_State] PRIMARY KEY CLUSTERED (
		[JobId] ASC,
		[Id]
	);
	PRINT 'Re-created constraint [PK_HangFire_State]';

	CREATE NONCLUSTERED INDEX [IX_HangFire_Job_StateName] ON [HangFire].[Job] ([StateName])
	WHERE [StateName] IS NOT NULL;
	PRINT 'Re-created index [IX_HangFire_Job_StateName], it is filtered now';

	CREATE NONCLUSTERED INDEX [IX_HangFire_AggregatedCounter_ExpireAt] ON [HangFire].[AggregatedCounter] ([ExpireAt])
	WHERE [ExpireAt] IS NOT NULL;
	PRINT 'Created index [IX_HangFire_AggregatedCounter_ExpireAt]. Made the index only for rows with non-null ExpireAt value';

	CREATE NONCLUSTERED INDEX [IX_HangFire_Hash_ExpireAt] ON [HangFire].[Hash] ([ExpireAt])
	WHERE [ExpireAt] IS NOT NULL;
	PRINT 'Re-created index [IX_HangFire_Hash_ExpireAt]. Made the index only for rows with non-null ExpireAt value';

	CREATE NONCLUSTERED INDEX [IX_HangFire_Job_ExpireAt] ON [HangFire].[Job] ([ExpireAt])
	WHERE [ExpireAt] IS NOT NULL;
	PRINT 'Re-created index [IX_HangFire_Job_ExpireAt]. Made the index only for rows with non-null ExpireAt value';

	CREATE NONCLUSTERED INDEX [IX_HangFire_List_ExpireAt] ON [HangFire].[List] ([ExpireAt])
	WHERE [ExpireAt] IS NOT NULL;
	PRINT 'Re-created index [IX_HangFire_List_ExpireAt]. Made the index only for rows with non-null ExpireAt value';

	CREATE NONCLUSTERED INDEX [IX_HangFire_Set_ExpireAt] ON [HangFire].[Set] ([ExpireAt])
	WHERE [ExpireAt] IS NOT NULL;
	PRINT 'Re-created index [IX_HangFire_Set_ExpireAt]. Made the index only for rows with non-null ExpireAt value';

	ALTER TABLE [HangFire].[JobParameter] ADD [ExpireAt] DATETIME NULL;
	ALTER TABLE [HangFire].[State] ADD [ExpireAt] DATETIME NULL;

	UPDATE [HangFire].[State]
	SET [ExpireAt] = (SELECT [ExpireAt] FROM [HangFire].[Job] j WHERE j.[Id] = [JobId]);

	UPDATE [HangFire].[JobParameter]
	SET [ExpireAt] = (SELECT [ExpireAt] FROM [HangFire].[Job] j WHERE j.[Id] = [JobId]);

	EXEC (N'CREATE NONCLUSTERED INDEX [IX_HangFire_JobParameter_ExpireAt] ON [HangFire].[JobParameter] ([ExpireAt])
	WHERE [ExpireAt] IS NOT NULL;');

	EXEC (N'CREATE NONCLUSTERED INDEX [IX_HangFire_State_ExpireAt] ON [HangFire].[State] ([ExpireAt])
	WHERE [ExpireAt] IS NOT NULL;');
	
	ALTER TABLE [HangFire].[Job] ALTER COLUMN [CreatedAt] DATETIME2 NOT NULL;
	ALTER TABLE [HangFire].[State] ALTER COLUMN [CreatedAt] DATETIME2 NOT NULL;

	ALTER TABLE [HangFire].[Counter] ALTER COLUMN [Value] INT NOT NULL;

	CREATE NONCLUSTERED INDEX [IX_HangFire_Set_Score] ON [HangFire].[Set] ([Score])
	WHERE [Score] IS NOT NULL;

	CREATE NONCLUSTERED INDEX [IX_HangFire_Server_LastHeartbeat] ON [HangFire].[Server] ([LastHeartbeat]);

	SET @CURRENT_SCHEMA_VERSION = 6;
END	

/*IF @CURRENT_SCHEMA_VERSION = 6
BEGIN
	PRINT 'Installing schema version 7';

	 Insert migration here

	SET @CURRENT_SCHEMA_VERSION = 7;
END*/

UPDATE [HangFire].[Schema] SET [Version] = @CURRENT_SCHEMA_VERSION
IF @@ROWCOUNT = 0 
	INSERT INTO [HangFire].[Schema] ([Version]) VALUES (@CURRENT_SCHEMA_VERSION)        

PRINT 'Hangfire database schema installed';

COMMIT TRANSACTION;
PRINT 'Hangfire SQL objects installed';

