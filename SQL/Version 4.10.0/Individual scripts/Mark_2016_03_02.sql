

-- Ensure the SobekCM_Builder_Get_Incoming_Folder stored procedure exists
IF object_id('SobekCM_Builder_Get_Incoming_Folder') IS NULL EXEC ('create procedure dbo.SobekCM_Builder_Get_Incoming_Folder as select 1;');
GO

-- Get the information about a single incoming folder
ALTER PROCEDURE [dbo].[SobekCM_Builder_Get_Incoming_Folder] 
	@FolderId int
AS
BEGIN

	-- Return all the data about it 
	select IncomingFolderId, NetworkFolder, ErrorFolder, ProcessingFolder, Perform_Checksum_Validation, Archive_TIFF, Archive_All_Files,
		   Allow_Deletes, Allow_Folders_No_Metadata, Allow_Metadata_Updates, FolderName, BibID_Roots_Restrictions,
		   F.ModuleSetID, S.SetName
	from SobekCM_Builder_Incoming_Folders F left outer join 
	     SobekCM_Builder_Module_Set S on F.ModuleSetID=S.ModuleSetID
	where F.IncomingFolderId=@FolderId;

	-- Also return the modules linked to each (enabled) folder module set
	select S.ModuleSetID, S.SetName, M.[Assembly], M.Class, M.[Enabled], M.Argument1, M.Argument2, M.Argument3, M.ModuleDesc, M.[Order], S.[Enabled]
	from SobekCM_Builder_Incoming_Folders F inner join
		 SobekCM_Builder_Module_Set S on S.ModuleSetID=F.ModuleSetID inner join 
		 SobekCM_Builder_Module M on M.ModuleSetID=S.ModuleSetID 	 
	where F.IncomingFolderId=@FolderId
	order by M.[Order];

END;
GO



-- Ensure the SobekCM_Builder_Get_Folder_Module_Sets stored procedure exists
IF object_id('SobekCM_Builder_Get_Folder_Module_Sets') IS NULL EXEC ('create procedure dbo.SobekCM_Builder_Get_Folder_Module_Sets as select 1;');
GO

-- Procedure returns the names (and details) of all the module sets used for folders
ALTER PROCEDURE [dbo].[SobekCM_Builder_Get_Folder_Module_Sets]
as
begin

	-- Get the count of used folder modules
	with folder_modules_used ( ModuleSetID, UsedCount ) as
	( 
		select ModuleSetID, count(*) as UsedCount
		from SobekCM_Builder_Incoming_Folders 
		group by ModuleSetID
	) 
	select S.ModuleSetID, S.SetName, coalesce(U.UsedCount, 0) as UsedCount
	from SobekCM_Builder_Module_Set S inner join 
		 SobekCM_Builder_Module_Type T on S.ModuleTypeID=T.ModuleTypeID left outer join
		 folder_modules_used U on U.ModuleSetID=S.ModuleSetID
	where ( T.TypeAbbrev = 'FOLD' )
	  and ( S.[Enabled] = 1 )
	order by UsedCount DESC;

	-- Also return the modules linked to each (enabled) folder module set
	select S.ModuleSetID, S.SetName, M.[Assembly], M.Class, M.[Enabled], M.Argument1, M.Argument2, M.Argument3, M.ModuleDesc, M.[Order]
	from SobekCM_Builder_Module_Set S inner join 
		 SobekCM_Builder_Module_Type T on S.ModuleTypeID=T.ModuleTypeID inner join
		 SobekCM_Builder_Module M on M.ModuleSetID=S.ModuleSetID
	where ( T.TypeAbbrev = 'FOLD' )
	  and ( S.[Enabled] = 1 )
	order by S.ModuleSetID, M.[Order];

end;
GO

GRANT EXECUTE ON [dbo].SobekCM_Builder_Get_Folder_Module_Sets to sobek_user;
GRANT EXECUTE ON [dbo].SobekCM_Builder_Get_Folder_Module_Sets to sobek_builder;
GO

GRANT EXECUTE ON [dbo].SobekCM_Builder_Incoming_Folder_Delete to sobek_user;
GRANT EXECUTE ON [dbo].SobekCM_Builder_Incoming_Folder_Delete to sobek_builder;
GO

