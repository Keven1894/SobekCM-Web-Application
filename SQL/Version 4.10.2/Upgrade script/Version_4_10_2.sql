/** Upgrades the database for a SobekCM system to Version 4.10.2 from Verrsion 4.10.1 **/


-- Since the constraint wasn't there before, there MAY be (incorrect) duplication
if ( exists ( select ViewType from SobekCM_Item_Viewer_Types group by ViewType having count(*) > 1 ))
begin
	-- Need to fix this then
	declare @viewtype varchar(50);
	declare @minViewTypeId int;
	declare @otherViewTypeId int;

	declare dupe_cursor cursor for
	select ViewType 
	from SobekCM_Item_Viewer_Types 
	group by ViewType having count(*) > 1;

	open dupe_cursor;

	-- Get the first viewtype with duplication
	fetch next from dupe_cursor   
	into @viewtype;

	while @@FETCH_STATUS = 0  
	begin 

		-- Get the MINIMUM id that matched ( we will keep that one )
		set @minViewTypeId = ( select MIN(ItemViewTypeID) from SobekCM_Item_Viewer_Types where ViewType=@viewtype );

		-- Using another cursor here actually seems like the best performance
		-- as it results in updating/scanning the least number of rows
		declare dupe2_cursor cursor for
		select ItemViewTypeID  
		from SobekCM_Item_Viewer_Types 
		where ViewType=@viewType  
		  and ItemViewTypeID != @minViewTypeId;

		open dupe2_cursor;

		-- Get the first view type id to remove
		fetch next from dupe2_cursor   
		into @otherViewTypeId;

		while @@FETCH_STATUS = 0  
		begin 
			-- Any items linked to this will be moved to the one we are keeping
			update SobekCM_Item_Viewers 
			set ItemViewTypeID=@minViewTypeId
			where ItemViewTypeID=@otherViewTypeId
			  and not exists ( select 1 
			                   from SobekCM_Item_Viewers V2 
			                   where V2.ItemID = SobekCM_Item_Viewers.ItemID 
							     and V2.ItemViewTypeID=@minViewTypeId );

			-- Any remaining links between the item and this view type are because they
			-- are already linked to the view type we are keeping
			delete from SobekCM_Item_Viewers 
			where ItemViewTypeID=@otherViewTypeId;

			-- Get the next matching view type id to remove (in case
			-- there were more than two dupes with the same viewtype)
			fetch next from dupe2_cursor   
			into @otherViewTypeId;
		end;

		close dupe2_cursor;  
		deallocate dupe2_cursor;  

		-- Now that all items are linked correctly, we can remove the extraneous views
		delete from SobekCM_Item_Viewer_Types 
		where ViewType=@viewtype
		  and ItemViewTypeID != @minViewTypeId;

		-- Next viewtype with duplication
		fetch next from dupe_cursor   
		into @viewtype;
	end;

	close dupe_cursor;  
	deallocate dupe_cursor;  
end;
GO

if ( not exists ( select 1 from INFORMATION_SCHEMA.TABLE_CONSTRAINTS where CONSTRAINT_NAME='SobekCM_Item_Viewer_Types_Viewer_Unique' ))
begin
	ALTER TABLE SobekCM_Item_Viewer_Types  
	ADD CONSTRAINT SobekCM_Item_Viewer_Types_Viewer_Unique UNIQUE (ViewType);   
end;
GO



IF object_id('SobekCM_Metadata_By_Bib_Vid') IS NULL EXEC ('create procedure dbo.SobekCM_Metadata_By_Bib_Vid as select 1;');
GO

ALTER PROCEDURE [dbo].[SobekCM_Metadata_By_Bib_Vid] 
	@aggregationcode varchar(20),
	@bibid1 varchar(10),
	@vid1 varchar(5),
	@bibid2 varchar(10),
	@vid2 varchar(5),
	@bibid3 varchar(10),
	@vid3 varchar(5),
	@bibid4 varchar(10),
	@vid4 varchar(5),
	@bibid5 varchar(10),
	@vid5 varchar(5),
	@bibid6 varchar(10),
	@vid6 varchar(5),
	@bibid7 varchar(10),
	@vid7 varchar(5),
	@bibid8 varchar(10),
	@vid8 varchar(5),
	@bibid9 varchar(10),
	@vid9 varchar(5),
	@bibid10 varchar(10),
	@vid10 varchar(5)											
AS
BEGIN
	-- No need to perform any locks here, especially given the possible
	-- length of this search
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	-- Create the temporary tables first
	-- Create the temporary table to hold all the item id's
	create table #TEMP_ITEMS ( ItemID int primary key, fk_TitleID int, Hit_Count int, SortDate bigint );
		
	-- Determine the aggregationid
	declare @aggregationid int;
	set @aggregationid = coalesce( (select AggregationID from SobekCM_Item_Aggregation where Code=@aggregationcode), -1 );
	
	-- Get the sql which will be used to return the aggregation-specific display values for all the items in this page of results
	declare @item_display_sql nvarchar(max);
	if ( @aggregationid < 0 )
	begin
		select @item_display_sql=coalesce(Browse_Results_Display_SQL, 'select S.ItemID, S.Publication_Date, S.Creator, S.[Publisher.Display], S.Format, S.Edition, S.Material, S.Measurements, S.Style_Period, S.Technique, S.[Subjects.Display], S.Source_Institution, S.Donor from SobekCM_Metadata_Basic_Search_Table S, @itemtable T where S.ItemID = T.ItemID order by T.RowNumber;')
		from SobekCM_Item_Aggregation
		where Code='all';
	end
	else
	begin
		select @item_display_sql=coalesce(Browse_Results_Display_SQL, 'select S.ItemID, S.Publication_Date, S.Creator, S.[Publisher.Display], S.Format, S.Edition, S.Material, S.Measurements, S.Style_Period, S.Technique, S.[Subjects.Display], S.Source_Institution, S.Donor from SobekCM_Metadata_Basic_Search_Table S, @itemtable T where S.ItemID = T.ItemID order by T.RowNumber;')
		from SobekCM_Item_Aggregation
		where AggregationID=@aggregationid;
	end;

	-- Perform the actual metadata search differently, depending on whether an aggregation was 
	-- included to limit this search
	if ( @aggregationid > 0 )
	begin		  
		insert into #TEMP_ITEMS ( ItemID, fk_TitleID, Hit_Count, SortDate )
		select CL.ItemID, I.GroupID, 1, I.SortDate
		from SobekCM_Item AS I inner join
				SobekCM_Item_Aggregation_Item_Link AS CL ON CL.ItemID = I.ItemID inner join
				SobekCM_Item_Group AS M on M.GroupID = I.GroupID
		where ( I.Deleted = 'false' )
			and ( CL.AggregationID = @aggregationid )
			and ( I.Dark = 'false' )
			and (    (( M.BibID=coalesce(@bibid1,'')) and ( I.VID=coalesce(@vid1,'')))
			      or (( M.BibID=coalesce(@bibid2,'')) and ( I.VID=coalesce(@vid2,'')))
				  or (( M.BibID=coalesce(@bibid3,'')) and ( I.VID=coalesce(@vid3,''))) 
				  or (( M.BibID=coalesce(@bibid4,'')) and ( I.VID=coalesce(@vid4,'')))
				  or (( M.BibID=coalesce(@bibid5,'')) and ( I.VID=coalesce(@vid5,'')))
				  or (( M.BibID=coalesce(@bibid6,'')) and ( I.VID=coalesce(@vid6,'')))
				  or (( M.BibID=coalesce(@bibid7,'')) and ( I.VID=coalesce(@vid7,'')))
				  or (( M.BibID=coalesce(@bibid8,'')) and ( I.VID=coalesce(@vid8,'')))
				  or (( M.BibID=coalesce(@bibid9,'')) and ( I.VID=coalesce(@vid9,'')))
				  or (( M.BibID=coalesce(@bibid10,'')) and ( I.VID=coalesce(@vid10,'')))  );			  
			  
	end
	else
	begin	
		insert into #TEMP_ITEMS ( ItemID, fk_TitleID, Hit_Count, SortDate )
		select I.ItemID, I.GroupID, 1, I.SortDate
		from SobekCM_Item AS I inner join
			 SobekCM_Item_Group AS M on M.GroupID = I.GroupID
		where ( I.Deleted = 'false' )
			and ( I.IncludeInAll = 'true' )
			and ( I.Dark = 'false' )
			and (    (( M.BibID=coalesce(@bibid1,'')) and ( I.VID=coalesce(@vid1,'')))
			      or (( M.BibID=coalesce(@bibid2,'')) and ( I.VID=coalesce(@vid2,'')))
				  or (( M.BibID=coalesce(@bibid3,'')) and ( I.VID=coalesce(@vid3,''))) 
				  or (( M.BibID=coalesce(@bibid4,'')) and ( I.VID=coalesce(@vid4,'')))
				  or (( M.BibID=coalesce(@bibid5,'')) and ( I.VID=coalesce(@vid5,'')))
				  or (( M.BibID=coalesce(@bibid6,'')) and ( I.VID=coalesce(@vid6,'')))
				  or (( M.BibID=coalesce(@bibid7,'')) and ( I.VID=coalesce(@vid7,'')))
				  or (( M.BibID=coalesce(@bibid8,'')) and ( I.VID=coalesce(@vid8,'')))
				  or (( M.BibID=coalesce(@bibid9,'')) and ( I.VID=coalesce(@vid9,'')))
				  or (( M.BibID=coalesce(@bibid10,'')) and ( I.VID=coalesce(@vid10,'')))  );		
	end;

	-- Create the temporary item table variable for paging purposes
	declare @TEMP_PAGED_ITEMS TempPagedItemsTableType;
			

	-- create the temporary title table definition
	declare @TEMP_TITLES table ( TitleID int, BibID varchar(10), RowNumber int);		
							  
	-- Create saved select across titles for row numbers
	with TITLES_SELECT AS
		(	select GroupID, G.BibID, ROW_NUMBER() OVER (ORDER BY BibID ASC) as RowNumber
			from #TEMP_ITEMS I, SobekCM_Item_Group G
			where I.fk_TitleID = G.GroupID
			group by G.GroupID, G.BibID, G.SortTitle )

	-- Insert the correct rows into the temp title table	
	insert into @TEMP_TITLES ( TitleID, BibID, RowNumber )
	select GroupID, BibID, RowNumber
	from TITLES_SELECT;
			
	-- Return the title information for this page
	select RowNumber as TitleID, T.BibID, G.GroupTitle, G.ALEPH_Number as OPAC_Number, G.OCLC_Number, coalesce(G.GroupThumbnail,'') as GroupThumbnail, G.[Type], coalesce(G.Primary_Identifier_Type,'') as Primary_Identifier_Type, coalesce(G.Primary_Identifier, '') as Primary_Identifier
	from @TEMP_TITLES T, SobekCM_Item_Group G
	where ( T.TitleID = G.GroupID )
	order by RowNumber ASC;
			
	-- Get the item id's for the items related to these titles
	insert into @TEMP_PAGED_ITEMS
	select ItemID, RowNumber
	from @TEMP_TITLES T, SobekCM_Item I
	where ( T.TitleID = I.GroupID )
		and ( I.Deleted = 'false' )
		and ( I.Dark = 'false' );
			
	-- Return the basic system required item information for this page of results
	select T.RowNumber as fk_TitleID, I.ItemID, VID, Title, IP_Restriction_Mask, coalesce(I.MainThumbnail,'') as MainThumbnail, coalesce(I.Level1_Index, -1) as Level1_Index, coalesce(I.Level1_Text,'') as Level1_Text, coalesce(I.Level2_Index, -1) as Level2_Index, coalesce(I.Level2_Text,'') as Level2_Text, coalesce(I.Level3_Index,-1) as Level3_Index, coalesce(I.Level3_Text,'') as Level3_Text, isnull(I.PubDate,'') as PubDate, I.[PageCount], coalesce(I.Link,'') as Link, coalesce( Spatial_KML, '') as Spatial_KML, coalesce(COinS_OpenURL, '') as COinS_OpenURL		
	from SobekCM_Item I, @TEMP_PAGED_ITEMS T
	where ( T.ItemID = I.ItemID )
	order by T.RowNumber, Level1_Index, Level2_Index, Level3_Index;			
								
	-- Return the aggregation-specific display values for all the items in this page of results
	execute sp_Executesql @item_display_sql, N' @itemtable TempPagedItemsTableType READONLY', @TEMP_PAGED_ITEMS; 	
	
	-- Drop the temporary table
	drop table #TEMP_ITEMS;
	
	SET NOCOUNT OFF;
