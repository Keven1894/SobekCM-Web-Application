/** Version 4.04 to 4.05 *****/

/****** Object:  StoredProcedure [dbo].[SobekCM_Item_Count_By_Collection_By_Date_Range]    Script Date: 12/20/2013 05:43:37 ******/
ALTER PROCEDURE [dbo].[SobekCM_Item_Count_By_Collection_By_Date_Range]
	@date1 datetime,
	@date2 datetime
AS
BEGIN

	-- No need to perform any locks here, especially given the possible
	-- length of this search
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;
	SET ARITHABORT ON;

	-- Get the id for the ALL aggregation
	declare @all_id int;
	set @all_id = coalesce(( select AggregationID from SObekCM_Item_Aggregation where Code='all'), -1);
	
	declare @Aggregation_List TABLE
	(
	  AggregationID int,
	  Code varchar(20),
	  ChildCode varchar(20),
	  Child2Code varchar(20),
	  AllCodes varchar(20),
	  Name nvarchar(255),
	  ShortName nvarchar(100),
	  [Type] varchar(50),
	  isActive bit
	);
	
	-- Insert the list of items linked to ALL or linked to NONE (include ALL)
	insert into @Aggregation_List ( AggregationID, Code, ChildCode, Child2Code, AllCodes, Name, ShortName, [Type], isActive )
	select AggregationID, Code, '', '', Code, Name, ShortName, [Type], isActive
	from SobekCM_Item_Aggregation A
	where ( [Type] not like 'Institut%' )
	  and ( Deleted='false' )
	  and exists ( select * from SobekCM_Item_Aggregation_Hierarchy where ChildID=A.AggregationID and ParentID=@all_id);
	  
	-- Insert the children under those top-level collections
	insert into @Aggregation_List ( AggregationID, Code, ChildCode, Child2Code, AllCodes, Name, ShortName, [Type], isActive )
	select A2.AggregationID, T.Code, A2.Code, '', A2.Code, A2.Name, A2.SHortName, A2.[Type], A2.isActive
	from @Aggregation_List T, SobekCM_Item_Aggregation A2, SobekCM_Item_Aggregation_Hierarchy H
	where ( A2.[Type] not like 'Institut%' )
	  and ( T.AggregationID = H.ParentID )
	  and ( A2.AggregationID = H.ChildID )
	  and ( Deleted='false' );
	  
	-- Insert the grand-children under those child collections
	insert into @Aggregation_List ( AggregationID, Code, ChildCode, Child2Code, AllCodes, Name, ShortName, [Type], isActive )
	select A2.AggregationID, T.Code, T.ChildCode, A2.Code, A2.Code, A2.Name, A2.SHortName, A2.[Type], A2.isActive
	from @Aggregation_List T, SobekCM_Item_Aggregation A2, SobekCM_Item_Aggregation_Hierarchy H
	where ( A2.[Type] not like 'Institut%' )
	  and ( T.AggregationID = H.ParentID )
	  and ( A2.AggregationID = H.ChildID )
	  and ( Deleted='false' )
	  and ( ChildCode <> '' );
	  
	-- Get total item count
	declare @total_item_count int
	select @total_item_count =  ( select count(*) from SobekCM_Item where Deleted = 'false' and Milestone_OnlineComplete is not null );

	-- Get total title count
	declare @total_title_count int
	select @total_title_count =  ( select count(*) from SobekCM_Item_Group G, SobekCM_Item I where I.GroupID=G.GroupID and G.Deleted = 'false' and I.Deleted = 'false' and Milestone_OnlineComplete is not null );

	-- Get total title count
	declare @total_page_count int
	select @total_page_count =  coalesce(( select sum( [PageCount] ) from SobekCM_Item where Deleted = 'false'  and ( Milestone_OnlineComplete is not null )), 0 );

	-- Get total item count
	declare @total_item_count_date1 int
	select @total_item_count_date1 =  ( select count(ItemID) 
										from SobekCM_Item I
										where ( I.Deleted = 'false' )
										  and ( Milestone_OnlineComplete is not null )
										  and ( Milestone_OnlineComplete <= @date1 ));

	-- Get total title count
	declare @total_title_count_date1 int
	select @total_title_count_date1 =  ( select count(G.GroupID)
										 from SobekCM_Item_Group G
										 where exists ( select *
														from SobekCM_Item I
														where ( I.Deleted = 'false' )
														  and ( Milestone_OnlineComplete is not null )
														  and ( Milestone_OnlineComplete <= @date1 ) 
														  and ( I.GroupID = G.GroupID )));


	-- Get total title count
	declare @total_page_count_date1 int
	select @total_page_count_date1 =  ( select sum( coalesce([PageCount],0) ) 
										from SobekCM_Item I
										where ( I.Deleted = 'false' )
										  and ( Milestone_OnlineComplete is not null )
										  and ( Milestone_OnlineComplete <= @date1 ));

	-- Return these values if this has just one date
	if ( isnull( @date2, '1/1/2000' ) = '1/1/2000' )
	begin
	
		-- Start to build the return set of values
		select code1 = Code, 
		       code2 = ChildCode,
		       code3 = Child2Code,
		       AllCodes,
		    [Name], 
		    C.isActive AS Active,
			title_count = ( select count(distinct(GroupID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID ),
			item_count = ( select count(distinct(ItemID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID ), 
			page_count = coalesce(( select sum( PageCount ) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID ), 0),
			title_count_date1 = ( select count(distinct(GroupID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID and Milestone_OnlineComplete is not null and Milestone_OnlineComplete <= @date1),
			item_count_date1 = ( select count(distinct(ItemID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID and Milestone_OnlineComplete is not null and Milestone_OnlineComplete <= @date1 ), 
			page_count_date1 = coalesce(( select sum( [PageCount] ) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID and Milestone_OnlineComplete is not null and Milestone_OnlineComplete <= @date1 ), 0)
		from @Aggregation_List C
		union
		select 'ZZZ','','', 'ZZZ', 'Total Count', 'false', @total_title_count, @total_item_count, @total_page_count, 
			coalesce(@total_title_count_date1,0), coalesce(@total_item_count_date1,0), coalesce(@total_page_count_date1,0)
		order by code, code2, code3;
		
	end
	else
	begin

		-- Get total item count
		declare @total_item_count_date2 int
		select @total_item_count_date2 =  ( select count(ItemID) 
											from SobekCM_Item I
											where ( I.Deleted = 'false' )
											  and ( Milestone_OnlineComplete is not null )
											  and ( Milestone_OnlineComplete <= @date2 ));

		-- Get total title count
		declare @total_title_count_date2 int
		select @total_title_count_date2 =  ( select count(G.GroupID)
											 from SobekCM_Item_Group G
											 where exists ( select *
															from SobekCM_Item I
															where ( I.Deleted = 'false' )
															  and ( Milestone_OnlineComplete is not null )
															  and ( Milestone_OnlineComplete <= @date2 ) 
															  and ( I.GroupID = G.GroupID )));


		-- Get total title count
		declare @total_page_count_date2 int
		select @total_page_count_date2 =  ( select sum( coalesce([PageCount],0) ) 
											from SobekCM_Item I
											where ( I.Deleted = 'false' )
											  and ( Milestone_OnlineComplete is not null )
											  and ( Milestone_OnlineComplete <= @date2 ));


		-- Start to build the return set of values
		select code1 = Code, 
		       code2 = ChildCode,
		       code3 = Child2Code,
		       AllCodes,
		    [Name], 
		    C.isActive AS Active,
			title_count = ( select count(distinct(GroupID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID ),
			item_count = ( select count(distinct(ItemID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID ), 
			page_count = coalesce(( select sum( PageCount ) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID ), 0),
			title_count_date1 = ( select count(distinct(GroupID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID and Milestone_OnlineComplete is not null and Milestone_OnlineComplete <= @date1),
			item_count_date1 = ( select count(distinct(ItemID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID and Milestone_OnlineComplete is not null and Milestone_OnlineComplete <= @date1 ), 
			page_count_date1 = coalesce(( select sum( [PageCount] ) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID and Milestone_OnlineComplete is not null and Milestone_OnlineComplete <= @date1 ), 0),
			title_count_date2 = ( select count(distinct(GroupID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID and Milestone_OnlineComplete is not null and Milestone_OnlineComplete <= @date2),
			item_count_date2 = ( select count(distinct(ItemID)) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID and Milestone_OnlineComplete is not null and Milestone_OnlineComplete <= @date2 ), 
			page_count_date2 = coalesce(( select sum( [PageCount] ) from Statistics_Item_Aggregation_Link_View T where T.AggregationID = C.AggregationID and Milestone_OnlineComplete is not null and Milestone_OnlineComplete <= @date2 ), 0)
		from @Aggregation_List C
		union
		select 'ZZZ','','','ZZZ', 'Total Count', 'false', @total_title_count, @total_item_count, @total_page_count, 
				coalesce(@total_title_count_date1,0), coalesce(@total_item_count_date1,0), coalesce(@total_page_count_date1,0),
				coalesce(@total_title_count_date2,0), coalesce(@total_item_count_date2,0), coalesce(@total_page_count_date2,0)
		order by code, code2, code3;
	end;
END;
GO



/****** Object:  StoredProcedure [dbo].[SobekCM_Statistics_Aggregation_Titles]    Script Date: 12/20/2013 05:43:38 ******/
-- Returns most often hit titles and items for an aggregation
ALTER PROCEDURE [dbo].[SobekCM_Statistics_Aggregation_Titles]
	@code varchar(20)
AS
BEGIN

	-- No need to perform any locks here.
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- Is this for the whole library, or just one aggregation?
	if (( @code != 'all' ) and ( LEN(@code) > 0 ))
	begin
		-- Get the aggregation id
		declare @aggregationid int;
		set @aggregationid = ISNULL( (select AggregationID from SobekCM_Item_Aggregation where Code=@code), -1 );
		
		-- Return top 100 items
		select top 100 G.BibID, I.VID, G.GroupTitle, I.Total_Hits
		from SobekCM_Item I, SobekCM_Item_Group G, SobekCM_Item_Aggregation_Item_Link L
		where ( I.GroupID = G.GroupID )
		  and ( I.ItemID = L.ItemID )
		  and ( L.AggregationID = @aggregationid )
		  and ( I.Total_Hits > 0 )
		order by I.Total_Hits DESC;
		
		-- Get the top 100 titles with the most hits
		select top 100 BibID, GroupTitle, SUM(I.Total_Hits) as Title_Hits
		from SobekCM_Item I, SobekCM_Item_Group G, SobekCM_Item_Aggregation_Item_Link L
		where ( I.GroupID = G.GroupID )
		  and ( I.ItemID = L.ItemID )
		  and ( L.AggregationID = @aggregationid )		  
		group by BibID, GroupTitle
		having SUM(I.Total_Hits) > 0
		order by Title_Hits DESC;
	end
	else
	begin
		-- Return top 100 items, library-wide
		select top 100 G.BibID, I.VID, G.GroupTitle, I.Total_Hits
		from SobekCM_Item I, SobekCM_Item_Group G
		where ( I.GroupID = G.GroupID )
		  and ( I.Total_Hits > 0 )
		order by I.Total_Hits DESC;
		
		-- Get the top 100 titles with the most hits, library-wide
		select top 100 BibID, GroupTitle, SUM(I.Total_Hits) as Title_Hits
		from SobekCM_Item I, SobekCM_Item_Group G
		where ( I.GroupID = G.GroupID )
		group by BibID, GroupTitle
		having SUM(I.Total_Hits) > 0
		order by Title_Hits DESC	
	end;
END;
GO


/****** Object:  StoredProcedure [dbo].[Tracking_Submit_Online_Page_Division]    Script Date: 12/20/2013 05:43:38 ******/
-- Submit a log about QCing a volume
-- Written by Mark Sullivan ( July 2013 )
ALTER PROCEDURE [dbo].[Tracking_Submit_Online_Page_Division]
	@itemid int,
	@notes varchar(255),
	@onlineuser varchar(100),
	@mainthumbnail varchar(100),
	@mainjpeg varchar(100),
	@pagecount int,
	@filecount int,
	@disksize_kb bigint
AS
begin transaction

	
		-- Add this new progress 
		if (( select count(*)
		      from Tracking_Progress T
		      where ( T.ItemID=@itemid ) and ( ProgressNote=@notes ) and ( WorkPerformedBy=@onlineuser ) 
		        and ( CONVERT(varchar(10), getdate(), 10) = CONVERT(varchar(10), DateCompleted, 10))) = 0 )
		begin
			insert into Tracking_Progress ( ItemID, WorkFlowID, DateCompleted, ProgressNote, WorkPerformedBy, WorkingFilePath )
			values ( @itemid, 45, getdate(), @notes, @onlineuser, '' );
		end;
		
		-- Update the QC milestones
		update SobekCM_Item
		set Milestone_DigitalAcquisition = ISNULL(Milestone_DigitalAcquisition, getdate()),
		    Milestone_ImageProcessing = ISNULL(Milestone_ImageProcessing, getdate()),
		    Milestone_QualityControl = ISNULL(Milestone_QualityControl, getdate())
		where ItemID=@itemid;
		
		-- update last mileston
		update SobekCM_Item
		set Last_Milestone = 3
		where ItemID = @itemid and Last_Milestone < 3;
		
		-- If the item is public, update the last milestone as well
		if ( ( select COUNT(*) from SobekCM_Item where ItemID=@itemid and (( Dark = 'true' ) or ( IP_Restriction_Mask >= 0 ))) > 0 )
		begin		
			-- Move along to the COMPLETED milestone
			update SobekCM_Item
			set Milestone_OnlineComplete = ISNULL(Milestone_OnlineComplete, getdate()),
				Last_MileStone=4
			where ItemID=@itemid		
		end;		

		--Update the item table
		update SobekCM_Item set [PageCount]=@pagecount, MainThumbnail = @mainthumbnail, MainJPEG = @mainjpeg, FileCount = @filecount, DiskSize_KB = @disksize_kb
		where ItemID = @itemid;
		
commit transaction
GO


if (( select count(*) from SobekCM_Database_Version ) = 0 )
begin
	insert into SobekCM_Database_Version ( Major_Version, Minor_Version, Release_Phase )
	values ( 4, 5, '' );
end
else
begin
	update SobekCM_Database_Version
	set Major_Version=4, Minor_Version=5, Release_Phase='';
end;
GO