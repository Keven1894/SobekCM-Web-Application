

if ( not exists ( select 1 from SobekCM_Settings where Setting_Key = 'Email On User Registration' ))
begin
	insert into SobekCM_Settings ( Setting_Key, Setting_Value, TabPage, Heading, Hidden, Reserved, Help, Dimensions )
	values ( 'Email On User Registration', '', 'General Settings', 'Email Settings', 0, 0, 'If an email address is provided here, an email will be sent when each new user registers.\n\nIf you are using multiple email addresses, seperate them with a semi-colon.\n\nExample: ''person1@corp.edu;person2@corp.edu''', 300 );
end;
GO


create procedure mySobek_Delete_User 
	@username varchar(20)
as
begin transaction

	if ( exists ( select 1 from mySobek_User where UserName=@username ))
	begin

		declare @userid int;
		set @userid = ( select UserID from mySobek_User where UserName=@username );

		delete from mySobek_User_Group_Link where UserID=@userid;
		delete from mySobek_User_DefaultMetadata_Link where UserID=@userid;
		delete from mySobek_User_Template_Link where UserID=@userid;
		delete from mySobek_User_Search where UserID=@userid;
		delete from mySobek_User_Item_Link where UserID=@userid;
		delete from mySobek_User_Item_Permissions where UserID=@userid;
		delete from mySobek_User_Edit_Aggregation where UserID=@userid;
		delete from mySobek_User_Bib_Link where UserID=@userid;
		delete from mySobek_User_Folder where UserID=@userid;
		delete from mySobek_User where UserID=@userid;

	end;

commit transaction
GO;


