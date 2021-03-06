
  -- Inser the module to reload the METS and basic DB info from the database 
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