﻿//#region Declarations

//global defines (do not change here)
var baseImagesDirURL;                   //holds the base image directory url
var mapDrawingManagerDisplayed;         //holds marker for drawing manager
var mapLayerActive;                     //holds the current map layer active
var prevMapLayerActive;                 //holds the previous active map layer
var actionActive;                       //holds the current active action
var prevActionActive;                   //holds the previous active action
var overlaysCurrentlyDisplayed;         //holds marker for overlays on map
var pageMode;                           //holds the page/viewer type
var mapCenter;                          //used to center map on load
var mapControlsDisplayed;               //by default, are map controls displayed (true/false)
var defaultDisplayDrawingMangerTool;    //by default, is the drawingmanger displayed (true/false)
var toolboxDisplayed;                   //by default, is the toolbox displayed (true/false)
var toolbarDisplayed;                   //by default, is the toolbar open (yes/no)
var kmlDisplayed;                       //by default, is kml layer on (yes/no)
var kmlLayer;                           //must be pingable by google
var defaultZoomLevel;                   //zoom level, starting
var maxZoomLevel;                       //max zoom out, default (21=lowest level, 1=highest level)
var minZoomLevel_Terrain;               //max zoom in, terrain
var minZoomLevel_Satellite;             //max zoom in, sat + hybrid
var minZoomLevel_Roadmap;               //max zoom in, roadmap (default)
var minZoomLevel_BlockLot;              //max zoom in, used for special layers not having default of roadmap
var isCustomOverlay;                    //used to determine if other overlays (block/lot etc) //unknown
var preservedRotation;                  //rotation, default
var knobRotationValue;                  //rotation to display by default 
var preserveOpacity;                    //opacity, default value (0-1,1=opaque)
var overlaysOnMap = [];                 //holds all overlays
var csoi = 0;                           //hold current saved overlay index
var pendingOverlaySave = false;         //hold the marker to indicate if we need to save the overlay (this prevents a save if we already saved)
var oomCount = 0;                       //counts how many overlays are on the map
var searchCount = 0;                    //interates how many searches
var degree = 0;                         //initializing degree
var firstMarker = 0;                    //used to iterate if marker placement was the first (to prevent duplicates)
var overlayCount = 0;                   //iterater
var mapInBounds;                        //is the map in bounds
var searchResult;                       //will contain object
var circleCenter;                       //hold center point of circle
var markerCenter;                       //hold center of marker
var placerType;                         //type of data (marker,overlay,poi)
var poiType = [];                       //typle of poi (marker, circle, rectangle, polygon, polyline)
var poiKML = [];                        //pou kml layer (or other geographic info)
var poi_i = -1;                         //increment the poi count (used to make IDs and such)
var poiObj = [];                        //poi object placholder
var poiCoord = [];                      //poi coord placeholder
var poiDesc = [];                       //desc poi placeholder
var infowindow = [];                    //poi infowindow
var label = [];                         //used as label of poi
var globalPolyline;                     //unknown
var geocoder;                           //must define before use
var rectangle;                          //must define before use
var firstDraw = 0;                      //used to increment first drawing of rectangle
var getCoord;                           //used to store coords from marker
var itemMarker;                         //hold current item marker
var savingMarkerCenter;                 //holds marker coords to save
var CustomOverlay;                      //does nothing
var cCoordsFrozen = "no";               //used to freeze/unfreeze coordinate viewer
var incomingPointCenter = [];           //defined in c# to js on page
var incomingPointLabel = [];            //defined in c# to js on page
var incomingOverlayBounds = [];         //defined in c# to js on page
var incomingOverlaySourceURL = [];      //defined in c# to js on page
var incomingOverlayRotation = [];       //defined in c# to js on page
var ghostOverlayRectangle = [];         //holds ghost overlay rectangles (IE overlay hotspots)
var workingOverlayIndex = null;         //holds the index of the overlay we are working with (and saving)
var currentlyEditing = "no";            //tells us if we are editing anything
var currentTopZindex = 5;               //current top zindex (used in displaying overlays over overlays)
var savingOverlayIndex = [];            //holds index of the overlay we are saving
var savingOverlaySourceURL = [];        //hold the source url of the overlay to save
var savingOverlayBounds = [];           //holds bounds of the overlay we are saving
var savingOverlayRotation = [];         //holds rotation of the overlay we are saving
var ghosting = {                        //define options for ghosting (IE being invisible)
    strokeOpacity: 0.0,                 //make border invisible
    fillOpacity: 0.0,                   //make fill transparent
    editable: false,                    //sobek standard
    draggable: false,                   //sobek standard
    zindex: 5                           //perhaps higher?
};
var editable = {                        //define options for visible and editable
    editable: true,                     //sobek standard
    draggable: true,                    //sobek standard
    strokeOpacity: 0.2,                 //sobek standard
    strokeWeight: 1,                    //sobek standard
    fillOpacity: 0.0,                   //sobek standard 
    zindex: 5                           //sobek standard
};
CustomOverlay.prototype = new google.maps.OverlayView(); //used to display custom overlay
var strictBounds;

//#endregion

