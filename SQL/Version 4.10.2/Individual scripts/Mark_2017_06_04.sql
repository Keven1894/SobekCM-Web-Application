/****** Script for SelectTopNRows command from SSMS  ******/
SELECT TOP 1000 [ModuleID]
      ,[ModuleSetID]
      ,[ModuleDesc]
      ,[Assembly]
      ,[Class]
      ,[Enabled]
      ,[Order]
      ,[Argument1]
      ,[Argument2]
      ,[Argument3]
  FROM [oswego].[dbo].[SobekCM_Builder_Module]
  where ModuleSetID=3
  order by [Order]


  -- Make room for this, right before creating other image derivatives
  update SObekCM_Builder_Module
  set [Order] = [Order] + 1
  where ModuleSetID=3
    and [Order] >= 9;


	-- Now, add this as order 9 in that module set		
	insert into SobekCM_Builder_Module ( ModuleSetID, ModuleDesc, [Assembly], Class, [Enabled], [Order], Argument1 )
	values ( 3, 'Handle extra large JPEGs', null, 'SobekCM.Builder_Library.Modules.Items.ConvertLargeJpegsItemModule', 'true', 9, null );
