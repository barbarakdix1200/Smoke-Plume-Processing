# Smoke-Plume-Processing
This repository contains the Igor Pro procedures used to identify, characterize, and analyze wildfire smoke plumes for the study:

Barbara Dix, Lindsey D. Anderson, J. Pepijn Veefkind, and Joost de Gouw:
Combustion Controls and Plume Structure of Wildfire Aerosol Optical Properties Observed by TROPOMI
submitted to Atmospheric Chemistry and Physics

The code implements the automated plume-identification and characterization workflow described in the accompanying paper.
This repository does not include the satellite or ancillary datasets required to execute the analysis, because these datasets originate from multiple external sources and are too large to distribute through GitHub.

The procedures expect preprocessed input files, including:
TROPOMI NO₂, CO, AOD and SSA
Fire Radiative Power (FRP) observations
Vapor Pressure Deficit (VPD) data
Land-cover data

Sources and the preprocessing steps used to generate these input files are described in the accompanying publication.
Note: These procedures are provided as the research code used in the published analysis. They are intended to document the implementation of the methodology described in the accompanying paper rather than to serve as a standalone software package. Consequently, some modification of file paths, data structures, and preprocessing steps will be required before the code can be applied to other datasets.

Software Requirements
Igor Pro 9

If you use this code in your research, please cite the above study  

This repository is distributed under a license.