GRANT EXECUTE ON [dbo].SobekCM_Builder_Incoming_Folder_Edit to sobek_user;
GRANT EXECUTE ON [dbo].SobekCM_Builder_Incoming_Folder_Edit to sobek_builder;
GO

GRANT EXECUTE ON [dbo].[SobekCM_Builder_Get_Incoming_Folder] to sobek_user;
GRANT EXECUTE ON [dbo].[SobekCM_Builder_Get_Incoming_Folder] to sobek_builder;
GO

-- Add a new incoming folder for the builder/bulk loader, or edit
-- an existing incoming folder (by incoming folder id)
ALTER PROCEDURE [dbo].[SobekCM_Builder_Incoming_Folder_Edit]
	@IncomingFolderId int,
	@NetworkFolder varchar(255),
	@ErrorFolder varchar(255),
	@ProcessingFolder varchar(255),
	@Perform_Checksum_Validation bit,
	@Archive_TIFF bit,
	@Archive_All_Files bit,
	@Allow_Deletes bit,
	@Allow_Folders_No_Metadata bit,
	@FolderName nvarchar(150),
	@BibID_Roots_Restrictions varchar(255),
	@ModuleSetID int,
	@NewID int output
AS 
BEGIN

	-- Is this a new incoming folder?
	if (( select COUNT(*) from SobekCM_Builder_Incoming_Folders where IncomingFolderId=@IncomingFolderId ) = 0 )
	begin	
		-- Insert new incoming folder
		insert into SobekCM_Builder_Incoming_Folders ( NetworkFolder, ErrorFolder, ProcessingFolder, Perform_Checksum_Validation, Archive_TIFF, Archive_All_Files, Allow_Deletes, Allow_Folders_No_Metadata, FolderName, Allow_Metadata_Updates, BibID_Roots_Restrictions, ModuleSetID )
		values ( @NetworkFolder, @ErrorFolder, @ProcessingFolder, @Perform_Checksum_Validation, @Archive_TIFF, @Archive_All_Files, @Allow_Deletes, @Allow_Folders_No_Metadata, @FolderName, 'true', @BibID_Roots_Restrictions, @ModuleSetID );
		
		-- Save the new id
		set @NewID = @@Identity;
	end
	else
	begin
		-- update existing incoming folder
		update SobekCM_Builder_Incoming_Folders
		set NetworkFolder=@NetworkFolder, ErrorFolder=@ErrorFolder, ProcessingFolder=@ProcessingFolder, 
			Perform_Checksum_Validation=@Perform_Checksum_Validation, Archive_TIFF=@Archive_TIFF, 
			Archive_All_Files=@Archive_All_Files, Allow_Deletes=@Allow_Deletes, 
			Allow_Folders_No_Metadata=@Allow_Folders_No_Metadata, FolderName=@FolderName,
			BibID_Roots_Restrictions=@BibID_Roots_Restrictions, ModuleSetID=@ModuleSetID
		where IncomingFolderId = @IncomingFolderId;
		
		-- Just return the same id
		set @NewID = @IncomingFolderId;	
	end;
END;
GO



-- Routine returns all the BUILDER-specific settings
ALTER procedure [dbo].[SobekCM_Builder_Get_Settings]
	@include_disabled bit