//setup everything with user defined options
function setupInterface(collection) {
    switch (collection) {
        case "default":
            baseImagesDirURL = "default/images/mapper/";                            //the default directory to the image files
            mapLayerActive = "Roadmap";                                             //what map layer is displayed
            mapDrawingManagerDisplayed = false;                                     //by default, is the drawing manager displayed (true/false)
            mapCenter = new google.maps.LatLng(29.6480, -82.3482);                  //used to center map on load
            mapControlsDisplayed = true;                                            //by default, are map controls displayed (true/false)
            defaultDisplayDrawingMangerTool = false;                                //by default, is the drawingmanger displayed (true/false)
            toolboxDisplayed = true;                                                //by default, is the toolbox displayed (true/false)
            toolbarDisplayed = true;                                                //by default, is the toolbar open (yes/no)
            kmlDisplayed = false;                                                   //by default, is kml layer on (yes/no)
            kmlLayer = new google.maps.KmlLayer("http://ufdc.ufl.edu/design/mapper/stAugParel_v6.kmz");  //must be pingable by google
            defaultZoomLevel = 13;                                                  //zoom level, starting
            maxZoomLevel = 2;                                                       //max zoom out, default (21=lowest level, 1=highest level)
            minZoomLevel_Terrain = 15;                                              //max zoom in, terrain
            minZoomLevel_Satellite = 20;                                            //max zoom in, sat + hybrid
            minZoomLevel_Roadmap = 21;                                              //max zoom in, roadmap (default)
            minZoomLevel_BlockLot = 19;                                             //max zoom in, used for special layers not having default of roadmap
            isCustomOverlay = false;                                                //used to determine if other overlays (block/lot etc) //unknown
            preservedRotation = 0;                                                  //rotation, default
            knobRotationValue = 0;                                                  //rotation to display by default 
            preserveOpacity = 0.75;                                                 //opacity, default value (0-1,1=opaque)
            strictBounds = null;                                                //set the bounds for this google map instance (set to null for no bounds)
            break;
        case "stAugustine":
            baseImagesDirURL = "default/images/mapper/";                            //the default directory to the image files
            mapDrawingManagerDisplayed = false;                                     //by default, is the drawing manager displayed (true/false)
            mapLayerActive = "Roadmap";                                             //what map layer is displayed
            mapCenter = new google.maps.LatLng(29.8944, -81.3147);                  //used to center map on load
            mapControlsDisplayed = true;                                            //by default, are map controls displayed (true/false)
            defaultDisplayDrawingMangerTool = false;                                //by default, is the drawingmanger displayed (true/false)
            toolboxDisplayed = true;                                                //by default, is the toolbox displayed (true/false)
            toolbarDisplayed = true;                                                //by default, is the toolbar open (yes/no)
            kmlDisplayed = false;                                                   //by default, is kml layer on (yes/no)
            //kmlLayer = new google.maps.KmlLayer("http://ufdc.ufl.edu/design/mapper/stAugParcel_v6.kmz");  //must be pingable by google
            kmlLayer = new google.maps.KmlLayer("http://ufdc.ufl.edu/design/mapper/stAugParcel_v6.kmz");  //must be pingable by google
            defaultZoomLevel = 14;                                                  //zoom level, starting
            maxZoomLevel = 10;                                                      //max zoom out, default (21=lowest level, 1=highest level)
            minZoomLevel_Terrain = 15;                                              //max zoom in, terrain
            minZoomLevel_Satellite = 20;                                            //max zoom in, sat + hybrid
            minZoomLevel_Roadmap = 21;                                              //max zoom in, roadmap (default)
            minZoomLevel_BlockLot = 19;                                             //max zoom in, used for special layers not having default of roadmap
            isCustomOverlay = false;                                                //used to determine if other overlays (block/lot etc) //unknown
            preservedRotation = 0;                                                  //rotation, default
            knobRotationValue = 0;                                                  //rotation to display by default 
            preserveOpacity = 0.35;                                                 //opacity, default value (0-1,1=opaque)
            strictBounds = new google.maps.LatLngBounds(                            //set the bounds for this google map instance
                new google.maps.LatLng(29.78225755812941, -81.4306640625),
                new google.maps.LatLng(29.99181288866604, -81.1917114257)
            );
            break;
        case "custom":
            baseImagesDirURL = "default/images/mapper/";                            //the default directory to the image files
            mapDrawingManagerDisplayed = false;                                     //by default, is the drawing manager displayed (true/false)
            mapLayerActive = "Roadmap";                                             //what map layer is displayed
            mapCenter = new google.maps.LatLng(29.6480, -82.3482);                  //used to center map on load
            mapControlsDisplayed = true;                                            //by default, are map controls displayed (true/false)
            defaultDisplayDrawingMangerTool = false;                                //by default, is the drawingmanger displayed (true/false)
            toolboxDisplayed = true;                                                //by default, is the toolbox displayed (true/false)
            toolbarDisplayed = true;                                                //by default, is the toolbar open (yes/no)
            kmlDisplayed = false;                                                   //by default, is kml layer on (yes/no)
            kmlLayer = new google.maps.KmlLayer("http://ufdc.ufl.edu/design/mapper/parcels_2012_kmz_fldor.kmz");  //must be pingable by google
            defaultZoomLevel = 13;                                                  //zoom level, starting
            maxZoomLevel = 10;                                                      //max zoom out, default (21=lowest level, 1=highest level)
            minZoomLevel_Terrain = 15;                                              //max zoom in, terrain
            minZoomLevel_Satellite = 20;                                            //max zoom in, sat + hybrid
            minZoomLevel_Roadmap = 21;                                              //max zoom in, roadmap (default)
            minZoomLevel_BlockLot = 19;                                             //max zoom in, used for special layers not having default of roadmap
            isCustomOverlay = false;                                                //used to determine if other overlays (block/lot etc) //unknown
            preservedRotation = 0;                                                  //rotation, default
            knobRotationValue = 0;                                                  //rotation to display by default 
            preserveOpacity = 0.75;                                                 //opacity, default value (0-1,1=opaque)
            strictBounds = new google.maps.LatLngBounds(                            //set the bounds for this google map instance
                new google.maps.LatLng(29.21570636285318, -82.87811279296875),
                new google.maps.LatLng(30.07978967039041, -81.76300048828125)
            );
            break;
        case "florida":
            baseImagesDirURL = "default/images/mapper/";                            //the default directory to the image files
            mapDrawingManagerDisplayed = false;                                     //by default, is the drawing manager displayed (true/false)
            mapLayerActive = "Roadmap";                                             //what map layer is displayed
            mapCenter = new google.maps.LatLng(29.6480, -82.3482);                  //used to center map on load
            mapControlsDisplayed = true;                                            //by default, are map controls displayed (true/false)
            defaultDisplayDrawingMangerTool = false;                                //by default, is the drawingmanger displayed (true/false)
            toolboxDisplayed = true;                                                //by default, is the toolbox displayed (true/false)
            toolbarDisplayed = true;                                                //by default, is the toolbar open (yes/no)
            kmlDisplayed = false;                                                   //by default, is kml layer on (yes/no)
            kmlLayer = new google.maps.KmlLayer("http://hlmatt.com/uf/kml/10.kml"); //must be pingable by google
            defaultZoomLevel = 13;                                                  //zoom level, starting
            maxZoomLevel = 1;                                                       //max zoom out, default (21=lowest level, 1=highest level)
            minZoomLevel_Terrain = 15;                                              //max zoom in, terrain
            minZoomLevel_Satellite = 20;                                            //max zoom in, sat + hybrid
            minZoomLevel_Roadmap = 21;                                              //max zoom in, roadmap (default)
            minZoomLevel_BlockLot = 19;                                             //max zoom in, used for special layers not having default of roadmap
            isCustomOverlay = false;                                                //used to determine if other overlays (block/lot etc) //unknown
            preservedRotation = 0;                                                  //rotation, default
            knobRotationValue = 0;                                                  //rotation to display by default 
            preserveOpacity = 0.75;                                                 //opacity, default value (0-1,1=opaque)
            
            strictBounds = new google.maps.LatLngBounds(                            //set the bounds for this google map instance
                //new google.maps.LatLng(30.69420636285318, -88.04311279296875), //fl nw
                //new google.maps.LatLng(25.06678967039041, -77.33330048828125) //fl se
                //new google.maps.LatLng(24.55531738915811, -81.78283295288095), //fl sw
                //new google.maps.LatLng(30.79109834517092, -81.53709923706058) //fl ne
                //new google.maps.LatLng(29.5862, -82.4146), //gville
                //new google.maps.LatLng(29.7490, -82.2106)
                new google.maps.LatLng(22.053908635225607, -86.18838838405613), //east coast
                new google.maps.LatLng(36.06512404320089, -76.72320000000003)
            );

            //strictBounds = new google.maps.LatLngBounds(                            //set the bounds for this google map instance
            //    new google.maps.LatLng(30.69420636285318, -88.04311279296875),
            //    new google.maps.LatLng(25.06678967039041, -77.33330048828125)
            //);
            break;
    }
}

