﻿#region Using directives

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Web;
using SobekCM.Bib_Package;
using SobekCM.Bib_Package.Bib_Info;
using SobekCM.Library.Application_State;
using SobekCM.Library.Users;

#endregion

namespace SobekCM.Library.Citation.Elements
{
    /// <summary> Element allows simple entry of subject terms for an item </summary>
    /// <remarks> This class extends the <see cref="simpleTextBox_Element"/> class. </remarks>
    public class Subject_Element : simpleTextBox_Element
    {
        /// <summary> Constructor for a new instance of the Subject_Element class </summary>
        public Subject_Element()
            : base("Subject Keywords: &nbsp; ", "subject")
        {
            Repeatable = true;
            Display_SubType = "simple";
            Type = Element_Type.Subject;
        }


        /// <summary> Renders the HTML for this element </summary>
        /// <param name="Output"> Textwriter to write the HTML for this element </param>
        /// <param name="Bib"> Object to populate this element from </param>
        /// <param name="Skin_Code"> Code for the current skin </param>
        /// <param name="isMozilla"> Flag indicates if the current browse is Mozilla Firefox (different css choices for some elements)</param>
        /// <param name="popup_form_builder"> Builder for any related popup forms for this element </param>
        /// <param name="Current_User"> Current user, who's rights may impact the way an element is rendered </param>
        /// <param name="CurrentLanguage"> Current user-interface language </param>
        /// <param name="Translator"> Language support object which handles simple translational duties </param>
        /// <param name="Base_URL"> Base URL for the current request </param>
        /// <remarks> This simple element does not append any popup form to the popup_form_builder</remarks>
        public override void Render_Template_HTML(TextWriter Output, SobekCM_Item Bib, string Skin_Code, bool isMozilla, StringBuilder popup_form_builder, User_Object Current_User, Language_Enum CurrentLanguage, Language_Support_Info Translator, string Base_URL )
        {
            // Check that an acronym exists
            if (Acronym.Length == 0)
            {
                const string defaultAcronym = "Enter any subject keyword to describe your material here.";
                switch (CurrentLanguage)
                {
                    case Language_Enum.English:
                        Acronym = defaultAcronym;
                        break;

                    case Language_Enum.Spanish:
                        Acronym = defaultAcronym;
                        break;

                    case Language_Enum.French:
                        Acronym = defaultAcronym;
                        break;

                    default:
                        Acronym = defaultAcronym;
                        break;
                }
            }

            List<string> instanceValues = new List<string>();
            if ( Bib.Bib_Info.Subjects_Count > 0 )
            {
                instanceValues.AddRange(from thisSubject in Bib.Bib_Info.Subjects where thisSubject.Class_Type == Subject_Info_Type.Standard select (Subject_Info_Standard) thisSubject into standSubject select standSubject.ToString().Replace("<i>", "").Replace("</i>", "").Replace("( " + standSubject.Authority + " )", "").Trim());
            }

            render_helper(Output, instanceValues, Skin_Code, Current_User, CurrentLanguage, Translator, Base_URL);
        }

        /// <summary> Prepares the bib object for the save, by clearing any existing data in this element's related field(s) </summary>
        /// <param name="Bib"> Existing digital resource object which may already have values for this element's data field(s) </param>
        /// <param name="Current_User"> Current user, who's rights may impact the way an element is rendered </param>
        /// <remarks> This clears any preexisting standard subjects ( not hierarchical geographic, title, etc..) </remarks>
        public override void Prepare_For_Save(SobekCM_Item Bib, User_Object Current_User)
        {
            if (Bib.Bib_Info.Subjects_Count > 0)
            {
                List<Subject_Info_Standard> clears = Bib.Bib_Info.Subjects.Where(thisSubject => thisSubject.Class_Type == Subject_Info_Type.Standard).Cast<Subject_Info_Standard>().ToList();
                foreach (Subject_Info_Standard clearSubject in clears)
                {
                    Bib.Bib_Info.Remove_Subject(clearSubject);
                }
            }
        }

        /// <summary> Saves the data rendered by this element to the provided bibliographic object during postback </summary>
        /// <param name="Bib"> Object into which to save the user's data, entered into the html rendered by this element </param>
        public override void Save_To_Bib(SobekCM_Item Bib)
        {
            string[] getKeys = HttpContext.Current.Request.Form.AllKeys;
            foreach (string thisKey in getKeys.Where(thisKey => thisKey.IndexOf(html_element_name) == 0))
            {
                Bib.Bib_Info.Add_Subject(HttpContext.Current.Request.Form[thisKey], String.Empty );
            }
        }
    }
}