as
begin

	-- Always return all the incoming folders
	select IncomingFolderId, NetworkFolder, ErrorFolder, ProcessingFolder, Perform_Checksum_Validation, Archive_TIFF, Archive_All_Files,
		   Allow_Deletes, Allow_Folders_No_Metadata, Allow_Metadata_Updates, FolderName, BibID_Roots_Restrictions,
		   F.ModuleSetID, S.SetName
	from SobekCM_Builder_Incoming_Folders F left outer join 
	     SobekCM_Builder_Module_Set S on F.ModuleSetID=S.ModuleSetID;

	-- Return all the non-scheduled type modules
	if ( @include_disabled = 'true' )
	begin
		select M.ModuleID, M.[Assembly], M.Class, M.ModuleDesc, M.Argument1, M.Argument2, M.Argument3, M.[Enabled], S.ModuleSetID, S.SetName, S.[Enabled] as SetEnabled, T.TypeAbbrev, T.TypeDescription
		from SobekCM_Builder_Module M, SobekCM_Builder_Module_Set S, SobekCM_Builder_Module_Type T
		where M.ModuleSetID = S.ModuleSetID
		  and S.ModuleTypeID = T.ModuleTypeID
		  and T.TypeAbbrev <> 'SCHD'
		order by TypeAbbrev, S.SetOrder, M.[Order];
	end
	else
	begin
		select M.ModuleID, M.[Assembly], M.Class, M.ModuleDesc, M.Argument1, M.Argument2, M.Argument3, M.[Enabled], S.ModuleSetID, S.SetName, S.[Enabled] as SetEnabled, T.TypeAbbrev, T.TypeDescription
		from SobekCM_Builder_Module M, SobekCM_Builder_Module_Set S, SobekCM_Builder_Module_Type T
		where M.ModuleSetID = S.ModuleSetID
		  and S.ModuleTypeID = T.ModuleTypeID
		  and M.[Enabled] = 'true'
		  and S.[Enabled] = 'true'
		  and T.TypeAbbrev <> 'SCHD'
		order by TypeAbbrev, S.SetOrder, M.[Order];
	end;

	-- Return all the scheduled type modules, with the schedule and the last run info
	if ( @include_disabled = 'true' )
	begin
		with last_run_cte ( ModuleScheduleID, LastRun) as 
		(
			select ModuleScheduleID, MAX([Timestamp])
			from SobekCM_Builder_Module_Scheduled_Run
			group by ModuleScheduleID
		)
		-- Return all the scheduled type modules, along with information on when it was last run
		select M.ModuleID, M.[Assembly], M.Class, M.ModuleDesc, M.Argument1, M.Argument2, M.Argument3, M.[Enabled], S.ModuleSetID, S.SetName, S.[Enabled] as SetEnabled, T.TypeAbbrev, T.TypeDescription, C.ModuleScheduleID, C.[Enabled] as ScheduleEnabled, C.DaysOfWeek, C.TimesOfDay, L.LastRun
		from SobekCM_Builder_Module M inner join
			 SobekCM_Builder_Module_Set S on M.ModuleSetID = S.ModuleSetID inner join
			 SobekCM_Builder_Module_Type T on S.ModuleTypeID = T.ModuleTypeID inner join
			 SobekCM_Builder_Module_Schedule C on C.ModuleSetID = S.ModuleSetID left outer join
			 last_run_cte L on L.ModuleScheduleID = C.ModuleScheduleID
		where T.TypeAbbrev = 'SCHD'
		order by TypeAbbrev, S.SetOrder, M.[Order];
	end 
	else
	begin
		with last_run_cte ( ModuleScheduleID, LastRun) as 
		(
			select ModuleScheduleID, MAX([Timestamp])
			from SobekCM_Builder_Module_Scheduled_Run
			group by ModuleScheduleID
		)
		-- Return all the scheduled type modules, along with information on when it was last run
		select M.ModuleID, M.[Assembly], M.Class, M.ModuleDesc, M.Argument1, M.Argument2, M.Argument3, M.[Enabled], S.ModuleSetID, S.SetName, S.[Enabled] as SetEnabled, T.TypeAbbrev, T.TypeDescription, C.ModuleScheduleID, C.[Enabled] as ScheduleEnabled, C.DaysOfWeek, C.TimesOfDay, L.LastRun
		from SobekCM_Builder_Module M inner join
			 SobekCM_Builder_Module_Set S on M.ModuleSetID = S.ModuleSetID inner join
			 SobekCM_Builder_Module_Type T on S.ModuleTypeID = T.ModuleTypeID inner join
			 SobekCM_Builder_Module_Schedule C on C.ModuleSetID = S.ModuleSetID left outer join
			 last_run_cte L on L.ModuleScheduleID = C.ModuleScheduleID
		where T.TypeAbbrev = 'SCHD'
		  and M.[Enabled] = 'true'
		  and S.[Enabled] = 'true'
		  and C.[Enabled] = 'true'
		order by TypeAbbrev, S.SetOrder, M.[Order];
	end;