var collectionTypeToLoad = "stAugustine"; //define collection settings to load
setupInterface(collectionTypeToLoad); //start the whole thing

//#region Define google map objects

google.maps.visualRefresh = true; //Enable the visual refresh (new gmaps)

//set the google map instance options
//supporting url: https://developers.google.com/maps/documentation/javascript/controls
var gmapPageDivId = "googleMap"; //get page div where google maps is to reside
var gmapOptions = {
    disableDefaultUI: false,                                    //set to false to start from a clean slate of map controls
    zoom: defaultZoomLevel,                                     //starting zoom level
    minZoom: maxZoomLevel,                                      //highest zoom out level
    center: mapCenter,                                          //default center point
    mapTypeId: google.maps.MapTypeId.ROADMAP,                   //default map type to display
    streetViewControl: false,                                   //is streetview active?
    tilt: 0,                                                    //set to 0 to disable 45 degree tilt
    zoomControl: false,                                          //is zoom control active?
    zoomControlOptions: {
        style: google.maps.ZoomControlStyle.SMALL,              //zoom control style
        position: google.maps.ControlPosition.LEFT_TOP          //zoom control position 
    },
    panControl: false,                                           //pan control active
    panControlOptions: {
        position: google.maps.ControlPosition.LEFT_TOP          //pan control position
    },
    mapTypeControl: false,                                       //map layer control active
    mapTypeControlOptions: {
        style: google.maps.MapTypeControlStyle.DROPDOWN_MENU,   //map layer control style
        position: google.maps.ControlPosition.RIGHT_TOP         //map layer control position
    },
    styles:                                                     //turn off all poi stylers (supporting url: https://developers.google.com/maps/documentation/javascript/reference#MapTypeStyleFeatureType)
    [
        {
            featureType: "poi", //poi
            elementType: "all", //or labels
            stylers: [{ visibility: "off" }]
        },
        //{
        //    featureType: "all", //poi
        //    elementType: "all", //labels
        //    stylers: [{ invert_lightness: "true" }]
        //},
        {
            featureType: "transit", //poi
            elementType: "labels", //labels
            stylers: [{ visibility: "off" }]
        }
    ]
    
};

//define drawing manager for this google maps instance
//support url: https://developers.google.com/maps/documentation/javascript/3.exp/reference#DrawingManager
var drawingManager = new google.maps.drawing.DrawingManager({
    //drawingMode: google.maps.drawing.OverlayType.MARKER, //set default/start type
    drawingControl: false,
    drawingControlOptions: {
        position: google.maps.ControlPosition.TOP_CENTER,
        drawingModes: [
          google.maps.drawing.OverlayType.MARKER,
          google.maps.drawing.OverlayType.CIRCLE,
          google.maps.drawing.OverlayType.RECTANGLE,
          google.maps.drawing.OverlayType.POLYGON,
          google.maps.drawing.OverlayType.POLYLINE
        ]
    },
    markerOptions: {
        draggable: true,
        zIndex: 5
    },
    circleOptions: {
        editable: true,
        draggable: true,
        zIndex: 5
    },
    polygonOptions: {
        editable: true,
        draggable: true,
        zIndex: 5
    },
    polylineOptions: {
        editable: true,
        draggable: true,
        zIndex: 5
    },
    rectangleOptions: {
        editable: true,
        draggable: true,
        zIndex: 5
    }
});
drawingManager.setOptions({
    drawingControl: true, drawingControlOptions: {
        position: google.maps.ControlPosition.RIGHT_TOP,
        drawingModes: [
            google.maps.drawing.OverlayType.MARKER,
            google.maps.drawing.OverlayType.CIRCLE,
            google.maps.drawing.OverlayType.RECTANGLE,
            google.maps.drawing.OverlayType.POLYGON,
            google.maps.drawing.OverlayType.POLYLINE
        ]
    }
});
kmlLayer.setOptions({ suppressInfoWindows: true });

//define custom copyright control
//supporting url: https://developers.google.com/maps/documentation/javascript/controls#CustomControls
var copyrightNode = document.createElement('div');
copyrightNode.id = 'copyright-control';
copyrightNode.style.fontSize = '10px';
copyrightNode.style.color = '#333333';
copyrightNode.style.fontFamily = 'Arial, sans-serif';
copyrightNode.style.margin = '0 2px 2px 0';
copyrightNode.style.whiteSpace = 'nowrap';
copyrightNode.index = 0;
copyrightNode.style.backgroundColor = '#FFFFFF';
copyrightNode.style.opacity = 0.75;
copyrightNode.innerHTML = L1; //localization copyright

