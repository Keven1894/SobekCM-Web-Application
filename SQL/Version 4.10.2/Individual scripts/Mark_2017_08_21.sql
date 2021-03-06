

-- Stored procedure to save the basic item aggregation information
ALTER PROCEDURE [dbo].[SobekCM_Save_Item_Aggregation]
	@aggregationid int,
	@code varchar(20),
	@name nvarchar(255),
	@shortname nvarchar(100),
	@description nvarchar(1000),
	@thematicHeadingId int,
	@type varchar(50),
	@isactive bit,
	@hidden bit,
	@display_options varchar(10),
	@map_search tinyint,
	@map_display tinyint,
	@oai_flag bit,
	@oai_metadata nvarchar(2000),
	@contactemail varchar(255),
	@defaultinterface varchar(10),
	@externallink nvarchar(255),
	@parentid int,
	@username varchar(100),
	@languageVariants varchar(500),
	@newaggregationid int output
AS
begin transaction

	-- Set flag to see if this was basically just created (either new or undeleted)
	declare @newly_added bit;
	set @newly_added = 'false';

   -- If the aggregation id is less than 1 then this is for a new aggregation
   if ((@aggregationid  < 1 ) and (( select COUNT(*) from SobekCM_Item_Aggregation where Code=@code ) = 0 ))
   begin

		-- Insert a new row
		insert into SobekCM_Item_Aggregation(Code, [Name], Shortname, Description, ThematicHeadingID, [Type], isActive, Hidden, DisplayOptions, Map_Search, Map_Display, OAI_Flag, OAI_Metadata, ContactEmail, HasNewItems, DefaultInterface, External_Link, DateAdded, LanguageVariants )
		values(@code, @name, @shortname, @description, @thematicHeadingId, @type, @isActive, @hidden, @display_options, @map_search, @map_display, @oai_flag, @oai_metadata, @contactemail, 'false', @defaultinterface, @externallink, GETDATE(), @languageVariants );

		-- Get the primary key
		set @newaggregationid = @@identity;
       
		-- insert the CREATED milestone
		insert into [SobekCM_Item_Aggregation_Milestones] ( AggregationID, Milestone, MilestoneDate, MilestoneUser )
		values ( @newaggregationid, 'Created', getdate(), @username );

		-- Add all the default views for this collection
		insert into [SobekCM_Item_Aggregation_Result_Views] ( AggregationID, ItemAggregationResultTypeID, DefaultView )
		select @newaggregationid, ItemAggregationResultTypeID, 'false' 
		from SobekCM_Item_Aggregation_Result_Types
		where DefaultView = 'true';

		-- Since this was a brand new, set flag
		set @newly_added='true';
   end
   else
   begin

	  -- Add special code to indicate if this aggregation was undeleted
	  if ( exists ( select 1 from SobekCM_Item_Aggregation where Code=@Code and Deleted='true'))
	  begin
		declare @deletedid int;
		set @deletedid = ( select aggregationid from SobekCM_Item_Aggregation where Code=@Code );

		-- insert the UNDELETED milestone
		insert into [SobekCM_Item_Aggregation_Milestones] ( AggregationID, Milestone, MilestoneDate, MilestoneUser )
		values ( @deletedid, 'Created (undeleted as previously existed)', getdate(), @username );

		-- Since this was undeleted, let's make sure this collection isn't linked 
		-- to any parent collections
		delete from SobekCM_Item_Aggregation_Hierarchy
		where ChildID=@deletedid;

		-- Since this was UNDELETED, set flag
		set @newly_added='true';
	  end;

      -- Update the existing row
      update SobekCM_Item_Aggregation
      set  
		Code = @code,
		[Name] = @name,
		ShortName = @shortname,
		[Description] = @description,
		ThematicHeadingID = @thematicHeadingID,
		[Type] = @type,
		isActive = @isactive,
		Hidden = @hidden,
		DisplayOptions = @display_options,
		Map_Search = @map_search,
		Map_Display = @map_display,
		OAI_Flag = @oai_flag,
		OAI_Metadata = @oai_metadata,
		ContactEmail = @contactemail,
		DefaultInterface = @defaultinterface,
		External_Link = @externallink,
		Deleted = 'false',
		DeleteDate = null,
		LanguageVariants = @languageVariants
      where AggregationID = @aggregationid or Code = @code;

      -- Set the return value to the existing id
      set @newaggregationid = ( select aggregationid from SobekCM_Item_Aggregation where Code=@Code );

   end;

	-- Was a parent id provided
	if ( isnull(@parentid, -1 ) > 0 )
	begin
		-- Now, see if the link to the parent exists
		if (( select count(*) from SobekCM_Item_Aggregation_Hierarchy H where H.ParentID = @parentid and H.ChildID = @newaggregationid ) < 1 )
		begin			
			insert into SobekCM_Item_Aggregation_Hierarchy ( ParentID, ChildID )
			values ( @parentid, @newaggregationid );
		end;

		-- If this was newly added (new or undeleted), ensure permissions copied over from parent
		if ( @newly_added = 'true' )
		begin
			-- Add individual user permissions first
			insert into mySobek_User_Edit_Aggregation ( UserID, AggregationID, CanSelect, CanEditItems, 
				IsCurator, IsAdmin, CanEditMetadata, CanEditBehaviors, CanPerformQc, 
				CanUploadFiles, CanChangeVisibility, CanDelete )
			select UserID, @newaggregationid, CanSelect, CanEditItems, 
				IsCurator, IsAdmin, CanEditMetadata, CanEditBehaviors, CanPerformQc, 
				CanUploadFiles, CanChangeVisibility, CanDelete
			from mySobek_User_Edit_Aggregation A
			where ( AggregationID = @parentid )
			  and ( not exists ( select * from mySobek_User_Edit_Aggregation L where L.UserID=A.UserID and L.AggregationID=@newaggregationid ))
			  and (    ( CanEditMetadata='true' ) 
	                or ( CanEditBehaviors='true' )
	                or ( CanPerformQc='true' )
	                or ( CanUploadFiles='true' )
	                or ( CanChangeVisibility='true' )
	                or ( IsCurator='true' )
	                or ( IsAdmin='true' ));

			-- Add user group permissions next 
			insert into mySobek_User_Group_Edit_Aggregation ( UserGroupID, AggregationID, CanSelect, CanEditItems, 
				IsCurator, IsAdmin, CanEditMetadata, CanEditBehaviors, CanPerformQc, 
				CanUploadFiles, CanChangeVisibility, CanDelete )
			select UserGroupID, @newaggregationid, CanSelect, CanEditItems, 
				IsCurator, IsAdmin, CanEditMetadata, CanEditBehaviors, CanPerformQc, 
				CanUploadFiles, CanChangeVisibility, CanDelete
			from mySobek_User_Group_Edit_Aggregation A
			where ( AggregationID = @parentid )
			  and ( not exists ( select * from mySobek_User_Group_Edit_Aggregation L where L.UserGroupID=A.UserGroupID and L.AggregationID=@newaggregationid ))
			  and (    ( CanEditMetadata='true' ) 
	                or ( CanEditBehaviors='true' )
	                or ( CanPerformQc='true' )
	                or ( CanUploadFiles='true' )
	                or ( CanChangeVisibility='true' )
	                or ( IsCurator='true' )
	                or ( IsAdmin='true' ));
		end;
	end;