END;
GO

GRANT EXECUTE ON SobekCM_Metadata_By_Bib_Vid TO Sobek_Builder;
GRANT EXECUTE ON SobekCM_Metadata_By_Bib_Vid TO Sobek_User;
GO

-- Add a setting for the Ace editor theme
if ( not exists ( select 1 from SobekCM_Settings where Setting_Key='Static Resources Source' ))
begin
	update SobekCM_Settings
	set Options='{STATIC_SOURCE_CODES}'
	where Setting_Key='Static Resources Source';
end;
GO


IF ( NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'SobekCM_Item_Aggregation_Result_Types'))
begin
	CREATE TABLE dbo.SobekCM_Item_Aggregation_Result_Types (
		ItemAggregationResultTypeID int IDENTITY(1,1) NOT NULL,
		ResultType varchar(50) NOT NULL,
		DefaultOrder int NOT NULL DEFAULT ((100)),
		DefaultView bit NOT NULL DEFAULT ('false'),
	 CONSTRAINT PK_SobekCM_Item_Aggregation_Result_Types PRIMARY KEY CLUSTERED ( ItemAggregationResultTypeID ASC ) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
	 CONSTRAINT SobekCM_Item_Aggregation_Result_Types_Unique UNIQUE NONCLUSTERED ( ResultType ASC ) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
	) ON [PRIMARY]
end;
GO

IF ( NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'SobekCM_Item_Aggregation_Result_Views'))
begin
	CREATE TABLE dbo.SobekCM_Item_Aggregation_Result_Views (
		ItemAggregationResultID int IDENTITY(1,1) NOT NULL,
		AggregationID int NOT NULL,
		ItemAggregationResultTypeID int NOT NULL,
		DefaultView bit NOT NULL DEFAULT('false'),
	 CONSTRAINT PK_SobekCM_Item_Aggregation_Result_Views PRIMARY KEY CLUSTERED ( ItemAggregationResultID ASC ) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
	) ON [PRIMARY]
end;
GO

IF ( not exists ( SELECT * FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_NAME='FK_SobekCM_Item_Aggregation_Result_Views_AggregationID' ))
begin
	ALTER TABLE dbo.SobekCM_Item_Aggregation_Result_Views ADD CONSTRAINT FK_SobekCM_Item_Aggregation_Result_Views_AggregationID FOREIGN KEY(AggregationID) REFERENCES [dbo].SobekCM_Item_Aggregation ([AggregationID]);
end;
GO

IF ( not exists ( SELECT * FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_NAME='FK_SobekCM_Item_Aggregation_Result_Views_AggregationID' ))
begin
	ALTER TABLE dbo.SobekCM_Item_Aggregation_Result_Views ADD CONSTRAINT FK_SobekCM_Item_Aggregation_Result_Views_TypeID FOREIGN KEY(ItemAggregationResultTypeID) REFERENCES dbo.SobekCM_Item_Aggregation_Result_Types (ItemAggregationResultTypeID);
end;
GO

-- Add all the standard result types
if ( ( select count(*) from SobekCM_Item_Aggregation_Result_Types ) = 0 )
begin
	insert into SobekCM_Item_Aggregation_Result_Types ( ResultType, DefaultOrder, DefaultView ) values ( 'BRIEF', 1, 1 );
	insert into SobekCM_Item_Aggregation_Result_Types ( ResultType, DefaultOrder, DefaultView ) values ( 'THUMBNAIL', 2, 1 );
	insert into SobekCM_Item_Aggregation_Result_Types ( ResultType, DefaultOrder, DefaultView ) values ( 'TABLE', 3, 1 );
	insert into SobekCM_Item_Aggregation_Result_Types ( ResultType, DefaultOrder, DefaultView ) values ( 'EXPORT', 4, 0 );
	insert into SobekCM_Item_Aggregation_Result_Types ( ResultType, DefaultOrder, DefaultView ) values ( 'GMAP', 5, 1 );
end;
GO

-- Add all the standard result types to the aggregations
insert into SobekCM_Item_Aggregation_Result_Views ( AggregationID, ItemAggregationResultTypeID, DefaultView )
select AggregationID, ItemAggregationResultTypeID, 'false'
from SobekCM_Item_Aggregation_Result_Types T, SobekCM_Item_Aggregation A
where ( T.DefaultView = 'true' )
  and ( not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views V
                     where V.AggregationID=A.AggregationID 
					   and V.ItemAggregationResultTypeID=T.ItemAggregationResultTypeID));

-- Also, set defaults
declare @briefid int;
set @briefid = ( select ItemAggregationResultTypeID from SobekCM_Item_Aggregation_Result_Types T where T.ResultType='BRIEF' );
if ( coalesce(@briefid, -1) > 0 )
begin
	with aggrs_no_default as
	( 
		select AggregationID 
		from SobekCM_Item_Aggregation A
		where not exists ( select 1 from SobekCM_Item_Aggregation_Result_Views V where V.AggregationID = A.AggregationID and V.DefaultView='true')
	)
	update SobekCM_Item_Aggregation_Result_Views
	set DefaultView='true'
	where ( exists ( select 1 from aggrs_no_default D where D.AggregationID=SobekCM_Item_Aggregation_Result_Views.AggregationID ))
	  and ( ItemAggregationResultTypeID = @briefid );
end;
GO



 
-- Deletes an item, and deletes the group if there are no additional items attached
ALTER PROCEDURE [dbo].[SobekCM_Delete_Item] 
	@bibid varchar(10),
	@vid varchar(5),
	@as_admin bit,
	@delete_message varchar(1000)