//define cursor lat long tool custom control
//supporting url: https://developers.google.com/maps/documentation/javascript/controls#CustomControls
var cursorLatLongTool = document.createElement('div');
cursorLatLongTool.id = 'cursorLatLongTool';
cursorLatLongTool.style.fontSize = '10px';
cursorLatLongTool.style.color = '#333333';
cursorLatLongTool.style.fontFamily = 'Arial, sans-serif';
cursorLatLongTool.style.margin = '0 2px 2px 0';
cursorLatLongTool.style.whiteSpace = 'nowrap';
cursorLatLongTool.index = 0;
cursorLatLongTool.style.backgroundColor = '#FFFFFF';
cursorLatLongTool.style.opacity = 0.75;
cursorLatLongTool.innerHTML = L2; //localization cursor lat/long tool

//buffer zone top left (used to push map controls down)
//supporting url: https://developers.google.com/maps/documentation/javascript/controls#CustomControls
toolbarBufferZone1 = document.createElement('div');
toolbarBufferZone1.id = 'toolbarBufferZone1';
toolbarBufferZone1.style.height = '50px';

//buffer zone top right
//supporting url: https://developers.google.com/maps/documentation/javascript/controls#CustomControls
toolbarBufferZone2 = document.createElement('div');
toolbarBufferZone2.id = 'toolbarBufferZone2';
toolbarBufferZone2.style.height = '50px';

//#endregion