end;
GO


-- Gets the list of all system-wide settings from the database, including the full list of all
-- metadata search fields, possible workflows, and all disposition data
ALTER PROCEDURE [dbo].[SobekCM_Get_Settings]
	@IncludeAdminViewInfo bit
AS
begin

	-- No need to perform any locks here.  A slightly dirty read won't hurt much
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	
	-- Get all the standard SobekCM settings
	if ( @IncludeAdminViewInfo = 'true' )
	begin
		select Setting_Key, Setting_Value, TabPage, Heading, Hidden, Reserved, Help, Options, SettingID, Dimensions
		from SobekCM_Settings
		where Hidden = 'false'
		order by TabPage, Heading, Setting_Key;
	end 
	else
	begin
		select Setting_Key, Setting_Value
		from SobekCM_Settings;
	end;

	-- Return all the metadata search fields
	select MetadataTypeID, MetadataName, SobekCode, SolrCode, DisplayTerm, FacetTerm, CustomField, canFacetBrowse
	from SobekCM_Metadata_Types
	order by DisplayTerm;

	-- Return all the possible workflow types
	select WorkFlowID, WorkFlowName, WorkFlowNotes, Start_Event_Number, End_Event_Number, Start_And_End_Event_Number, Start_Event_Desc, End_Event_Desc
	from Tracking_WorkFlow;

	-- Return all the possible disposition options
	select DispositionID, DispositionFuture, DispositionPast, DispositionNotes
	from Tracking_Disposition_Type;

	-- Always return all the incoming folders
	select IncomingFolderId, NetworkFolder, ErrorFolder, ProcessingFolder, Perform_Checksum_Validation, Archive_TIFF, Archive_All_Files,
		   Allow_Deletes, Allow_Folders_No_Metadata, Allow_Metadata_Updates, FolderName, BibID_Roots_Restrictions,
		   F.ModuleSetID, S.SetName
	from SobekCM_Builder_Incoming_Folders F left outer join 
	     SobekCM_Builder_Module_Set S on F.ModuleSetID=S.ModuleSetID;

	-- Return all the non-scheduled type modules
	select M.ModuleID, M.[Assembly], M.Class, M.ModuleDesc, M.Argument1, M.Argument2, M.Argument3, M.[Enabled], S.ModuleSetID, S.SetName, S.[Enabled] as SetEnabled, T.TypeAbbrev, T.TypeDescription
	from SobekCM_Builder_Module M, SobekCM_Builder_Module_Set S, SobekCM_Builder_Module_Type T
	where M.ModuleSetID = S.ModuleSetID
	  and S.ModuleTypeID = T.ModuleTypeID
	  and T.TypeAbbrev <> 'SCHD'
	order by TypeAbbrev, S.SetOrder, M.[Order];


	-- Return all the scheduled type modules, with the schedule and the last run info
	with last_run_cte ( ModuleScheduleID, LastRun) as 
	(
		select ModuleScheduleID, MAX([Timestamp])
		from SobekCM_Builder_Module_Scheduled_Run
		group by ModuleScheduleID
	)
	-- Return all the scheduled type modules, along with information on when it was last run
	select M.ModuleID, M.[Assembly], M.Class, M.ModuleDesc, M.Argument1, M.Argument2, M.Argument3, M.[Enabled], S.ModuleSetID, S.SetName, S.[Enabled] as SetEnabled, T.TypeAbbrev, T.TypeDescription, C.ModuleScheduleID, C.[Enabled] as ScheduleEnabled, C.DaysOfWeek, C.TimesOfDay, L.LastRun
	from SobekCM_Builder_Module M inner join
		 SobekCM_Builder_Module_Set S on M.ModuleSetID = S.ModuleSetID inner join
		 SobekCM_Builder_Module_Type T on S.ModuleTypeID = T.ModuleTypeID inner join
		 SobekCM_Builder_Module_Schedule C on C.ModuleSetID = S.ModuleSetID left outer join
		 last_run_cte L on L.ModuleScheduleID = C.ModuleScheduleID
	where T.TypeAbbrev = 'SCHD'
	order by TypeAbbrev, S.SetOrder, M.[Order];

end;
GO
