﻿#region Using directives

using System.IO;
using System.Text;
using System.Web;
using SobekCM.Core.ApplicationState;
using SobekCM.Core.Configuration;
using SobekCM.Core.Configuration.Localization;
using SobekCM.Core.Users;
using SobekCM.Resource_Object;
using SobekCM.Resource_Object.Bib_Info;

#endregion

namespace SobekCM.Library.Citation.Elements
{
    /// <summary> Element allows simple entry of the attribution for an item </summary>
    /// <remarks> This class extends the <see cref="SimpleTextBox_Element"/> class. </remarks>
    public class Acquisition_Note_Element : SimpleTextBox_Element
    {
        /// <summary> Constructor for a new instance of the Attribution_Element class </summary>
        public Acquisition_Note_Element()
            : base("Acquisition", "acquisition")
        {
            Repeatable = false;
        }


        /// <summary> Renders the HTML for this element </summary>
        /// <param name="Output"> Textwriter to write the HTML for this element </param>
        /// <param name="Bib"> Object to populate this element from </param>
        /// <param name="Skin_Code"> Code for the current skin </param>
        /// <param name="IsMozilla"> Flag indicates if the current browse is Mozilla Firefox (different css choices for some elements)</param>
        /// <param name="PopupFormBuilder"> Builder for any related popup forms for this element </param>
        /// <param name="Current_User"> Current user, who's rights may impact the way an element is rendered </param>
        /// <param name="CurrentLanguage"> Current user-interface language </param>
        /// <param name="Translator"> Language support object which handles simple translational duties </param>
        /// <param name="Base_URL"> Base URL for the current request </param>
        /// <remarks> This simple element does not append any popup form to the popup_form_builder</remarks>
        public override void Render_Template_HTML(TextWriter Output, SobekCM_Item Bib, string Skin_Code, bool IsMozilla, StringBuilder PopupFormBuilder, User_Object Current_User, Web_Language_Enum CurrentLanguage, Language_Support_Info Translator, string Base_URL )
        {
            // Check that an acronym exists
            if (Acronym.Length == 0)
            {
                const string defaultAcronym = "This field specifies how this material was acquired by this library.";
                switch (CurrentLanguage)
                {
                    case Web_Language_Enum.English:
                        Acronym = defaultAcronym;
                        break;

                    case Web_Language_Enum.Spanish:
                        Acronym = defaultAcronym;
                        break;

                    case Web_Language_Enum.French:
                        Acronym = defaultAcronym;
                        break;

                    default:
                        Acronym = defaultAcronym;
                        break;
                }
            }

            string attribution = string.Empty;
            if (Bib.Bib_Info.Notes_Count > 0)
            {
                foreach (Note_Info thisNote in Bib.Bib_Info.Notes)
                {
                    if (thisNote.Note_Type == Note_Type_Enum.Acquisition)
                    {
                        attribution = thisNote.Note;
                        break;
                    }
                }
            }
            render_helper(Output, attribution, Skin_Code, Current_User, CurrentLanguage, Translator, Base_URL);
        }

        /// <summary> Prepares the bib object for the save, by clearing any existing data in this element's related field(s) </summary>
        /// <param name="Bib"> Existing digital resource object which may already have values for this element's data field(s) </param>
        /// <param name="Current_User"> Current user, who's rights may impact the way an element is rendered </param>
        /// <remarks> This does nothing since there is only one attribution statement </remarks>
        public override void Prepare_For_Save(SobekCM_Item Bib, User_Object Current_User)
        {
            // Do nothing since there is only one rights statement
        }

        /// <summary> Saves the data rendered by this element to the provided bibliographic object during postback </summary>
        /// <param name="Bib"> Object into which to save the user's data, entered into the html rendered by this element </param>
        public override void Save_To_Bib(SobekCM_Item Bib)
        {
            string[] getKeys = HttpContext.Current.Request.Form.AllKeys;
            foreach (string thisKey in getKeys)
            {
                if (thisKey.IndexOf(html_element_name.Replace("_", "")) == 0)
                {
                    Bib.Bib_Info.Add_Note(HttpContext.Current.Request.Form[thisKey], Note_Type_Enum.Acquisition);
                    return;
                }
            }
        }

        /// <summary> Saves the constants to the bib id </summary>
        /// <param name="Bib"> Object into which to save this element's constant data </param>
        public override void Save_Constant_To_Bib(SobekCM_Item Bib)
        {
            if (DefaultValues.Count > 0)
            {
                // Look for an existing attribution statement
                if (Bib.Bib_Info.Notes_Count > 0)
                {
                    foreach (Note_Info thisNote in Bib.Bib_Info.Notes)
                    {
                        if (thisNote.Note_Type == Note_Type_Enum.Acquisition)
                        {
                            thisNote.Note = DefaultValues[0];
                            return;
                        }
                    }
                }

                // None was found, so just add it
                Bib.Bib_Info.Add_Note(DefaultValues[0], Note_Type_Enum.Acquisition);
            }
        }
    }
}



