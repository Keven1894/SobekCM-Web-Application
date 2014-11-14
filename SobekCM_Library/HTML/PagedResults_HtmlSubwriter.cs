#region Using directives

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Web;
using System.Web.UI.WebControls;
using SobekCM.Core.Aggregations;
using SobekCM.Core.Configuration;
using SobekCM.Core.Navigation;
using SobekCM.Core.Results;
using SobekCM.Core.Search;
using SobekCM.Engine_Library.Navigation;
using SobekCM.Library.Database;
using SobekCM.Library.Email;
using SobekCM.Library.ResultsViewer;
using SobekCM.Tools;
using SobekCM.UI_Library;

#endregion

namespace SobekCM.Library.HTML
{
	/// <summary> Accepts a result set of titles and items and renders the correct page of results in the result view the user has requested </summary>
	/// <remarks> This class extends the <see cref="abstractHtmlSubwriter"/> abstract class. </remarks>
	public class PagedResults_HtmlSubwriter : abstractHtmlSubwriter
	{
		private const int MINIMIZED_FACET_COUNT = 10;
		private const int MAXIMIZED_FACET_COUNT = 100;
		private const int RESULTS_PER_PAGE = 20;

		private string leftButtons;
		private string rightButtons;
		private readonly string facetInformation;
		private iResultsViewer resultWriter;
		private string sortOptions;
		private int term_counter;

		/// <summary> Constructor for a new instance of the paged_result_html_subwriter class </summary>
        /// <param name="RequestSpecificValues"> All the necessary, non-global data specific to the current request </param>
        public PagedResults_HtmlSubwriter(RequestCache RequestSpecificValues) : base(RequestSpecificValues) 
		{

			Browse_Title = String.Empty;
			sortOptions = String.Empty;
			leftButtons = String.Empty;
			rightButtons = String.Empty;
			Showing_Text = String.Empty;
			Include_Bookshelf_View = false;
			Outer_Form_Name = String.Empty;
			Folder_Owner_Name = String.Empty;
			Folder_Owner_Email = String.Empty;
			term_counter = 0;

			// Try to get the facet configuration information
			facetInformation = "0000000";
			if (HttpContext.Current.Request.Form["facet"] != null)
				facetInformation = HttpContext.Current.Request.Form["facet"].PadRight(7, '0');

			if ( true ) // if (currentMode.isPostBack)
			{
				// Pull the standard values
				NameValueCollection form = HttpContext.Current.Request.Form;

			
				if (form["item_action"] != null)
				{
					string action = form["item_action"].ToLower().Trim();
					string url_description = form["url_description"].Trim();
					
					if (action == "email")
					{
						string address = form["email_address"].Replace(";", ",").Trim();
						string comments = form["email_comments"].Trim();
						string format = form["email_format"].Trim().ToUpper();
						string list_type = form["list_type"].Trim();

						if (address.Length > 0)
						{
							// Determine the email format
							bool is_html_format = format != "TEXT";

							// CC: the user, unless they are already on the list
							string cc_list = RequestSpecificValues.Current_User.Email;
							if (address.ToUpper().IndexOf(RequestSpecificValues.Current_User.Email.ToUpper()) >= 0)
								cc_list = String.Empty;

							// Send the email
							string any_error = URL_Email_Helper.Send_Email(address, cc_list, comments, RequestSpecificValues.Current_User.Full_Name, RequestSpecificValues.Current_Mode.SobekCM_Instance_Abbreviation, is_html_format, HttpContext.Current.Items["Original_URL"].ToString(), url_description, list_type, RequestSpecificValues.Current_User.UserID);
							HttpContext.Current.Session.Add("ON_LOAD_MESSAGE", any_error.Length > 0 ? any_error : "Your email has been sent");

							RequestSpecificValues.Current_Mode.isPostBack = true;

							// Do this to force a return trip (cirumnavigate cacheing)
							string original_url = HttpContext.Current.Items["Original_URL"].ToString();
							if ( original_url.IndexOf("?") < 0 )
								HttpContext.Current.Response.Redirect(original_url + "?p=" + DateTime.Now.Millisecond, false);
							else
								HttpContext.Current.Response.Redirect(original_url + "&p=" + DateTime.Now.Millisecond, false);

							HttpContext.Current.ApplicationInstance.CompleteRequest();
                            RequestSpecificValues.Current_Mode.Request_Completed = true;
							return;
						}
					}

					if (action == "save_search")
					{
						string usernotes = HttpContext.Current.Request.Form["add_notes"].Trim();
						bool open_searches = HttpContext.Current.Request.Form["open_searches"] != null;

						string original_url = HttpContext.Current.Items["Original_URL"].ToString();
                        if (SobekCM_Database.Save_User_Search(RequestSpecificValues.Current_User.UserID, original_url, url_description, 0, usernotes, RequestSpecificValues.Tracer) != -1000)
						{
							if (open_searches)
							{
								HttpContext.Current.Session.Add("ON_LOAD_WINDOW", "?m=lms");
							}

							HttpContext.Current.Session.Add("ON_LOAD_MESSAGE", "Search has been saved to your saved searches.");
						}
						else
						{
							HttpContext.Current.Session.Add("ON_LOAD_MESSAGE", "ERROR encountered while saving!");
						}

						// Do this to force a return trip (cirumnavigate cacheing)
						RequestSpecificValues.Current_Mode.isPostBack = true;
						if (original_url.IndexOf("?") > 0)
						{
							HttpContext.Current.Response.Redirect(original_url + "&p=" + DateTime.Now.Millisecond, false);
						}
						else
						{
							HttpContext.Current.Response.Redirect(original_url + "?p=" + DateTime.Now.Millisecond, false);
						}
						HttpContext.Current.ApplicationInstance.CompleteRequest();
                        RequestSpecificValues.Current_Mode.Request_Completed = true;
					}
				}
			}
		}

        #region Properties

        /// <summary> If the results dataset should be displayed in the context of an outer form (such as in
        /// the case that this is part of the mySobek bookshelf functionality) then the form name should go here.  If 
        /// no outer form name is provided, this will create its own sort form  </summary>
        public string Outer_Form_Name { get; set; }

        /// <summary> Flag indicates if the bookshelf view should be included in the list of possible views  </summary>
        public bool Include_Bookshelf_View { get; set; }

        /// <summary> Name of the owner of this folder </summary>
        public string Folder_Owner_Name { private get; set; }

        /// <summary> Email of the owner of this folder </summary>
        public string Folder_Owner_Email { private get; set; }

        /// <summary> Text which indicates which values of the current result or browse are being shown</summary>
        public string Showing_Text { get; private set; }

        /// <summary> Title for the current view, which is used rather than the search explanation </summary>
        public string Browse_Title { get; set; }
        
        #endregion