function initialize() {

    //alert(document.documentElement.clientHeight);

    var totalPX = document.documentElement.clientHeight;
    var headerPX = 83;
    var bodyPX = totalPX - headerPX;

    var percentOfHeight = Math.round((bodyPX / totalPX)*100);

    document.getElementById("container").style.height = percentOfHeight +"%";

    //alert(percentOfHeight);
    

    //initialize google map objects
    map = new google.maps.Map(document.getElementById(gmapPageDivId), gmapOptions);                             //initialize map    
    map.controls[google.maps.ControlPosition.RIGHT_BOTTOM].push(copyrightNode);                                 //initialize custom copyright
    map.controls[google.maps.ControlPosition.BOTTOM_LEFT].push(cursorLatLongTool);                              //initialize cursor lat long tool
    map.controls[google.maps.ControlPosition.TOP_LEFT].push(toolbarBufferZone1);                                //initialize spacer
    map.controls[google.maps.ControlPosition.TOP_RIGHT].push(toolbarBufferZone2);                               //intialize spacer
    drawingManager.setMap(map);                                                                                 //initialize drawing manager
    drawingManager.setMap(null);                                                                                //initialize drawing manager (hide)
    geocoder = new google.maps.Geocoder();                                                                      //initialize geocoder
    
    //#region Google Specific Listeners  

    //initialize drawingmanger listeners
    google.maps.event.addListener(drawingManager, 'markercomplete', function (marker) {
        testBounds(); //are we still in the bounds 
        if (placerType == "item") {
            //used to prevent multi markers
            if (firstMarker > 0) {
                itemMarker.setMap(null);
                drawingManager.setDrawingMode(null); //only place one at a time
            } else {
                firstMarker++;
            }
            itemMarker = marker; //assign globally
            document.getElementById('content_toolbox_posItem').value = itemMarker.getPosition();
            savingMarkerCenter = itemMarker.getPosition(); //store coords to save
            codeLatLng(itemMarker.getPosition());
        }

        if (placerType == "poi") {
            poi_i++;

            label[poi_i] = new MarkerWithLabel({
                position: marker.getPosition(), //position of real marker
                map: map,
                zIndex: 2,
                labelContent: poi_i + 1, //the current user count
                labelAnchor: new google.maps.Point(15, 0),
                labelClass: "labels", // the CSS class for the label
                labelStyle: { opacity: 0.75 },
                icon: {} //initialize to nothing so no marker shows
            });

            poiObj[poi_i] = marker;
            poiType[poi_i] = "marker";
            var poiId = poi_i + 1;
            var poiDescTemp = L_Marker;
            document.getElementById("poiList").innerHTML += "<div id=\"poi" + poi_i + "\" class=\"poiListItem\"> " + poiId + ". " + poiDescTemp + " <div class=\"poiActionButton\"><a href=\"#\" onclick=\"poiEditMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "edit.png\"/></a>" + " <a id=\"poiToggle" + poi_i + "\" href=\"#\"><img src=\"" + baseURL + baseImagesDirURL + "sub.png\" onclick=\"poiHideMe(" + poi_i + ");\" /></a>" + " <a href=\"#\" onclick=\"poiDeleteMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "delete.png\"/></a></div></div>";
            var contentString = "<textarea id=\"poiDesc" + poi_i + "\" class=\"descPOI\" placeholder=\"" + L3 + "\"></textarea> <br/>" + " <div class=\"buttonPOIDesc\" id=\"poiGetDesc\" onClick=\"poiGetDesc(" + poi_i + ");\">Save</div>";
            infowindow[poi_i] = new google.maps.InfoWindow({
                content: contentString,
                pixelOffset: new google.maps.Size(0, 0)
            });
            infowindow[poi_i].open(map, poiObj[poi_i]);
        }

        google.maps.event.addListener(marker, 'dragstart', function () {
            
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) { 
                    if (poiObj[i] == this) {
                        infowindow[i].setMap(null);
                        label[i].setMap(null);
                    }
                }
            }
        });
        google.maps.event.addListener(marker, 'dragend', function () {
            if (placerType == "item") {
                document.getElementById('content_toolbox_posItem').value = marker.getPosition();
                codeLatLng(marker.getPosition());
            }
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setOptions({ position: marker.getPosition(), pixelOffset: new google.maps.Size(0, -40) });
                        infowindow[i].open(map);
                        label[i].setPosition(marker.getPosition());
                        label[i].setMap(map);
                    }
                }
            }
        });
        google.maps.event.addListener(marker, 'click', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setOptions({ position: marker.getPosition(), pixelOffset: new google.maps.Size(0, -40) });
                        infowindow[i].open(map);
                    }
                }
            }
        });
    });
    google.maps.event.addListener(drawingManager, 'circlecomplete', function (circle) {
        testBounds();
        if (placerType == "poi") {
            poi_i++;

            label[poi_i] = new MarkerWithLabel({
                position: circle.getCenter(), //position of real marker
                zIndex: 2,
                map: map,
                labelContent: poi_i + 1, //the current user count
                labelAnchor: new google.maps.Point(15, 0),
                labelClass: "labels", // the CSS class for the label
                labelStyle: { opacity: 0.75 },
                icon: {} //initialize to nothing so no marker shows
            });

            var poiId = poi_i + 1;
            poiObj[poi_i] = circle;
            poiType[poi_i] = "circle";
            var poiDescTemp = L_Circle;
            document.getElementById("poiList").innerHTML += "<div id=\"poi" + poi_i + "\" class=\"poiListItem\"> " + poiId + ". " + poiDescTemp + " <div class=\"poiActionButton\"><a href=\"#\" onclick=\"poiEditMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "edit.png\"/></a> <a id=\"poiToggle" + poi_i + "\" href=\"#\"><img src=\"" + baseURL + baseImagesDirURL + "sub.png\" onclick=\"poiHideMe(" + poi_i + ");\" /></a> <a href=\"#\" onclick=\"poiDeleteMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "delete.png\"/></a></div></div>";
            var contentString = "<textarea id=\"poiDesc" + poi_i + "\" class=\"descPOI\" placeholder=\"" + L3 + "\"></textarea> <br/> <div class=\"buttonPOIDesc\" id=\"poiGetDesc\" onClick=\"poiGetDesc(" + poi_i + ");\">Save</div>";
            infowindow[poi_i] = new google.maps.InfoWindow({
                content: contentString
            });
            infowindow[poi_i].setPosition(circle.getCenter());
            infowindow[poi_i].open(map);
        }

        google.maps.event.addListener(circle, 'dragstart', function () {

            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setMap(null);
                        label[i].setMap(null);
                    }
                }
            }
        });
        google.maps.event.addListener(circle, 'drag', function () {
            //used to get the center point for lat/long tool
            circleCenter = circle.getCenter();
            var str = circle.getCenter().toString();
            var cLatV = str.replace("(", "").replace(")", "").split(",", 1);
            var cLongV = str.replace(cLatV, "").replace("(", "").replace(")", "").replace(",", ""); //is this better than passing into array?s
            if (cLatV.indexOf("-") != 0) {
                latH = "N";
            } else {
                latH = "S";
            }
            if (cLongV.indexOf("-") != 0) {
                longH = "W";
            } else {
                longH = "E";
            }
            cLat.innerHTML = cLatV + " (" + latH + ")";
            cLong.innerHTML = cLongV + " (" + longH + ")";           
        });
        google.maps.event.addListener(circle, 'dragend', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(circle.getCenter());
                        infowindow[i].open(map);
                        label[i].setPosition(circle.getCenter());
                        label[i].setMap(map);
                    }
                }
            }
        });
        google.maps.event.addListener(circle, 'click', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(circle.getCenter());
                        infowindow[i].open(map);
                    }
                }
            }
        });
    });
    google.maps.event.addListener(drawingManager, 'rectanglecomplete', function (rectangle) {
        
        testBounds();                                   //check the bounds to make sure you havent strayed too far away

        if (placerType == "poi") {
            poi_i++;

            label[poi_i] = new MarkerWithLabel({
                position: rectangle.getBounds().getCenter(), //position of real marker
                zIndex: 2,
                map: map,
                labelContent: poi_i + 1, //the current user count
                labelAnchor: new google.maps.Point(15, 0),
                labelClass: "labels", // the CSS class for the label
                labelStyle: { opacity: 0.75 },
                icon: {} //initialize to nothing so no marker shows
            });

            var poiId = poi_i + 1;
            poiObj[poi_i] = rectangle;
            poiType[poi_i] = "rectangle";
            var poiDescTemp = L_Rectangle;
            document.getElementById("poiList").innerHTML += "<div id=\"poi" + poi_i + "\" class=\"poiListItem\"> " + poiId + ". " + poiDescTemp + " <div class=\"poiActionButton\"><a href=\"#\" onclick=\"poiEditMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "edit.png\"/></a> <a id=\"poiToggle" + poi_i + "\" href=\"#\"><img src=\"" + baseURL + baseImagesDirURL + "sub.png\" onclick=\"poiHideMe(" + poi_i + ");\" /></a> <a href=\"#\" onclick=\"poiDeleteMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "delete.png\"/></a></div></div>";
            var contentString = "<textarea id=\"poiDesc" + poi_i + "\" class=\"descPOI\" placeholder=\"" + L3 + "\"></textarea> <br/> <div class=\"buttonPOIDesc\" id=\"poiGetDesc\" onClick=\"poiGetDesc(" + poi_i + ");\">Save</div>";
            infowindow[poi_i] = new google.maps.InfoWindow({
                content: contentString
            });
            infowindow[poi_i].setPosition(rectangle.getBounds().getCenter());
            infowindow[poi_i].open(map);
        }
        
        google.maps.event.addListener(rectangle, 'bounds_changed', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(rectangle.getBounds().getCenter());
                        infowindow[i].setMap(map);
                        label[i].setPosition(rectangle.getBounds().getCenter());
                        label[i].setMap(map);
                    }
                }   
            }
        });
        google.maps.event.addListener(rectangle, 'dragstart', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setMap(null);
                        label[i].setMap(null);
                    }
                }
            }
        });
        google.maps.event.addListener(rectangle, 'drag', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setMap(null);
                        label[i].setMap(null);
                    }
                }
            }
            //used to get center point for lat/long tool
            var str = rectangle.getBounds().getCenter().toString();
            var cLatV = str.replace("(", "").replace(")", "").split(",", 1);
            var cLongV = str.replace(cLatV, "").replace("(", "").replace(")", "").replace(",", "");
            if (cLatV.indexOf("-") != 0) {
                latH = "N";
            } else {
                latH = "S";
            }
            if (cLongV.indexOf("-") != 0) {
                longH = "W";
            } else {
                longH = "E";
            }
            cLat.innerHTML = cLatV + " (" + latH + ")";
            cLong.innerHTML = cLongV + " (" + longH + ")";
        });
        google.maps.event.addListener(rectangle, 'dragend', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(rectangle.getBounds().getCenter());
                        infowindow[i].open(map);
                        label[i].setPosition(rectangle.getBounds().getCenter());
                        label[i].setMap(map);
                    }
                }
            }
        });
        google.maps.event.addListener(rectangle, 'click', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(rectangle.getBounds().getCenter());
                        infowindow[i].open(map);
                    }
                }
            }
        });
        
    });
    google.maps.event.addListener(drawingManager, 'polygoncomplete', function (polygon) {
        testBounds();
        if (placerType == "poi") {
            poi_i++;

            label[poi_i] = new MarkerWithLabel({
                position: polygonCenter(polygon), //position of real marker
                zIndex: 2,
                map: map,
                labelContent: poi_i + 1, //the current user count
                labelAnchor: new google.maps.Point(15, 0),
                labelClass: "labels", // the CSS class for the label
                labelStyle: { opacity: 0.75 },
                icon: {} //initialize to nothing so no marker shows
            });

            var poiId = poi_i + 1;
            poiObj[poi_i] = polygon;
            poiType[poi_i] = "polygon";
            var poiDescTemp = L_Polygon;
            document.getElementById("poiList").innerHTML += "<div id=\"poi" + poi_i + "\" class=\"poiListItem\"> " + poiId + ". " + poiDescTemp + " <div class=\"poiActionButton\"><a href=\"#\" onclick=\"poiEditMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "edit.png\"/></a> <a id=\"poiToggle" + poi_i + "\" href=\"#\"><img src=\"" + baseURL + baseImagesDirURL + "sub.png\" onclick=\"poiHideMe(" + poi_i + ");\" /></a> <a href=\"#\" onclick=\"poiDeleteMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "delete.png\"/></a></div></div>";
            var contentString = "<textarea id=\"poiDesc" + poi_i + "\" class=\"descPOI\" placeholder=\"" + L3 + "\"></textarea> <br/> <div class=\"buttonPOIDesc\" id=\"poiGetDesc\" onClick=\"poiGetDesc(" + poi_i + ");\">Save</div>";
            infowindow[poi_i] = new google.maps.InfoWindow({
                content: contentString
            });
            infowindow[poi_i].setPosition(polygonCenter(polygon));
            infowindow[poi_i].open(map);
        }
        google.maps.event.addListener(polygon.getPath(), 'set_at', function () { //if bounds change
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(polygonCenter(polygon));
                        infowindow[i].setMap(map);
                        label[i].setPosition(polygonCenter(polygon));
                        label[i].setMap(null);
                    }
                }
            }
        });
        google.maps.event.addListener(polygon, 'dragstart', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setMap(null);
                        label[i].setMap(null);
                    }
                }
            }
        });
        google.maps.event.addListener(polygon, 'drag', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setMap(null);
                        label[i].setMap(null);
                    }
                }
            }
            //used for lat/long tool
            var str = polygonCenter(polygon).toString();
            var cLatV = str.replace("(", "").replace(")", "").split(",", 1);
            var cLongV = str.replace(cLatV, "").replace("(", "").replace(")", "").replace(",", ""); //is this better than passing into array?s
            if (cLatV.indexOf("-") != 0) {
                latH = "N";
            } else {
                latH = "S";
            }
            if (cLongV.indexOf("-") != 0) {
                longH = "W";
            } else {
                longH = "E";
            }
            cLat.innerHTML = cLatV + " (" + latH + ")";
            cLong.innerHTML = cLongV + " (" + longH + ")";
        });
        google.maps.event.addListener(polygon, 'dragend', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(polygonCenter(polygon));
                        infowindow[i].open(map);
                        label[i].setPosition(polygonCenter(polygon));
                        label[i].setMap(map);
                    }
                }
            }
        });
        google.maps.event.addListener(polygon, 'click', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(polygonCenter(polygon));
                        infowindow[i].open(map);
                    }
                }
            }
        });
    });
    google.maps.event.addListener(drawingManager, 'polylinecomplete', function (polyline) {
        testBounds();
        if (placerType == "poi") {
            poi_i++;
            var poiId = poi_i + 1;
            poiObj[poi_i] = polyline;
            poiType[poi_i] = "polyline";
            var poiDescTemp = L_Line;
            document.getElementById("poiList").innerHTML += "<div id=\"poi" + poi_i + "\" class=\"poiListItem\"> " + poiId + ". " + poiDescTemp + " <div class=\"poiActionButton\"><a href=\"#\" onclick=\"poiEditMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "edit.png\"/></a> <a id=\"poiToggle" + poi_i + "\" href=\"#\"><img src=\"" + baseURL + baseImagesDirURL + "sub.png\" onclick=\"poiHideMe(" + poi_i + ");\" /></a> <a href=\"#\" onclick=\"poiDeleteMe(" + poi_i + ");\"><img src=\"" + baseURL + baseImagesDirURL + "delete.png\"/></a></div></div>";
            var contentString = "<textarea id=\"poiDesc" + poi_i + "\" class=\"descPOI\" placeholder=\"" + L3 + "\"></textarea> <br/> <div class=\"buttonPOIDesc\" id=\"poiGetDesc\" onClick=\"poiGetDesc(" + poi_i + ");\">Save</div>";
            infowindow[poi_i] = new google.maps.InfoWindow({
                content: contentString
            });
            var bounds = new google.maps.LatLngBounds;
            polyline.getPath().forEach(function (latLng) { bounds.extend(latLng); });
            var polylineCenter = bounds.getCenter();
            infowindow[poi_i].setPosition(polylineCenter);
            infowindow[poi_i].open(map);

            label[poi_i] = new MarkerWithLabel({
                position: polylineCenter, //position of real marker
                zIndex: 2,
                map: map,
                labelContent: poiId, //the current user count
                labelAnchor: new google.maps.Point(15, 0),
                labelClass: "labels", // the CSS class for the label
                labelStyle: { opacity: 0.75 },
                icon: {} //initialize to nothing so no marker shows
            });

        }
        google.maps.event.addListener(polyline.getPath(), 'set_at', function () { //what is path?
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        var bounds = new google.maps.LatLngBounds;
                        polyline.getPath().forEach(function (latLng) { bounds.extend(latLng); });
                        var polylineCenter = bounds.getCenter();
                        infowindow[i].setPosition(polylineCenter);
                        infowindow[i].setMap(map);
                        label[i].setPosition(polylineCenter);
                        label[i].setMap(map);
                    }
                }
                
            }
        });
        google.maps.event.addListener(polyline, 'dragstart', function () {
            if (placerType == "poi") {
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setMap(null);
                        label[i].setMap(null);
                    }
                }
            }
        });
        google.maps.event.addListener(polyline, 'drag', function () {
            //used for lat/long tooll
            var bounds = new google.maps.LatLngBounds;
            polyline.getPath().forEach(function (latLng) { bounds.extend(latLng); });
            var polylineCenter = bounds.getCenter();
            var str = polylineCenter.toString();
            var cLatV = str.replace("(", "").replace(")", "").split(",", 1);
            var cLongV = str.replace(cLatV, "").replace("(", "").replace(")", "").replace(",", ""); //is this better than passing into array?s
            if (cLatV.indexOf("-") != 0) {
                latH = "N";
            } else {
                latH = "S";
            }
            if (cLongV.indexOf("-") != 0) {
                longH = "W";
            } else {
                longH = "E";
            }
            cLat.innerHTML = cLatV + " (" + latH + ")";
            cLong.innerHTML = cLongV + " (" + longH + ")";
        });
        google.maps.event.addListener(polyline, 'dragend', function () {
            if (placerType == "poi") {
                var bounds = new google.maps.LatLngBounds;
                polyline.getPath().forEach(function (latLng) { bounds.extend(latLng); });
                var polylineCenter = bounds.getCenter();
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(polylineCenter);
                        infowindow[i].open(map);
                        label[i].setPosition(polylineCenter);
                        label[i].setMap(map);
                    }
                }
                
            }
        });
        google.maps.event.addListener(polyline, 'click', function () {
            if (placerType == "poi") {
                var bounds = new google.maps.LatLngBounds;
                polyline.getPath().forEach(function (latLng) { bounds.extend(latLng); });
                var polylineCenter = bounds.getCenter();
                for (var i = 0; i < poiObj.length; i++) {
                    if (poiObj[i] == this) {
                        infowindow[i].setPosition(polylineCenter);
                        infowindow[i].open(map);
                    }
                }
                
            }
        });
    });
    
    //initialize map specific listeners
    
    //on right click stop drawing thing
    google.maps.event.addListener(map, 'rightclick', function () {
        drawingManager.setDrawingMode(null); //reset drawing manager no matter what
    });                                           
    
    //used to process lat/long points
    google.maps.event.addDomListener(map, 'mousemove', function (point) {

        if (cCoordsFrozen == "no") {
            //cCoord.innerHTML = point.latLng.toString(); //directly inject into page
            var str = point.latLng.toString();
            var cLatV = str.replace("(", "").replace(")", "").split(",", 1);
            var cLongV = str.replace(cLatV, "").replace("(", "").replace(")", "").replace(",", ""); //is this better than passing into array?s
            if (cLatV.indexOf("-") != 0) {
                latH = "N";
            } else {
                latH = "S";
            }
            if (cLongV.indexOf("-") != 0) {
                longH = "W";
            } else {
                longH = "E";
            }

            cLat.innerHTML = cLatV + " (" + latH + ")";
            cLong.innerHTML = cLongV + " (" + longH + ")";
        }
        
    });                                    //used to display cursor location via lat/long
    google.maps.event.addListener(map, 'dragend', function () {
        testBounds();
    });                                              //drag listener (for boundary test)
    google.maps.event.addListener(map, 'zoom_changed', function () {
        checkZoomLevel();
    });                                         //check the zoom level display message if out limits

    //when kml layer is clicked, get feature that was clicked
    google.maps.event.addListener(kmlLayer, 'click', function (kmlEvent) {
        var name = kmlEvent.featureData.name;
        displayMessage("ParcelID: " + name); //temp
    });                                           

    //#endregion
    
    initGeoObjects(); //initialize all the incoming geo obejects (the fcn is written via c#)
    
    google.maps.event.addListenerOnce(map, 'tilesloaded', function () {
        //this part runs when the mapobject is created and rendered
        initOptions(); //setup the graphical user interface (enhances visual effect to do all of this after map loads)
    });
    
    
}                         //on page load functions (mainly google map event listeners)