commit transaction;
GO


IF object_id('SobekCM_Save_Item_Aggregation_ResultViews') IS NULL EXEC ('create procedure dbo.SobekCM_Save_Item_Aggregation_ResultViews as select 1;');
GO


-- Stored procedure to save the basic item aggregation information
ALTER PROCEDURE [dbo].SobekCM_Save_Item_Aggregation_ResultViews
	@code varchar(20),
	@results1 varchar(50),
	@results2 varchar(50),
	@results3 varchar(50),
	@results4 varchar(50),
	@results5 varchar(50),
	@results6 varchar(50),
	@results7 varchar(50),
	@results8 varchar(50),
	@results9 varchar(50),
	@results10 varchar(50),
	@default varchar(50)
AS
begin transaction

	-- Only continue if there is a match on the aggregation code
	if ( exists ( select 1 from SobekCM_Item_Aggregation where Code = @code ))
	begin
		declare @id int;
		set @id = ( select AggregationID from SobekCM_Item_Aggregation where Code = @code );

		-- Clear any existing viewers
		delete from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id;

		-- Add the FIRST results view
		if (( len(@results1) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results1)))
		begin
			declare @results1_id int;
			set @results1_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results1 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results1_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results1_id, 'false' );
			end;
		end;

		-- Add the SECOND results view
		if (( len(@results2) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results2)))
		begin
			declare @results2_id int;
			set @results2_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results2 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results2_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results2_id, 'false' );
			end;
		end;

		-- Add the THIRD results view
		if (( len(@results3) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results3)))
		begin
			declare @results3_id int;
			set @results3_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results3 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results3_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results3_id, 'false' );
			end;
		end;

		-- Add the FOURTH results view
		if (( len(@results4) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results4)))
		begin
			declare @results4_id int;
			set @results4_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results4 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results4_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results4_id, 'false' );
			end;
		end;

		-- Add the FIFTH results view
		if (( len(@results5) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results5)))
		begin
			declare @results5_id int;
			set @results5_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results5 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results5_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results5_id, 'false' );
			end;
		end;

		-- Add the SIXTH results view
		if (( len(@results6) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results6)))
		begin
			declare @results6_id int;
			set @results6_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results6 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results6_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results6_id, 'false' );
			end;
		end;

		-- Add the SEVENTH results view
		if (( len(@results7) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results7)))
		begin
			declare @results7_id int;
			set @results7_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results7 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results7_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results7_id, 'false' );
			end;
		end;

		-- Add the EIGHTH results view
		if (( len(@results8) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results8)))
		begin
			declare @results8_id int;
			set @results8_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results8 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results8_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results8_id, 'false' );
			end;
		end;

		-- Add the NINTH results view
		if (( len(@results9) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results9)))
		begin
			declare @results9_id int;
			set @results9_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results9 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results9_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results9_id, 'false' );
			end;
		end;

		-- Add the TENTH results view
		if (( len(@results10) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@results10)))
		begin
			declare @results10_id int;
			set @results10_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@results10 );

			if ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views where AggregationID=@id and ItemAggregationResultTypeID=@results10_id ))
			begin
				insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
				values ( @id, @results10_id, 'false' );
			end;
		end;

		-- Set the DEFAULT view
		if (( len(@default) > 0 ) and ( exists ( select 1 from SobekCM_Item_Aggregation_Result_Types where ResultType=@default )))
		begin
			-- Get the ID for the default
			declare @default_id int;
			set @default_id = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types where ResultType=@default );

			-- Update, if it exists
			update SobekCM_Item_Aggregation_Result_Views
			set DefaultView = 'true'
			where AggregationID = @id and ItemAggregationResultTypeID = @default_id;
		end;

	end;

