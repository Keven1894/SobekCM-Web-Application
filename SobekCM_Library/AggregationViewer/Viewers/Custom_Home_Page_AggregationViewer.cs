﻿#region Using directives

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using SobekCM.Core.Aggregations;
using SobekCM.Core.Navigation;
using SobekCM.Library.HTML;
using SobekCM.Tools;

#endregion

namespace SobekCM.Library.AggregationViewer.Viewers
{
    /// <summary> Aggregation viewer displays the aggregation home page from a custom file, without putting the text
    /// within the usual SobekCM/web skin frame </summary>
    public class Custom_Home_Page_AggregationViewer : abstractAggregationViewer
    {

        /// <summary> Constructor for a new instance of the Custom_Home_Page_AggregationViewer class </summary>
        /// <param name="RequestSpecificValues"> All the necessary, non-global data specific to the current request </param>
        /// <param name="ViewBag"> Aggregation-specific request information, such as aggregation object and any browse object requested </param>
        public Custom_Home_Page_AggregationViewer(RequestCache RequestSpecificValues, AggregationViewBag ViewBag)
            : base(RequestSpecificValues, ViewBag)
        {
            // All work done in base class?
        }

        /// <summary> Gets the type of collection view or search supported by this collection viewer </summary>
        /// <value> This returns the <see cref="Item_Aggregation_Views_Searches_Enum.Custom_Home_Page"/> enumerational value </value>
        public override Item_Aggregation_Views_Searches_Enum Type
        {
            get { return Item_Aggregation_Views_Searches_Enum.Custom_Home_Page; }
        }

     

        /// <summary>Flag indicates whether the subaggregation selection panel is displayed for this collection viewer</summary>
        /// <value> This property always returns the <see cref="Selection_Panel_Display_Enum.Always"/> enumerational value </value>
        public override Selection_Panel_Display_Enum Selection_Panel_Display
        {
            get
            {
                return Selection_Panel_Display_Enum.Never;
            }
        }

        /// <summary> Gets the collection of special behaviors which this aggregation viewer  requests from the main HTML subwriter. </summary>
        public override List<HtmlSubwriter_Behaviors_Enum> AggregationViewer_Behaviors
        {
            get
            {
                return new List<HtmlSubwriter_Behaviors_Enum>
                        {
                            HtmlSubwriter_Behaviors_Enum.Aggregation_Suppress_Home_Text,
                            HtmlSubwriter_Behaviors_Enum.Suppress_Header,
                            HtmlSubwriter_Behaviors_Enum.Suppress_Footer,
                            HtmlSubwriter_Behaviors_Enum.Suppress_Banner,
                            HtmlSubwriter_Behaviors_Enum.Suppress_MainMenu,
                            HtmlSubwriter_Behaviors_Enum.Suppress_SearchForm
                        };
            }
        }

        /// <summary> Add the HTML to be displayed in the search box </summary>
        /// <param name="Output"> Textwriter to write the HTML for this viewer</param>
        /// <param name="Tracer">Trace object keeps a list of each method executed and important milestones in rendering</param>
        public override void Add_Search_Box_HTML(TextWriter Output, Custom_Tracer Tracer)
        {
            // do nothing
        }