        /// <summary> Creates the specific results viewer according the user's preferences in the current request mode </summary>
		private void create_resultwriter()
		{
			if ( RequestSpecificValues.Results_Statistics.Total_Items == 0)
			{
			    resultWriter = new No_Results_ResultsViewer(RequestSpecificValues);
				return;
			}

			// If this is default, determine the type from the aggregation (currently) or user
			if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Default)
			{
				if (RequestSpecificValues.Current_Mode.Coordinates.Length > 0)
					RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Map;
				else
				{
					string user_view = "default";
					if (HttpContext.Current.Session["User_Default_View"] != null)
						user_view = HttpContext.Current.Session["User_Default_View"].ToString();
					RequestSpecificValues.Current_Mode.Result_Display_Type = RequestSpecificValues.Hierarchy_Object.Default_Result_View;
					switch (user_view)
					{
						case "brief":
							if (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Brief))
								RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Brief;
							break;

						case "thumb":
							if (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Thumbnails))
								RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Thumbnails;
							break;

						case "table":
							if (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Table))
								RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Table;
							break;

					}

				}
			}

			// Create the bookshelf view
			if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Bookshelf)
			{
				if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.My_Sobek)
				{
                    resultWriter = new Bookshelf_View_ResultsViewer(RequestSpecificValues);
				}
				else
				{
                    resultWriter = new Brief_ResultsViewer(RequestSpecificValues);
				}
			}

			// Create the result writer and populate the sort list for BRIEF view
			if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Brief)
			{
                resultWriter = new Brief_ResultsViewer(RequestSpecificValues);
			}

			// Create the result writer and populate the sort list for THUMBNAIL view
			if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Thumbnails)
			{
                resultWriter = new Thumbnail_ResultsViewer(RequestSpecificValues);
			}

			// Create the result writer and populate the sort list for TABLE view
			if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Table)
			{
                resultWriter = new Table_ResultsViewer(RequestSpecificValues);
			}

			// Create the result writer and populate the sort list for FULL view
			if ((RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Full_Citation) || (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Full_Image))
			{
                resultWriter = new Full_ResultsViewer(RequestSpecificValues);
			}

			// Create the result writer and populate the sort list for MAP view
			if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Map)
			{
                resultWriter = new Google_Map_ResultsViewer(RequestSpecificValues);
			}

            // Create the result writer and populate the sort list for MAP view
            if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Map_Beta)
            {
                resultWriter = new Google_Map_ResultsViewer_Beta(RequestSpecificValues);
            }

			// Create the result writer and populate the sort list for TEXT view
			if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Export)
			{
				resultWriter = new Export_File_ResultsViewer(RequestSpecificValues);
			}
			
			// Populate the sort list and sort the result set
			sortOptions = String.Empty;
			StringBuilder sort_options_builder = new StringBuilder(1000);
			if ((resultWriter.Sortable) && (!RequestSpecificValues.Current_Mode.Is_Robot))
			{
				// Add the special sorts for browses
				if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Aggregation) // browse info only
				{
					if (RequestSpecificValues.Current_Mode.Info_Browse_Mode.ToUpper().IndexOf("NEW") >= 0)
					{
						if (RequestSpecificValues.Current_Mode.Sort == 0)
						{
							sort_options_builder.Append("      <option value=\"" + 0 + "\" selected=\"selected\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Date Added", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
						}
						else
						{
							sort_options_builder.Append("      <option value=\"" + 0 + "\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Date Added", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
						}

						if (RequestSpecificValues.Current_Mode.Sort == 1)
						{
							sort_options_builder.Append("      <option value=\"" + 1 + "\" selected=\"selected\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Title", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
						}
						else
						{
							sort_options_builder.Append("      <option value=\"" + 1 + "\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Title", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
						}
					}
					else
					{
						if ((RequestSpecificValues.Current_Mode.Sort == 0) || (RequestSpecificValues.Current_Mode.Sort == 1))
						{
							sort_options_builder.Append("      <option value=\"" + 0 + "\" selected=\"selected\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Title", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
						}
						else
						{
							sort_options_builder.Append("      <option value=\"" + 0 + "\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Title", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
						}
					}
				}

				// Add the special sorts for searches
				if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Results)
				{
					if (RequestSpecificValues.Current_Mode.Sort == 0)
					{
						sort_options_builder.Append("      <option value=\"" + 0 + "\" selected=\"selected\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Rank", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
					}
					else
					{
						sort_options_builder.Append("      <option value=\"" + 0 + "\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Rank", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
					}

					if (RequestSpecificValues.Current_Mode.Sort == 1)
					{
						sort_options_builder.Append("      <option value=\"" + 1 + "\" selected=\"selected\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Title", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
					}
					else
					{
						sort_options_builder.Append("      <option value=\"" + 1 + "\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Title", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
					}
				}

				// Add the bibid sorts if this is an internal user
				if (RequestSpecificValues.Current_Mode.Internal_User)
				{
					if (RequestSpecificValues.Current_Mode.Sort == 2)
					{
						sort_options_builder.Append("      <option value=\"" + 2 + "\" selected=\"selected\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("BibID Ascending", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
					}
					else
					{
						sort_options_builder.Append("      <option value=\"" + 2 + "\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("BibID Ascending", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
					}

					if (RequestSpecificValues.Current_Mode.Sort == 3)
					{
						sort_options_builder.Append("      <option value=\"" + 3 + "\" selected=\"selected\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("BibID Descending", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
					}
					else
					{
						sort_options_builder.Append("      <option value=\"" + 3 + "\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("BibID Descending", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
					}
				}

				// Add the publication date sorts
				if (RequestSpecificValues.Current_Mode.Sort == 10)
				{
					sort_options_builder.Append("      <option value=\"" + 10 + "\" selected=\"selected\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Date Ascending", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
				}
				else
				{
					sort_options_builder.Append("      <option value=\"" + 10 + "\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Date Ascending", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
				}

				if (RequestSpecificValues.Current_Mode.Sort == 11)
				{
					sort_options_builder.Append("      <option value=\"" + 11 + "\" selected=\"selected\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Date Descending", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
				}
				else
				{
					sort_options_builder.Append("      <option value=\"" + 11 + "\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("Date Descending", RequestSpecificValues.Current_Mode.Language) + "</option>" + Environment.NewLine );
				}

				sortOptions = sort_options_builder.ToString();
			}
		}

		/// <summary> Adds controls to the main navigational page </summary>
		/// <param name="MainPlaceHolder"> Main place holder ( &quot;mainPlaceHolder&quot; ) in the itemNavForm form, widely used throughout the application</param>
		/// <param name="Tracer"> Trace object keeps a list of each method executed and important milestones in rendering </param>
		/// <returns> Sorted tree with the results in hierarchical structure with volumes and issues under the titles and sorted by serial hierarchy </returns>
		public void Add_Controls(PlaceHolder MainPlaceHolder, Custom_Tracer Tracer)
		{
			Tracer.Add_Trace("paged_result_html_subwriter.Add_Controls", "Adding controls for the result set");

			// If the results have facets, this should be rendered in a table with the facets to the left
			if ((RequestSpecificValues.Results_Statistics.Has_Facet_Info) && (RequestSpecificValues.Results_Statistics.Total_Items > 1) && (RequestSpecificValues.Current_Mode.Result_Display_Type != Result_Display_Type_Enum.Export) && (RequestSpecificValues.Current_Mode.Result_Display_Type != Result_Display_Type_Enum.Map))
			{
				// Start this table, write the facets, and start the next TD section for the results
				Literal startFacetTable = new Literal { Text = string.Format("<table id=\"sbkPrsw_ResultsOuterTable\">" + Environment.NewLine + "<tr style=\"vertical-align:top;\">" + Environment.NewLine + "<td id=\"sbkPrsw_FacetOuterColumn\">" + Environment.NewLine + "{0}" + Environment.NewLine + "</td>" + Environment.NewLine + "<td>" + Environment.NewLine, Add_Facet_Information(Tracer)) };
				MainPlaceHolder.Controls.Add(startFacetTable);
			}
			else
			{
				Literal startFacetTable = new Literal { Text = "<table style=\"width:100%;\">" + Environment.NewLine + "<tr style=\"vertical-align:top;\">" + Environment.NewLine + "<td style=\"text-align:center\">" + Environment.NewLine };
				MainPlaceHolder.Controls.Add(startFacetTable);
			}

			// Make sure the result writer has been created
			if (resultWriter == null)
				create_resultwriter();
			Debug.Assert(resultWriter != null, "resultWriter != null");
			if (resultWriter == null)
				return;


			if (RequestSpecificValues.Results_Statistics.Total_Items == 0)
			{
				resultWriter.Add_HTML(MainPlaceHolder, Tracer);
				return;
			}

			Literal startingLiteral = new Literal{ Text = (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Map) ? "</div>" + Environment.NewLine + "<div class=\"sbkPrsw_ResultsPanel\">" + Environment.NewLine : (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Map_Beta) ? "</div>" + Environment.NewLine + "<div>" + Environment.NewLine : "<div class=\"sbkPrsw_ResultsPanel\">" + Environment.NewLine};
			MainPlaceHolder.Controls.Add(startingLiteral);

			resultWriter.Add_HTML(MainPlaceHolder, Tracer );

            Literal endingLiteral = new Literal { Text = (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Map || RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Map_Beta) ? "</div>" + Environment.NewLine + "<div id=\"pagecontainer_resumed\">" + Environment.NewLine : "</div>" + Environment.NewLine };
			MainPlaceHolder.Controls.Add(endingLiteral);

			// If the results have facets, end the result table
			Literal endResultTable = new Literal {Text = "</td>" + Environment.NewLine + "</tr>" + Environment.NewLine + "</table>" + Environment.NewLine };
			MainPlaceHolder.Controls.Add(endResultTable);
		}

		/// <summary> Writes the final output to close this result view, including the results page navigation buttons </summary>
		/// <param name="Output"> Stream to which to write the HTML for this subwriter </param>
		/// <param name="Tracer"> Trace object keeps a list of each method executed and important milestones in rendering </param>
		public override void Write_Final_HTML(TextWriter Output, Custom_Tracer Tracer)
		{
			Tracer.Add_Trace("paged_result_html_subwriter.Write_Final_Html", "Rendering HTML ( finish the main viewer section )");

			if ( RequestSpecificValues.Results_Statistics.Total_Items > 0 )
			{
				Output.WriteLine("<div class=\"sbkPrsw_ResultsNavBar\">");
				Output.Write(leftButtons);
				Output.WriteLine("  " + Showing_Text);
				Output.Write(rightButtons);
				Output.WriteLine("</div>");
				Output.WriteLine("<br />");
				Output.WriteLine();
			}
		}

		/// <summary> Writes the HTML generated to browse the list of titles/itemsr  directly to the response stream </summary>
		/// <param name="Output"> Stream to which to write the HTML for this subwriter </param>
		/// <param name="Tracer"> Trace object keeps a list of each method executed and important milestones in rendering </param>
		/// <returns> TRUE -- Value indicating if html writer should finish the page immediately after this, or if there are other controls or routines which need to be called first </returns>
		public override bool Write_HTML(TextWriter Output, Custom_Tracer Tracer)
		{
			Tracer.Add_Trace("paged_result_html_subwriter.Write_HTML", "Rendering HTML");

            if (RequestSpecificValues.Current_Mode.Result_Display_Type != Result_Display_Type_Enum.Map_Beta)
            {
                #region all but map beta

                string sort_by = "Sort By";
                string showing_range_text = "{0} - {1} of {2} matching titles";
                string showing_coord_range_text = "{0} - {1} of {2} matching coordinates";

                if (RequestSpecificValues.Current_Mode.Aggregation == "aerials")
                {
                    showing_coord_range_text = "{0} - {1} of {2} matching flights";
                }

                if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.Spanish)
                {
                    sort_by = "Organizar";
                    showing_range_text = "{0} - {1} de {2} t�tulos correspondientes";
                }

                if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.French)
                {
                    sort_by = "Limiter";
                    showing_range_text = "{0} - {1} de {2} titres correspondants";
                }

                if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Map)
                    showing_range_text = showing_coord_range_text;

                if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Map_Beta)
                    showing_range_text = showing_coord_range_text;

                Display_Mode_Enum initialMode = RequestSpecificValues.Current_Mode.Mode;

                Tracer.Add_Trace("paged_result_html_subwriter.Write_HTML", "Building appropriate ResultsWriter");

                RequestSpecificValues.Current_Mode.Mode = initialMode;
                if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Search)
                    RequestSpecificValues.Current_Mode.Mode = Display_Mode_Enum.Results;

                // If no results, display different information here
                if ((RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Results) && (RequestSpecificValues.Results_Statistics.Total_Items == 0))
                {
                    Output.WriteLine("<div class=\"sbkPrsw_DescPanel\" style=\"margin-top:10px\">");
                    Show_Search_Info(Output);
                    Output.WriteLine("</div>");
                    Output.WriteLine("<div class=\"sbkPrsw_ResultsNavBar\">&nbsp;</div>");
                    return true;
                }

                // Make sure the result writer has been created
                if (resultWriter == null)
                    create_resultwriter();
                Debug.Assert(resultWriter != null, "resultWriter != null");
                if (resultWriter == null)
                    return false;

                // Determine which rows are being displayed
                int lastRow = RequestSpecificValues.Current_Mode.Page * RESULTS_PER_PAGE;
                int startRow = lastRow - 19;

                // Start the form for this, unless we are already in an appropriate form
                string form_name = Outer_Form_Name;
                if (form_name.Length == 0)
                    form_name = "sort_form";
                if (Outer_Form_Name.Length == 0)
                {
                    string post_url = HttpUtility.HtmlEncode(HttpContext.Current.Items["Original_URL"].ToString());
                    Output.WriteLine("<form name=\"sort_form\" id=\"addedForm\" method=\"post\" action=\"" + post_url + "\" >");
                }

                // Get the name of this
                string currentName = "browse";
                string currentTitle = "Browse";
                if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Results)
                {
                    currentName = "search";
                    currentTitle = "Search";
                }
                if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Public_Folder)
                {
                    currentName = "public bookshelf";
                    currentTitle = "Public Bookshelf";
                }

                // Load the HTML that can be used to customize the search/results bar
                string html_source = String.Empty;
                string fileToRead = HttpContext.Current.Server.MapPath("default/fragments/search_browse_bar.html");
                if (File.Exists(fileToRead))
                {
                    html_source = File.ReadAllText(fileToRead);
                }

                // Get the value for the <%SORTER%> directive (to sort the results)
                string SORTER = String.Empty;
                if ((resultWriter.Sortable) && (!RequestSpecificValues.Current_Mode.Is_Robot) && (RequestSpecificValues.Current_Mode.Mode != Display_Mode_Enum.My_Sobek) && (RequestSpecificValues.Current_Mode.Mode != Display_Mode_Enum.Public_Folder))
                {
                    StringBuilder sorterBuilder = new StringBuilder("  <div class=\"sbkPrsw_ResultsSort\">");
                    short current_order = RequestSpecificValues.Current_Mode.Sort;
                    RequestSpecificValues.Current_Mode.Sort = 0;
                    string url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode);
                    RequestSpecificValues.Current_Mode.Sort = current_order;
                    sorterBuilder.AppendLine("    " + sort_by + ": &nbsp;");
                    sorterBuilder.AppendLine("    <select name=\"sorter_input\" onchange=\"sort_results('" + url.Replace("&", "&amp;") + "')\" id=\"sorter_input\" class=\"sbkPrsw_SorterDropDown\">");
                    sorterBuilder.AppendLine(sortOptions);
                    sorterBuilder.AppendLine("    </select>");
                    sorterBuilder.AppendLine("  </div>");
                    SORTER = sorterBuilder.ToString();
                }

                // Get the value for the <%DESCRIPTION%> directive (to explain current display)
                string DESCRIPTION = String.Empty;
                string summation;
                if ((RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Aggregation) || (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Public_Folder) || ((RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.My_Sobek) && (RequestSpecificValues.Current_Mode.My_Sobek_Type == My_Sobek_Type_Enum.Folder_Management))) // browse info only for aggregation
                {
                    if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Public_Folder)
                    {
                        DESCRIPTION = "<h1>&quot;" + UI_ApplicationCache_Gateway.Translation.Get_Translation(Browse_Title, RequestSpecificValues.Current_Mode.Language) + "&quot;</h1>" + Environment.NewLine + "  <span class=\"sbkPrsw_PublicFolderAuthor\">This is a publicly shared bookshelf of <a href=\"mailto:" + Folder_Owner_Email + "\">" + Folder_Owner_Name + "</a>.</span>";

                        summation = UI_ApplicationCache_Gateway.Translation.Get_Translation(Browse_Title, RequestSpecificValues.Current_Mode.Language) + " (publicly shared folder)";
                    }
                    else
                    {
                        DESCRIPTION = "<h1>" + UI_ApplicationCache_Gateway.Translation.Get_Translation(Browse_Title, RequestSpecificValues.Current_Mode.Language) + "</h1>";
                        summation = UI_ApplicationCache_Gateway.Translation.Get_Translation(Browse_Title, RequestSpecificValues.Current_Mode.Language) + " browse in " + RequestSpecificValues.Hierarchy_Object.Name;
                    }
                }
                else
                {
                    StringBuilder descriptionBuilder = new StringBuilder();
                    descriptionBuilder.Append("<div class=\"sbkPrsw_ResultsExplanation\">");
                    StringBuilder searchInfoBuilder = new StringBuilder();
                    StringWriter writer = new StringWriter(searchInfoBuilder);
                    Show_Search_Info(writer);
                    summation = searchInfoBuilder.ToString().Replace("<i>", "").Replace("</i>", "").Replace("\"", "").Replace("'", "").Replace("\n", "").Replace("\r", "").Replace("&", "%26").Replace("</td>", "");
                    descriptionBuilder.Append(searchInfoBuilder);
                    descriptionBuilder.Append("</div>");
                    DESCRIPTION = descriptionBuilder.ToString();
                }


                // Get the value for the <%DESCRIPTION%> directive (to explain current display)
                //ushort current_page = currentMode.Page;
                string SHOWING = String.Empty;
                if (RequestSpecificValues.Current_Mode.Result_Display_Type == Result_Display_Type_Enum.Export)
                {
                    SHOWING = RequestSpecificValues.Results_Statistics.Total_Items.ToString();
                }
                else
                {
                    SHOWING = String.Format(showing_range_text, startRow, Math.Min(lastRow, RequestSpecificValues.Results_Statistics.Total_Titles), resultWriter.Total_Results);
                    if (startRow == lastRow)
                    {
                        SHOWING = Showing_Text.Replace(startRow + " - " + startRow, startRow + " ");
                    }
                }

                // Get the values for the <%LEFTBUTTONS%> and <%RIGHTBUTTONS%>
                string LEFT_BUTTONS = String.Empty;
                string RIGHT_BUTTONS = String.Empty;
                string first_page = "First Page";
                string previous_page = "Previous Page";
                string next_page = "Next Page";
                string last_page = "Last Page";
                string first_page_text = "First";
                string previous_page_text = "Previous";
                string next_page_text = "Next";
                string last_page_text = "Last";

                if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.Spanish)
                {
                    first_page = "Primera P�gina";
                    previous_page = "P�gina Anterior";
                    next_page = "P�gina Siguiente";
                    last_page = "�ltima P�gina";
                    first_page_text = "Primero";
                    previous_page_text = "Anterior";
                    next_page_text = "Proximo";
                    last_page_text = "�ltimo";
                }

                if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.French)
                {
                    first_page = "Premi�re Page";
                    previous_page = "Page Pr�c�dente";
                    next_page = "Page Suivante";
                    last_page = "Derni�re Page";
                    first_page_text = "Premi�re";
                    previous_page_text = "Pr�c�dente";
                    next_page_text = "Suivante";
                    last_page_text = "Derniere";
                }

                // Make sure the result writer has been created
                if (resultWriter == null)
                    create_resultwriter();
                if (resultWriter != null)
                {
                    Debug.Assert(resultWriter != null, "resultWriter != null");

                    if (RESULTS_PER_PAGE < resultWriter.Total_Results)
                    {
                        ushort current_page = RequestSpecificValues.Current_Mode.Page;
                        StringBuilder buttons_builder = new StringBuilder(1000);

                        // Should the previous and first buttons be enabled?
                        if (current_page > 1)
                        {
                            buttons_builder.Append("<div class=\"sbkPrsw_LeftButtons\">");
                            RequestSpecificValues.Current_Mode.Page = 1;
                            buttons_builder.Append("<button title=\"" + first_page + "\" class=\"sbkPrsw_RoundButton\" onclick=\"window.location='" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "'; return false;\"><img src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/button_first_arrow.png\" class=\"roundbutton_img_left\" alt=\"\" />" + first_page_text + "</button>&nbsp;");
                            RequestSpecificValues.Current_Mode.Page = (ushort)(current_page - 1);
                            buttons_builder.Append("<button title=\"" + previous_page + "\" class=\"sbkPrsw_RoundButton\" onclick=\"window.location='" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "'; return false;\"><img src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/button_previous_arrow.png\" class=\"roundbutton_img_left\" alt=\"\" />" + previous_page_text + "</button>");
                            buttons_builder.Append("</div>");
                            LEFT_BUTTONS = buttons_builder.ToString();
                            buttons_builder.Clear();
                        }
                        else
                        {
                            LEFT_BUTTONS = "<div class=\"sbkPrsw_NoLeftButtons\">&nbsp;</div>";
                        }


                        // Should the next and last buttons be enabled?
                        if ((current_page * RESULTS_PER_PAGE) < resultWriter.Total_Results)
                        {
                            buttons_builder.Append("<div class=\"sbkPrsw_RightButtons\">");
                            RequestSpecificValues.Current_Mode.Page = (ushort)(current_page + 1);
                            buttons_builder.Append("<button title=\"" + next_page + "\" class=\"sbkPrsw_RoundButton\" onclick=\"window.location='" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "'; return false;\">" + next_page_text + "<img src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/button_next_arrow.png\" class=\"roundbutton_img_right\" alt=\"\" /></button>&nbsp;");
                            RequestSpecificValues.Current_Mode.Page = (ushort)(resultWriter.Total_Results / RESULTS_PER_PAGE);
                            if (resultWriter.Total_Results % RESULTS_PER_PAGE > 0)
                                RequestSpecificValues.Current_Mode.Page = (ushort)(RequestSpecificValues.Current_Mode.Page + 1);
                            buttons_builder.Append("<button title=\"" + last_page + "\" class=\"sbkPrsw_RoundButton\" onclick=\"window.location='" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "'; return false;\">" + last_page_text + "<img src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/button_last_arrow.png\" class=\"roundbutton_img_right\" alt=\"\" /></button>");
                            buttons_builder.Append("</div>");
                            RIGHT_BUTTONS = buttons_builder.ToString();
                        }
                        else
                        {
                            RIGHT_BUTTONS = "<div class=\"sbkPrsw_NoRightButtons\">&nbsp;</div>";
                        }

                        RequestSpecificValues.Current_Mode.Page = current_page;
                    }
                }

                // Empty strings for now
                string brief_view = "BRIEF VIEW";
                string map_view = "MAP VIEW";
                string table_view = "TABLE VIEW";
                string thumbnail_view = "THUMBNAIL VIEW";
                if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.Spanish)
                {
                    map_view = "VISTA MAPA";
                    brief_view = "VISTA BREVE";
                    table_view = "VISTA TABLERA";
                    thumbnail_view = "VISTA MINIATURA";
                }
                if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.French)
                {
                    map_view = "MODE CARTE";
                    brief_view = "MODE SIMPLE";
                    table_view = "MODE DE TABLE";
                    thumbnail_view = "MODE IMAGETTE";
                }
                Result_Display_Type_Enum resultView = RequestSpecificValues.Current_Mode.Result_Display_Type;
                StringBuilder iconBuilder = new StringBuilder(1000);
                iconBuilder.AppendLine();
                iconBuilder.AppendLine("    <div class=\"sbkPrsw_ViewIconButtons\">");
                if ((RequestSpecificValues.Current_Mode.Coordinates.Length > 0) || (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Map)))
                {
                    if (resultView == Result_Display_Type_Enum.Map)
                    {
                        iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "geo_blue.png\" alt=\"MAP\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
                    }
                    else
                    {
                        RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Map;
                        iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + map_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "geo_blue.png\" alt=\"MAP\" class=\"sbkPrsw_ViewIconButton\"/></a>");
                    }
                }

                if ((RequestSpecificValues.Current_Mode.Coordinates.Length > 0) || (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Map_Beta)))
                {
                    if (resultView == Result_Display_Type_Enum.Map_Beta)
                    {
                        iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "geo_blue.png\" alt=\"MAP\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
                    }
                    else
                    {
                        RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Map_Beta;
                        iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + map_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "geo_blue.png\" alt=\"MAP\" class=\"sbkPrsw_ViewIconButton\"/></a>");
                    }
                }

                if (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Brief))
                {
                    if (resultView == Result_Display_Type_Enum.Brief)
                    {
                        iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "brief_blue.png\" alt=\"BRIEF\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
                    }
                    else
                    {
                        RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Brief;
                        iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + brief_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "brief_blue.png\" alt=\"BRIEF\" class=\"sbkPrsw_ViewIconButton\"/></a>");
                    }
                }

                if (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Table))
                {
                    if (resultView == Result_Display_Type_Enum.Table)
                    {
                        iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "table_blue.png\" alt=\"TABLE\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
                    }
                    else
                    {
                        RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Table;
                        iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + table_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "table_blue.png\" alt=\"TABLE\" class=\"sbkPrsw_ViewIconButton\"/></a>");
                    }
                }

                if (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Thumbnails))
                {
                    if (resultView == Result_Display_Type_Enum.Thumbnails)
                    {
                        iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "thumb_blue.png\" alt=\"THUMB\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
                    }
                    else
                    {
                        RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Thumbnails;
                        iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + thumbnail_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "thumb_blue.png\" alt=\"THUMB\" class=\"sbkPrsw_ViewIconButton\"/></a>");
                    }
                }
                RequestSpecificValues.Current_Mode.Result_Display_Type = resultView;
                iconBuilder.AppendLine("    </div>");
                string VIEWICONS = iconBuilder.ToString();
                string NEWSEARCH = String.Empty;
                string ADDFILTER = String.Empty;

                // Start the division for the sort and then description and buttons, etc..
                switch (RequestSpecificValues.Current_Mode.Mode)
                {
                    case Display_Mode_Enum.Public_Folder:
                        Output.WriteLine("<div class=\"sbkPrsw_DescPanel sbkPrsw_FolderDescPanel\">");
                        break;

                    case Display_Mode_Enum.Aggregation:  // browse info only
                        Output.WriteLine("<div class=\"sbkPrsw_DescPanel sbkPrsw_BrowseDescPanel\">");
                        break;

                    default:
                        Output.WriteLine("<div class=\"sbkPrsw_DescPanel sbkPrsw_ResultsDescPanel\">");
                        break;
                }

                // Now, write this 
                Output.WriteLine(html_source.Replace("<%DESCRIPTION%>", DESCRIPTION).Replace("<%NEWSEARCH%>", NEWSEARCH).Replace("<%ADDFILTER%>", ADDFILTER).Replace("<%VIEWICONS%>", VIEWICONS).Replace("<%LEFTBUTTONS%>", LEFT_BUTTONS).Replace("<%SHOWING%>", SHOWING).Replace("<%RIGHTBUTTONS%>", RIGHT_BUTTONS).Replace("<%SORTER%>", SORTER));

                // End this division
                Output.WriteLine("</div>");
                Output.WriteLine();

                // Configure the way to remove search terms
                if ((UI_ApplicationCache_Gateway.Settings.Can_Remove_Single_Term) && (term_counter > 0))
                {
                    Output.WriteLine("<script>");
                    for (int i = 1; i <= term_counter; i++)
                    {
                        Output.WriteLine("  init_search_term('searchterm" + i + "', 'removesearchterm" + i + "');");
                    }
                    Output.WriteLine("</script>");
                    Output.WriteLine();
                }

                // Save the buttons for later, to be used at the bottom of the page
                leftButtons = LEFT_BUTTONS;
                rightButtons = RIGHT_BUTTONS;

                // Determine the number of columns for text areas, depending on browser
                int actual_cols = 50;
                if (RequestSpecificValues.Current_Mode.Browser_Type.ToUpper().IndexOf("FIREFOX") >= 0)
                    actual_cols = 45;

                // Add the hidden field
                Output.WriteLine("<!-- Hidden field is used for postbacks to indicate what to save and reset -->");
                if (RequestSpecificValues.Current_Mode.Mode != Display_Mode_Enum.My_Sobek)
                {
                    Output.WriteLine("<input type=\"hidden\" id=\"item_action\" name=\"item_action\" value=\"\" />");
                }
                Output.WriteLine("<input type=\"hidden\" id=\"url_description\" name=\"url_description\" value=\"" + HttpUtility.HtmlEncode(summation) + "\" />");
                Output.WriteLine("<input type=\"hidden\" id=\"list_type\" name=\"list_type\" value=\"" + currentName + "\" />");
                Output.WriteLine();

                // Add the scripts needed
                if (RequestSpecificValues.Current_Mode.Mode != Display_Mode_Enum.My_Sobek)
                {
                    Output.WriteLine("<script type=\"text/javascript\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/scripts/jquery/jquery-ui-1.10.3.custom.min.js\"></script>");
                    Output.WriteLine();
                }

                #region Email form

                if (RequestSpecificValues.Current_User != null)
                {
                    Output.WriteLine("<!-- Email form -->");
                    Output.WriteLine("<div class=\"email_popup_div\" id=\"form_email\" style=\"display:none;\">");
                    Output.WriteLine("  <div class=\"popup_title\"><table width=\"100%\"><tr><td align=\"left\">S<span class=\"smaller\">END THIS</span> " + currentTitle + "<span class=\"smaller\"> TO A</span> F<span class=\"smaller\">RIEND</span></td><td align=\"right\"> <a href=\"#template\" alt=\"CLOSE\" onclick=\"email_form_close()\">X</a> &nbsp; </td></tr></table></div>");
                    Output.WriteLine("  <br />");
                    Output.WriteLine("  <fieldset><legend>Enter the email information below &nbsp; </legend>");
                    Output.WriteLine("    <br />");
                    Output.WriteLine("    <table class=\"popup_table\">");


                    // Add email address line
                    Output.Write("      <tr align=\"left\"><td width=\"80px\"><label for=\"email_address\">To:</label></td>");
                    Output.WriteLine("<td><input class=\"email_input\" name=\"email_address\" id=\"email_address\" type=\"text\" value=\"" + RequestSpecificValues.Current_User.Email + "\" onfocus=\"javascript:textbox_enter('email_address', 'email_input_focused')\" onblur=\"javascript:textbox_leave('email_address', 'email_input')\" /></td></tr>");

                    // Add comments area
                    Output.Write("      <tr align=\"left\" valign=\"top\"><td><br /><label for=\"email_comments\">Comments:</label></td>");
                    Output.WriteLine("<td><textarea rows=\"6\" cols=\"" + actual_cols + "\" name=\"email_comments\" id=\"email_comments\" class=\"email_textarea\" onfocus=\"javascript:textbox_enter('email_comments','email_textarea_focused')\" onblur=\"javascript:textbox_leave('email_comments','email_textarea')\"></textarea></td></tr>");

                    // Add format area
                    Output.Write("      <tr align=\"left\" valign=\"top\"><td>Format:</td>");
                    Output.Write("<td><input type=\"radio\" name=\"email_format\" id=\"email_format_html\" value=\"html\" checked=\"checked\" /> <label for=\"email_format_html\">HTML</label> &nbsp; &nbsp; ");
                    Output.WriteLine("<input type=\"radio\" name=\"email_format\" id=\"email_format_text\" value=\"text\" /> <label for=\"email_format_text\">Plain Text</label></td></tr>");


                    Output.WriteLine("    </table>");
                    Output.WriteLine("    <br />");
                    Output.WriteLine("  </fieldset><br />");
                    Output.WriteLine("  <center><a href=\"\" onclick=\"return email_form_close();\"><img border=\"0\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "design/skins/" + RequestSpecificValues.Current_Mode.Base_Skin + "/buttons/cancel_button_g.gif\" alt=\"CLOSE\" /></a> &nbsp; &nbsp; <input type=\"image\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "design/skins/" + RequestSpecificValues.Current_Mode.Base_Skin + "/buttons/send_button_g.gif\" value=\"Submit\" alt=\"Submit\"></center><br />");
                    Output.WriteLine("</div>");
                    Output.WriteLine();
                }

                #endregion

                if (RequestSpecificValues.Current_Mode.Mode != Display_Mode_Enum.My_Sobek)
                {

                    #region Save search/browse form

                    if (RequestSpecificValues.Current_User != null)
                    {
                        Output.WriteLine("<!-- Save search/browse -->");
                        Output.WriteLine("<div class=\"add_popup_div\" id=\"add_item_form\" style=\"display:none;\">");
                        Output.WriteLine("  <div class=\"popup_title\"><table width=\"100%\"><tr><td align=\"left\">A<span class=\"smaller\">DD THIS</span> " + currentTitle + "<span class=\"smaller\"> TO YOUR</span> S<span class=\"smaller\">AVED</span> S<span class=\"smaller\">EARCHES</span></td><td align=\"right\"> <a href=\"#template\" alt=\"CLOSE\" onclick=\"add_item_form_close()\">X</a> &nbsp; </td></tr></table></div>");
                        Output.WriteLine("  <br />");
                        Output.WriteLine("  <fieldset><legend>Enter notes for this " + currentName + " &nbsp; </legend>");
                        Output.WriteLine("    <br />");
                        Output.WriteLine("    <table class=\"popup_table\">");

                        // Add comments area
                        Output.Write("      <tr align=\"left\" valign=\"top\"><td><br /><label for=\"add_notes\">Description:</label></td>");
                        Output.WriteLine("<td><textarea rows=\"8\" cols=\"" + actual_cols + "\" name=\"add_notes\" id=\"add_notes\" class=\"add_notes_textarea\" onfocus=\"javascript:textbox_enter('add_notes','add_notes_textarea_focused')\" onblur=\"javascript:textbox_leave('add_notes','add_notes_textarea')\">" + summation + "</textarea></td></tr>");
                        Output.WriteLine("      <tr align=\"left\" valign=\"top\"><td>&nbsp;</td><td><input type=\"checkbox\" id=\"open_searches\" name=\"open_searches\" value=\"open\" /> <label for=\"open_searches\">Open saved searches in new window</label></td></tr>");
                        Output.WriteLine("    </table>");
                        Output.WriteLine("    <br />");
                        Output.WriteLine("  </fieldset><br />");
                        Output.WriteLine("  <center><a href=\"\" onclick=\"return add_item_form_close();\"><img border=\"0\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "design/skins/" + RequestSpecificValues.Current_Mode.Base_Skin + "/buttons/cancel_button_g.gif\" alt=\"CLOSE\" /></a> &nbsp; &nbsp; <input type=\"image\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "design/skins/" + RequestSpecificValues.Current_Mode.Base_Skin + "/buttons/save_button_g.gif\" value=\"Submit\" alt=\"Submit\"></center><br />");
                        Output.WriteLine("</div>");
                        Output.WriteLine();
                    }

                    #endregion

                    #region Share form

                    // Calculate the title and url
                    string title = HttpUtility.HtmlEncode(summation);
                    string share_url = HttpContext.Current.Items["Original_URL"].ToString().Replace("&", "%26").Replace("?", "%3F").Replace("http://", "").Replace("=", "%3D").Replace("\"", "&quot;");

                    Output.WriteLine("<!-- Share form -->");
                    Output.WriteLine("<div class=\"share_popup_div\" id=\"share_form\" style=\"display:none;\">");

                    Output.WriteLine("<a href=\"http://www.facebook.com/share.php?u=" + share_url + "&amp;t=" + title + "\" target=\"FACEBOOK_WINDOW\" onmouseover=\"facebook_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/facebook_share_h.gif'\" onmouseout=\"facebook_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/facebook_share.gif'\" onclick=\"\"><img class=\"ResultSavePrintButtons\" border=\"0px\" id=\"facebook_share\" name=\"facebook_share\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/facebook_share.gif\" alt=\"FACEBOOK\" /></a>");
                    Output.WriteLine("<a href=\"http://buzz.yahoo.com/buzz?targetUrl=" + share_url + "&amp;headline=" + title + "\" target=\"YAHOOBUZZ_WINDOW\" onmouseover=\"yahoobuzz_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/yahoobuzz_share_h.gif'\" onmouseout=\"yahoobuzz_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/yahoobuzz_share.gif'\" onclick=\"\"><img class=\"ResultSavePrintButtons\" border=\"0px\" id=\"yahoobuzz_share\" name=\"yahoobuzz_share\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/yahoobuzz_share.gif\" alt=\"YAHOO BUZZ\" /></a>");
                    Output.WriteLine("<br />");

                    Output.WriteLine("<a href=\"http://twitter.com/home?status=Currently reading " + share_url + "\" target=\"TWITTER_WINDOW\" onmouseover=\"twitter_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/twitter_share_h.gif'\" onmouseout=\"twitter_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/twitter_share.gif'\" onclick=\"\"><img class=\"ResultSavePrintButtons\" border=\"0px\" id=\"twitter_share\" name=\"twitter_share\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/twitter_share.gif\" alt=\"TWITTER\" /></a>");
                    Output.WriteLine("<a href=\"http://www.google.com/bookmarks/mark?op=add&amp;bkmk=" + share_url + "&amp;title=" + title + "\" target=\"GOOGLE_WINDOW\" onmouseover=\"google_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/google_share_h.gif'\" onmouseout=\"google_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/google_share.gif'\" onclick=\"\"><img class=\"ResultSavePrintButtons\" border=\"0px\" id=\"google_share\" name=\"google_share\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/google_share.gif\" alt=\"GOOGLE SHARE\" /></a>");
                    Output.WriteLine("<br />");

                    Output.WriteLine("<a href=\"http://www.stumbleupon.com/submit?url=" + share_url + "&amp;title=" + title + "\" target=\"STUMBLEUPON_WINDOW\" onmouseover=\"stumbleupon_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/stumbleupon_share_h.gif'\" onmouseout=\"stumbleupon_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/stumbleupon_share.gif'\" onclick=\"\"><img class=\"ResultSavePrintButtons\" border=\"0px\" id=\"stumbleupon_share\" name=\"stumbleupon_share\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/stumbleupon_share.gif\" alt=\"STUMBLEUPON\" /></a>");
                    Output.WriteLine("<a href=\"http://myweb.yahoo.com/myresults/bookmarklet?t=" + title + "&amp;u=" + share_url + "\" target=\"YAHOO_WINDOW\" onmouseover=\"yahoo_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/yahoo_share_h.gif'\" onmouseout=\"yahoo_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/yahoo_share.gif'\" onclick=\"\"><img class=\"ResultSavePrintButtons\" border=\"0px\" id=\"yahoo_share\" name=\"yahoo_share\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/yahoo_share.gif\" alt=\"YAHOO SHARE\" /></a>");
                    Output.WriteLine("<br />");

                    Output.WriteLine("<a href=\"http://digg.com/submit?phase=2&amp;url=" + share_url + "&amp;title=" + title + "\" target=\"DIGG_WINDOW\" onmouseover=\"digg_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/digg_share_h.gif'\" onmouseout=\"digg_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/digg_share.gif'\" onclick=\"\"><img class=\"ResultSavePrintButtons\" border=\"0px\" id=\"digg_share\" name=\"digg_share\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/digg_share.gif\" alt=\"DIGG\" /></a>");
                    Output.WriteLine("<a onmouseover=\"favorites_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/favorites_share_h.gif'\" onmouseout=\"favorites_share.src='" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/favorites_share.gif'\" onclick=\"javascript:add_to_favorites();\"><img class=\"ResultSavePrintButtons\" border=\"0px\" id=\"favorites_share\" name=\"favorites_share\" src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "default/images/favorites_share.gif\" alt=\"MY FAVORITES\" /></a>");
                    Output.WriteLine("<br />");

                    Output.WriteLine("</div>");
                    Output.WriteLine();

                    #endregion

                }

                if (Outer_Form_Name.Length == 0)
                    Output.WriteLine("</form>");

                #endregion
            }
            else
		    {
                #region map beta

                Display_Mode_Enum initialMode = RequestSpecificValues.Current_Mode.Mode;

                RequestSpecificValues.Current_Mode.Mode = initialMode;
                if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Search)
                    RequestSpecificValues.Current_Mode.Mode = Display_Mode_Enum.Results;

                // If no results, display different information here
                if ((RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Results) && (RequestSpecificValues.Results_Statistics.Total_Items == 0))
                {
                    Output.WriteLine("<div class=\"sbkPrsw_DescPanel\" style=\"margin-top:10px\">");
                    Show_Search_Info(Output);
                    Output.WriteLine("</div>");
                    Output.WriteLine("<div class=\"sbkPrsw_ResultsNavBar\">&nbsp;</div>");
                    return true;
                }

                // Load the HTML that can be used to customize the search/results bar
                string html_source = String.Empty;
                string fileToRead = HttpContext.Current.Server.MapPath("default/fragments/search_browse_bar.html");
                if (File.Exists(fileToRead))
                {
                    html_source = File.ReadAllText(fileToRead);
                }

                // Get the value for the <%SORTER%> directive (to sort the results)
                string SORTER = String.Empty;

                // Get the value for the <%DESCRIPTION%> directive (to explain current display)
                string DESCRIPTION = String.Empty;
                string summation;
                if ((RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Aggregation) || (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Public_Folder) || ((RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.My_Sobek) && (RequestSpecificValues.Current_Mode.My_Sobek_Type == My_Sobek_Type_Enum.Folder_Management))) // browse info only for aggregation
                {
                    if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Public_Folder)
                    {
                        DESCRIPTION = "<h1>&quot;" + UI_ApplicationCache_Gateway.Translation.Get_Translation(Browse_Title, RequestSpecificValues.Current_Mode.Language) + "&quot;</h1>" + Environment.NewLine + "  <span class=\"sbkPrsw_PublicFolderAuthor\">This is a publicly shared bookshelf of <a href=\"mailto:" + Folder_Owner_Email + "\">" + Folder_Owner_Name + "</a>.</span>";

                        summation = UI_ApplicationCache_Gateway.Translation.Get_Translation(Browse_Title, RequestSpecificValues.Current_Mode.Language) + " (publicly shared folder)";
                    }
                    else
                    {
                        DESCRIPTION = "<h1>" + UI_ApplicationCache_Gateway.Translation.Get_Translation(Browse_Title, RequestSpecificValues.Current_Mode.Language) + "</h1>";
                        summation = UI_ApplicationCache_Gateway.Translation.Get_Translation(Browse_Title, RequestSpecificValues.Current_Mode.Language) + " browse in " + RequestSpecificValues.Hierarchy_Object.Name;
                    }
                }
                else
                {
                    StringBuilder descriptionBuilder = new StringBuilder();
                    descriptionBuilder.Append("<div class=\"sbkPrsw_ResultsExplanation\">");
                    StringBuilder searchInfoBuilder = new StringBuilder();
                    StringWriter writer = new StringWriter(searchInfoBuilder);
                    Show_Search_Info(writer);
                    summation = searchInfoBuilder.ToString().Replace("<i>", "").Replace("</i>", "").Replace("\"", "").Replace("'", "").Replace("\n", "").Replace("\r", "").Replace("&", "%26").Replace("</td>", "");
                    descriptionBuilder.Append(searchInfoBuilder);
                    descriptionBuilder.Append("</div>");
                    DESCRIPTION = descriptionBuilder.ToString();
                }

                //// Get the value for the <%DESCRIPTION%> directive (to explain current display)
                //string DESCRIPTION = String.Empty;
                //DESCRIPTION = "<div id\"descriptionHolder\"></div>";

                string SHOWING = String.Empty;
                SHOWING = "showing <div id=\"showingCountHook\" style=\"display:inline;\"></div> matching titles";

                // Get the values for the <%LEFTBUTTONS%> and <%RIGHTBUTTONS%>
                string LEFT_BUTTONS = String.Empty;
                string RIGHT_BUTTONS = String.Empty;

                #region view icons

                // Empty strings for now
                string brief_view = "BRIEF VIEW";
                string map_view = "MAP VIEW";
                string table_view = "TABLE VIEW";
                string thumbnail_view = "THUMBNAIL VIEW";
                if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.Spanish)
                {
                    map_view = "VISTA MAPA";
                    brief_view = "VISTA BREVE";
                    table_view = "VISTA TABLERA";
                    thumbnail_view = "VISTA MINIATURA";
                }
                if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.French)
                {
                    map_view = "MODE CARTE";
                    brief_view = "MODE SIMPLE";
                    table_view = "MODE DE TABLE";
                    thumbnail_view = "MODE IMAGETTE";
                }
                Result_Display_Type_Enum resultView = RequestSpecificValues.Current_Mode.Result_Display_Type;
                StringBuilder iconBuilder = new StringBuilder(1000);
                iconBuilder.AppendLine();
                iconBuilder.AppendLine("    <div class=\"sbkPrsw_ViewIconButtons\">");
                if ((RequestSpecificValues.Current_Mode.Coordinates.Length > 0) || (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Map)))
                {
                    if (resultView == Result_Display_Type_Enum.Map)
                    {
                        iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "geo_blue.png\" alt=\"MAP\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
                    }
                    else
                    {
                        RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Map;
                        iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + map_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "geo_blue.png\" alt=\"MAP\" class=\"sbkPrsw_ViewIconButton\"/></a>");
                    }
                }

		        if ((RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Map_Beta)) & (RequestSpecificValues.Current_Mode.Use_Beta))
		        {
		            if (resultView == Result_Display_Type_Enum.Map_Beta)
		            {
		                iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "geo_blue.png\" alt=\"MAPBETA\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
		            }
		            else
		            {
		                RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Map_Beta;
		                iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + map_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "geo_blue.png\" alt=\"MAPBETA\" class=\"sbkPrsw_ViewIconButton\"/></a>");
		            }
		        }

		        if (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Brief))
                {
                    if (resultView == Result_Display_Type_Enum.Brief)
                    {
                        iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "brief_blue.png\" alt=\"BRIEF\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
                    }
                    else
                    {
                        RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Brief;
                        iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + brief_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "brief_blue.png\" alt=\"BRIEF\" class=\"sbkPrsw_ViewIconButton\"/></a>");
                    }
                }

                if (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Table))
                {
                    if (resultView == Result_Display_Type_Enum.Table)
                    {
                        iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "table_blue.png\" alt=\"TABLE\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
                    }
                    else
                    {
                        RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Table;
                        iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + table_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "table_blue.png\" alt=\"TABLE\" class=\"sbkPrsw_ViewIconButton\"/></a>");
                    }
                }

                if (RequestSpecificValues.Hierarchy_Object.Result_Views.Contains(Result_Display_Type_Enum.Thumbnails))
                {
                    if (resultView == Result_Display_Type_Enum.Thumbnails)
                    {
                        iconBuilder.AppendLine("      <img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "thumb_blue.png\" alt=\"THUMB\" class=\"sbkPrsw_ViewIconButtonCurrent\"/>");
                    }
                    else
                    {
                        RequestSpecificValues.Current_Mode.Result_Display_Type = Result_Display_Type_Enum.Thumbnails;
                        iconBuilder.AppendLine("      <a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("&", "&amp;") + "\" title=\"" + thumbnail_view + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "thumb_blue.png\" alt=\"THUMB\" class=\"sbkPrsw_ViewIconButton\"/></a>");
                    }
                }
                RequestSpecificValues.Current_Mode.Result_Display_Type = resultView;
                iconBuilder.AppendLine("    </div>");
                string VIEWICONS = iconBuilder.ToString();

                #endregion

                string NEWSEARCH = String.Empty;

                string ADDFILTER = String.Empty;

                // Start the division for the sort and then description and buttons, etc..
                switch (RequestSpecificValues.Current_Mode.Mode)
                {
                    case Display_Mode_Enum.Public_Folder:
                        Output.WriteLine("<div class=\"sbkPrsw_DescPanel sbkPrsw_FolderDescPanel\">");
                        break;

                    case Display_Mode_Enum.Aggregation:  // browse info only
                        Output.WriteLine("<div class=\"sbkPrsw_DescPanel sbkPrsw_BrowseDescPanel\">");
                        break;

                    default:
                        Output.WriteLine("<div class=\"sbkPrsw_DescPanel sbkPrsw_ResultsDescPanel\">");
                        break;
                }

                // Now, write this 
                Output.WriteLine(html_source.Replace("<%DESCRIPTION%>", DESCRIPTION).Replace("<%NEWSEARCH%>", NEWSEARCH).Replace("<%ADDFILTER%>", ADDFILTER).Replace("<%VIEWICONS%>", VIEWICONS).Replace("<%LEFTBUTTONS%>", LEFT_BUTTONS).Replace("<%SHOWING%>", SHOWING).Replace("<%RIGHTBUTTONS%>", RIGHT_BUTTONS).Replace("<%SORTER%>", SORTER));

                // End this division
                Output.WriteLine("</div>");
                Output.WriteLine();

                // Configure the way to remove search terms
                if ((UI_ApplicationCache_Gateway.Settings.Can_Remove_Single_Term) && (term_counter > 0))
                {
                    Output.WriteLine("<script>");
                    for (int i = 1; i <= term_counter; i++)
                    {
                        Output.WriteLine("  init_search_term('searchterm" + i + "', 'removesearchterm" + i + "');");
                    }
                    Output.WriteLine("</script>");
                    Output.WriteLine();
                }

                #endregion
            }

			return true;
		}

		/// <summary> Renders the text about this search (i.e., &quot;Your search for ... resulted in ...&quot; )
		/// directly to the output stream </summary>
		/// <param name="Output"> Stream to which to write the HTML for this subwriter </param>
		protected void Show_Search_Info(TextWriter Output)
		{
			string and_language = "and ";
			string or_language = "or ";
			string and_not_language = "not ";
			string no_matches_language = "resulted in no matching records.";
			string one_match_language = "resulted in one matching record.";
			string multiple_records_language = "resulted in {0} matching records.";
			string one_item_language = "resulted in one item in ";
			string multiple_items_language = "resulted in {0} items in ";
			string one_title_language = "one title.";
			string multiple_titles_language = " titles.";

			string between_two_dates = "between {0} and {1} ";
			string on_one_date = "in {0} ";

			// Set special language for aerials
			if (RequestSpecificValues.Current_Mode.Aggregation == "aerials")
			{
				no_matches_language = "resulted in no matching flights.";
				one_match_language = "resulted in one matching flight.";
				multiple_records_language = "resulted in {0} matching flights.";
				one_item_language = "resulted in one flight in ";
				multiple_items_language = "resulted in {0} flights in ";
				one_title_language = "one county.";
				multiple_titles_language = " counties.";
			}
			
			switch (RequestSpecificValues.Current_Mode.Language)
			{
				case Web_Language_Enum.French:
					Output.Write("Votre recherche de <i>" + RequestSpecificValues.Hierarchy_Object.Name + "</i> en ");
					and_language = "et ";
					or_language = "ou ";
					and_not_language = "non ";

					no_matches_language = "aucun des documents correspondants.";
					one_match_language = ", correpsonde � 1 document.";
					multiple_records_language = ", correpsonde � {0} documents";
					one_item_language = ", correpsonde � 1 document en ";
					multiple_items_language = ", correpsonde � {0} documents en ";
					one_title_language = "1 titre.";
					multiple_titles_language = " titres.";
					break;

				case Web_Language_Enum.Spanish:
					Output.Write("Su b�squeda de <i>" + RequestSpecificValues.Hierarchy_Object.Name + "</i> en ");
					and_language = "y ";
					or_language = "o ";
					and_not_language = "no ";

					no_matches_language = "no dio lugar a los objetos.";
					one_match_language = ", result� en 1 objeto.";
					multiple_records_language = ", result� en {0} objetos.";
					one_item_language = ", result� en 1 objeto en ";
					multiple_items_language = ", result� en {0} objetos en ";
					one_title_language = "1 t�tulo.";
					multiple_titles_language = " t�tulos.";
					break;

				default:
					if ((RequestSpecificValues.Current_Mode.Search_Type == Search_Type_Enum.Map)||(RequestSpecificValues.Current_Mode.Search_Type == Search_Type_Enum.Map_Beta))
						Output.Write("Your geographic search of <i>" + RequestSpecificValues.Hierarchy_Object.Name + "</i> ");
					else
						Output.Write("Your search of <i>" + RequestSpecificValues.Hierarchy_Object.Name + "</i> for ");
					break;
			}

			// Split the parts
			if ((RequestSpecificValues.Current_Mode.Search_Type != Search_Type_Enum.Map)||(RequestSpecificValues.Current_Mode.Search_Type != Search_Type_Enum.Map_Beta))
			{
				int length_of_explanation = 0;
				List<string> terms = new List<string>();
				List<string> fields = new List<string>();

				// Split the terms correctly
				SobekCM_Assistant.Split_Clean_Search_Terms_Fields(RequestSpecificValues.Current_Mode.Search_String, RequestSpecificValues.Current_Mode.Search_Fields, RequestSpecificValues.Current_Mode.Search_Type, terms, fields, UI_ApplicationCache_Gateway.Search_Stop_Words, RequestSpecificValues.Current_Mode.Search_Precision, ',');

				try
				{
					// Create this differently depending on whether users can remove a search term from their current search
					if (UI_ApplicationCache_Gateway.Settings.Can_Remove_Single_Term)
					{
						string current_search_string = RequestSpecificValues.Current_Mode.Search_String;
						string current_search_field = RequestSpecificValues.Current_Mode.Search_Fields;
						Display_Mode_Enum current_display_mode = RequestSpecificValues.Current_Mode.Mode;
						Aggregation_Type_Enum current_aggr_mode = RequestSpecificValues.Current_Mode.Aggregation_Type;
						string current_info_browse_mode = RequestSpecificValues.Current_Mode.Info_Browse_Mode;

						StringBuilder fieldsBuilder = new StringBuilder();
						StringBuilder termsBuilder = new StringBuilder();

						term_counter = 0;
						for (int i = 0; i < Math.Min(terms.Count, fields.Count); i++)
						{
							if ((terms[i].Length > 0) && (fields[i].Length > 0))
							{
								Output.WriteLine();
								Output.Write("        ");

								// Remove the leading + sign
								if (fields[i][0] == '+')
									fields[i] = fields[i].Substring(1);
								if (fields[i][0] == ' ')
									fields[i] = fields[i].Substring(1);

								// Add the 'AND' value
								if (i > 0)
								{
									if (fields[i][0] == '=')
									{
										Output.Write(or_language);
										length_of_explanation += or_language.Length;
										fields[i] = fields[i].Substring(1);
									}
									else
									{
										Output.Write(and_language);
										length_of_explanation += and_language.Length;
									}
								}

								//// This explanataion need to be capped
								//if (length_of_explanation >= 160)
								//{
								//	Output.Write("... ");
								//	break;
								//}

								term_counter++;
								Output.Write("<div id=\"searchterm" + term_counter + "\" class=\"sbkPrsw_SearchTerm\">");


                                // Special code for MIMETYPE of NOT NONE
							    string write_value;
							    if ((String.Compare(terms[i], "NONE", true) == 0) && (String.Compare(fields[i], "-MI", true) == 0))
							    {
							        write_value = "items with files ";
							        Output.Write("items with files ");
							    }
							    else
							    {
							        // Add the term
							        if (terms[i].Contains(" "))
							        {
							            Output.Write("\"" + terms[i].Replace("''''", "'").Replace("''", "'") + "\" ");
							            length_of_explanation += terms[i].Length + 1;
							        }
							        else
							        {
							            Output.Write("'" + terms[i].Replace("''''", "'").Replace("''", "'") + "' ");
							            length_of_explanation += terms[i].Length + 3;
							        }

							        // Does the field start with a negative?
							        if (fields[i][0] == '-')
							        {
							            Output.Write(and_not_language);
							            length_of_explanation += and_not_language.Length;
							            fields[i] = fields[i].Substring(1);
							        }

							        write_value = Search_Label_from_Sobek_Code(fields[i]).ToLower() + " ";
							        Output.Write(write_value);
							    }

							    // Determine URL of this search without this one term
								if (terms.Count > 1)
								{
									termsBuilder.Clear();
									fieldsBuilder.Clear();

									// Add all fields, EXCEPT the one to be skipped
									for (int j = 0; j < Math.Min(terms.Count, fields.Count); j++)
									{
										if (j != i)
										{
											if (termsBuilder.Length > 0)
												termsBuilder.Append(",");
											termsBuilder.Append(terms[j]);

											if (fieldsBuilder.Length > 0)
												fieldsBuilder.Append(",");
											fieldsBuilder.Append(fields[j]);
										}
									}
									RequestSpecificValues.Current_Mode.Search_String = termsBuilder.ToString();
									RequestSpecificValues.Current_Mode.Search_Fields = fieldsBuilder.ToString();
								}
								else
								{
									if (RequestSpecificValues.Hierarchy_Object.Views_And_Searches.Contains(Item_Aggregation.CollectionViewsAndSearchesEnum.All_New_Items))
									{
										RequestSpecificValues.Current_Mode.Mode = Display_Mode_Enum.Aggregation;
										RequestSpecificValues.Current_Mode.Aggregation_Type = Aggregation_Type_Enum.Browse_Info;
										RequestSpecificValues.Current_Mode.Info_Browse_Mode = "all";
									}
									else
									{
										RequestSpecificValues.Current_Mode.Mode = Display_Mode_Enum.Aggregation;
										RequestSpecificValues.Current_Mode.Aggregation_Type = Aggregation_Type_Enum.Home;
									}
								}


								Output.WriteLine("<a href=\"" + UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode) + "\" title=\"Click to remove this search term\"><img src=\"" + RequestSpecificValues.Current_Mode.Default_Images_URL + "removeIcon.gif\" id=\"removesearchterm" + term_counter + "\" class=\"sbkPrsw_RemoveSearchTerm\" /></a></div>");
								length_of_explanation += write_value.Length;
							}
						}

						RequestSpecificValues.Current_Mode.Search_String = current_search_string;
						RequestSpecificValues.Current_Mode.Search_Fields = current_search_field;
						RequestSpecificValues.Current_Mode.Mode = current_display_mode;
						RequestSpecificValues.Current_Mode.Aggregation_Type = current_aggr_mode;
						RequestSpecificValues.Current_Mode.Info_Browse_Mode = current_info_browse_mode;
					}
					else
					{

						for (int i = 0; (i < terms.Count) && (i < fields.Count); i++)
						{
							if ((terms[i].Length > 0) && (fields[i].Length > 0))
							{
								// Remove the leading + sign
								if (fields[i][0] == '+')
									fields[i] = fields[i].Substring(1);
								if (fields[i][0] == ' ')
									fields[i] = fields[i].Substring(1);

								// Add the 'AND' value
								if (i > 0)
								{
									if (fields[i][0] == '=')
									{
										Output.Write(or_language);
										length_of_explanation += or_language.Length;
										fields[i] = fields[i].Substring(1);
									}
									else
									{
										Output.Write(and_language);
										length_of_explanation += and_language.Length;
									}
								}

								//// This explanataion need to be capped
								//if (length_of_explanation >= 160)
								//{
								//	Output.Write("... ");
								//	break;
								//}

								// Add the term
								if (terms[i].Contains(" "))
								{
									Output.Write("\"" + terms[i].Replace("''''", "'").Replace("''", "'") + "\" ");
									length_of_explanation += terms[i].Length + 1;
								}
								else
								{
									Output.Write("'" + terms[i].Replace("''''", "'").Replace("''", "'") + "' ");
									length_of_explanation += terms[i].Length + 3;
								}

								// Does the field start with a negative?
								if (fields[i][0] == '-')
								{
									Output.Write(and_not_language);
									length_of_explanation += and_not_language.Length;
									fields[i] = fields[i].Substring(1);
								}

								string write_value = Search_Label_from_Sobek_Code(fields[i]).ToLower() + " ";
								Output.Write(write_value);



								length_of_explanation += write_value.Length;
							}
						}

					}
				}
				catch
				{
					Output.Write("UNRECOGNIZED SEARCH ");
				}
			}

			// Add the year date range text here as well
			if (RequestSpecificValues.Current_Mode.DateRange_Year1 >= 0)
			{
				if (RequestSpecificValues.Current_Mode.DateRange_Year2 >= 0)
				{
					Output.Write(between_two_dates, RequestSpecificValues.Current_Mode.DateRange_Year1, RequestSpecificValues.Current_Mode.DateRange_Year2 );
				}
				else
				{
					Output.Write(on_one_date, RequestSpecificValues.Current_Mode.DateRange_Year1);
				}
			}

            if ((RequestSpecificValues.Results_Statistics == null) || (RequestSpecificValues.Results_Statistics.Total_Titles == 0))
			{
				Output.WriteLine(no_matches_language );
			}
			else
			{
				if (RequestSpecificValues.Results_Statistics.Total_Titles == RequestSpecificValues.Results_Statistics.Total_Items)
				{
					Output.WriteLine(RequestSpecificValues.Results_Statistics.Total_Titles == 1 ? one_match_language : String.Format(multiple_records_language, RequestSpecificValues.Results_Statistics.Total_Titles));
				}
				else
				{
					Output.Write(RequestSpecificValues.Results_Statistics.Total_Items == 1 ? one_item_language : String.Format(multiple_items_language, RequestSpecificValues.Results_Statistics.Total_Items.ToString()));

					if (RequestSpecificValues.Results_Statistics.Total_Titles == 1)
					{
						Output.WriteLine(one_title_language);
					}
					else
					{
						Output.WriteLine(RequestSpecificValues.Results_Statistics.Total_Titles + multiple_titles_language);
					}
				}
			}
		}

		private string Search_Label_from_Sobek_Code(string Code)
		{
			string in_language = "in ";
			if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.French)
			{
				in_language = "en ";
			}
			if (RequestSpecificValues.Current_Mode.Language == Web_Language_Enum.Spanish)
			{
				in_language = "en ";
			}

			if (Code == "ZZ")
				return UI_ApplicationCache_Gateway.Translation.Get_Translation("anywhere", RequestSpecificValues.Current_Mode.Language);

			Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_Code(Code);
			return (field != null) ? in_language + UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Display_Term, RequestSpecificValues.Current_Mode.Language) : in_language + Code;
		}

		#region Methods to create the facets on the left side of the results

		/// <summary> Returns the facets for this result/browse as HTML to be added into the form </summary>
		/// <param name="Tracer"> Trace object keeps a list of each method executed and important milestones in rendering </param>
		/// <returns> Formatted facet information in HTML table format </returns>
		protected string Add_Facet_Information(Custom_Tracer Tracer)
		{

            StringBuilder builder = new StringBuilder();

            if (RequestSpecificValues.Current_Mode.Result_Display_Type != Result_Display_Type_Enum.Map_Beta)
            {
                #region all but mapbeta

                string collection = UI_ApplicationCache_Gateway.Translation.Get_Translation("Collection", RequestSpecificValues.Current_Mode.Language);
                string show_more = UI_ApplicationCache_Gateway.Translation.Get_Translation("Show More", RequestSpecificValues.Current_Mode.Language);
                string show_less = UI_ApplicationCache_Gateway.Translation.Get_Translation("Show Less", RequestSpecificValues.Current_Mode.Language);
                string sort_by_frequency = UI_ApplicationCache_Gateway.Translation.Get_Translation("Sort these facets by frequency", RequestSpecificValues.Current_Mode.Language);
                string sort_alphabetically = UI_ApplicationCache_Gateway.Translation.Get_Translation("Sort these facets alphabetically", RequestSpecificValues.Current_Mode.Language);
                
                builder.AppendLine("<input type=\"hidden\" id=\"facet\" name=\"facet\" value=\"" + HttpUtility.HtmlEncode(facetInformation) + "\" />");

                builder.AppendLine("<script type=\"text/javascript\">");
                builder.AppendLine("  //<![CDATA[");
                builder.AppendLine("    function add_facet(code, new_value) {");

                string url = String.Empty;
                string aggregation_url = String.Empty;

                if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Aggregation)  // browse info only
                {
                    Display_Mode_Enum displayMode = RequestSpecificValues.Current_Mode.Mode;
                    RequestSpecificValues.Current_Mode.Mode = Display_Mode_Enum.Results;
                    RequestSpecificValues.Current_Mode.Search_Type = Search_Type_Enum.Advanced;
                    RequestSpecificValues.Current_Mode.Search_Fields = "<%CODE%>";
                    RequestSpecificValues.Current_Mode.Search_String = "<%VALUE%>";
                    ushort page = RequestSpecificValues.Current_Mode.Page;
                    RequestSpecificValues.Current_Mode.Page = 1;
                    url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("%3c%25", "<%").Replace("%25%3e", "%>").Replace("<%VALUE%>", "\"<%VALUE%>\"");
                    RequestSpecificValues.Current_Mode.Mode = displayMode;
                    RequestSpecificValues.Current_Mode.Page = page;
                    RequestSpecificValues.Current_Mode.Search_Fields = String.Empty;
                    RequestSpecificValues.Current_Mode.Search_String = String.Empty;

                    if ((RequestSpecificValues.Current_Mode.Aggregation.Length == 0) || (RequestSpecificValues.Current_Mode.Aggregation == "all"))
                    {
                        RequestSpecificValues.Current_Mode.Aggregation = "<%AGGREGATION%>";
                        aggregation_url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode);
                        RequestSpecificValues.Current_Mode.Aggregation = String.Empty;
                    }
                }
                else
                {
                    if ((RequestSpecificValues.Current_Mode.Aggregation.Length == 0) || (RequestSpecificValues.Current_Mode.Aggregation == "all"))
                    {
                        RequestSpecificValues.Current_Mode.Aggregation = "<%AGGREGATION%>";
                        aggregation_url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode);
                        RequestSpecificValues.Current_Mode.Aggregation = String.Empty;
                    }

                    if (RequestSpecificValues.Current_Mode.Search_Type == Search_Type_Enum.Advanced)
                    {
                        string orig_field = RequestSpecificValues.Current_Mode.Search_Fields;
                        string orig_terms = RequestSpecificValues.Current_Mode.Search_String;
                        RequestSpecificValues.Current_Mode.Search_Fields = RequestSpecificValues.Current_Mode.Search_Fields + ",<%CODE%>";
                        RequestSpecificValues.Current_Mode.Search_String = RequestSpecificValues.Current_Mode.Search_String + ",<%VALUE%>";
                        ushort page = RequestSpecificValues.Current_Mode.Page;
                        RequestSpecificValues.Current_Mode.Page = 1;
                        url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("%3c%25", "<%").Replace("%25%3e", "%>").Replace("<%VALUE%>", "\"<%VALUE%>\"");
                        RequestSpecificValues.Current_Mode.Page = page;
                        RequestSpecificValues.Current_Mode.Search_Fields = orig_field;
                        RequestSpecificValues.Current_Mode.Search_String = orig_terms;
                    }
                    if (RequestSpecificValues.Current_Mode.Search_Type == Search_Type_Enum.Basic)
                    {
                        List<string> output_terms = new List<string>();
                        List<string> output_fields = new List<string>();
                        SobekCM_Assistant.Split_Clean_Search_Terms_Fields(RequestSpecificValues.Current_Mode.Search_String, RequestSpecificValues.Current_Mode.Search_Fields, RequestSpecificValues.Current_Mode.Search_Type, output_terms, output_fields, UI_ApplicationCache_Gateway.Search_Stop_Words, RequestSpecificValues.Current_Mode.Search_Precision, ',');

                        string original_search = RequestSpecificValues.Current_Mode.Search_String;
                        RequestSpecificValues.Current_Mode.Search_Type = Search_Type_Enum.Advanced;
                        StringBuilder term_builder = new StringBuilder();
                        foreach (string thisTerm in output_terms)
                        {
                            if (term_builder.Length > 0)
                                term_builder.Append(",");
                            term_builder.Append(thisTerm);
                        }
                        StringBuilder field_builder = new StringBuilder();
                        foreach (string thisField in output_fields)
                        {
                            if (field_builder.Length > 0)
                                field_builder.Append(",");
                            field_builder.Append(thisField);
                        }
                        RequestSpecificValues.Current_Mode.Search_Fields = field_builder.ToString();
                        RequestSpecificValues.Current_Mode.Search_String = term_builder.ToString();

                        RequestSpecificValues.Current_Mode.Search_Fields = RequestSpecificValues.Current_Mode.Search_Fields + ",<%CODE%>";
                        RequestSpecificValues.Current_Mode.Search_String = RequestSpecificValues.Current_Mode.Search_String + ",<%VALUE%>";
                        url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("%3c%25", "<%").Replace("%25%3e", "%>").Replace("<%VALUE%>", "\"<%VALUE%>\"");

                        RequestSpecificValues.Current_Mode.Search_Type = Search_Type_Enum.Basic;
                        RequestSpecificValues.Current_Mode.Search_Fields = String.Empty;
                        RequestSpecificValues.Current_Mode.Search_String = original_search;

                    }
                }
                builder.AppendLine("      var stem_url = '" + url + "';");
                builder.AppendLine("      var new_url = stem_url.replace('<%CODE%>', code).replace('<%VALUE%>', new_value);");
                builder.AppendLine("      window.location.href = new_url;");
                builder.AppendLine("      return false;");
                builder.AppendLine("    }");
                builder.AppendLine("  //]]>");
                builder.AppendLine("</script>");
                builder.AppendLine();

                builder.AppendLine("<div class=\"sbkPrsw_FacetColumn\">");
                builder.AppendLine("<div class=\"sbkPrsw_FacetColumnTitle\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("NARROW RESULTS BY", RequestSpecificValues.Current_Mode.Language) + ":</div>");


                // Add the aggregation information first
                if (((RequestSpecificValues.Current_Mode.Aggregation.Length == 0) || (RequestSpecificValues.Current_Mode.Aggregation == "all")) && (RequestSpecificValues.Results_Statistics.Aggregation_Facets_Count > 0))
                {
                    string title = collection;
                    const int FACET_INDEX = 0;
                    int facet_count = 0;
                    int total_facets_to_show = MINIMIZED_FACET_COUNT;
                    char other_sort_type = '2';
                    char other_show_type = '1';
                    if ((facetInformation[FACET_INDEX] == '1') || (facetInformation[FACET_INDEX] == '3'))
                    {
                        total_facets_to_show = MAXIMIZED_FACET_COUNT;
                    }

                    string resort_image = "2_to_1.gif";
                    string sort_instructions = sort_by_frequency;
                    switch (facetInformation[FACET_INDEX])
                    {
                        case '0':
                            other_sort_type = '2';
                            other_show_type = '1';
                            sort_instructions = sort_alphabetically;
                            break;

                        case '1':
                            other_sort_type = '3';
                            other_show_type = '0';
                            sort_instructions = sort_alphabetically;
                            break;

                        case '2':
                            other_sort_type = '0';
                            other_show_type = '3';
                            resort_image = "a_to_z.gif";
                            break;

                        case '3':
                            other_sort_type = '1';
                            other_show_type = '2';
                            resort_image = "a_to_z.gif";
                            break;
                    }

                    builder.AppendLine("<div class=\"sbkPrsw_FacetBoxTitle\">" + title + "</div>");
                    builder.AppendLine("<div class=\"sbkPrsw_FacetBox\">");
                    if (RequestSpecificValues.Results_Statistics.Aggregation_Facets.Count > 1)
                        builder.AppendLine("<div class=\"sbkPrsw_FacetReorder\"><a href=\"\" onclick=\"return set_facet(" + FACET_INDEX + ",'" + other_sort_type + "');\" title=\"" + sort_instructions + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "design/skins/" + RequestSpecificValues.Current_Mode.Base_Skin + "/buttons/" + resort_image + "\" alt=\"RESORT\" /></a></div>");
                    if ((facetInformation[FACET_INDEX] == '2') || (facetInformation[FACET_INDEX] == '3'))
                    {
                        SortedList<string, string> order_facets = new SortedList<string, string>();
                        while ((facet_count < total_facets_to_show) && (facet_count < RequestSpecificValues.Results_Statistics.Aggregation_Facets.Count))
                        {
                            if (RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Code.ToLower() != "iuf")
                            {
                                order_facets[RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Facet.ToUpper()] = "<a href=\"" + aggregation_url.Replace("<%AGGREGATION%>", RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Code.ToLower()) + "\">" + RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Facet + "</a> ( " + RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Frequency + " ) <br />";
                            }
                            facet_count++;
                        }
                        foreach (string html in order_facets.Values)
                        {
                            builder.AppendLine(html);
                        }
                    }
                    else
                    {
                        while ((facet_count < total_facets_to_show) && (facet_count < RequestSpecificValues.Results_Statistics.Aggregation_Facets.Count))
                        {
                            if (RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Code.ToLower() != "iuf")
                            {
                                builder.AppendLine("<a href=\"" + aggregation_url.Replace("<%AGGREGATION%>", RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Code.ToLower()) + "\">" + RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Facet + "</a> ( " + RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Frequency + " ) <br />");
                            }
                            facet_count++;
                        }
                    }
                    if (facet_count > MINIMIZED_FACET_COUNT)
                    {
                        builder.AppendLine("<div class=\"sbkPrsw_ShowHideFacets\"><a href=\"\" onclick=\"return set_facet(" + FACET_INDEX + ",'" + other_show_type + "');\">&lt;&lt; " + show_less + " &nbsp; &nbsp;</a></div>");
                    }
                    else
                    {
                        if (facet_count < RequestSpecificValues.Results_Statistics.Aggregation_Facets.Count)
                        {
                            builder.AppendLine("<div class=\"sbkPrsw_ShowHideFacets\"><a href=\"\" onclick=\"return set_facet(" + FACET_INDEX + ",'" + other_show_type + "');\">" + show_more + " &gt;&gt; &nbsp;</a></div>");
                        }
                    }
                    builder.AppendLine("</div>");
                }

                // Add the first facet information 
                if (RequestSpecificValues.Results_Statistics.First_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.First_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 1, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.First_Facets);
                    }
                }

                // Add the second facet information 
                if (RequestSpecificValues.Results_Statistics.Second_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Second_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 2, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Second_Facets);
                    }
                }

                // Add the third facet information 
                if (RequestSpecificValues.Results_Statistics.Third_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Third_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 3, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Third_Facets);
                    }
                }

                // Add the fourth facet information 
                if (RequestSpecificValues.Results_Statistics.Fourth_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Fourth_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 4, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Fourth_Facets);
                    }
                }

                // Add the fifth facet information 
                if (RequestSpecificValues.Results_Statistics.Fifth_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Fifth_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 5, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Fifth_Facets);
                    }
                }

                // Add the sixth facet information 
                if (RequestSpecificValues.Results_Statistics.Sixth_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Sixth_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 6, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Sixth_Facets);
                    }
                }

                // Add the seventh facet information 
                if (RequestSpecificValues.Results_Statistics.Seventh_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Seventh_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 7, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Seventh_Facets);
                    }
                }

                // Add the eighth facet information 
                if (RequestSpecificValues.Results_Statistics.Eighth_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Eighth_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 8, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Eighth_Facets);
                    }
                }

                builder.AppendLine("</div>");

                #endregion
            }
            else
            {
                #region mapbeta

                string collection = UI_ApplicationCache_Gateway.Translation.Get_Translation("Collection", RequestSpecificValues.Current_Mode.Language);
                string show_more = UI_ApplicationCache_Gateway.Translation.Get_Translation("Show More", RequestSpecificValues.Current_Mode.Language);
                string show_less = UI_ApplicationCache_Gateway.Translation.Get_Translation("Show Less", RequestSpecificValues.Current_Mode.Language);
                string sort_by_frequency = UI_ApplicationCache_Gateway.Translation.Get_Translation("Sort these facets by frequency", RequestSpecificValues.Current_Mode.Language);
                string sort_alphabetically = UI_ApplicationCache_Gateway.Translation.Get_Translation("Sort these facets alphabetically", RequestSpecificValues.Current_Mode.Language);

                #region js

                builder.AppendLine("<input type=\"hidden\" id=\"facet\" name=\"facet\" value=\"" + HttpUtility.HtmlEncode(facetInformation) + "\" />");

                builder.AppendLine("<script type=\"text/javascript\">");
                builder.AppendLine("  //<![CDATA[");
                builder.AppendLine("    function add_facet_callback(code, new_value) {");

                string url = String.Empty;
                string aggregation_url = String.Empty;

                if (RequestSpecificValues.Current_Mode.Mode == Display_Mode_Enum.Aggregation)  // browse info only
                {
                    Display_Mode_Enum displayMode = RequestSpecificValues.Current_Mode.Mode;
                    RequestSpecificValues.Current_Mode.Mode = Display_Mode_Enum.Results;
                    RequestSpecificValues.Current_Mode.Search_Type = Search_Type_Enum.Advanced;
                    RequestSpecificValues.Current_Mode.Search_Fields = "<%CODE%>";
                    RequestSpecificValues.Current_Mode.Search_String = "<%VALUE%>";
                    ushort page = RequestSpecificValues.Current_Mode.Page;
                    RequestSpecificValues.Current_Mode.Page = 1;
                    url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("%3c%25", "<%").Replace("%25%3e", "%>").Replace("<%VALUE%>", "\"<%VALUE%>\"");
                    RequestSpecificValues.Current_Mode.Mode = displayMode;
                    RequestSpecificValues.Current_Mode.Page = page;
                    RequestSpecificValues.Current_Mode.Search_Fields = String.Empty;
                    RequestSpecificValues.Current_Mode.Search_String = String.Empty;

                    if ((RequestSpecificValues.Current_Mode.Aggregation.Length == 0) || (RequestSpecificValues.Current_Mode.Aggregation == "all"))
                    {
                        RequestSpecificValues.Current_Mode.Aggregation = "<%AGGREGATION%>";
                        aggregation_url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode);
                        RequestSpecificValues.Current_Mode.Aggregation = String.Empty;
                    }
                }
                else
                {
                    if ((RequestSpecificValues.Current_Mode.Aggregation.Length == 0) || (RequestSpecificValues.Current_Mode.Aggregation == "all"))
                    {
                        RequestSpecificValues.Current_Mode.Aggregation = "<%AGGREGATION%>";
                        aggregation_url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode);
                        RequestSpecificValues.Current_Mode.Aggregation = String.Empty;
                    }

                    if (RequestSpecificValues.Current_Mode.Search_Type == Search_Type_Enum.Advanced)
                    {
                        string orig_field = RequestSpecificValues.Current_Mode.Search_Fields;
                        string orig_terms = RequestSpecificValues.Current_Mode.Search_String;
                        RequestSpecificValues.Current_Mode.Search_Fields = RequestSpecificValues.Current_Mode.Search_Fields + ",<%CODE%>";
                        RequestSpecificValues.Current_Mode.Search_String = RequestSpecificValues.Current_Mode.Search_String + ",<%VALUE%>";
                        ushort page = RequestSpecificValues.Current_Mode.Page;
                        RequestSpecificValues.Current_Mode.Page = 1;
                        url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("%3c%25", "<%").Replace("%25%3e", "%>").Replace("<%VALUE%>", "\"<%VALUE%>\"");
                        RequestSpecificValues.Current_Mode.Page = page;
                        RequestSpecificValues.Current_Mode.Search_Fields = orig_field;
                        RequestSpecificValues.Current_Mode.Search_String = orig_terms;
                    }
                    if (RequestSpecificValues.Current_Mode.Search_Type == Search_Type_Enum.Basic)
                    {
                        List<string> output_terms = new List<string>();
                        List<string> output_fields = new List<string>();
                        SobekCM_Assistant.Split_Clean_Search_Terms_Fields(RequestSpecificValues.Current_Mode.Search_String, RequestSpecificValues.Current_Mode.Search_Fields, RequestSpecificValues.Current_Mode.Search_Type, output_terms, output_fields, UI_ApplicationCache_Gateway.Search_Stop_Words, RequestSpecificValues.Current_Mode.Search_Precision, ',');

                        string original_search = RequestSpecificValues.Current_Mode.Search_String;
                        RequestSpecificValues.Current_Mode.Search_Type = Search_Type_Enum.Advanced;
                        StringBuilder term_builder = new StringBuilder();
                        foreach (string thisTerm in output_terms)
                        {
                            if (term_builder.Length > 0)
                                term_builder.Append(",");
                            term_builder.Append(thisTerm);
                        }
                        StringBuilder field_builder = new StringBuilder();
                        foreach (string thisField in output_fields)
                        {
                            if (field_builder.Length > 0)
                                field_builder.Append(",");
                            field_builder.Append(thisField);
                        }
                        RequestSpecificValues.Current_Mode.Search_Fields = field_builder.ToString();
                        RequestSpecificValues.Current_Mode.Search_String = term_builder.ToString();

                        RequestSpecificValues.Current_Mode.Search_Fields = RequestSpecificValues.Current_Mode.Search_Fields + ",<%CODE%>";
                        RequestSpecificValues.Current_Mode.Search_String = RequestSpecificValues.Current_Mode.Search_String + ",<%VALUE%>";
                        url = UrlWriterHelper.Redirect_URL(RequestSpecificValues.Current_Mode).Replace("%3c%25", "<%").Replace("%25%3e", "%>").Replace("<%VALUE%>", "\"<%VALUE%>\"");

                        RequestSpecificValues.Current_Mode.Search_Type = Search_Type_Enum.Basic;
                        RequestSpecificValues.Current_Mode.Search_Fields = String.Empty;
                        RequestSpecificValues.Current_Mode.Search_String = original_search;

                    }
                }
                builder.AppendLine("      var stem_url = '" + url + "';");
                builder.AppendLine("      var new_url = stem_url.replace('<%CODE%>', code).replace('<%VALUE%>', new_value);");
                builder.AppendLine("      //window.location.href = new_url;");
                builder.AppendLine("      //return false;");
                builder.AppendLine("      var new_url_hash = \"?t=\\\"\"+new_value+\"\\\"&f=\"+code;");
                builder.AppendLine("      window.location.hash = new_url_hash;");
                builder.AppendLine("    }");
                builder.AppendLine("  //]]>");
                builder.AppendLine("</script>");
                builder.AppendLine();

                #endregion

                builder.AppendLine("<div id=\"filterBox\" class=\"sbkPrsw_FacetColumn\">");

                #region filterbox

                builder.AppendLine("<div class=\"sbkPrsw_FacetColumnTitle\">" + UI_ApplicationCache_Gateway.Translation.Get_Translation("NARROW RESULTS BY", RequestSpecificValues.Current_Mode.Language) + ":</div>");
                
                // Add the aggregation information first
                if (((RequestSpecificValues.Current_Mode.Aggregation.Length == 0) || (RequestSpecificValues.Current_Mode.Aggregation == "all")) && (RequestSpecificValues.Results_Statistics.Aggregation_Facets_Count > 0))
                {
                    string title = collection;
                    const int FACET_INDEX = 0;
                    int facet_count = 0;
                    int total_facets_to_show = MINIMIZED_FACET_COUNT;
                    char other_sort_type = '2';
                    char other_show_type = '1';
                    if ((facetInformation[FACET_INDEX] == '1') || (facetInformation[FACET_INDEX] == '3'))
                    {
                        total_facets_to_show = MAXIMIZED_FACET_COUNT;
                    }

                    string resort_image = "2_to_1.gif";
                    string sort_instructions = sort_by_frequency;
                    switch (facetInformation[FACET_INDEX])
                    {
                        case '0':
                            other_sort_type = '2';
                            other_show_type = '1';
                            sort_instructions = sort_alphabetically;
                            break;

                        case '1':
                            other_sort_type = '3';
                            other_show_type = '0';
                            sort_instructions = sort_alphabetically;
                            break;

                        case '2':
                            other_sort_type = '0';
                            other_show_type = '3';
                            resort_image = "a_to_z.gif";
                            break;

                        case '3':
                            other_sort_type = '1';
                            other_show_type = '2';
                            resort_image = "a_to_z.gif";
                            break;
                    }

                    builder.AppendLine("<div class=\"sbkPrsw_FacetBoxTitle\">" + title + "</div>");
                    builder.AppendLine("<div class=\"sbkPrsw_FacetBox\">");
                    if (RequestSpecificValues.Results_Statistics.Aggregation_Facets.Count > 1)
                        builder.AppendLine("<div class=\"sbkPrsw_FacetReorder\"><a onclick=\"set_facet_callback(" + FACET_INDEX + ",'" + other_sort_type + "');\" title=\"" + sort_instructions + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "design/skins/" + RequestSpecificValues.Current_Mode.Base_Skin + "/buttons/" + resort_image + "\" alt=\"RESORT\" /></a></div>");
                    if ((facetInformation[FACET_INDEX] == '2') || (facetInformation[FACET_INDEX] == '3'))
                    {
                        SortedList<string, string> order_facets = new SortedList<string, string>();
                        while ((facet_count < total_facets_to_show) && (facet_count < RequestSpecificValues.Results_Statistics.Aggregation_Facets.Count))
                        {
                            if (RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Code.ToLower() != "iuf")
                            {
                                order_facets[RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Facet.ToUpper()] = "<a href=\"" + aggregation_url.Replace("<%AGGREGATION%>", RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Code.ToLower()) + "\">" + RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Facet + "</a> ( " + RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Frequency + " ) <br />";
                            }
                            facet_count++;
                        }
                        foreach (string html in order_facets.Values)
                        {
                            builder.AppendLine(html);
                        }
                    }
                    else
                    {
                        while ((facet_count < total_facets_to_show) && (facet_count < RequestSpecificValues.Results_Statistics.Aggregation_Facets.Count))
                        {
                            if (RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Code.ToLower() != "iuf")
                            {
                                builder.AppendLine("<a href=\"" + aggregation_url.Replace("<%AGGREGATION%>", RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Code.ToLower()) + "\">" + RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Facet + "</a> ( " + RequestSpecificValues.Results_Statistics.Aggregation_Facets[facet_count].Frequency + " ) <br />");
                            }
                            facet_count++;
                        }
                    }
                    if (facet_count > MINIMIZED_FACET_COUNT)
                    {
                        builder.AppendLine("<div class=\"sbkPrsw_ShowHideFacets\"><a onclick=\"set_facet_callback(" + FACET_INDEX + ",'" + other_show_type + "');\">&lt;&lt; " + show_less + " &nbsp; &nbsp;</a></div>");
                    }
                    else
                    {
                        if (facet_count < RequestSpecificValues.Results_Statistics.Aggregation_Facets.Count)
                        {
                            builder.AppendLine("<div class=\"sbkPrsw_ShowHideFacets\"><a onclick=\"set_facet_callback(" + FACET_INDEX + ",'" + other_show_type + "');\">" + show_more + " &gt;&gt; &nbsp;</a></div>");
                        }
                    }
                    builder.AppendLine("</div>");
                }

                #endregion

                #region add the filters

                List<string> FIDS = new List<string>();

                // Add the first facet information 
                if (RequestSpecificValues.Results_Statistics.First_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.First_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet_Callback(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 1, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.First_Facets);
                        FIDS.Add(field.Display_Term);
                    }
                }

                // Add the second facet information 
                if (RequestSpecificValues.Results_Statistics.Second_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Second_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet_Callback(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 2, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Second_Facets);
                        FIDS.Add(field.Display_Term);
                    }
                }

                // Add the third facet information 
                if (RequestSpecificValues.Results_Statistics.Third_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Third_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet_Callback(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 3, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Third_Facets);
                        FIDS.Add(field.Display_Term);
                    }
                }

                // Add the fourth facet information 
                if (RequestSpecificValues.Results_Statistics.Fourth_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Fourth_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet_Callback(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 4, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Fourth_Facets);
                        FIDS.Add(field.Display_Term);
                    }
                }

                // Add the fifth facet information 
                if (RequestSpecificValues.Results_Statistics.Fifth_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Fifth_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet_Callback(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 5, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Fifth_Facets);
                        FIDS.Add(field.Display_Term);
                    }
                }

                // Add the sixth facet information 
                if (RequestSpecificValues.Results_Statistics.Sixth_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Sixth_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet_Callback(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 6, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Sixth_Facets);
                        FIDS.Add(field.Display_Term);
                    }
                }

                // Add the seventh facet information 
                if (RequestSpecificValues.Results_Statistics.Seventh_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Seventh_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet_Callback(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 7, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Seventh_Facets);
                        FIDS.Add(field.Display_Term);
                    }
                }

                // Add the eighth facet information 
                if (RequestSpecificValues.Results_Statistics.Eighth_Facets_Count > 0)
                {
                    Metadata_Search_Field field = UI_ApplicationCache_Gateway.Settings.Metadata_Search_Field_By_ID(RequestSpecificValues.Results_Statistics.Eighth_Facets_MetadataTypeID);
                    if (field != null)
                    {
                        Add_Single_Facet_Callback(builder, UI_ApplicationCache_Gateway.Translation.Get_Translation(field.Facet_Term, RequestSpecificValues.Current_Mode.Language), field.Web_Code, show_less, show_more, 8, sort_by_frequency, sort_alphabetically, RequestSpecificValues.Results_Statistics.Eighth_Facets);
                        FIDS.Add(field.Display_Term);
                    }
                }

                #region FIDKey Support

                //create fid key hash and id and session state
                int FIDKeyHashSpecial = 0;
                foreach (string FID in FIDS)
                {
                    byte[] tempFIDChars = Encoding.ASCII.GetBytes(FID);
                    foreach (byte tempFIDChar in tempFIDChars)
                    {
                        FIDKeyHashSpecial += Convert.ToInt32(tempFIDChar);
                    }
                }
                //finish processing FIDkeyhash and store
                FIDKeyHashSpecial = Convert.ToInt32(FIDKeyHashSpecial * FIDS.Count);
                HttpContext.Current.Session["FIDKey"] = "FIDKey_" + FIDKeyHashSpecial.ToString();

                HttpContext.Current.Cache[HttpContext.Current.Session["FIDKey"].ToString()] = FIDS;

                #endregion
                
                #endregion

                builder.AppendLine("</div>");

                #endregion
            }

            return builder.ToString();

		}

        private void Add_Single_Facet(StringBuilder Builder, string Title, string SearchCode, string ShowLess, string ShowMore, int FacetIndex, string SortByFrequency, string SortAlphabetically, List<Search_Facet> Collection)
		{
			int facet_count = 0;
			int total_facets_to_show = MINIMIZED_FACET_COUNT;
			char other_sort_type = '2';
			char other_show_type = '1';
			if ((facetInformation[FacetIndex - 1] == '1') || ( facetInformation[FacetIndex - 1 ] == '3' ))
			{
				total_facets_to_show = MAXIMIZED_FACET_COUNT;
			}

			string resort_image = "2_to_1.gif";
			string sort_instructions = SortByFrequency;
			switch ( facetInformation[FacetIndex - 1])
			{
				case '0':
					other_sort_type = '2';
					other_show_type = '1';
					sort_instructions = SortAlphabetically;
					break;

				case '1':
					other_sort_type = '3';
					other_show_type = '0';
					sort_instructions = SortAlphabetically;
					break;

				case '2':
					other_sort_type = '0';
					other_show_type = '3';
					resort_image = "a_to_z.gif";
					break;

				case '3':
					other_sort_type = '1';
					other_show_type = '2';
					resort_image = "a_to_z.gif";
					break;
			}

			Builder.AppendLine("<div class=\"sbkPrsw_FacetBoxTitle\">" + Title + "</div>");
			Builder.AppendLine("<div class=\"sbkPrsw_FacetBox\">");
			if (Collection.Count > 1)
			{
				Builder.AppendLine("<div class=\"sbkPrsw_FacetReorder\"><a href=\"\" onclick=\"return set_facet(" + (FacetIndex - 1) + ",'" + other_sort_type + "');\" title=\"" + sort_instructions + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "design/skins/" + RequestSpecificValues.Current_Mode.Base_Skin + "/buttons/" + resort_image + "\" alt=\"RESORT\" /></a></div>");
			}
			if ((facetInformation[FacetIndex - 1] == '2') || (facetInformation[FacetIndex - 1] == '3'))
			{
				SortedList<string, string> order_facets = new SortedList<string, string>();
				while ((facet_count < total_facets_to_show) && (facet_count < Collection.Count))
				{
					order_facets[Collection[facet_count].Facet.ToUpper()] = "<a href=\"\" onclick=\"return add_facet('" + SearchCode + "','" + HttpUtility.HtmlEncode(Collection[facet_count].Facet.Replace("&", "")).Replace("'", "\\'").Replace(",", "").Replace("&", "") + "');\">" + Collection[facet_count].Facet.Replace("&", "&amp;") + "</a> ( " + Collection[facet_count].Frequency + " ) <br />";
					facet_count++;
				}
				foreach (string html in order_facets.Values)
				{
					Builder.AppendLine(html);
				}
			}
			else
			{
				while ((facet_count < total_facets_to_show) && (facet_count < Collection.Count))
				{
					Builder.AppendLine("<a href=\"\" onclick=\"return add_facet('" + SearchCode + "','" + HttpUtility.HtmlEncode(Collection[facet_count].Facet.Replace("&", "")).Replace("'", "\\'").Replace(",", "").Replace("&", "") + "');\">" + Collection[facet_count].Facet.Replace("&", "&amp;" ) + "</a> ( " + Collection[facet_count].Frequency + " ) <br />");
					facet_count++;
				}
			}
			if (facet_count > MINIMIZED_FACET_COUNT)
			{
				Builder.AppendLine("<div class=\"sbkPrsw_ShowHideFacets\"><a href=\"\" onclick=\"return set_facet(" + (FacetIndex - 1) + ",'" + other_show_type + "');\">&lt;&lt; " + ShowLess + " &nbsp; &nbsp;</a></div>");
			}
			else
			{
				if (facet_count < Collection.Count)
				{
					Builder.AppendLine("<div class=\"sbkPrsw_ShowHideFacets\"><a href=\"\" onclick=\"return set_facet(" + (FacetIndex - 1) + ",'" + other_show_type + "');\">" + ShowMore + " &gt;&gt; &nbsp;</a></div>");
				}
			}
			Builder.AppendLine("</div>");
		}

        private void Add_Single_Facet_Callback(StringBuilder Builder, string Title, string SearchCode, string ShowLess, string ShowMore, int FacetIndex, string SortByFrequency, string SortAlphabetically, List<Search_Facet> Collection)
        {
            int facet_count = 0;
            int total_facets_to_show = MINIMIZED_FACET_COUNT;
            char other_sort_type = '2';
            char other_show_type = '1';
            if ((facetInformation[FacetIndex - 1] == '1') || (facetInformation[FacetIndex - 1] == '3'))
            {
                total_facets_to_show = MAXIMIZED_FACET_COUNT;
            }

            string resort_image = "2_to_1.gif";
            string sort_instructions = SortByFrequency;
            switch (facetInformation[FacetIndex - 1])
            {
                case '0':
                    other_sort_type = '2';
                    other_show_type = '1';
                    sort_instructions = SortAlphabetically;
                    break;

                case '1':
                    other_sort_type = '3';
                    other_show_type = '0';
                    sort_instructions = SortAlphabetically;
                    break;

                case '2':
                    other_sort_type = '0';
                    other_show_type = '3';
                    resort_image = "a_to_z.gif";
                    break;

                case '3':
                    other_sort_type = '1';
                    other_show_type = '2';
                    resort_image = "a_to_z.gif";
                    break;
            }

            Builder.AppendLine("<div class=\"sbkPrsw_FacetBoxTitle\">" + Title + "</div>");
            Builder.AppendLine("<div class=\"sbkPrsw_FacetBox\"><ul>");
            if (Collection.Count > 1)
            {
                Builder.AppendLine("<div class=\"sbkPrsw_FacetReorder\"><a onclick=\"set_facet_callback(" + (FacetIndex - 1) + ",'" + other_sort_type + "');\" title=\"" + sort_instructions + "\"><img src=\"" + RequestSpecificValues.Current_Mode.Base_URL + "design/skins/" + RequestSpecificValues.Current_Mode.Base_Skin + "/buttons/" + resort_image + "\" alt=\"RESORT\" /></a></div>");
            }
            if ((facetInformation[FacetIndex - 1] == '2') || (facetInformation[FacetIndex - 1] == '3'))
            {
                SortedList<string, string> order_facets = new SortedList<string, string>();
                while ((facet_count < total_facets_to_show) && (facet_count < Collection.Count))
                {
                    order_facets[Collection[facet_count].Facet.ToUpper()] = "<li><a onclick=\"add_facet_callback('" + SearchCode + "','" + HttpUtility.HtmlEncode(Collection[facet_count].Facet.Replace("&", "")).Replace("'", "\\'").Replace(",", "").Replace("&", "") + "');\">" + Collection[facet_count].Facet.Replace("&", "&amp;") + "</a> ( " + Collection[facet_count].Frequency + " ) </li>";
                    facet_count++;
                }
                foreach (string html in order_facets.Values)
                {
                    Builder.AppendLine(html);
                }
            }
            else
            {
                while ((facet_count < total_facets_to_show) && (facet_count < Collection.Count))
                {
                    Builder.AppendLine("<li><a onclick=\"add_facet_callback('" + SearchCode + "','" + HttpUtility.HtmlEncode(Collection[facet_count].Facet.Replace("&", "")).Replace("'", "\\'").Replace(",", "").Replace("&", "") + "');\">" + Collection[facet_count].Facet.Replace("&", "&amp;") + "</a> ( " + Collection[facet_count].Frequency + " )</li>");
                    facet_count++;
                }
            }
            if (facet_count > MINIMIZED_FACET_COUNT)
            {
                Builder.AppendLine("<div class=\"sbkPrsw_ShowHideFacets loadmoreResults\"><a onclick=\"set_facet_callback(" + (FacetIndex - 1) + ",'" + other_show_type + "');\">&lt;&lt; " + ShowLess + " &nbsp; &nbsp;</a></div>");
            }
            else
            {
                if (facet_count < Collection.Count)
                {
                    Builder.AppendLine("<div class=\"sbkPrsw_ShowHideFacets loadmoreResults\"><a onclick=\"set_facet_callback(" + (FacetIndex - 1) + ",'" + other_show_type + "');\">" + ShowMore + " &gt;&gt; &nbsp;</a></div>");
                }
            }
            Builder.AppendLine("</ul></div>");
        }
		
        #endregion
	}
}
