﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace SobekCM.Bib_Package.VRACore
{
    /// <summary> Stores basic information about the materials used in the making of an object or substance(s) of which a work or an image is composed, in VRA Core metadata </summary>
    public class VRACore_Materials_Info
    {
        private string type, materials;

        /// <summary> Constructor for a new instance of the VRACore_Materials_Info class </summary>
        public VRACore_Materials_Info()
        {
            // Do nothing
        }

        /// <summary> Constructor for a new instance of the VRACore_Materials_Info class </summary>
        /// <param name="Materials">Substance(s) of which a work or an image is composed</param>
        /// <param name="Type">Type of materials described here, such as ( medium, support, etc.. )</param>
        public VRACore_Materials_Info(string Materials, string Type)
        {
            materials = Materials;
            type = Type;
        }

        /// <summary> Substance(s) of which a work or an image is composed </summary>
        public string Materials
        {
            get { return materials ?? String.Empty; }
            set { materials = value; }
        }

        /// <summary> Type of materials described here, such as ( medium, support, etc.. )</summary>
        public string Type
        {
            get { return type ?? String.Empty; }
            set { type = value; }
        }
    }
}