AS
begin transaction
	-- Perform transactionally in case there is a problem deleting some of the rows
	-- so the entire delete is rolled back

   declare @itemid int;
   set @itemid = 0;

    -- first to get the itemid of the specified bibid and vid
   select @itemid = isnull(I.itemid, 0)
   from SobekCM_Item I, SobekCM_Item_Group G
   where (G.bibid = @bibid) 
       and (I.vid = @vid)
       and ( I.GroupID = G.GroupID );

   -- if there is such an itemid in the UFDC database, then delete this item and its related information
  if ( isnull(@itemid, 0 ) > 0)
  begin

	-- Delete all references to this item 
	delete from SobekCM_Metadata_Unique_Link where ItemID=@itemid;
	delete from SobekCM_Metadata_Basic_Search_Table where ItemID=@itemid;
	delete from SobekCM_Item_Footprint where ItemID=@itemid;
	delete from SobekCM_Item_Icons where ItemID=@itemid;
	delete from SobekCM_Item_Statistics where ItemID=@itemid;
	delete from SobekCM_Item_GeoRegion_Link where ItemID=@itemid;
	delete from SobekCM_Item_Aggregation_Item_Link where ItemID=@itemid;
	delete from mySobek_User_Item where ItemID=@itemid;
	delete from mySobek_User_Item_Link where ItemID=@itemid;
	delete from mySobek_User_Description_Tags where ItemID=@itemid;
	delete from SobekCM_Item_Viewers where ItemID=@itemid;
	delete from Tracking_Item where ItemID=@itemid;
	delete from Tracking_Progress where ItemID=@itemid;
	delete from SobekCM_Item_OAI where ItemID=@itemid;
	delete from SobekCM_QC_Errors where ItemID=@itemid;
	delete from SobekCM_QC_Errors_History where ItemID=@itemid;
	delete from SobekCM_Item_Settings where ItemID=@itemid;
	
	if ( @as_admin = 'true' )
	begin
		delete from Tracking_Archive_Item_Link where ItemID=@itemid;
		update Tivoli_File_Log set DeleteMsg=@delete_message, ItemID = -1 where ItemID=@itemid;
	end;
	
	-- Finally, delete the item 
	delete from SobekCM_Item where ItemID=@itemid;
	
	-- Delete the item group if it is the last one existing
	if (( select count(I.ItemID) from SobekCM_Item_Group G, SobekCM_Item I where ( G.BibID = @bibid ) and ( G.GroupID = I.GroupID ) and ( I.Deleted = 0 )) < 1 )
	begin
		
		declare @groupid int;
		set @groupid = 0;	
		
		-- first to get the itemid of the specified bibid and vid
		select @groupid = isnull(G.GroupID, 0)
		from SobekCM_Item_Group G
		where (G.bibid = @bibid);
		
		-- Delete if this selected something
		if ( ISNULL(@groupid, 0 ) > 0 )
		begin		
			-- delete from the item group table	and all references
			delete from SobekCM_Item_Group_External_Record where GroupID=@groupid;
			delete from SobekCM_Item_Group_Web_Skin_Link where GroupID=@groupid;
			delete from SobekCM_Item_Group_Statistics where GroupID=@groupid;
			delete from mySobek_User_Bib_Link where GroupID=@groupid;
			delete from SobekCM_Item_Group_OAI where GroupID=@groupid;
			delete from SobekCM_Item_Group where GroupID=@groupid;
		end;
	end
	else
	begin
		-- Finally set the volume count for this group correctly
		update SobekCM_Item_Group
		set ItemCount = ( select count(*) from SobekCM_Item I where ( I.GroupID = SobekCM_Item_Group.GroupID ))	
		where ( SobekCM_Item_Group.BibID = @bibid );
	end;
  end;
   
commit transaction;
GO


-- Retrive the very simple list of items to save in XML format or to step through
-- and add to the solr/lucene index, etc..  
ALTER PROCEDURE [dbo].[SobekCM_Simple_Item_List]
	@collection_code varchar(10)
AS
BEGIN

	-- No need to perform any locks here
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	
	if ( len( isnull( @collection_code, '' )) = 0 )
	begin

		select G.BibID, I.VID, I.Title, I.CreateDate, Resource_Link = File_Location, I.LastSaved
		from SobekCM_Item_Group G, SobekCM_Item I
		where ( G.GroupID = I.GroupID )
		  and ( I.IP_Restriction_Mask = 0 )
		  and ( G.Deleted = CONVERT(bit,0) )
	      and ( I.Deleted = CONVERT(bit,0) )
		  and ( I.Dark = 0 )

	end
	else
	begin

		select G.BibID, I.VID, I.Title, I.CreateDate, Resource_Link = File_Location, I.LastSaved
		from SobekCM_Item_Group G, SobekCM_Item I, SobekCM_Item_Aggregation C, SobekCM_Item_Aggregation_Item_Link CL
		where ( G.GroupID = I.GroupID )
		  and ( I.IP_Restriction_Mask = 0 )
		  and ( G.Deleted = CONVERT(bit,0) )
	      and ( I.Deleted = CONVERT(bit,0) )
		  and ( I.Dark = 0 )
		  and ( I.ItemID = CL.ItemID )
		  and ( CL.AggregationID = C.AggregationID )
		  and ( Code = @collection_code );
	end;
END;
GO


-- Pull any additional item details before showing this item
ALTER PROCEDURE [dbo].[SobekCM_Get_Item_Details2]
	@BibID varchar(10),
	@VID varchar(5)