commit transaction;
GO



-- Gets all of the information about a single item aggregation
ALTER PROCEDURE [dbo].[SobekCM_Get_Item_Aggregation]
	@code varchar(20)
AS
begin

	-- No need to perform any locks here
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- Create the temporary table
	create table #TEMP_CHILDREN_BUILDER (AggregationID int, Code varchar(20), ParentCode varchar(20), Name varchar(255), [Type] varchar(50), ShortName varchar(100), isActive bit, Hidden bit, HierarchyLevel int );
	
	-- Get the aggregation id
	declare @aggregationid int
	set @aggregationid = coalesce((select AggregationID from SobekCM_Item_Aggregation AS C where C.Code = @code and Deleted=0), -1 );
	
	-- Return information about this aggregation
	select AggregationID, Code, [Name], coalesce(ShortName,[Name]) AS ShortName, [Type], isActive, Hidden, HasNewItems,
	   ContactEmail, DefaultInterface, [Description], Map_Display, Map_Search, OAI_Flag, OAI_Metadata, DisplayOptions, LastItemAdded, 
	   Can_Browse_Items, Items_Can_Be_Described, External_Link, T.ThematicHeadingID, LanguageVariants, ThemeName
	from SobekCM_Item_Aggregation AS C left outer join
	     SobekCM_Thematic_Heading as T on C.ThematicHeadingID=T.ThematicHeadingID 
	where C.AggregationID = @aggregationid;

	-- Drive down through the children in the item aggregation hierarchy (first level below)
	insert into #TEMP_CHILDREN_BUILDER ( AggregationID, Code, ParentCode, Name, [Type], ShortName, isActive, Hidden, HierarchyLevel )
	select C.AggregationID, C.Code, ParentCode=@code, C.[Name], C.[Type], coalesce(C.ShortName,C.[Name]) AS ShortName, C.isActive, C.Hidden, -1
	from SobekCM_Item_Aggregation AS P INNER JOIN
		 SobekCM_Item_Aggregation_Hierarchy AS H ON H.ParentID = P.AggregationID INNER JOIN
		 SobekCM_Item_Aggregation AS C ON H.ChildID = C.AggregationID 
	where ( P.AggregationID = @aggregationid )
	  and ( C.Deleted = 'false' );
	
	-- Now, try to find any children to this ( second level below )
	insert into #TEMP_CHILDREN_BUILDER ( AggregationID, Code, ParentCode, Name, [Type], ShortName, isActive, Hidden, HierarchyLevel )
	select C.AggregationID, C.Code, P.Code, C.[Name], C.[Type], coalesce(C.ShortName,C.[Name]) AS ShortName, C.isActive, C.Hidden, -2
	from #TEMP_CHILDREN_BUILDER AS P INNER JOIN
			SobekCM_Item_Aggregation_Hierarchy AS H ON H.ParentID = P.AggregationID INNER JOIN
			SobekCM_Item_Aggregation AS C ON H.ChildID = C.AggregationID 
	where ( HierarchyLevel = -1 )
	  and ( C.Deleted = 'false' );

	-- Now, try to find any children to this ( third level below )
	insert into #TEMP_CHILDREN_BUILDER ( AggregationID, Code, ParentCode, Name, [Type], ShortName, isActive, Hidden, HierarchyLevel )
	select C.AggregationID, C.Code, P.Code, C.[Name], C.[Type], coalesce(C.ShortName,C.[Name]) AS ShortName, C.isActive, C.Hidden, -3
	from #TEMP_CHILDREN_BUILDER AS P INNER JOIN
			SobekCM_Item_Aggregation_Hierarchy AS H ON H.ParentID = P.AggregationID INNER JOIN
			SobekCM_Item_Aggregation AS C ON H.ChildID = C.AggregationID 
	where ( HierarchyLevel = -2 )
	  and ( C.Deleted = 'false' );

	-- Now, try to find any children to this ( fourth level below )
	insert into #TEMP_CHILDREN_BUILDER ( AggregationID, Code, ParentCode, Name, [Type], ShortName, isActive, Hidden, HierarchyLevel )
	select C.AggregationID, C.Code, P.Code, C.[Name], C.[Type], coalesce(C.ShortName,C.[Name]) AS ShortName, C.isActive, C.Hidden, -4
	from #TEMP_CHILDREN_BUILDER AS P INNER JOIN
			SobekCM_Item_Aggregation_Hierarchy AS H ON H.ParentID = P.AggregationID INNER JOIN
			SobekCM_Item_Aggregation AS C ON H.ChildID = C.AggregationID 
	where ( HierarchyLevel = -3 )
	  and ( C.Deleted = 'false' );

	-- Return all the children
	select Code, ParentCode, [Name], [ShortName], [Type], HierarchyLevel, isActive, Hidden
	from #TEMP_CHILDREN_BUILDER
	order by HierarchyLevel, Code ASC;
	
	-- drop the temporary tables
	drop table #TEMP_CHILDREN_BUILDER;

	-- Return all the metadata ids for metadata types which have values 
	select T.MetadataTypeID, T.canFacetBrowse, T.DisplayTerm, T.SobekCode, T.SolrCode
	into #TEMP_METADATA
	from SobekCM_Metadata_Types T
	where ( LEN(T.SobekCode) > 0 )
	  and exists ( select * from SobekCM_Item_Aggregation_Metadata_Link L where L.AggregationID=@aggregationid and L.MetadataTypeID=T.MetadataTypeID and L.Metadata_Count > 0 );

	if (( select count(*) from #TEMP_METADATA ) > 0 )
	begin
		select * from #TEMP_METADATA order by DisplayTerm ASC;
	end
	else
	begin
		select MetadataTypeID, canFacetBrowse, DisplayTerm, SobekCode, SolrCode
		from SobekCM_Metadata_Types 
		where DefaultAdvancedSearch = 'true'
		order by DisplayTerm ASC;
	end;
			
	-- Return all the parents 
	select Code, [Name], [ShortName], [Type], isActive
	from SobekCM_Item_Aggregation A, SobekCM_Item_Aggregation_Hierarchy H
	where A.AggregationID = H.ParentID 
	  and H.ChildID = @aggregationid
	  and A.Deleted = 'false';

	-- Return the max/min of latitude and longitude - spatial footprint to cover all items with coordinate info
	select Min(F.Point_Latitude) as Min_Latitude, Max(F.Point_Latitude) as Max_Latitude, Min(F.Point_Longitude) as Min_Longitude, Max(F.Point_Longitude) as Max_Longitude
	from SobekCM_Item I, SobekCM_Item_Aggregation_Item_Link L, SobekCM_Item_Footprint F
	where ( I.ItemID = L.ItemID  )
	  and ( L.AggregationID = @aggregationid )
	  and ( F.ItemID = I.ItemID )
	  and ( F.Point_Latitude is not null )
	  and ( F.Point_Longitude is not null )
	  and ( I.Dark = 'false' );

	-- Return all of the key/value pairs of settings
	select Setting_Key, Setting_Value
	from SobekCM_Item_Aggregation_Settings 
	where AggregationID=@aggregationid;

	-- Get the list of result views for this aggregation
	select T.ResultType, A.DefaultView
	from SobekCM_Item_Aggregation_Result_Views A, SobekCM_Item_Aggregation_Result_Types T
	where A.AggregationID=@aggregationid
	  and A.ItemAggregationResultTypeID=T.ItemAggregationResultTypeID
	order by T.DefaultOrder ASC;
	--order by A.DefaultView DESC, T.DefaultOrder ASC;

end;
GO


-- Get the information about the ALL aggregation - standard fron home page collection
-- Written by Mark Sullivan (September 2005), Updated ( January 2010 )
ALTER PROCEDURE [dbo].[SobekCM_Get_All_Groups]
	@metadata_count_to_use_cache int
AS
begin 

	-- No need to perform any locks here
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	
	-- Create the temporary table variable
	declare @TEMP_CHILDREN_BUILDER table ( AggregationID int primary key, Code varchar(20), ParentCode varchar(20), Name nvarchar(255), ShortName nvarchar(100), [Type] nvarchar(50), HierarchyLevel int, isActive bit, Hidden bit );

	-- Get the aggregation id for 'all'
	declare @aggregationid int;
	
	-- Get the aggregation id
	select @aggregationid = AggregationID
	from SobekCM_Item_Aggregation AS C 
	where ( C.Code = 'all' );
	
	-- Return information about this aggregation
	select AggregationID, Code, [Name], isnull(ShortName,[Name]) AS ShortName, [Type], isActive, Hidden, HasNewItems,
	   ContactEmail, DefaultInterface, [Description], Map_Display, Map_Search, OAI_Flag, OAI_Metadata, DisplayOptions, 
	   LastItemAdded=(select MAX(CreateDate) from SobekCM_Item), Can_Browse_Items, Items_Can_Be_Described, External_Link
	from SobekCM_Item_Aggregation AS C 
	where ( C.AggregationID=@aggregationid );
	
	-- Return every metadata term for which any data is present
	if ( ( select COUNT(*) from SobekCM_Item_Aggregation_Metadata_Link where AggregationID=@aggregationid ) > @metadata_count_to_use_cache )
	begin
		-- Just pull the cached links here
		select distinct(S.MetadataTypeID), T.canFacetBrowse, DisplayTerm, T.SobekCode, T.SolrCode
		from SobekCM_Item_Aggregation_Metadata_Link S, 
			SobekCM_Metadata_Types T
		where ( S.MetadataTypeID = T.MetadataTypeID )
		  and ( S.AggregationID = @aggregationid )
		group by S.MetadataTypeID, DisplayTerm, T.canFacetBrowse, T.SobekCode, T.SolrCode
		order by DisplayTerm ASC;		
		
	end
	else
	begin
		-- Just pull this from the actual metadata links then
		select distinct(S.MetadataTypeID), T.canFacetBrowse, DisplayTerm, T.SobekCode, T.SolrCode
		from SobekCM_Metadata_Unique_Search_Table S, 
			SobekCM_Metadata_Types T
		where ( S.MetadataTypeID = T.MetadataTypeID )
		group by S.MetadataTypeID, DisplayTerm, T.canFacetBrowse, T.SobekCode, T.SolrCode
		order by DisplayTerm ASC;		
	end;

	-- Return the max/min of latitude and longitude - spatial footprint to cover all items with coordinate info
	select Min(F.Point_Latitude) as Min_Latitude, Max(F.Point_Latitude) as Max_Latitude, Min(F.Point_Longitude) as Min_Longitude, Max(F.Point_Longitude) as Max_Longitude
	from SobekCM_Item I, SobekCM_Item_Footprint F
	where ( F.ItemID = I.ItemID )
	  and ( F.Point_Latitude is not null )
	  and ( F.Point_Longitude is not null )
	  and ( I.Dark = 'false' );

	-- Return all of the key/value pairs of settings
	select Setting_Key, Setting_Value
	from SobekCM_Item_Aggregation_Settings 
	where AggregationID=@aggregationid;

	-- Get the list of result views for this aggregation
	select T.ResultType, A.DefaultView
	from SobekCM_Item_Aggregation_Result_Views A, SobekCM_Item_Aggregation_Result_Types T
	where A.AggregationID=@aggregationid
	  and A.ItemAggregationResultTypeID=T.ItemAggregationResultTypeID
	order by T.DefaultOrder ASC;
	--order by A.DefaultView DESC, T.DefaultOrder ASC;
end;
GO