//Displays all the points sent from the C# code.
function displayIncomingPoints() {
    //go through and display points as long as there is a point to display (note, currently only supports one point)
    for (var i = 0; i < incomingPointCenter.length; i++) {
        firstMarker++;
        itemMarker = new google.maps.Marker({
            position: incomingPointCenter[i],
            map: map,
            draggable: true,
            title: incomingPointLabel[i]
        });
        document.getElementById('content_toolbox_posItem').value = itemMarker.getPosition();
        codeLatLng(itemMarker.getPosition());
        google.maps.event.addListener(itemMarker, 'dragend', function () {
            savingMarkerCenter = itemMarker.getPosition(); //store coords to save
            document.getElementById('content_toolbox_posItem').value = itemMarker.getPosition();
            codeLatLng(itemMarker.getPosition());
        });
    }
}

//Displays all the overlays sent from the C# code. Also calls displayGhostOverlayRectangle.
function displayIncomingOverlays() {
    for (var i = 0; i < incomingOverlayBounds.length; i++) {                                                                                //go through and display overlays as long as there is an overlay to display
        overlaysOnMap[i] = new CustomOverlay(i, incomingOverlayBounds[i], incomingOverlaySourceURL[i], map, incomingOverlayRotation[i]);    //create overlay with incoming
        overlaysOnMap[i].setMap(map);                                                                                                       //set the overlay to the map
        setGhostOverlay(i, incomingOverlayBounds[i]);                                                                                       //set hotspot on top of overlay
    }
    overlaysCurrentlyDisplayed = true;
}