AS
BEGIN

	-- No need to perform any locks here
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- Does this BIbID exist?
	if (not exists ( select 1 from SobekCM_Item_Group where BibID = @BibID ))
	begin
		select 'INVALID BIBID' as ErrorMsg, '' as BibID, '' as VID;
		return;
	end;

	-- Was this for one item within a group?
	if ( LEN( ISNULL(@VID,'')) > 0 )
	begin	

		-- Does this VID exist in that stored procedure?
		if ( not exists ( select 1 from SobekCM_Item I, SobekCM_Item_Group G where I.GroupID = G.GroupID and G.BibID=@BibID and I.VID = @VID ))
		begin

			select top 1 'INVALID VID' as ErrorMsg, @BibID as BibID, VID
			from SobekCM_Item I, SobekCM_Item_Group G
			where I.GroupID = G.GroupID 
			  and G.BibID = @BibID
			order by VID;

			return;
		end;
	
		-- Only continue if there is ONE match
		if (( select COUNT(*) from SobekCM_Item I, SobekCM_Item_Group G where I.GroupID = G.GroupID and G.BibID = @BibID and I.VID = @VID ) = 1 )
		begin
			-- Get the itemid
			declare @ItemID int;
			select @ItemID = ItemID from SobekCM_Item I, SobekCM_Item_Group G where I.GroupID = G.GroupID and G.BibID = @BibID and I.VID = @VID;

			-- Return any descriptive tags
			select U.FirstName, U.NickName, U.LastName, G.BibID, I.VID, T.Description_Tag, T.TagID, T.Date_Modified, U.UserID, isnull([PageCount], 0) as Pages, ExposeFullTextForHarvesting
			from mySobek_User U, mySobek_User_Description_Tags T, SobekCM_Item I, SobekCM_Item_Group G
			where ( T.ItemID = @ItemID )
			  and ( I.ItemID = T.ItemID )
			  and ( I.GroupID = G.GroupID )
			  and ( T.UserID = U.UserID );
			
			-- Return the aggregation information linked to this item
			select A.Code, A.Name, A.ShortName, A.[Type], A.Map_Search, A.DisplayOptions, A.Items_Can_Be_Described, L.impliedLink, A.Hidden, A.isActive, ISNULL(A.External_Link,'') as External_Link
			from SobekCM_Item_Aggregation_Item_Link L, SobekCM_Item_Aggregation A
			where ( L.ItemID = @ItemID )
			  and ( A.AggregationID = L.AggregationID );
		  
			-- Return information about the actual item/group
			select G.BibID, I.VID, G.File_Location, G.SuppressEndeca, 'true' as [Public], I.IP_Restriction_Mask, G.GroupID, I.ItemID, I.CheckoutRequired, Total_Volumes=(select COUNT(*) from SobekCM_Item J where G.GroupID = J.GroupID ),
				isnull(I.Level1_Text, '') as Level1_Text, isnull( I.Level1_Index, 0 ) as Level1_Index, 
				isnull(I.Level2_Text, '') as Level2_Text, isnull( I.Level2_Index, 0 ) as Level2_Index, 
				isnull(I.Level3_Text, '') as Level3_Text, isnull( I.Level3_Index, 0 ) as Level3_Index,
				G.GroupTitle, I.TextSearchable, Comments=isnull(I.Internal_Comments,''), Dark, G.[Type],
				I.Title, I.Publisher, I.Author, I.Donor, I.PubDate, G.ALEPH_Number, G.OCLC_Number, I.Born_Digital, 
				I.Disposition_Advice, I.Material_Received_Date, I.Material_Recd_Date_Estimated, I.Tracking_Box, I.Disposition_Advice_Notes, 
				I.Left_To_Right, I.Disposition_Notes, G.Track_By_Month, G.Large_Format, G.Never_Overlay_Record, I.CreateDate, I.SortDate, 
				G.Primary_Identifier_Type, G.Primary_Identifier, G.[Type] as GroupType, coalesce(I.MainThumbnail,'') as MainThumbnail,
				T.EmbargoEnd, coalesce(T.UMI,'') as UMI, T.Original_EmbargoEnd, coalesce(T.Original_AccessCode,'') as Original_AccessCode,
				I.CitationSet
			from SobekCM_Item as I inner join
				 SobekCM_Item_Group as G on G.GroupID=I.GroupID left outer join
				 Tracking_Item as T on T.ItemID=I.ItemID
			where ( I.ItemID = @ItemID );
		  
			-- Return any ticklers associated with this item
			select MetadataValue
			from SobekCM_Metadata_Unique_Search_Table M, SobekCM_Metadata_Unique_Link L
			where ( L.ItemID = @ItemID ) 
			  and ( L.MetadataID = M.MetadataID )
			  and ( M.MetadataTypeID = 20 );
			
			-- Return the viewers for this item
			select T.ViewType, V.Attribute, V.Label, coalesce(V.MenuOrder, T.MenuOrder) as MenuOrder, V.Exclude, coalesce(V.OrderOverride, T.[Order])
			from SobekCM_Item_Viewers V, SobekCM_Item_Viewer_Types T
			where ( V.ItemID = @ItemID )
			  and ( V.ItemViewTypeID = T.ItemViewTypeID )
			group by T.ViewType, V.Attribute, V.Label, coalesce(V.MenuOrder, T.MenuOrder), V.Exclude, coalesce(V.OrderOverride, T.[Order])
			order by coalesce(V.OrderOverride, T.[Order]) ASC;
				
			-- Return the icons for this item
			select Icon_URL, Link, Icon_Name, I.Title
			from SobekCM_Icon I, SobekCM_Item_Icons L
			where ( L.IconID = I.IconID ) 
			  and ( L.ItemID = @ItemID )
			order by Sequence;
			  
			-- Return any web skin restrictions
			select S.WebSkinCode
			from SobekCM_Item_Group_Web_Skin_Link L, SobekCM_Item I, SobekCM_Web_Skin S
			where ( L.GroupID = I.GroupID )
			  and ( L.WebSkinID = S.WebSkinID )
			  and ( I.ItemID = @ItemID )
			order by L.Sequence;

			-- Return all of the key/value pairs of settings
			select Setting_Key, Setting_Value
			from SobekCM_Item_Settings 
			where ItemID=@ItemID;
		end;		
	end
	else
	begin
		-- Return the aggregation information linked to this item
		select GroupTitle, BibID, G.[Type], G.File_Location, isnull(AGGS.Code,'') AS Code, G.GroupID, isnull(GroupThumbnail,'') as Thumbnail, G.Track_By_Month, G.Large_Format, G.Never_Overlay_Record, G.Primary_Identifier_Type, G.Primary_Identifier
		from SobekCM_Item_Group AS G LEFT JOIN
			 ( select distinct(A.Code),  G2.GroupID
			   from SobekCM_Item_Group G2, SobekCM_Item IL, SobekCM_Item_Aggregation_Item_Link L, SobekCM_Item_Aggregation A
		       where IL.ItemID=L.ItemID 
		         and A.AggregationID=L.AggregationID
		         and G2.GroupID=IL.GroupID
		         and G2.BibID=@BibID
		         and G2.Deleted='false'
		       group by A.Code, G2.GroupID ) AS AGGS ON G.GroupID=AGGS.GroupID
		where ( G.BibID = @BibID )
		  and ( G.Deleted = 'false' );

		-- Get list of icon ids
		select distinct(IconID)
		into #TEMP_ICON
		from SobekCM_Item_Icons II, SobekCM_Item It, SobekCM_Item_Group G
		where ( It.GroupID = G.GroupID )
			and ( G.BibID = @bibid )
			and ( It.Deleted = 0 )
			and ( II.ItemID = It.ItemID )
		group by IconID;

		-- Return icons
		select Icon_URL, Link, Icon_Name, Title
		from SobekCM_Icon I, (	select distinct(IconID)
								from SobekCM_Item_Icons II, SobekCM_Item It, SobekCM_Item_Group G
								where ( It.GroupID = G.GroupID )
							 	  and ( G.BibID = @bibid )
								  and ( It.Deleted = 0 )
								  and ( II.ItemID = It.ItemID )
								group by IconID) AS T
		where ( T.IconID = I.IconID );
		
		-- Return any web skin restrictions
		select S.WebSkinCode
		from SobekCM_Item_Group_Web_Skin_Link L, SobekCM_Item_Group G, SobekCM_Web_Skin S
		where ( L.GroupID = G.GroupID )
		  and ( L.WebSkinID = S.WebSkinID )
		  and ( G.BibID = @BibID )
		order by L.Sequence;
		
		-- Get the distinct list of all aggregations linked to this item
		select distinct( Code )
		from SobekCM_Item_Aggregation A, SobekCM_Item_Aggregation_Item_Link L, SobekCM_Item_Group G, SobekCM_Item I
		where ( I.ItemID = L.ItemID )
		  and ( I.GroupID = G.GroupID )
		  and ( G.BibID = @BibID )
		  and ( L.AggregationID = A.AggregationID );		
	end;
		
	-- Get the list of related item groups
	select B.BibID, B.GroupTitle, R.Relationship_A_to_B AS Relationship
	from SobekCM_Item_Group A, SobekCM_Item_Group_Relationship R, SobekCM_Item_Group B
	where ( A.BibID = @bibid ) 
	  and ( R.GroupA = A.GroupID )
	  and ( R.GroupB = B.GroupID )
	union
	select A.BibID, A.GroupTitle, R.Relationship_B_to_A AS Relationship
	from SobekCM_Item_Group A, SobekCM_Item_Group_Relationship R, SobekCM_Item_Group B
	where ( B.BibID = @bibid ) 
	  and ( R.GroupB = B.GroupID )
	  and ( R.GroupA = A.GroupID );
		  
END;
GO

-- Correction so that searching within an aggregation doess not bother looking at the 
-- IncludeInaAll flag ( from zines collection under/separate from wolfsonian )

-- Perform metadata search 
ALTER PROCEDURE [dbo].[SobekCM_Metadata_Search_Paged]
	@link1 int,
	@term1 nvarchar(255),
	@field1 int,
	@link2 int,
	@term2 nvarchar(255),
	@field2 int,
	@link3 int,
	@term3 nvarchar(255),
	@field3 int,
	@link4 int,
	@term4 nvarchar(255),
	@field4 int,
	@link5 int,
	@term5 nvarchar(255),
	@field5 int,
	@link6 int,
	@term6 nvarchar(255),
	@field6 int,
	@link7 int,
	@term7 nvarchar(255),
	@field7 int,
	@link8 int,
	@term8 nvarchar(255),
	@field8 int,
	@link9 int,
	@term9 nvarchar(255),
	@field9 int,
	@link10 int,
	@term10 nvarchar(255),
	@field10 int,
	@include_private bit,
	@aggregationcode varchar(20),	
	@daterange_start bigint,
	@daterange_end bigint,
	@pagesize int, 
	@pagenumber int,
	@sort int,
	@minpagelookahead int,
	@maxpagelookahead int,
	@lookahead_factor float,
	@include_facets bit,
	@facettype1 smallint,
	@facettype2 smallint,
	@facettype3 smallint,
	@facettype4 smallint,
	@facettype5 smallint,
	@facettype6 smallint,
	@facettype7 smallint,
	@facettype8 smallint,
	@total_items int output,
	@total_titles int output,
	@all_collections_items int output,
	@all_collections_titles int output	