        /// <summary> Add the HTML to be displayed below the search box </summary>
        /// <param name="Output"> Textwriter to write the HTML for this viewer</param>
        /// <param name="Tracer"> Trace object keeps a list of each method executed and important milestones in rendering</param>
        /// <remarks> This adds the search tips by calling the base method <see cref="abstractAggregationViewer.Add_Simple_Search_Tips"/> </remarks>
        public override void Add_Secondary_HTML(TextWriter Output, Custom_Tracer Tracer)
        {
            if (Tracer != null)
            {
                Tracer.Add_Trace("Custom_Home_Page_AggregationViewer.Add_Secondary_HTML", "Add the entire custom page, doing suitable replacements");
            }

            // Do all the replacements
            string text = ViewBag.Hierarchy_Object.HomePageHtml.Content; //.Content;
            StringBuilder textToDisplay = new StringBuilder(text);
           
            // Determine if certain (more costly) replacements are even needed
            bool header_replacement_needed = text.IndexOf("%HEADER%") > 0;
            bool footer_replacement_needed = text.IndexOf("%FOOTER%") > 0;
            bool menu_replacement_needed = text.IndexOf("%MAINMENU%") > 0;

            // If necessary, replace the header
            if (header_replacement_needed)
            {
                StringBuilder headerBuilder = new StringBuilder();
                StringWriter headerWriter = new StringWriter(headerBuilder);
                HeaderFooter_Helper_HtmlSubWriter.Add_Header(headerWriter, RequestSpecificValues, "container-inner-custom", ViewBag.Hierarchy_Object.ShortName, null, ViewBag.Hierarchy_Object, null);
                string header = headerBuilder.ToString();
                textToDisplay = textToDisplay.Replace("<%HEADER%>", header).Replace("[%HEADER%]", header);
            }

            // If necessary, replace the footer
            if (footer_replacement_needed)
            {
                StringBuilder footerBuilder = new StringBuilder();
                StringWriter footerWriter = new StringWriter(footerBuilder);
                HeaderFooter_Helper_HtmlSubWriter.Add_Footer(footerWriter, RequestSpecificValues, null, ViewBag.Hierarchy_Object, null);
                string footer = footerBuilder.ToString();
                textToDisplay = textToDisplay.Replace("<%FOOTER%>", footer).Replace("[%FOOTER%]", footer);
            }

            // If necessary, insert the main menu
            if (menu_replacement_needed)
            {
                StringBuilder menuBuilder = new StringBuilder();
                StringWriter menuWriter = new StringWriter(menuBuilder);
                MainMenus_Helper_HtmlSubWriter.Add_Aggregation_Main_Menu(menuWriter, RequestSpecificValues, ViewBag.Hierarchy_Object);
                string menu = menuBuilder.ToString();
                textToDisplay = textToDisplay.Replace("<%MAINMENU%>", menu).Replace("[%MAINMENU%]", menu);
            }

            // Determine the different counts as strings
            string page_count = "0";
            string item_count = "0";
            string title_count = "0";
            if (ViewBag.Hierarchy_Object.Statistics != null)
            {
                page_count = Int_To_Comma_String(ViewBag.Hierarchy_Object.Statistics.Page_Count);
                item_count = Int_To_Comma_String(ViewBag.Hierarchy_Object.Statistics.Item_Count);
                title_count = Int_To_Comma_String(ViewBag.Hierarchy_Object.Statistics.Title_Count);
            }

            string url_options = UrlWriterHelper.URL_Options(RequestSpecificValues.Current_Mode);
            string urlOptions1 = String.Empty;
            string urlOptions2 = String.Empty;
            if (url_options.Length > 0)
            {
                urlOptions1 = "?" + url_options;
                urlOptions2 = "&" + url_options;
            }

            string home_text = textToDisplay.ToString().Replace("<%BASEURL%>", RequestSpecificValues.Current_Mode.Base_URL).Replace("<%URLOPTS%>", url_options).Replace("<%?URLOPTS%>", urlOptions1).Replace("<%&URLOPTS%>", urlOptions2).Replace("<%INTERFACE%>", RequestSpecificValues.Current_Mode.Base_Skin_Or_Skin).Replace("<%WEBSKIN%>", RequestSpecificValues.Current_Mode.Base_Skin_Or_Skin).Replace("<%PAGES%>", page_count).Replace("<%ITEMS%>", item_count).Replace("<%TITLES%>", title_count);


            Output.Write(home_text);
        }

        private string Int_To_Comma_String(int Value)
        {
            if (Value < 1000)
                return Value.ToString();

            string value_string = Value.ToString();
            if ((Value >= 1000) && (Value < 1000000))
            {
                return value_string.Substring(0, value_string.Length - 3) + "," + value_string.Substring(value_string.Length - 3);
            }

            return value_string.Substring(0, value_string.Length - 6) + "," + value_string.Substring(value_string.Length - 6, 3) + "," + value_string.Substring(value_string.Length - 3);
        }

    }
}