//Creates and sets the ghost overlays (used to tie actions with actual overlay)
function setGhostOverlay(ghostIndex, ghostBounds) {
    
    //create ghost directly over an overlay
    ghostOverlayRectangle[ghostIndex] = new google.maps.Rectangle();        //init ghost
    ghostOverlayRectangle[ghostIndex].setOptions(ghosting);                 //set ghosting 
    ghostOverlayRectangle[ghostIndex].setBounds(ghostBounds);               //set bounds
    ghostOverlayRectangle[ghostIndex].setMap(map);                          //set to map
    
    //create listener for if clicked
    google.maps.event.addListener(ghostOverlayRectangle[ghostIndex], 'click', function () {
        if (pageMode == "edit") {
            if (currentlyEditing == "yes") {                                                            //if editing is being done, save
                cacheSaveOverlay(ghostIndex);                                                           //trigger a cache of current working overlay
                ghostOverlayRectangle[workingOverlayIndex].setOptions(ghosting);                        //set rectangle to ghosting
                currentlyEditing = "no";                                                                //reset editing marker
                preservedRotation = 0;                                                                  //reset preserved rotation
            }
            if (currentlyEditing == "no") {                                                             //if editing is not being done, start editing
                $("#toolbox").show();                                                                   //show the toolbox
                toolboxDisplayed = true;                                                                //mark that the toolbox is open
                $("#toolboxTabs").accordion({ active: 3 });                                             //open edit overlay tab in toolbox
                currentlyEditing = "yes";                                                               //enable editing marker
                workingOverlayIndex = ghostIndex;                                                       //set this overay as the one being e
                ghostOverlayRectangle[ghostIndex].setOptions(editable);                                 //show ghost
                currentTopZindex++;                                                                     //iterate top z index
                document.getElementById("overlay" + ghostIndex).style.zIndex = currentTopZindex;        //bring overlay to front
                ghostOverlayRectangle[ghostIndex].setOptions({ zIndex: currentTopZindex });             //bring ghost to front
                for (var i = 0; i < savingOverlayIndex.length; i++) {                                   //set rotation if the overlay was previously saved
                    if (ghostIndex == savingOverlayIndex[i]) {
                        preservedRotation = savingOverlayRotation[i];
                    }
                }
            }
        }
    });
    
    //set listener for bounds changed
    google.maps.event.addListener(ghostOverlayRectangle[ghostIndex], 'bounds_changed', function () {
        if (pageMode == "edit") {
            overlaysOnMap[ghostIndex].setMap(null);                                                                                                                                 //hide previous overlay
            overlaysOnMap[ghostIndex] = null;                                                                                                                                       //delete previous overlay values
            overlaysOnMap[ghostIndex] = new CustomOverlay(ghostIndex, ghostOverlayRectangle[ghostIndex].getBounds(), incomingOverlaySourceURL[ghostIndex], map, preservedRotation); //redraw the overlay within the new bounds
            overlaysOnMap[ghostIndex].setMap(map);                                                                                                                                  //set the overlay with new bounds to the map
            currentlyEditing = "yes";                                                                                                                                               //enable editing marker
            cacheSaveOverlay(ghostIndex);                                                                                                                                           //trigger a cache of current working overlay
        }
    });

}