AS
BEGIN
	-- No need to perform any locks here, especially given the possible
	-- length of this search
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;
	
	-- Field#'s indicate which metadata field (if any).  These are numbers from the 
	-- SobekCM_Metadata_Types table.  A field# of -1, means all fields are included.
	
	-- Link#'s indicate if this is an AND-joiner ( intersect ) or an OR-joiner ( union )
	-- 0 = AND, 1 = OR, 2 = AND NOT
	
	-- Examples of using this procedure are:
	-- exec SobekCM_Metadata_Search 'haiti',1,0,'kesse',4,0,'',0
	-- This searches for materials which have haiti in the title AND kesse in the creator
	
	-- exec SobekCM_Metadata_Search 'haiti',1,1,'kesse',-1,0,'',0
	-- This searches for materials which have haiti in the title OR kesse anywhere
	
	-- Create the temporary table variables first
	-- Create the temporary table to hold all the item id's
	create table #TEMPZERO ( ItemID int primary key );
	create table #TEMP_ITEMS ( ItemID int primary key, fk_TitleID int, Hit_Count int, SortDate bigint );
		    
	-- declare both the sql query and the parameter definitions
	declare @SQLQuery AS nvarchar(max);
	declare @rankselection AS nvarchar(1000);
    declare @ParamDefinition AS NVarchar(2000);
		
    -- Determine the aggregationid
	declare @aggregationid int;
	set @aggregationid = coalesce(( select AggregationID from SobekCM_Item_Aggregation where Code=@aggregationcode ), -1);
	
	-- Get the sql which will be used to return the aggregation-specific display values for all the items in this page of results
	declare @item_display_sql nvarchar(max);
	if ( @aggregationid < 0 )
	begin
		select @item_display_sql=coalesce(Browse_Results_Display_SQL, 'select S.ItemID, S.Publication_Date, S.Creator, S.[Publisher.Display], S.Format, S.Edition, S.Material, S.Measurements, S.Style_Period, S.Technique, S.[Subjects.Display], S.Source_Institution, S.Donor from SobekCM_Metadata_Basic_Search_Table S, @itemtable T where S.ItemID = T.ItemID;')
		from SobekCM_Item_Aggregation
		where Code='all';
	end
	else
	begin
		select @item_display_sql=coalesce(Browse_Results_Display_SQL, 'select S.ItemID, S.Publication_Date, S.Creator, S.[Publisher.Display], S.Format, S.Edition, S.Material, S.Measurements, S.Style_Period, S.Technique, S.[Subjects.Display], S.Source_Institution, S.Donor from SobekCM_Metadata_Basic_Search_Table S, @itemtable T where S.ItemID = T.ItemID;')
		from SobekCM_Item_Aggregation
		where AggregationID=@aggregationid;
	end;
	
    -- Set value for filtering privates
	declare @lower_mask int;
	set @lower_mask = 0;
	if ( @include_private = 'true' )
	begin
		set @lower_mask = -256;
	end;
	    
    -- Start to build the main bulk of the query   
	set @SQLQuery = '( I.Dark = ''false'' ) and ( I.Deleted = ''false'' ) and ( I.IP_Restriction_Mask >= ' + cast(@lower_mask as varchar(3)) + ' ) and ';
	
	-- Start with the date range information, if this includes a date range search
	if ( @daterange_end > 0 )
	begin
		set @SQLQuery = @SQLQuery + ' ( L.SortDate > ' + cast(@daterange_start as nvarchar(12)) + ') and ( L.SortDate < ' +  cast(@daterange_end as nvarchar(12)) + ') and ';	
	end;
    
    -- Was a field listed?
    if (( @field1 > 0 ) and ( @field1 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
    begin
		-- Was this an AND, OR, or AND NOT?
		if ( @link1 = 2 ) set @SQLQuery = @SQLQuery + ' not';

		-- Get the name of this column then
		declare @field1_name varchar(100);
		set @field1_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field1 );

		-- Add this search then
		set @SQLQuery = @SQLQuery + ' contains ( L.' + @field1_name + ', @innerterm1 )';
	end
	else
	begin
		-- Search the full citation then
		set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm1 )';	
	end;
            
    -- Start to build the query which will do ranking over the results which match this search
    set @rankselection = @term1;

	-- Add the second term, if there is one
	if (( LEN( ISNULL(@term2,'')) > 0 ) and (( @link2 = 0 ) or ( @link2 = 1 ) or ( @link2 = 2 )))
	begin	
		-- Was this an AND, OR, or AND NOT?
		if ( @link2 = 0 ) set @SQLQuery = @SQLQuery + ' and';
		if ( @link2 = 1 ) set @SQLQuery = @SQLQuery + ' or';
		if ( @link2 = 2 ) set @SQLQuery = @SQLQuery + ' and not';
		
		-- Was a field listed?
		if (( @field2 > 0 ) and ( @field2 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
		begin
			-- Get the name of this column then
			declare @field2_name varchar(100);
			set @field2_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field2 );

			-- Add this search then
			set @SQLQuery = @SQLQuery + ' contains ( L.' + @field2_name + ', @innerterm2 )';
		end
		else
		begin
			-- Search the full citation then
			set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm2 )';	
		end;			
		
		-- Build the ranking query
		if ( @link2 != 2 )
		begin
			set @rankselection = @rankselection + ' or ' + @term2;	
		end
	end;    
	
	-- Add the third term, if there is one
	if (( LEN( ISNULL(@term3,'')) > 0 ) and (( @link3 = 0 ) or ( @link3 = 1 ) or ( @link3 = 2 )))
	begin	
		-- Was this an AND, OR, or AND NOT?
		if ( @link3 = 0 ) set @SQLQuery = @SQLQuery + ' and';
		if ( @link3 = 1 ) set @SQLQuery = @SQLQuery + ' or';
		if ( @link3 = 2 ) set @SQLQuery = @SQLQuery + ' and not';
		
		-- Was a field listed?
		if (( @field3 > 0 ) and ( @field3 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
		begin
			-- Get the name of this column then
			declare @field3_name varchar(100);
			set @field3_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field3 );

			-- Add this search then
			set @SQLQuery = @SQLQuery + ' contains ( L.' + @field3_name + ', @innerterm3 )';
		end
		else
		begin
			-- Search the full citation then
			set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm3 )';	
		end;	
		
		-- Build the ranking query
		if ( @link3 != 2 )
		begin
			set @rankselection = @rankselection + ' or ' + @term3;		
		end
	end;   
	
	-- Add the fourth term, if there is one
	if (( LEN( ISNULL(@term4,'')) > 0 ) and (( @link4 = 0 ) or ( @link4 = 1 ) or ( @link4 = 2 )))
	begin	
		-- Was this an AND, OR, or AND NOT?
		if ( @link4 = 0 ) set @SQLQuery = @SQLQuery + ' and';
		if ( @link4 = 1 ) set @SQLQuery = @SQLQuery + ' or';
		if ( @link4 = 2 ) set @SQLQuery = @SQLQuery + ' and not';
		
		-- Was a field listed?
		if (( @field4 > 0 ) and ( @field4 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
		begin
			-- Get the name of this column then
			declare @field4_name varchar(100);
			set @field4_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field4 );

			-- Add this search then
			set @SQLQuery = @SQLQuery + ' contains ( L.' + @field4_name + ', @innerterm4 )';
		end
		else
		begin
			-- Search the full citation then
			set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm4 )';	
		end;	
			
		-- Build the ranking query
		if ( @link4 != 2 )
		begin
			set @rankselection = @rankselection + ' or ' + @term4;		
		end
	end;
	
	-- Add the fifth term, if there is one
	if (( LEN( ISNULL(@term5,'')) > 0 ) and (( @link5 = 0 ) or ( @link5 = 1 ) or ( @link5 = 2 )))
	begin	
		-- Was this an AND, OR, or AND NOT?
		if ( @link5 = 0 ) set @SQLQuery = @SQLQuery + ' and';
		if ( @link5 = 1 ) set @SQLQuery = @SQLQuery + ' or';
		if ( @link5 = 2 ) set @SQLQuery = @SQLQuery + ' and not';
		
		-- Was a field listed?
		if (( @field5 > 0 ) and ( @field5 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
		begin
			-- Get the name of this column then
			declare @field5_name varchar(100);
			set @field5_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field5 );

			-- Add this search then
			set @SQLQuery = @SQLQuery + ' contains ( L.' + @field5_name + ', @innerterm5 )';
		end
		else
		begin
			-- Search the full citation then
			set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm5 )';	
		end;
			
		-- Build the ranking query
		if ( @link5 != 2 )
		begin
			set @rankselection = @rankselection + ' or ' + @term5;		
		end
	end;
	
	-- Add the sixth term, if there is one
	if (( LEN( ISNULL(@term6,'')) > 0 ) and (( @link6 = 0 ) or ( @link6 = 1 ) or ( @link6 = 2 )))
	begin	
		-- Was this an AND, OR, or AND NOT?
		if ( @link6 = 0 ) set @SQLQuery = @SQLQuery + ' and';
		if ( @link6 = 1 ) set @SQLQuery = @SQLQuery + ' or';
		if ( @link6 = 2 ) set @SQLQuery = @SQLQuery + ' and not';
		
		-- Was a field listed?
		if (( @field6 > 0 ) and ( @field6 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
		begin
			-- Get the name of this column then
			declare @field6_name varchar(100);
			set @field6_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field6 );

			-- Add this search then
			set @SQLQuery = @SQLQuery + ' contains ( L.' + @field6_name + ', @innerterm6 )';
		end
		else
		begin
			-- Search the full citation then
			set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm6 )';	
		end;
		
		-- Build the ranking query
		if ( @link6 != 2 )
		begin
			set @rankselection = @rankselection + ' or ' + @term6;		
		end
	end; 
	
	-- Add the seventh term, if there is one
	if (( LEN( ISNULL(@term7,'')) > 0 ) and (( @link7 = 0 ) or ( @link7 = 1 ) or ( @link7 = 2 )))
	begin	
		-- Was this an AND, OR, or AND NOT?
		if ( @link7 = 0 ) set @SQLQuery = @SQLQuery + ' and';
		if ( @link7 = 1 ) set @SQLQuery = @SQLQuery + ' or';
		if ( @link7 = 2 ) set @SQLQuery = @SQLQuery + ' and not';
		
		-- Was a field listed?
		if (( @field7 > 0 ) and ( @field7 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
		begin
			-- Get the name of this column then
			declare @field7_name varchar(100);
			set @field7_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field7 );

			-- Add this search then
			set @SQLQuery = @SQLQuery + ' contains ( L.' + @field7_name + ', @innerterm7 )';
		end
		else
		begin
			-- Search the full citation then
			set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm7 )';	
		end;
		
		-- Build the ranking query
		if ( @link7 != 2 )
		begin
			set @rankselection = @rankselection + ' or ' + @term7;		
		end
	end;
	
	-- Add the eighth term, if there is one
	if (( LEN( ISNULL(@term8,'')) > 0 ) and (( @link8 = 0 ) or ( @link8 = 1 ) or ( @link8 = 2 )))
	begin	
		-- Was this an AND, OR, or AND NOT?
		if ( @link8 = 0 ) set @SQLQuery = @SQLQuery + ' and';
		if ( @link8 = 1 ) set @SQLQuery = @SQLQuery + ' or';
		if ( @link8 = 2 ) set @SQLQuery = @SQLQuery + ' and not';
		
		-- Was a field listed?
		if (( @field8 > 0 ) and ( @field8 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
		begin
			-- Get the name of this column then
			declare @field8_name varchar(100);
			set @field8_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field8 );

			-- Add this search then
			set @SQLQuery = @SQLQuery + ' contains ( L.' + @field8_name + ', @innerterm8 )';
		end
		else
		begin
			-- Search the full citation then
			set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm8 )';	
		end;
		
		-- Build the ranking query
		if ( @link8 != 2 )
		begin
			set @rankselection = @rankselection + ' or ' + @term8;		
		end
	end;
	
	-- Add the ninth term, if there is one
	if (( LEN( ISNULL(@term9,'')) > 0 ) and (( @link9 = 0 ) or ( @link9 = 1 ) or ( @link9 = 2 )))
	begin	
		-- Was this an AND, OR, or AND NOT?
		if ( @link9 = 0 ) set @SQLQuery = @SQLQuery + ' and';
		if ( @link9 = 1 ) set @SQLQuery = @SQLQuery + ' or';
		if ( @link9 = 2 ) set @SQLQuery = @SQLQuery + ' and not';
		
		-- Was a field listed?
		if (( @field9 > 0 ) and ( @field9 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
		begin
			-- Get the name of this column then
			declare @field9_name varchar(100);
			set @field9_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field9 );

			-- Add this search then
			set @SQLQuery = @SQLQuery + ' contains ( L.' + @field9_name + ', @innerterm9 )';
		end
		else
		begin
			-- Search the full citation then
			set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm9 )';	
		end;
		
		-- Build the ranking query
		if ( @link9 != 2 )
		begin
			set @rankselection = @rankselection + ' or ' + @term9;		
		end
	end;
	
	-- Add the tenth term, if there is one
	if (( LEN( ISNULL(@term10,'')) > 0 ) and (( @link10 = 0 ) or ( @link10 = 1 ) or ( @link10 = 2 )))
	begin	
		-- Was this an AND, OR, or AND NOT?
		if ( @link10 = 0 ) set @SQLQuery = @SQLQuery + ' and';
		if ( @link10 = 1 ) set @SQLQuery = @SQLQuery + ' or';
		if ( @link10 = 2 ) set @SQLQuery = @SQLQuery + ' and not';
		
		-- Was a field listed?
		if (( @field10 > 0 ) and ( @field10 in ( select MetadataTypeID from SobekCM_Metadata_Types )))
		begin
			-- Get the name of this column then
			declare @field10_name varchar(100);
			set @field10_name = ( select REPLACE(MetadataName, ' ', '_') from SobekCM_Metadata_Types where MetadataTypeID = @field10 );

			-- Add this search then
			set @SQLQuery = @SQLQuery + ' contains ( L.' + @field10_name + ', @innerterm10 )';
		end
		else
		begin
			-- Search the full citation then
			set @SQLQuery = @SQLQuery + ' contains ( L.FullCitation, @innerterm10 )';	
		end;
		
		-- Build the ranking query
		if ( @link10 != 2 )
		begin
			set @rankselection = @rankselection + ' or ' + @term10;		
		end		
	end;
	
	-- Add the recompile option
	--set @SQLQuery = @SQLQuery + ' option (RECOMPILE)';

    -- Add the first term and start to build the query which will provide the items which match the search
    declare @mainquery nvarchar(max);
    set @mainquery = 'select L.Itemid from SobekCM_Metadata_Basic_Search_Table as L join SobekCM_Item as I on ( I.itemID = L.ItemID ) ';
    
    -- Do we need to limit by aggregation id as well?
    if ( @aggregationid > 0 )
    begin
		set @mainquery = @mainquery + ' join SobekCM_Item_Aggregation_Item_Link AS A ON ( A.ItemID = L.ItemID ) and ( A.AggregationID = ' + CAST( @aggregationid as varchar(5) ) + ')';   
    end    
    
    -- Add the full text search portion here
    set @mainquery = @mainquery + ' where ' + @SQLQuery;
	
	-- Set the parameter definition
	set @ParamDefinition = ' @innerterm1 nvarchar(255), @innerterm2 nvarchar(255), @innerterm3 nvarchar(255), @innerterm4 nvarchar(255), @innerterm5 nvarchar(255), @innerterm6 nvarchar(255), @innerterm7 nvarchar(255), @innerterm8 nvarchar(255), @innerterm9 nvarchar(255), @innerterm10 nvarchar(255)';
		
	-- Execute this stored procedure
	insert #TEMPZERO execute sp_Executesql @mainquery, @ParamDefinition, @term1, @term2, @term3, @term4, @term5, @term6, @term7, @term8, @term9, @term10;

	-- DEBUG
	--declare @tempzero_count int;
	--set @tempzero_count = (select count(*) from #TEMPZERO );
	--print '-- #TEMPZERO count = ' + cast(@tempzero_count as varchar(10));

	-- If we are looking within a particular aggregation, no need to incelu the Inclu
			
	-- Perform ranking against the items and insert into another temporary table 
	-- with all the possible data elements needed for applying the user's sort

	insert into #TEMP_ITEMS ( ItemID, fk_TitleID, SortDate, Hit_Count )
	select I.ItemID, I.GroupID, SortDate=isnull( I.SortDate,-1), isnull(KEY_TBL.RANK, 0 )
	from #TEMPZERO AS T1 inner join
		 SobekCM_Item as I on T1.ItemID=I.ItemID left outer join
		 CONTAINSTABLE(SobekCM_Metadata_Basic_Search_Table, FullCitation, @rankselection ) AS KEY_TBL on KEY_TBL.[KEY] = T1.ItemID
	where ( I.Deleted = 'false' )
      and ( I.IP_Restriction_Mask >= @lower_mask )	
      and (( I.IncludeInAll = 'true' ) or ( @aggregationid > 0 ))

	-- DEBUG
	-- print '-- @rankselection = ' + @rankselection;
	-- select * from #TEMP_ITEMS;
	-- declare @tempitems_count int;
	-- set @tempitems_count = ( select count(*) from #TEMP_ITEMS);
	-- print '-- ##TEMP_ITEMS count = ' + cast(@tempitems_count as varchar(10));

	-- Determine the start and end rows
	declare @rowstart int;
	declare @rowend int;
	set @rowstart = (@pagesize * ( @pagenumber - 1 )) + 1;
	set @rowend = @rowstart + @pagesize - 1; 
	
	-- If there were no results at all, check the count in the entire library
	if ( ( select COUNT(*) from #TEMP_ITEMS ) = 0 )
	begin
		-- Set the items and titles correctly
		set @total_items = 0;
		set @total_titles = 0;
		
		-- If there was an aggregation id, just return the counts for the whole library
		if ( @aggregationid > 0 )	
		begin
		
			-- Truncate the table and repull the data
			truncate table #TEMPZERO;
			
			-- Query against ALL aggregations this time
			declare @allquery nvarchar(max);
			set @allquery = 'select L.Itemid from SobekCM_Metadata_Basic_Search_Table AS L join SobekCM_Item as I on ( I.itemID = L.ItemID ) where ' + @SQLQuery;
			
			-- Execute this stored procedure
			insert #TEMPZERO execute sp_Executesql @allquery, @ParamDefinition, @term1, @term2, @term3, @term4, @term5, @term6, @term7, @term8, @term9, @term10;
			
			-- Get all items in the entire library then		  
			insert into #TEMP_ITEMS ( ItemID, fk_TitleID )
			select I.ItemID, I.GroupID
			from #TEMPZERO T1, SobekCM_Item I
			where ( T1.ItemID = I.ItemID )
			  and ( I.Deleted = 'false' )
			  and ( I.IP_Restriction_Mask >= @lower_mask )	
			  and ( I.IncludeInAll = 'true' );  
			  
			-- Return these counts
			select @all_collections_items=COUNT(*), @all_collections_titles=COUNT(distinct fk_TitleID)
			from #TEMP_ITEMS;
		end;
		
		-- Drop the big temporary table
		drop table #TEMPZERO;
	
	end
	else
	begin	
	
		-- Drop the big temporary table
		drop table #TEMPZERO;	
		
		-- Create the temporary item table variable for paging purposes
		declare @TEMP_PAGED_ITEMS TempPagedItemsTableType;
		  
		-- There are essentially two major paths of execution, depending on whether this should
		-- be grouped as items within the page requested titles ( sorting by title or the basic
		-- sorting by rank, which ranks this way ) or whether each item should be
		-- returned by itself, such as sorting by individual publication dates, etc..
		
		if ( @sort < 10 )
		begin	
			-- create the temporary title table definition
			declare @TEMP_TITLES table ( TitleID int, BibID varchar(10), RowNumber int );	
			
			-- Return these counts
			select @total_items=COUNT(*), @total_titles=COUNT(distinct fk_TitleID)
			from #TEMP_ITEMS;
			
			-- Now, calculate the actual ending row, based on the ration, page information,
			-- and the lookahead factor
			if (( @total_items > 0 ) and ( @total_titles > 0 ))
			begin		
				-- Compute equation to determine possible page value ( max - log(factor, (items/title)/2))
				declare @computed_value int;
				select @computed_value = (@maxpagelookahead - CEILING( LOG10( ((cast(@total_items as float)) / (cast(@total_titles as float)))/@lookahead_factor)));
				
				-- Compute the minimum value.  This cannot be less than @minpagelookahead.
				declare @floored_value int;
				select @floored_value = 0.5 * ((@computed_value + @minpagelookahead) + ABS(@computed_value - @minpagelookahead));
				
				-- Compute the maximum value.  This cannot be more than @maxpagelookahead.
				declare @actual_pages int;
				select @actual_pages = 0.5 * ((@floored_value + @maxpagelookahead) - ABS(@floored_value - @maxpagelookahead));

				-- Set the final row again then
				set @rowend = @rowstart + ( @pagesize * @actual_pages ) - 1; 
			end;	
					  
			-- Create saved select across titles for row numbers
			with TITLES_SELECT AS
				(	select GroupID, G.BibID, 
						ROW_NUMBER() OVER (order by case when @sort=0 THEN (SUM(Hit_COunt)/COUNT(*)) end DESC,
													case when @sort=1 THEN G.SortTitle end ASC,												
													case when @sort=2 THEN BibID end ASC,
													case when @sort=3 THEN BibID end DESC) as RowNumber
					from #TEMP_ITEMS I, SobekCM_Item_Group G
					where I.fk_TitleID = G.GroupID
					group by G.GroupID, G.BibID, G.SortTitle )

			-- Insert the correct rows into the temp title table	
			insert into @TEMP_TITLES ( TitleID, BibID, RowNumber )
			select GroupID, BibID, RowNumber
			from TITLES_SELECT
			where RowNumber >= @rowstart
			  and RowNumber <= @rowend;
		
			-- Return the title information for this page
			select RowNumber as TitleID, T.BibID, G.GroupTitle, G.ALEPH_Number as OPAC_Number, G.OCLC_Number, isnull(G.GroupThumbnail,'') as GroupThumbnail, G.[Type], isnull(G.Primary_Identifier_Type,'') as Primary_Identifier_Type, isnull(G.Primary_Identifier, '') as Primary_Identifier
			from @TEMP_TITLES T, SobekCM_Item_Group G
			where ( T.TitleID = G.GroupID )
			order by RowNumber ASC;
			
			-- Get the item id's for the items related to these titles
			insert into @TEMP_PAGED_ITEMS
			select ItemID, RowNumber
			from @TEMP_TITLES T, SobekCM_Item I
			where ( T.TitleID = I.GroupID );			  
			
			-- Return the basic system required item information for this page of results
			select T.RowNumber as fk_TitleID, I.ItemID, VID, Title, IP_Restriction_Mask, coalesce(I.MainThumbnail,'') as MainThumbnail, coalesce(I.Level1_Index, -1) as Level1_Index, coalesce(I.Level1_Text,'') as Level1_Text, coalesce(I.Level2_Index, -1) as Level2_Index, coalesce(I.Level2_Text,'') as Level2_Text, coalesce(I.Level3_Index,-1) as Level3_Index, coalesce(I.Level3_Text,'') as Level3_Text, isnull(I.PubDate,'') as PubDate, I.[PageCount], coalesce(I.Link,'') as Link, coalesce( Spatial_KML, '') as Spatial_KML, coalesce(COinS_OpenURL, '') as COinS_OpenURL		
			from SobekCM_Item I, @TEMP_PAGED_ITEMS T
			where ( T.ItemID = I.ItemID )
			order by T.RowNumber, Level1_Index, Level2_Index, Level3_Index;			
								
			-- Return the aggregation-specific display values for all the items in this page of results
			execute sp_Executesql @item_display_sql, N' @itemtable TempPagedItemsTableType READONLY', @TEMP_PAGED_ITEMS; 		

		end
		else
		begin		
			-- Since these sorts make each item paired with a single title row,
			-- number of items and titles are equal
			select @total_items=COUNT(*), @total_titles=COUNT(*)
			from #TEMP_ITEMS; 
			
			-- In addition, always return the max lookahead pages
			set @rowend = @rowstart + ( @pagesize * @maxpagelookahead ) - 1; 
			
			-- Create saved select across items for row numbers
			with ITEMS_SELECT AS
			 (	select I.ItemID, 
					ROW_NUMBER() OVER (order by case when @sort=10 THEN isnull(SortDate,9223372036854775807)  end ASC,
												case when @sort=11 THEN isnull(SortDate,-1) end DESC) as RowNumber
					from #TEMP_ITEMS I
					group by I.ItemID, SortDate )
						  
			-- Insert the correct rows into the temp item table	
			insert into @TEMP_PAGED_ITEMS ( ItemID, RowNumber )
			select ItemID, RowNumber
			from ITEMS_SELECT
			where RowNumber >= @rowstart
			  and RowNumber <= @rowend;
			  
			-- Return the title information for this page
			select RowNumber as TitleID, G.BibID, G.GroupTitle, G.ALEPH_Number as OPAC_Number, G.OCLC_Number, isnull(G.GroupThumbnail,'') as GroupThumbnail, G.[Type], isnull(G.Primary_Identifier_Type,'') as Primary_Identifier_Type, isnull(G.Primary_Identifier, '') as Primary_Identifier
			from @TEMP_PAGED_ITEMS T, SobekCM_Item I, SobekCM_Item_Group G
			where ( T.ItemID = I.ItemID )
			  and ( I.GroupID = G.GroupID )
			order by RowNumber ASC;
			
			-- Return the basic system required item information for this page of results
			select T.RowNumber as fk_TitleID, I.ItemID, VID, Title, IP_Restriction_Mask, coalesce(I.MainThumbnail,'') as MainThumbnail, coalesce(I.Level1_Index, -1) as Level1_Index, coalesce(I.Level1_Text,'') as Level1_Text, coalesce(I.Level2_Index, -1) as Level2_Index, coalesce(I.Level2_Text,'') as Level2_Text, coalesce(I.Level3_Index,-1) as Level3_Index, coalesce(I.Level3_Text,'') as Level3_Text, isnull(I.PubDate,'') as PubDate, I.[PageCount], coalesce(I.Link,'') as Link, coalesce( Spatial_KML, '') as Spatial_KML, coalesce(COinS_OpenURL, '') as COinS_OpenURL		
			from SobekCM_Item I, @TEMP_PAGED_ITEMS T
			where ( T.ItemID = I.ItemID )
			order by T.RowNumber, Level1_Index, Level2_Index, Level3_Index;			
			
			-- Return the aggregation-specific display values for all the items in this page of results
			execute sp_Executesql @item_display_sql, N' @itemtable TempPagedItemsTableType READONLY', @TEMP_PAGED_ITEMS; 

		end;

		-- Return the facets if asked for
		if ( @include_facets = 'true' )
		begin	
			if (( LEN( isnull( @aggregationcode, '')) = 0 ) or ( @aggregationcode = 'all' ))
			begin
				-- Build the aggregation list
				select A.Code, A.ShortName, Metadata_Count=Count(*)
				from SobekCM_Item_Aggregation A, SobekCM_Item_Aggregation_Item_Link L, SobekCM_Item I, #TEMP_ITEMS T
				where ( T.ItemID = I.ItemID )
				  and ( I.ItemID = L.ItemID )
				  and ( L.AggregationID = A.AggregationID )
				  and ( A.Hidden = 'false' )
				  and ( A.isActive = 'true' )
				  and ( A.Include_In_Collection_Facet = 'true' )
				group by A.Code, A.ShortName
				order by Metadata_Count DESC, ShortName ASC;	
			end;
			
			-- Return the FIRST facet
			if ( @facettype1 > 0 )
			begin
				-- Return the first 100 values
				select MetadataValue, Metadata_Count
				from (	select top(100) U.MetadataID, Metadata_Count = COUNT(*)
						from #TEMP_ITEMS I, Metadata_Item_Link_Indexed_View U with (NOEXPAND)
						where ( U.ItemID = I.ItemID )
						  and ( U.MetadataTypeID = @facettype1 )
						group by U.MetadataID
						order by Metadata_Count DESC ) F, SobekCM_Metadata_Unique_Search_Table M
				where M.MetadataID = F.MetadataID
				order by Metadata_Count DESC, MetadataValue ASC;
			end;
			
			-- Return the SECOND facet
			if ( @facettype2 > 0 )
			begin
				-- Return the first 100 values
				select MetadataValue, Metadata_Count
				from (	select top(100) U.MetadataID, Metadata_Count = COUNT(*)
						from #TEMP_ITEMS I, Metadata_Item_Link_Indexed_View U with (NOEXPAND)
						where ( U.ItemID = I.ItemID )
						  and ( U.MetadataTypeID = @facettype2 )
						group by U.MetadataID
						order by Metadata_Count DESC ) F, SobekCM_Metadata_Unique_Search_Table M
				where M.MetadataID = F.MetadataID
				order by Metadata_Count DESC, MetadataValue ASC;
			end;
			
			-- Return the THIRD facet
			if ( @facettype3 > 0 )
			begin
				-- Return the first 100 values
				select MetadataValue, Metadata_Count
				from (	select top(100) U.MetadataID, Metadata_Count = COUNT(*)
						from #TEMP_ITEMS I, Metadata_Item_Link_Indexed_View U with (NOEXPAND)
						where ( U.ItemID = I.ItemID )
						  and ( U.MetadataTypeID = @facettype3 )
						group by U.MetadataID
						order by Metadata_Count DESC ) F, SobekCM_Metadata_Unique_Search_Table M
				where M.MetadataID = F.MetadataID
				order by Metadata_Count DESC, MetadataValue ASC;
			end;
			
			-- Return the FOURTH facet
			if ( @facettype4 > 0 )
			begin
				-- Return the first 100 values
				select MetadataValue, Metadata_Count
				from (	select top(100) U.MetadataID, Metadata_Count = COUNT(*)
						from #TEMP_ITEMS I, Metadata_Item_Link_Indexed_View U with (NOEXPAND)
						where ( U.ItemID = I.ItemID )
						  and ( U.MetadataTypeID = @facettype4 )
						group by U.MetadataID
						order by Metadata_Count DESC ) F, SobekCM_Metadata_Unique_Search_Table M
				where M.MetadataID = F.MetadataID
				order by Metadata_Count DESC, MetadataValue ASC;
			end;
			
			-- Return the FIFTH facet
			if ( @facettype5 > 0 )
			begin
				-- Return the first 100 values
				select MetadataValue, Metadata_Count
				from (	select top(100) U.MetadataID, Metadata_Count = COUNT(*)
						from #TEMP_ITEMS I, Metadata_Item_Link_Indexed_View U with (NOEXPAND)
						where ( U.ItemID = I.ItemID )
						  and ( U.MetadataTypeID = @facettype5 )
						group by U.MetadataID
						order by Metadata_Count DESC ) F, SobekCM_Metadata_Unique_Search_Table M
				where M.MetadataID = F.MetadataID
				order by Metadata_Count DESC, MetadataValue ASC;
			end;
			
			-- Return the SIXTH facet
			if ( @facettype6 > 0 )
			begin
				-- Return the first 100 values
				select MetadataValue, Metadata_Count
				from (	select top(100) U.MetadataID, Metadata_Count = COUNT(*)
						from #TEMP_ITEMS I, Metadata_Item_Link_Indexed_View U with (NOEXPAND)
						where ( U.ItemID = I.ItemID )
						  and ( U.MetadataTypeID = @facettype6 )
						group by U.MetadataID
						order by Metadata_Count DESC ) F, SobekCM_Metadata_Unique_Search_Table M
				where M.MetadataID = F.MetadataID
				order by Metadata_Count DESC, MetadataValue ASC;
			end;
			
			-- Return the SEVENTH facet
			if ( @facettype7 > 0 )
			begin
				-- Return the first 100 values
				select MetadataValue, Metadata_Count
				from (	select top(100) U.MetadataID, Metadata_Count = COUNT(*)
						from #TEMP_ITEMS I, Metadata_Item_Link_Indexed_View U with (NOEXPAND)
						where ( U.ItemID = I.ItemID )
						  and ( U.MetadataTypeID = @facettype7 )
						group by U.MetadataID
						order by Metadata_Count DESC ) F, SobekCM_Metadata_Unique_Search_Table M
				where M.MetadataID = F.MetadataID
				order by Metadata_Count DESC, MetadataValue ASC;
			end;
			
			-- Return the EIGHTH facet
			if ( @facettype8 > 0 )
			begin
				-- Return the first 100 values
				select MetadataValue, Metadata_Count
				from (	select top(100) U.MetadataID, Metadata_Count = COUNT(*)
						from #TEMP_ITEMS I, Metadata_Item_Link_Indexed_View U with (NOEXPAND)
						where ( U.ItemID = I.ItemID )
						  and ( U.MetadataTypeID = @facettype8 )
						group by U.MetadataID
						order by Metadata_Count DESC ) F, SobekCM_Metadata_Unique_Search_Table M
				where M.MetadataID = F.MetadataID
				order by Metadata_Count DESC, MetadataValue ASC;
			end;
		end; -- End overall FACET block
	end; -- End else statement entered if there are any results to return
	
	-- return the query string as well, for debuggins
	select Query = @mainquery;
	select RankSelection = @rankselection;
	
	-- drop the temporary tables
	drop table #TEMP_ITEMS;
	
	Set NoCount OFF;
			
	If @@ERROR <> 0 GoTo ErrorHandler;
    Return(0);
  
ErrorHandler:
    Return(@@ERROR);
	
END;
GO

if ( not exists ( select 1 from SobekCM_Settings where Setting_Key = 'Email On User Registration' ))
begin
	insert into SobekCM_Settings ( Setting_Key, Setting_Value, TabPage, Heading, Hidden, Reserved, Help, Dimensions )
	values ( 'Email On User Registration', '', 'General Settings', 'Email Settings', 0, 0, 'If an email address is provided here, an email will be sent when each new user registers.\n\nIf you are using multiple email addresses, seperate them with a semi-colon.\n\nExample: ''person1@corp.edu;person2@corp.edu''', 300 );
end;
GO

IF object_id('mySobek_Delete_User') IS NULL EXEC ('create procedure dbo.mySobek_Delete_User as select 1;');
GO

alter procedure mySobek_Delete_User 
	@username varchar(20)
as
begin transaction

	if ( exists ( select 1 from mySobek_User where UserName=@username ))
	begin

		-- Get the 	user id
		declare @userid int;
		set @userid = ( select UserID from mySobek_User where Username=@username);

		-- Delete from all the satellite tables
		delete from mySobek_User_Bib_Link where UserID=@userid;
		delete from mySobek_User_DefaultMetadata_Link where UserID=@userid;
		delete from mySobek_User_Description_Tags where UserID=@userid;
		delete from mySobek_User_Edit_Aggregation where UserID=@userid;
		delete from mySobek_User_Editable_Link where UserID=@userid;

		delete from mySobek_User_Item_Link where UserID=@userid;
		delete from mySobek_User_Item_Permissions where UserID=@userid;
		delete from mySobek_User_Search where UserID=@userid;
		delete from mySobek_User_Settings where UserID=@userid;
		delete from mySobek_User_Template_Link where UserID=@userid;
		delete from mySobek_User_Group_Link where UserID=@userid;

		-- Delete the folder
		delete from mySobek_User_Item where UserFolderID in ( select UserFolderID from mySobek_User_Folder where UserID=@userid);
		delete from mySobek_User_Folder where UserID=@userid;

		-- Delete from main user table
		delete from mySobek_User where UserID=@userid;

	end;

commit transaction
GO;


-- Ensure the module to convert large jpegs is included in the builder module list
if ( not exists ( select 1 from SobekCM_Builder_Module where ModuleSetID=3 and [Assembly] = 'SobekCM.Builder_Library.Modules.Items.ConvertLargeJpegsItemModule' ))
begin

  -- Make room for this, right before creating other image derivatives
  update SObekCM_Builder_Module
  set [Order] = [Order] + 1
  where ModuleSetID=3
    and [Order] >= 9;


	-- Now, add this as order 9 in that module set		
	insert into SobekCM_Builder_Module ( ModuleSetID, ModuleDesc, [Assembly], Class, [Enabled], [Order], Argument1 )
	values ( 3, 'Handle extra large JPEGs', null, 'SobekCM.Builder_Library.Modules.Items.ConvertLargeJpegsItemModule', 'true', 9, null );
end;
GO

-- Insert the module to reload the METS and basic DB info from the database into the list of modules for deleting items
if ( not exists ( select 1 from SobekCM_Builder_Module where ModuleSetID=4 and Class='SobekCM.Builder_Library.Modules.Items.ReloadMetsAndBasicDbInfoModule' ))
begin

	-- Make room
	update SobekCM_Builder_Module 
	set [Order] = [Order] + 1
	where ModuleSetID=4;

	-- Add this
	insert into SobekCM_Builder_Module ( ModuleSetID, ModuleDesc, Class, [Enabled], [Order] )
	values ( 4, 'Loads the METS and basic database info', 'SobekCM.Builder_Library.Modules.Items.ReloadMetsAndBasicDbInfoModule', 'true', 1 );

end;
GO


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


-- The list of static resource options should be a drop-down in the system-wide settings
update SobekCM_Settings set Options = '{STATIC_SOURCE_CODES}' where Setting_Key='Static Resources Source'
GO


-- Update the version number
if (( select count(*) from SobekCM_Database_Version ) = 0 )
begin
	insert into SobekCM_Database_Version ( Major_Version, Minor_Version, Release_Phase )
	values ( 4, 10, '2' );
end
else
begin
	update SobekCM_Database_Version
	set Major_Version=4, Minor_Version=10, Release_Phase='2';
end;
GO