//Stores the overlays to save and their associated data
function cacheSaveOverlay(index) {
    savingOverlayIndex[csoi] = workingOverlayIndex;                                         //set overlay index to save
    savingOverlaySourceURL[csoi] = incomingOverlaySourceURL[workingOverlayIndex];           //set source url to save
    savingOverlayBounds[csoi] = ghostOverlayRectangle[workingOverlayIndex].getBounds();     //set bounds to save
    savingOverlayRotation[csoi] = preservedRotation;                                        //set rotation to save
    if (savingOverlayIndex[csoi] != index) {                                                
        csoi++;                                                                             //iterate the current save overlay index   
    }
}

//Starts the creation of a custom overlay div which contains a rectangular image.
//Supporting URL: https://developers.google.com/maps/documentation/javascript/overlays#CustomOverlays
function CustomOverlay(id, bounds, image, map, rotation) {
    overlayCount++;                 //iterate how many overlays have been drawn
    this.bounds_ = bounds;          //set the bounds
    this.image_ = image;            //set source url
    this.map_ = map;                //set to map
    preservedRotation = rotation;   //set the rotation
    this.div_ = null;               //defines a property to hold the image's div. We'll actually create this div upon receipt of the onAdd() method so we'll leave it null for now.
    this.index_ = id;               //set the index/id of this overlay
}

//Continues support for adding an custom overlay
//Supporting URL: https://developers.google.com/maps/documentation/javascript/overlays#CustomOverlays
// Note: an overlay's receipt of onAdd() indicates that the map's panes are now available for attaching the overlay to the map via the DOM.
CustomOverlay.prototype.onAdd = function () {
  
    // Create the DIV and set some basic attributes.
    var div = document.createElement("div");
    div.id = "overlay" + this.index_;
    div.style.borderStyle = 'none';
    div.style.borderWidth = '0px';
    div.style.position = 'absolute';
    div.style.opacity = preserveOpacity;

    // Create an IMG element and attach it to the DIV.
    var img = document.createElement('img');
    img.src = this.image_;
    img.style.width = '100%';
    img.style.height = '100%';
    img.style.position = 'absolute';
    div.appendChild(img);

    // Set the overlay's div_ property to this DIV
    this.div_ = div;

    // We add an overlay to a map via one of the map's panes.
    // We'll add this overlay to the overlayLayer pane.
    var panes = this.getPanes();
    panes.overlayLayer.appendChild(div);
};

//Continues support for adding an custom overlay
//Supporting URL: https://developers.google.com/maps/documentation/javascript/overlays#CustomOverlays
CustomOverlay.prototype.draw = function () {
    // Size and position the overlay. We use a southwest and northeast
    // position of the overlay to peg it to the correct position and size.
    // We need to retrieve the projection from this overlay to do this.
    var overlayProjection = this.getProjection();

    // Retrieve the southwest and northeast coordinates of this overlay
    // in latlngs and convert them to pixels coordinates.
    // We'll use these coordinates to resize the DIV.
    var sw = overlayProjection.fromLatLngToDivPixel(this.bounds_.getSouthWest());
    var ne = overlayProjection.fromLatLngToDivPixel(this.bounds_.getNorthEast());

    // Resize the image's DIV to fit the indicated dimensions.
    var div = this.div_;
    div.style.left = sw.x + 'px';
    div.style.top = ne.y + 'px';
    div.style.width = (ne.x - sw.x) + 'px';
    div.style.height = (sw.y - ne.y) + 'px';

    //for a preserved rotation
    if (preservedRotation != 0) {
        keepRotate(preservedRotation);
    }
    
};

//Not currently used
//Supporting URL: https://developers.google.com/maps/documentation/javascript/overlays#CustomOverlays
CustomOverlay.prototype.onRemove = function () {
    this.div_.parentNode.removeChild(this.div_);
    this.div_ = null;
};

//start this whole mess once the google map is loaded
google.maps.event.addDomListener(window, 'load', initialize);