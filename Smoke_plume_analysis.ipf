#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

#include <Percentile and Box Plot>


function load_data_detect_plumes_and_analyze()

//This function gathers all pre-existing input data and performs automated smoke plume analysis  
//Analysis period is determined here by available input data
	
	//USER DEFINED INPUT
			
	// dimension of analysis box centered on NO2 maximum
	variable/g analysis_box_dim_lat = 0.8 //degrees with at leat one significant digit	
	//variable analysis_box_dim_long determined later based on local latitude to ensure equal physical dimensions
		
	//NO2 plume percentile to define a plume core and split plume data into core and rest
	string/g NO2_plume_core_perc = "80"
		
	//QUALITY FILTERS
	//minimum frp points in frp cluster contour - empirical
	variable/g frp_npnts_limit = 3
		 
	//To avoid including neighboring plumes when iteratively growing the NO2 plume contour - empirical
	variable/g contour_grow_size_limit = 12
			
	//limits for plume data coverage
	variable/g plume_npnts_limit = 20 
	variable/g plume_frac_limit = 0.5
	variable/g bg_npnts_limit = 20 
	
		
	//PATHS TO INPUT DATA
	string/g file_path_start = "C:01_DATA:TROPOMI_gridded:AUS:AUS_"
	
	string/g file_path_NO2 = file_path_start + "NO2:NO2_res0p05:"
	string/g file_path_CO = file_path_start + "CO:CO_res0p05:"
		
	string/g file_path_aer_aod = file_path_start + "aer:aod_res0p05:"
	string/g file_path_aer_ssa = file_path_start + "aer:ssa_res0p05:"
		
	string/g file_path_vpd = "C:01_DATA:ECMWF_gridded:AUS:vpd_res0p05:"
		
	string/g frp_DT_wve_name = "frp_DT_AUS_2018_05_2020_01"
	string/g frp_lat_wve_name = "frp_lat_AUS_2018_05_2020_01"
	string/g frp_long_wve_name = "frp_long_AUS_2018_05_2020_01"
	string/g frp_frp_wve_name = "frp_frp_AUS_2018_05_2020_01"
	string/g frp_landc_wve_name = "frp_landc_AUS_2018_05_2020_01"
	
	variable/g res_lat = 0.05
	variable/g res_long = 0.05
	
	
	//*****no changes below here *************************************************************************************
		
		//CREATING AND NAMING ALL WAVES TO STORE RESULTS
		
		string dim_lat_str = num2str(analysis_box_dim_lat)
		variable dim_lat_str_length = strlen(dim_lat_str)
		string result_suffix = "box" + dim_lat_str[0] + "p" + dim_lat_str[2,dim_lat_str_length-1] + "_core" + NO2_plume_core_perc + "perc"
			
		string/g results_wve_name = "results_" + result_suffix
		string/g results_DT_wve_name = "results_DT_" + result_suffix
		string/g results_DT_suffix_wve_name = "results_DT_suffix_" + result_suffix
		
		//Averages over the whole analysis period
		string/g NO2_avg_wve_name = "NO2_avg_" + result_suffix
		string/g CO_avg_wve_name = "CO_avg_" + result_suffix 
		string/g vpd_avg_wve_name = "vpd_avg_" + result_suffix 
							
		A_create_result_wves()
		wave results_wve = $results_wve_name
		wave results_DT_wve = $results_DT_wve_name
		wave/T results_DT_suffix_wve = $results_DT_suffix_wve_name
					
		//ITERATING THROUGH ALL ORBITS
		
		NewPath/O/Q data_path file_path_NO2
		string filename_list = IndexedFile(data_path, -1, ".ibw")

		variable file_counter, nump, i,j
		variable/g orbit_lat_long_done = 0
		variable/g total_avg_wves_done = 0
		
		for(file_counter=0;file_counter<itemsinlist(filename_list);file_counter+=1)
				
			string file_name = stringfromlist(file_counter,filename_list)	//e.g. NO2_tVCD_0p05_20200226_0350 
			string DT_suffix = file_name[strlen(file_name)-17,strlen(file_name)-5]	
									
			variable/g load_fail = 0
			variable/g load_fail_vpd	 = 0	
						
			B_load_input_files(DT_suffix)
			
			if(load_fail == 1)
				continue
			endif
				
			wave NO2_wve, CO_wve, aod_wve, ssa_wve, vpd_wve
			wave sat_long_wve,sat_lat_wve,sat_long_wve_1d,sat_lat_wve_1d  			
									
			
			// PREPPING FRP, VPD AND LANDCOVER DATA MATCHING ORBIT
						
			variable year = str2num(file_name[strlen(file_name)-17,strlen(file_name)-14])		//e.g. 20210704_1950
			variable month = str2num(file_name[strlen(file_name)-13,strlen(file_name)-12]) 
			variable day = str2num(file_name[strlen(file_name)-11,strlen(file_name)-10])
			variable hour = str2num(file_name[strlen(file_name)-8,strlen(file_name)-7])
			variable minute = str2num(file_name[strlen(file_name)-6,strlen(file_name)-5])
			
			variable sat_DT = date2secs(year,month,day) + 3600*hour + 60*minute
								
			variable/g frp_found = 0
			
			C_extract_frp_matching_orbit(sat_DT)
			
			if(frp_found == 0)
				killwaves/Z NO2_wve, CO_wve, aod_wve, ssa_wve, vpd_wve
				continue
			endif		
			
			//waves containing FRP contour lines and FRP, VPD and land cover stats
			wave frp_cont_lat_wve, frp_cont_long_wve
			wave frp_cont_avg_wve, frp_cont_sdev_wve, frp_cont_med_wve, frp_cont_sum_wve, frp_cont_max_wve, frp_cont_npnts_wve,frp_cont_grid_npnts_wve
			wave frp_cont_number_wve
			wave frp_cont_landc_A_wve, frp_cont_landc_A_frac_wve, frp_cont_landc_B_wve,frp_cont_landc_B_frac_wve, frp_cont_landc_rest_frac_wve
			wave frp_cont_vpd_avg_wve, frp_cont_vpd_sdev_wve, frp_cont_vpd_med_wve						
			
			//ITERATING THROUGH ALL FRP CLUSTER CONTOUR LINES		
			
			variable frp_counter
			for(frp_counter=0;frp_counter<dimsize(frp_cont_lat_wve,0);frp_counter+=1)
			
			if(numtype(frp_cont_number_wve[frp_counter]) == 0)	 // in case frp fire locations got merged, then the merged locations further down the list were labeled "0" and are skipped				
				
				string frp_contour_x_wve_name = "contour_frp_x_" + num2str(frp_cont_number_wve[frp_counter])
				string frp_contour_y_wve_name = "contour_frp_y_" + num2str(frp_cont_number_wve[frp_counter])
				
				duplicate/o $frp_contour_x_wve_name, frp_contour_x_wve 
				duplicate/o $frp_contour_y_wve_name, frp_contour_y_wve 
				
				wavestats/q frp_contour_x_wve
				variable frp_contour_long_max = V_max
				variable frp_contour_long_min = V_min
				wavestats/q frp_contour_y_wve
				variable frp_contour_lat_max = V_max
				variable frp_contour_lat_min = V_min
			
				variable NO2_point_long = nan
				variable NO2_point_lat = nan
				variable NO2_threshold_high = nan
				
				//defining NO2 maximum in FRP cluster box
				wavestats/q/rmd=(frp_contour_long_min,frp_contour_long_max)(frp_contour_lat_max,frp_contour_lat_min) NO2_wve
				
				if( (V_npnts == 0) || (numtype(V_npnts) == 2) || (V_max == 0) )
					//if frp contour contains only NO2 nan -> when frp location is just outside swath
					//if frp contour contains only NO2 zeros (nans were replaced to 0 in B_load_input_files to aid in NO2 plume contouring later on)
					//move on to next contour
					killwaves frp_contour_x_wve,frp_contour_y_wve   
					continue
				else
					NO2_point_lat = V_maxColLoc
					NO2_point_long = V_maxRowLoc
					NO2_threshold_high = V_max				
				endif
				
				//Analysis box is centered around NO2_point_lat and NO2_point_long of NO2 maximum in FRP cluster box  
				variable analysis_box_dim_long = analysis_box_dim_lat / (cos(NO2_point_lat*pi/180))		
				variable analysis_box_long_max = NO2_point_long+(analysis_box_dim_long/2)
				variable analysis_box_long_min = NO2_point_long-(analysis_box_dim_long/2)
				variable analysis_box_lat_max = NO2_point_lat+(analysis_box_dim_lat/2)
				variable analysis_box_lat_min = NO2_point_lat-(analysis_box_dim_lat/2)
								
				//if analysis box were to exceed sat file boundaries, move on to next frp contour
				if( (analysis_box_long_max > sat_long_wve[numpnts(sat_long_wve)-1]) || (analysis_box_long_min < sat_long_wve[0]) )
					killwaves frp_contour_x_wve,frp_contour_y_wve
					continue
				endif
				if( (analysis_box_lat_min < sat_lat_wve[numpnts(sat_lat_wve)-1]) || (analysis_box_lat_max > sat_lat_wve[0]) )
					killwaves frp_contour_x_wve,frp_contour_y_wve
					continue
				endif
								
				//any FRP cluster contour with a valid NO2 maximum gets stored as result
				
				nump = dimsize(results_wve,0)
      			insertpoints/M=0 nump, 1, results_wve, results_DT_wve, results_DT_suffix_wve
					
				results_wve[nump][] = nan
				results_DT_wve[nump] = sat_DT
				results_DT_suffix_wve[nump] = DT_suffix
															
				results_wve[nump][%frp_lat] = frp_cont_lat_wve[frp_counter]
				results_wve[nump][%frp_long] = frp_cont_long_wve[frp_counter]
				results_wve[nump][%frp_avg] = frp_cont_avg_wve[frp_counter]
				results_wve[nump][%frp_sdev] = frp_cont_sdev_wve[frp_counter]
				results_wve[nump][%frp_med] = frp_cont_med_wve[frp_counter]
				results_wve[nump][%frp_sum] = frp_cont_sum_wve[frp_counter]
				results_wve[nump][%frp_max] = frp_cont_max_wve[frp_counter]
				results_wve[nump][%frp_npnts] = frp_cont_npnts_wve[frp_counter]
				results_wve[nump][%frp_grid_npnts] = frp_cont_grid_npnts_wve[frp_counter]
								
				results_wve[nump][%frp_merged] = nan
										
				results_wve[nump][%frp_landc_A] = frp_cont_landc_A_wve[frp_counter]
				results_wve[nump][%frp_landc_A_frac] = frp_cont_landc_A_frac_wve[frp_counter]
				results_wve[nump][%frp_landc_B] = frp_cont_landc_B_wve[frp_counter]
				results_wve[nump][%frp_landc_B_frac] = frp_cont_landc_B_frac_wve[frp_counter]
				results_wve[nump][%frp_landc_rest_frac] = frp_cont_landc_rest_frac_wve[frp_counter]
				
				if(load_fail_vpd == 0)
					results_wve[nump][%frp_vpd_avg] = frp_cont_vpd_avg_wve[frp_counter]
					results_wve[nump][%frp_vpd_sdev] = frp_cont_vpd_sdev_wve[frp_counter]
					results_wve[nump][%frp_vpd_med] = frp_cont_vpd_med_wve[frp_counter]	
				endif
											
				
				
				//ITERATIVE NO2 PLUME THRESHOLDING
				
				duplicate/o/rmd=(analysis_box_long_min,analysis_box_long_max)(analysis_box_lat_max,analysis_box_lat_min) NO2_wve, NO2_wve_box								
				
				D_create_lat_long_1d_wve(NO2_wve_box)
				wave long_wve_NO2_wve_box_1d, lat_wve_NO2_wve_box_1d
				
				make/o/d/n=1 no2_point_long_wve=nan, no2_point_lat_wve=nan
				no2_point_long_wve[0] = NO2_point_long
				no2_point_lat_wve[0] = NO2_point_lat
				
				variable/g NO2_plume_threshold = nan
				variable NO2_plume_threshold_start = nan
								
				variable NO2_max_in_cont, NO2_cont_closed
				variable cont_start_size, cont_grow_size
    			    				
    			variable threshold_start_found = 0
    			variable threshold_found = 0  
    			
    			variable/g CO_plume_threshold = nan
    			variable/g aod_plume_threshold = nan
    			
    			//2-iteration step approach to determine NO2 plume threshold that defines the plume outline
    			
    			//1) Determining starting NO2 threshold: starting with NO2 point max value and lowering vale in 1e14 steps
    			// until it creates a contour line containing the NO2 point max within FRP cluster box and least a total of 5 pixels
				
				//NOTE: during loading of NO2 wave, all nans are set to 0, so that 
				//contour lines do not get broken by nans
				//After contourline is found, 0s are set back to nan in G_populate_stats_and_fit_wves
				    				
    			variable thresh_value  				
				for(thresh_value=NO2_threshold_high;thresh_value>0;thresh_value+=-1e14)
						
					FindContour/DSTX=NO2_contour_x_wve/DSTY=NO2_contour_y_wve NO2_wve_box, thresh_value
					
					NO2_max_in_cont=0
					NO2_cont_closed=0
					cont_start_size=0
					cont_grow_size=0
	
					[NO2_max_in_cont,NO2_cont_closed,cont_start_size,cont_grow_size] = E_check_contour_for_frp_NO2_max_and_closedness(analysis_box_dim_long,analysis_box_dim_lat)
					
					killwaves NO2_contour_x_wve,NO2_contour_y_wve
					wave NO2_contour_x_wve_cont,NO2_contour_y_wve_cont //only exists when NO2_max_in_cont==1
															
					if(waveexists(NO2_contour_x_wve_cont) == 1)
						FindPointsInPoly long_wve_NO2_wve_box_1d, lat_wve_NO2_wve_box_1d,  NO2_contour_x_wve_cont, NO2_contour_y_wve_cont
						wave W_inPoly
						wavestats/q W_inPoly
						killwaves W_inPoly	
						if(V_sum < 3)	//number of pixels in NO2_contour
							killwaves NO2_contour_x_wve_cont, NO2_contour_y_wve_cont
							continue	
						endif
					endif	
											
					if( (NO2_max_in_cont == 1) && (NO2_cont_closed == 1)	)
						NO2_plume_threshold_start = thresh_value
						threshold_start_found = 1
						cont_start_size = numpnts(NO2_contour_x_wve_cont)
						killwaves NO2_contour_x_wve_cont, NO2_contour_y_wve_cont
						break
					endif
					
					killwaves/z NO2_contour_x_wve_cont,NO2_contour_y_wve_cont	
				
				endfor	 //thresh_value
				
				
				if(threshold_start_found == 0)
						
					results_wve[nump][%contour_fail] = 1
    				killwaves NO2_wve_box
   					killwaves no2_point_long_wve, no2_point_lat_wve
   					killwaves long_wve_NO2_wve_box_1d, lat_wve_NO2_wve_box_1d
    				killwaves frp_contour_x_wve,frp_contour_y_wve    					
    				continue  	
	   					   				
				endif
					
				//2) Lowering threshold, i.e. increasing plume size, until it opens or becomes too big too quickly,
				// e.g. when including a smaller nearby plume, determined by contour grow size limit (empirical)
							
				
				cont_grow_size=0
				for(thresh_value=NO2_plume_threshold_start;thresh_value>0;thresh_value+=-1e14)
						
					FindContour/DSTX=NO2_contour_x_wve/DSTY=NO2_contour_y_wve NO2_wve_box, thresh_value
											
					NO2_max_in_cont=0
					NO2_cont_closed=0
					[NO2_max_in_cont,NO2_cont_closed,cont_start_size,cont_grow_size] = E_check_contour_for_frp_NO2_max_and_closedness(analysis_box_dim_long,analysis_box_dim_lat)
					
					killwaves NO2_contour_x_wve,NO2_contour_y_wve
					wave NO2_contour_x_wve_cont,NO2_contour_y_wve_cont //only exists when NO2_max_in_cont==1
														
					if( (NO2_max_in_cont == 0) || (NO2_cont_closed == 0) || (cont_grow_size > contour_grow_size_limit) )
						
						NO2_plume_threshold = thresh_value + 1e14
						threshold_found = 1
												
						killwaves/z NO2_contour_x_wve_cont, NO2_contour_y_wve_cont
						break
					endif
					
					killwaves/z NO2_contour_x_wve_cont, NO2_contour_y_wve_cont
				
				endfor	
							
					
				if(threshold_found == 1)
					results_wve[nump][%no2_threshold] = NO2_plume_threshold
				else
					//don't think that ever happens, because contour will open eventually
					//if threshstart is so small that lowering it makes contour disappear
					results_wve[nump][%contour_fail] = 1
    				killwaves NO2_wve_box
   					killwaves no2_point_long_wve, no2_point_lat_wve
   					killwaves long_wve_NO2_wve_box_1d, lat_wve_NO2_wve_box_1d
    				killwaves frp_contour_x_wve,frp_contour_y_wve    					
    				continue  	
	   					   			
				endif
				
												
				//This step to extract final plume contour wave
				FindContour/DSTX=NO2_contour_x_wve/DSTY=NO2_contour_y_wve NO2_wve_box, NO2_plume_threshold
				NO2_max_in_cont=0
				[NO2_max_in_cont,NO2_cont_closed,cont_start_size,cont_grow_size] = E_check_contour_for_frp_NO2_max_and_closedness(analysis_box_dim_long,analysis_box_dim_lat)
				killwaves NO2_contour_x_wve, NO2_contour_y_wve	
				wave NO2_contour_x_wve_cont,NO2_contour_y_wve_cont
				    			    			
    			// Does the current plume contain other frp clusters defined by average FRP lat/long
				// if yes, frp info will be merged and averaged together
									
				FindPointsInPoly frp_cont_long_wve, frp_cont_lat_wve, NO2_contour_x_wve_cont, NO2_contour_y_wve_cont
				wave W_inPoly
				wavestats/q W_inPoly
								
				//Note: the frp lat/long point belonging to the current NO2 plume could be inside or outside the NO2 plume contour line
				if( (V_sum > 1) || ((V_sum == 1) && (V_maxloc != frp_counter)) ) 
					
					F_create_merged_frp_info(frp_counter,W_inPoly,nump)
																						
				else
					killwaves W_inPoly			
				endif
								
   				duplicate/o/rmd=(analysis_box_long_min,analysis_box_long_max)(analysis_box_lat_max,analysis_box_lat_min) CO_wve, CO_wve_box
				duplicate/o/rmd=(analysis_box_long_min,analysis_box_long_max)(analysis_box_lat_max,analysis_box_lat_min) aod_wve, aod_wve_box
				duplicate/o/rmd=(analysis_box_long_min,analysis_box_long_max)(analysis_box_lat_max,analysis_box_lat_min) ssa_wve, ssa_wve_box
				
				     	 		
      	 		// creating quality filtered waves for plume/background statistics and NO2/CO fits
				     			
      			variable no2_co_stats_fail=0
      			variable aer_stats_fail=0
      			variable plume_npnts=0
      			       			      			
      			[no2_co_stats_fail,aer_stats_fail,plume_npnts] = G_populate_stats_and_fit_wves()
      			  			
      			if(no2_co_stats_fail == 1) 	
					results_wve[nump][%no2_co_stats_fail] = 1
											
					killwaves long_wve_NO2_wve_box_1d, lat_wve_NO2_wve_box_1d
					killwaves NO2_contour_y_wve_cont, NO2_contour_x_wve_cont
					killwaves no2_point_long_wve, no2_point_lat_wve
					killwaves/z NO2_wve_box,CO_wve_box
					killwaves aod_wve_box,ssa_wve_box
					killwaves frp_contour_x_wve,frp_contour_y_wve
													
					continue
				endif
      				
    			//any plume with NO2 and CO passing qa gets stored as result
    			
    			results_wve[nump][%co_threshold] = CO_plume_threshold
      			results_wve[nump][%plume_npnts] = plume_npnts      					
      			
      			wave no2_wve_plume_1d, co_wve_plume_1d
   				wave no2_wve_bg_1d, co_wve_bg_1d
      			      			
      			wavestats/q no2_wve_plume_1d	 
				results_wve[nump][%no2_npnts] = V_npnts 
				results_wve[nump][%no2_frac] = (V_npnts/plume_npnts) 
				results_wve[nump][%no2_avg] = V_avg
      			results_wve[nump][%no2_sdev] = V_sdev
      			results_wve[nump][%no2_med] = median(no2_wve_plume_1d)
      			results_wve[nump][%no2_max] = V_max
      			results_wve[nump][%no2_min] = V_min
      			      			
      			wavestats/q co_wve_plume_1d	
				results_wve[nump][%co_npnts] = V_npnts
				results_wve[nump][%co_frac] =(V_npnts/plume_npnts)  
				results_wve[nump][%co_avg] = V_avg
      			results_wve[nump][%co_sdev] = V_sdev
      			results_wve[nump][%co_med] = median(co_wve_plume_1d)
      			results_wve[nump][%co_max] = V_max
      			results_wve[nump][%co_min] = V_min
      			
      			wavestats/q no2_wve_bg_1d
				results_wve[nump][%no2_bg_npnts] = V_npnts
				results_wve[nump][%no2_bg_avg] = V_avg
      			results_wve[nump][%no2_bg_sdev] = V_sdev
      			results_wve[nump][%no2_bg_med] = median(no2_wve_bg_1d)
				
				no2_wve_plume_1d = no2_wve_plume_1d - V_avg
				wavestats/q no2_wve_plume_1d 
				results_wve[nump][%no2_bgc_avg] = V_avg
				
				string whiskerresult = "w_temp"
				string wve_temp_name	
				
				variable NO2_core_perc=nan
      			wve_temp_name = "no2_wve_plume_1d"
      			fWavePercentile(wve_temp_name,NO2_plume_core_perc, whiskerresult,0,0,0)
				wave w_temp = $("w_temp_" + NO2_plume_core_perc)
      			NO2_core_perc = w_temp[0]
      			killwaves $nameofwave(w_temp)
      								
				wavestats/q co_wve_bg_1d
				results_wve[nump][%co_bg_npnts] = V_npnts
				results_wve[nump][%co_bg_avg] = V_avg
      			results_wve[nump][%co_bg_sdev] = V_sdev
      			results_wve[nump][%co_bg_med] = median(co_wve_bg_1d)
      			
      			co_wve_plume_1d = co_wve_plume_1d - V_avg
      			wavestats/q co_wve_plume_1d 
				results_wve[nump][%co_bgc_avg] = V_avg
				
				killwaves no2_wve_bg_1d, co_wve_bg_1d 
					
				//Dilution metric
				wve_temp_name = "co_wve_plume_1d"
      			fWavePercentile(wve_temp_name,"95", whiskerresult,0,0,0)
				wave w_temp_95
				results_wve[nump][%co_95perc_bgc] = w_temp_95[0]
				results_wve[nump][%co_dilution_bgc] = results_wve[nump][%co_bgc_avg] / w_temp_95[0] 
				killwaves w_temp_95
				
				//core-rest results
				duplicate/o no2_wve_plume_1d, no2_plume_wve_core_temp, no2_plume_wve_rest_temp
      			duplicate/o CO_wve_plume_1d, CO_plume_wve_core_temp, CO_plume_wve_rest_temp
      			variable kk
      			for(kk=0;kk<numpnts(no2_wve_plume_1d);kk+=1)
      				if(no2_wve_plume_1d[kk] < NO2_core_perc)
      					no2_plume_wve_core_temp[kk] = nan
      					CO_plume_wve_core_temp[kk] = nan
      				else	
      					no2_plume_wve_rest_temp[kk] = nan
      					CO_plume_wve_rest_temp[kk] = nan
      				endif
      			endfor
      			
      			wavestats/q no2_plume_wve_core_temp
      			results_wve[nump][%no2_core_avg] = V_avg
      			results_wve[nump][%no2_core_sdev] = V_sdev
      			wavestats/q no2_plume_wve_rest_temp
      			results_wve[nump][%no2_rest_avg] = V_avg
      			results_wve[nump][%no2_rest_sdev] = V_sdev
      			results_wve[nump][%no2_core_rest] = results_wve[nump][%no2_core_avg] - results_wve[nump][%no2_rest_avg]
      			
      			wavestats/q co_plume_wve_core_temp
      			results_wve[nump][%co_core_avg] = V_avg
      			results_wve[nump][%co_core_sdev] = V_sdev
      			wavestats/q co_plume_wve_rest_temp
      			results_wve[nump][%co_rest_avg] = V_avg
      			results_wve[nump][%co_rest_sdev] = V_sdev
      			results_wve[nump][%co_core_rest] = results_wve[nump][%co_core_avg] - results_wve[nump][%co_rest_avg]
      			      			
      			killwaves no2_plume_wve_core_temp,no2_plume_wve_rest_temp,co_plume_wve_core_temp,co_plume_wve_rest_temp
      							
      			//NO2/CO fit								
				variable V_FitError
      			wave no2_co_wve_fit_1d, co_no2_wve_fit_1d 
      			
      			wavestats/q no2_co_wve_fit_1d
				results_wve[nump][%no2_co_npnts] = V_npnts
      			
      			V_FitError = 0	//no stopping on failed fits
				CurveFit/q line, no2_co_wve_fit_1d/X=co_no2_wve_fit_1d/D
				wave w_coef,w_sigma
				if( (waveexists(w_coef) == 1) && (waveexists(w_sigma) == 1) )
					results_wve[nump][%no2_co_fit_ofs] = w_coef[0]
					results_wve[nump][%no2_co_fit_slope] = w_coef[1]
					results_wve[nump][%no2_co_fit_err] = w_sigma[1]
					results_wve[nump][%no2_co_fit_r2] = V_r2
				endif
				killwaves/z w_coef,w_sigma,fit_no2_co_wve_fit_1d
					
				killwaves no2_co_wve_fit_1d, co_no2_wve_fit_1d
				   
      			if(aer_stats_fail == 1) 	
		      		
		      		results_wve[nump][%aer_stats_fail] = 1
									
				else
					
					//if aerosol data passes qa, then these results get stored
					
     				results_wve[nump][%aod_threshold] = aod_plume_threshold
     					 
					//testing for AOD bias in SSA avg
					wave ssa_wve_temp = $("ssa_wve_plume_1d")
					wave aod_wve_temp = $("aod_wve_plume_1d")
					make/o/d/n=(dimsize(ssa_wve_temp,0)) ssa_aod_wve_temp=nan
					ssa_aod_wve_temp = ssa_wve_temp*aod_wve_temp
					wavestats/q ssa_aod_wve_temp
					results_wve[nump][%ssa_aod_avg] = V_avg
					killwaves ssa_aod_wve_temp 
										
					string aer_wve_name_list
					string label_str
					string var_name, aer_wve_name, aer_bg_wve_name
					variable wve_counter
				
					aer_wve_name_list = "aod;ssa"
										
					
					for(wve_counter=0;wve_counter<itemsinlist(aer_wve_name_list);wve_counter+=1)
						var_name = stringfromlist(wve_counter,aer_wve_name_list)
						aer_wve_name = stringfromlist(wve_counter,aer_wve_name_list) + "_wve_plume_1d"
						aer_bg_wve_name = stringfromlist(wve_counter,aer_wve_name_list) + "_wve_bg_1d"
						
						wavestats/q $aer_wve_name
						label_str = var_name + "_npnts"	
						results_wve[nump][%$label_str] = V_npnts
						label_str = var_name + "_frac"
						results_wve[nump][%$label_str] = (V_npnts/plume_npnts)  
						label_str = var_name + "_avg"
						results_wve[nump][%$label_str] = V_avg
      					label_str = var_name + "_sdev"
      					results_wve[nump][%$label_str] = V_sdev
      					label_str = var_name + "_med"
      					results_wve[nump][%$label_str] = median($aer_wve_name)
      					label_str = var_name + "_max"
      					results_wve[nump][%$label_str] = V_max
      					label_str = var_name + "_min"
      					results_wve[nump][%$label_str] = V_min
      					      					
      					wavestats/q $aer_bg_wve_name
						label_str = var_name + "_bg_npnts"
						results_wve[nump][%$label_str] = V_npnts
						label_str = var_name + "_bg_avg"
						results_wve[nump][%$label_str] = V_avg
						label_str = var_name + "_bg_sdev"
      					results_wve[nump][%$label_str] = V_sdev
      					label_str = var_name + "_bg_med"
      					results_wve[nump][%$label_str] = median($aer_bg_wve_name)
      					
      					if(stringmatch(var_name,"aod") == 1)
      						wave aer_wve = $aer_wve_name 
      						aer_wve = aer_wve - V_avg
							wavestats/q aer_wve
							label_str = var_name + "_bgc_avg"
							results_wve[nump][%$label_str] = V_avg
						endif	
						
      					duplicate/o $aer_wve_name, aer_plume_wve_core_temp, aer_plume_wve_rest_temp
      						      						
      					for(kk=0;kk<numpnts(no2_wve_plume_1d);kk+=1)
      						if(no2_wve_plume_1d[kk] < NO2_core_perc)
      							aer_plume_wve_core_temp[kk] = nan
      						else	
      							aer_plume_wve_rest_temp[kk] = nan
      						endif
      					endfor
      					wavestats/q aer_plume_wve_core_temp
      					label_str = var_name + "_core_avg"	
						results_wve[nump][%$label_str] = V_avg
						label_str = var_name + "_core_sdev"	
						results_wve[nump][%$label_str] = V_sdev
						wavestats/q aer_plume_wve_rest_temp
						label_str = var_name + "_rest_avg"	
						results_wve[nump][%$label_str] = V_avg
						label_str = var_name + "_rest_sdev"	
						results_wve[nump][%$label_str] = V_sdev
						if(stringmatch(var_name,"aod") == 1) 
							results_wve[nump][%aod_core_rest] = results_wve[nump][%aod_core_avg] - results_wve[nump][%aod_rest_avg]
      					endif
      					if(stringmatch(var_name,"ssa") == 1) 
							results_wve[nump][%ssa_core_rest] = results_wve[nump][%ssa_core_avg] - results_wve[nump][%ssa_rest_avg]
      					endif
      					
      					killwaves $aer_wve_name, aer_plume_wve_core_temp, aer_plume_wve_rest_temp
      					      						
      			   endfor
      			     			     			
				endif //(aer_stats_fail == 1) ) 	
      														
				killwaves long_wve_NO2_wve_box_1d, lat_wve_NO2_wve_box_1d
				killwaves frp_contour_x_wve,frp_contour_y_wve
				killwaves/z NO2_wve_box,CO_wve_box
				killwaves aod_wve_box,ssa_wve_box
				killwaves no2_point_long_wve, no2_point_lat_wve
				killwaves NO2_contour_y_wve_cont, NO2_contour_x_wve_cont				
				
												
						
			endif //if(numtype(frp_contour_number[frp_counter]) == 0)	 
			endfor //frp_counter -> ITERATING THROUGH ALL FRP CLUSTER CONTOUR LINES		
			
			killwaves/Z NO2_wve, CO_wve, aod_wve, ssa_wve, vpd_wve
			killwaves frp_cont_lat_wve, frp_cont_long_wve
			killwaves frp_cont_avg_wve, frp_cont_sdev_wve, frp_cont_med_wve, frp_cont_sum_wve, frp_cont_max_wve, frp_cont_npnts_wve, frp_cont_grid_npnts_wve
			killwaves frp_cont_number_wve
			killwaves frp_cont_landc_A_wve, frp_cont_landc_A_frac_wve, frp_cont_landc_B_wve,frp_cont_landc_B_frac_wve, frp_cont_landc_rest_frac_wve
			killwaves frp_cont_vpd_avg_wve, frp_cont_vpd_sdev_wve, frp_cont_vpd_med_wve	
			wave frp_long_wve_sat_day, frp_lat_wve_sat_day	,frp_frp_wve_sat_day,frp_landc_wve_sat_day 
			killwaves frp_long_wve_sat_day, frp_lat_wve_sat_day	,frp_frp_wve_sat_day,frp_landc_wve_sat_day

									
			string delete_list = WaveList("contour_frp*",";", "")
			for(wve_counter=0;wve_counter<itemsinlist(delete_list);wve_counter+=1)
				string delete_wve_name = stringfromlist(wve_counter,delete_list)
				killwaves/Z $delete_wve_name
			endfor	
						
			print DT_suffix
		endfor	// file_counter -> ITERATING THROUGH ALL ORBITS
		
		wave NO2_avg_wve = $NO2_avg_wve_name
		wave CO_avg_wve = $CO_avg_wve_name
		wave vpd_avg_wve = $vpd_avg_wve_name	
		wave NO2_avg_divider_wve = $(NO2_avg_wve_name + "_stats")
		wave CO_avg_divider_wve = $(CO_avg_wve_name + "_stats")
		wave vpd_avg_divider_wve = $(vpd_avg_wve_name + "_stats")
				
		NO2_avg_wve = NO2_avg_wve/NO2_avg_divider_wve
		CO_avg_wve = CO_avg_wve/CO_avg_divider_wve
		vpd_avg_wve = vpd_avg_wve/vpd_avg_divider_wve
		
		killwaves sat_long_wve, sat_lat_wve, sat_long_wve_1d, sat_lat_wve_1d
		wave sat_long_matrix, sat_lat_matrix
		killwaves sat_long_matrix, sat_lat_matrix 
				
		//remove info on FRP clusters that were merged from results
		for(i=0;i<dimsize(results_wve,0);i+=1)
			if(results_wve[i][%frp_merged] == -1)
				DeletePoints i,1, results_wve,results_DT_wve,results_DT_suffix_wve 
				i+=-1
			endif
		endfor		

		
	end			
				
/////////////////////////////////END OF MAIN //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	

//***************** CREATING RESULT WAVES	***********************************
						

function A_create_result_wves()
		
	
	svar results_wve_name, results_DT_wve_name,results_DT_suffix_wve_name
			
	string col_labels_list =	"frp_lat;frp_long;frp_avg;frp_sdev;frp_med;frp_sum;frp_max;frp_npnts;frp_grid_npnts;frp_merged;" + \
									"frp_landc_A;frp_landc_A_frac;frp_landc_B;frp_landc_B_frac;frp_landc_rest_frac;" + \
									"frp_vpd_avg;frp_vpd_sdev;frp_vpd_med;" + \
									"contour_fail;no2_co_stats_fail;aer_stats_fail;" + \
									"no2_threshold;co_threshold;aod_threshold;plume_npnts;" + \
									"no2_npnts;no2_frac;no2_avg;no2_sdev;no2_med;no2_max;no2_min;co_npnts;co_frac;co_avg;co_sdev;co_med;co_max;co_min;" + \
									"no2_co_npnts;no2_co_fit_ofs;no2_co_fit_slope;no2_co_fit_err;no2_co_fit_r2;" + \
									"no2_bg_npnts;no2_bg_avg;no2_bg_sdev;no2_bg_med;no2_bgc_avg;co_bg_npnts;co_bg_avg;co_bg_sdev;co_bg_med;co_bgc_avg;co_95perc_bgc;co_dilution_bgc;" + \
									"aod_npnts;aod_frac;aod_avg;aod_sdev;aod_med;aod_max;aod_min;ssa_npnts;ssa_frac;ssa_avg;ssa_sdev;ssa_med;ssa_max;ssa_min;ssa_aod_avg;" + \
									"aod_bg_npnts;aod_bg_avg;aod_bgc_avg;aod_bg_sdev;aod_bg_med;ssa_bg_npnts;ssa_bg_avg;ssa_bg_sdev;ssa_bg_med;" + \
									"no2_core_avg;no2_core_sdev;co_core_avg;co_core_sdev;no2_rest_avg;no2_rest_sdev;co_rest_avg;co_rest_sdev;no2_core_rest;co_core_rest;" + \
									"aod_core_avg;aod_core_sdev;ssa_core_avg;ssa_core_sdev;aod_rest_avg;aod_rest_sdev;ssa_rest_avg;ssa_rest_sdev;aod_core_rest;ssa_core_rest"
										
	
	//*****no changes below here ***************************************************************************************************
		
		make/o/d/n=0 $results_DT_wve_name
		make/o/T/n=0 $results_DT_suffix_wve_name
		
		make/o/d/n=(0,itemsinlist(col_labels_list)) $results_wve_name=nan
		
		variable i
		for(i=0;i<itemsinlist(col_labels_list);i+=1)
			string col_label = stringfromlist(i,col_labels_list)
			SetDimLabel 1, i, $col_label, $results_wve_name
		endfor	

end		
		


//**************** LOAD GRIDDED ORBIT AND VPD FILES ********************************************************************

function B_load_input_files(DT_suffix)
	string DT_suffix
	
	svar file_path_start 
	svar file_path_NO2, file_path_CO
	svar file_path_aer_aod, file_path_aer_ssa
	svar file_path_vpd
	
	svar NO2_avg_wve_name, CO_avg_wve_name, vpd_avg_wve_name
	nvar load_fail, load_fail_vpd, orbit_lat_long_done, total_avg_wves_done, res_lat, res_long
	
	
	//*****no changes below here *************************************************************************************
				
		string NO2_wve_name = "NO2_tVCD_0p05_" + DT_suffix
		string CO_wve_name = "CO_VCD_0p05_" + DT_suffix
		string aer_aod_wve_name = "aod_0p05_" + DT_suffix
		string aer_ssa_wve_name = "ssa_0p05_" + DT_suffix
		string vpd_wve_name = "vpd_0p05_" + DT_suffix
		
		string file_path
		
		file_path = file_path_NO2 + NO2_wve_name	
		loadwave/Q/H/O file_path
		duplicate/o $NO2_wve_name, NO2_wve 
		killwaves $NO2_wve_name
		NO2_wve = NO2_wve*6.02214e19
		
		if(orbit_lat_long_done == 0)
			duplicate/o NO2_wve,temp_matrix
			make/o/d/n=(dimsize(temp_matrix,0)) sat_long_wve
			make/o/d/n=(dimsize(temp_matrix,1)) sat_lat_wve
			copyscales temp_matrix, sat_long_wve
			sat_long_wve = x
			matrixtranspose temp_matrix
			copyscales temp_matrix, sat_lat_wve
			sat_lat_wve = x
			killwaves temp_matrix
				
			make/o/d/n=(dimsize(sat_long_wve,0)*dimsize(sat_lat_wve,0)) sat_long_wve_1d=nan, sat_lat_wve_1d=nan 
			make/o/d/n=(dimsize(sat_long_wve,0),dimsize(sat_lat_wve,0)) sat_long_matrix=nan, sat_lat_matrix=nan 
								
			variable i,j
			variable col_num =dimsize(sat_lat_wve,0) 
			for(i=0;i<dimsize(sat_long_wve,0);i+=1)
				for(j=0;j<dimsize(sat_lat_wve,0);j+=1)
					sat_long_wve_1d[i*col_num+j] = sat_long_wve[i]
					sat_lat_wve_1d[i*col_num+j] = sat_lat_wve[j]
					sat_long_matrix[i][j] = sat_long_wve[i]
					sat_lat_matrix[i][j] = sat_lat_wve[j]
				endfor
			endfor	
			
			SetScale/P x,sat_long_wve[0], res_long, sat_long_matrix, sat_lat_matrix 
			SetScale/P y,sat_lat_wve[0], -res_lat, sat_long_matrix, sat_lat_matrix 
										
			orbit_lat_long_done = 1
		endif						
		
		wave sat_long_wve,sat_lat_wve
		
		if(total_avg_wves_done == 0)
			string NO2_avg_divider_wve_name = NO2_avg_wve_name + "_stats"
			string CO_avg_divider_wve_name = CO_avg_wve_name + "_stats"
			string vpd_avg_divider_wve_name = vpd_avg_wve_name + "_stats"
			make/o/d/n=(dimsize(NO2_wve,0),dimsize(NO2_wve,1)) $NO2_avg_wve_name=0, $CO_avg_wve_name=0,$vpd_avg_wve_name=0
			make/o/d/n=(dimsize(NO2_wve,0),dimsize(NO2_wve,1)) $NO2_avg_divider_wve_name=nan, $CO_avg_divider_wve_name=nan, $vpd_avg_divider_wve_name=nan
			setscale/P x,sat_long_wve[0], res_long, $NO2_avg_wve_name,$CO_avg_wve_name,$vpd_avg_wve_name 
			setscale/P y,sat_lat_wve[0], -res_lat, $NO2_avg_wve_name,$CO_avg_wve_name,$vpd_avg_wve_name
			setscale/P x,sat_long_wve[0], res_long, $NO2_avg_divider_wve_name,$CO_avg_divider_wve_name,$vpd_avg_divider_wve_name 
			setscale/P y,sat_lat_wve[0], -res_lat, $NO2_avg_divider_wve_name,$CO_avg_divider_wve_name,$vpd_avg_divider_wve_name
			total_avg_wves_done = 1
		endif
		
		wave NO2_avg_wve = $NO2_avg_wve_name
		wave CO_avg_wve = $CO_avg_wve_name
		wave vpd_avg_wve = $vpd_avg_wve_name	
		wave NO2_avg_divider_wve = $(NO2_avg_wve_name + "_stats")
		wave CO_avg_divider_wve = $(CO_avg_wve_name + "_stats")
		wave vpd_avg_divider_wve = $(vpd_avg_wve_name + "_stats")
		
		//sat file search is based on NO2 folder
		//if any of the other files for same DT_suffix were missing, the orbit is discarded
		NewPath/O/Q check_path file_path_CO
		GetFileFolderInfo/P=check_path/Q/Z CO_wve_name + ".ibw"	
		if(V_flag != 0)
			load_fail = 1
		else	
			file_path = file_path_CO + CO_wve_name + ".ibw"	
			loadwave/Q/H/O file_path
			duplicate/o $CO_wve_name, CO_wve 
			killwaves $CO_wve_name
			CO_wve = CO_wve*6.02214e19
		endif
		
		NewPath/O/Q check_path file_path_aer_aod
		GetFileFolderInfo/P=check_path/Q/Z aer_aod_wve_name + ".ibw"	
		if(V_flag != 0)
			load_fail = 1
		else	
			file_path = file_path_aer_aod + aer_aod_wve_name + ".ibw"	
			loadwave/Q/H/O file_path
			duplicate/o $aer_aod_wve_name, aod_wve 
			killwaves $aer_aod_wve_name
		endif
				
		NewPath/O/Q check_path file_path_aer_ssa
		GetFileFolderInfo/P=check_path/Q/Z aer_ssa_wve_name + ".ibw"	
		if(V_flag != 0)
			load_fail = 1
		else	
			file_path = file_path_aer_ssa + aer_ssa_wve_name + ".ibw"	
			loadwave/Q/H/O file_path
			duplicate/o $aer_ssa_wve_name, ssa_wve 
			killwaves $aer_ssa_wve_name
		endif
		
				
		NewPath/O/Q check_path file_path_vpd
		GetFileFolderInfo/P=check_path/Q/Z vpd_wve_name + ".ibw"	
		if(V_flag != 0)
			load_fail_vpd = 1
		else	
			file_path = file_path_vpd + vpd_wve_name + ".ibw"	
			loadwave/Q/H/O file_path
			duplicate/o $vpd_wve_name, vpd_wve 
			killwaves $vpd_wve_name
		endif
		
				
		if(load_fail == 0)
			for(i=0;i<dimsize(NO2_wve,0);i+=1)
				for(j=0;j<dimsize(NO2_wve,1);j+=1)
					
					if(numtype(NO2_wve[i][j]) == 0)
						NO2_avg_wve[i][j] = NO2_avg_wve[i][j] + NO2_wve[i][j]
						if(numtype(NO2_avg_divider_wve[i][j]) == 2) 
							NO2_avg_divider_wve[i][j] = 0
						endif	
						NO2_avg_divider_wve[i][j] = NO2_avg_divider_wve[i][j] + 1
					else
						//Turning nans to 0 to get closed contour lines for plume deliniation
						NO2_wve[i][j] = 0
					endif
					
					if(numtype(CO_wve[i][j]) == 0)
						CO_avg_wve[i][j] = CO_avg_wve[i][j] + CO_wve[i][j]
						if(numtype(CO_avg_divider_wve[i][j]) == 2) 
							CO_avg_divider_wve[i][j] = 0
						endif	
						CO_avg_divider_wve[i][j] = CO_avg_divider_wve[i][j] + 1
					endif
					
					if(load_fail_vpd == 0)
						if(numtype(vpd_wve[i][j]) == 0)
							vpd_avg_wve[i][j] = vpd_avg_wve[i][j] + vpd_wve[i][j]
							if(numtype(vpd_avg_divider_wve[i][j]) == 2) 
								vpd_avg_divider_wve[i][j] = 0
							endif	
							vpd_avg_divider_wve[i][j] = vpd_avg_divider_wve[i][j] + 1
						endif
					endif
						
				endfor
			endfor		
		
		endif
				
		if(load_fail == 1)
			killwaves/Z NO2_wve,CO_wve,aod_wve,ssa_wve,vpd_wve
		endif
			   
end	
	



//****************************** EXTRACT FRP POINTS THAT MATCH sat_DT *******************************************************

function C_extract_frp_matching_orbit(sat_DT)
	variable sat_DT
	
	nvar frp_found,load_fail_vpd
	nvar res_lat, res_long
	nvar frp_npnts_limit
		
	svar frp_DT_wve_name, frp_lat_wve_name, frp_long_wve_name, frp_frp_wve_name, frp_landc_wve_name
	 
	wave sat_long_wve, sat_lat_wve, sat_long_wve_1d, sat_lat_wve_1d, sat_long_matrix, sat_lat_matrix 
	wave vpd_wve
	
	variable frp_grid_threshold = 1

	//*****no changes below here *************************************************************************************
	 	
		wave frp_DT_wve = $frp_DT_wve_name
		wave frp_lat_wve = $frp_lat_wve_name
		wave frp_long_wve = $frp_long_wve_name
		wave frp_frp_wve = $frp_frp_wve_name
		wave frp_landc_wve = $frp_landc_wve_name
	 
	   	 
	   //1) Find all FRP data within +30 min from sat_orbit_file DT - SUOMI-NPP is behind TROPOMI
	   // 30 min ensures all data from same orbit, but not from next orbit
	   	   
		variable frp_counter1,frp_counter2, frp_start=0,frp_start_found=0, frp_stop=0
    	for(frp_counter1=0;frp_counter1<numpnts(frp_DT_wve);frp_counter1+=1)
    		if(frp_DT_wve[frp_counter1] >= sat_DT)
    			frp_start = frp_counter1
    			frp_start_found = 1
    			for(frp_counter2=frp_counter1+1;frp_counter2<numpnts(frp_DT_wve);frp_counter2+=1)
    				if(frp_DT_wve[frp_counter2] > (sat_DT+30*60))
    					frp_stop = frp_counter2-1
    					break
    				endif
    			endfor
    			break
    		endif			
    	endfor
    	
    	if(frp_stop == 0)
    		frp_stop = numpnts(frp_DT_wve)-1
    	endif
    	
    	if(frp_start_found == 1)
    									
			duplicate/o/r=[frp_start,frp_stop] frp_lat_wve, frp_lat_wve_sat_day
			duplicate/o/r=[frp_start,frp_stop] frp_long_wve, frp_long_wve_sat_day
			duplicate/o/r=[frp_start,frp_stop] frp_frp_wve, frp_frp_wve_sat_day
			duplicate/o/r=[frp_start,frp_stop] frp_landc_wve, frp_landc_wve_sat_day
		
			
		  	//2) grid frp data on sat file grid as sum and create frp cluster contours with sum ==1
		
			make/o/d/n=(dimsize(sat_long_wve,0),dimsize(sat_lat_wve,0)) frp_grid_sum=0
			SetScale/P x,sat_long_wve[0], res_long, frp_grid_sum 
			SetScale/P y,sat_lat_wve[0], -res_lat, frp_grid_sum 
						
			variable i,j
			for(i=0;i<dimsize(frp_frp_wve_sat_day,0);i+=1)
				if(numtype(frp_frp_wve_sat_day[i]) == 0)
					variable long_point = x2pnt(sat_long_wve, frp_long_wve_sat_day[i])
					variable lat_point = x2pnt(sat_lat_wve, frp_lat_wve_sat_day[i])
					if( (long_point < 0) || (long_point >= dimsize(sat_long_wve,0)) || (lat_point < 0) || (lat_point >= dimsize(sat_lat_wve,0)) )
						continue
					else	
						frp_grid_sum[long_point][lat_point] = frp_grid_sum[long_point][lat_point] + frp_frp_wve_sat_day[i]
					endif	
				endif
			endfor
			
			FindContour/DSTX=contour_grid_sum_x_wve/DSTY=contour_grid_sum_y_wve frp_grid_sum, frp_grid_threshold
			     	      
			//contours are separated by nans in lat and long waves
    		//adding nan at the end of the wave for easier search below
    		variable nump = numpnts(contour_grid_sum_x_wve)
    		insertpoints nump,1,contour_grid_sum_x_wve,contour_grid_sum_y_wve 
    		contour_grid_sum_x_wve[nump] = nan
    		contour_grid_sum_y_wve[nump] = nan 
			
			//Storing FRP contour lines and FRP, VPD and land cover stats
			make/o/d/n=0 frp_cont_lat_wve, frp_cont_long_wve 
			make/o/d/n=0 frp_cont_avg_wve, frp_cont_sdev_wve, frp_cont_med_wve, frp_cont_sum_wve, frp_cont_max_wve, frp_cont_npnts_wve,frp_cont_grid_npnts_wve
			make/o/d/n=0 frp_cont_number_wve
			make/o/d/n=0 frp_cont_landc_A_wve, frp_cont_landc_A_frac_wve, frp_cont_landc_B_wve,frp_cont_landc_B_frac_wve, frp_cont_landc_rest_frac_wve
			make/o/d/n=0 frp_cont_vpd_avg_wve, frp_cont_vpd_sdev_wve, frp_cont_vpd_med_wve
			 
								
			variable counter, counter_start=0
   		 	for(counter=0;counter<numpnts(contour_grid_sum_x_wve)-1;counter+=1)
    		    		
    			//extracting one contour at time
    			if(numtype(contour_grid_sum_x_wve[counter]) == 2) 
    				duplicate/o/r=[counter_start,counter-1] contour_grid_sum_x_wve, contour_grid_sum_x_wve_temp
    				duplicate/o/r=[counter_start,counter-1] contour_grid_sum_y_wve, contour_grid_sum_y_wve_temp
    			
    				FindPointsInPoly frp_long_wve_sat_day, frp_lat_wve_sat_day, contour_grid_sum_x_wve_temp, contour_grid_sum_y_wve_temp
					wave W_inPoly
					wavestats/q W_inPoly
					if(V_sum > frp_npnts_limit)	
						make/o/d/n=0 frp_frp_wve_temp,frp_long_wve_temp,frp_lat_wve_temp,frp_landc_wve_temp,frp_vpd_wve_temp
						for(i=0;i<dimsize(W_inPoly,0);i+=1)
							if(W_inPoly[i] == 1)
								nump=dimsize(frp_frp_wve_temp,0)
								insertpoints/M=0 nump,1,frp_frp_wve_temp,frp_long_wve_temp,frp_lat_wve_temp,frp_landc_wve_temp,frp_vpd_wve_temp
								frp_frp_wve_temp[nump] = frp_frp_wve_sat_day[i]
								frp_long_wve_temp[nump] = frp_long_wve_sat_day[i]*frp_frp_wve_sat_day[i]
								frp_lat_wve_temp[nump] = frp_lat_wve_sat_day[i]*frp_frp_wve_sat_day[i]
								frp_landc_wve_temp[nump] = frp_landc_wve_sat_day[i]
								if(load_fail_vpd == 0)
									variable plume_long_point = ScaleToIndex(vpd_wve,frp_long_wve_sat_day[i],0)
									variable plume_lat_point = ScaleToIndex(vpd_wve,frp_lat_wve_sat_day[i],1) 
									frp_vpd_wve_temp[nump] = vpd_wve[plume_long_point][plume_lat_point]
								endif
							endif
						endfor
					 	killwaves W_inPoly
					
						//contours with majority -1 are skipped
						//-1 is bad land cover data
						variable majority_landc_min1 = 0
						wavestats/q	frp_landc_wve_temp
						variable landc_points = V_npnts
						histogram/B={-1,1,18}/dest=frp_landc_wve_temp_histo frp_landc_wve_temp
						wavestats/q frp_landc_wve_temp_histo
						if( (V_maxloc == -1) && ((V_max/landc_points) > 0.49) )
							majority_landc_min1 = 1
						endif
						killwaves frp_landc_wve_temp_histo
					
										
						if(majority_landc_min1 == 0)
									
							nump=dimsize(frp_cont_lat_wve,0)
							insertpoints/M=0 nump,1,frp_cont_lat_wve, frp_cont_long_wve
							insertpoints/M=0 nump,1,frp_cont_avg_wve, frp_cont_sdev_wve, frp_cont_med_wve, frp_cont_sum_wve, frp_cont_max_wve, frp_cont_npnts_wve, frp_cont_grid_npnts_wve
							insertpoints/M=0 nump,1,frp_cont_number_wve
							insertpoints/M=0 nump,1,frp_cont_landc_A_wve, frp_cont_landc_A_frac_wve, frp_cont_landc_B_wve, frp_cont_landc_B_frac_wve, frp_cont_landc_rest_frac_wve
							insertpoints/M=0 nump,1,frp_cont_vpd_avg_wve, frp_cont_vpd_sdev_wve, frp_cont_vpd_med_wve						
						
						
							wavestats/q frp_frp_wve_temp 
							frp_cont_avg_wve[nump] = V_avg
							frp_cont_sdev_wve[nump] = V_sdev
							frp_cont_med_wve[nump] = median(frp_frp_wve_temp)
							frp_cont_sum_wve[nump] = V_sum
							variable frp_sum = V_sum
							frp_cont_max_wve[nump] = V_max
							frp_cont_npnts_wve[nump] = V_npnts
							killwaves frp_frp_wve_temp
						
							frp_cont_number_wve[nump] = nump
																							
							//FRP cluster contour gets an average lat/long point
							wavestats/q frp_long_wve_temp
							frp_cont_long_wve[nump] = V_sum/frp_sum
							wavestats/q frp_lat_wve_temp
							frp_cont_lat_wve[nump] = V_sum/frp_sum
							killwaves frp_long_wve_temp,frp_lat_wve_temp 
																			
							wavestats/q	frp_landc_wve_temp
							landc_points = V_npnts
												
							histogram/B={-1,1,18}/dest=frp_landc_wve_temp_histo frp_landc_wve_temp
						
							wavestats/q frp_landc_wve_temp_histo
							frp_cont_landc_A_wve[nump] = V_maxloc
							frp_cont_landc_A_frac_wve[nump] = V_max/landc_points
							frp_landc_wve_temp_histo[V_maxRowLoc] = nan
							wavestats/q frp_landc_wve_temp_histo
							if(V_max > 0)
								frp_cont_landc_B_wve[nump] = V_maxloc
							endif	
							frp_cont_landc_B_frac_wve[nump] = V_max/landc_points
							if(frp_cont_landc_A_wve[nump] == 0)
								frp_cont_landc_A_wve[nump] = frp_cont_landc_B_wve[nump]
							endif		
												
							frp_cont_landc_rest_frac_wve[nump] = 1 - (frp_cont_landc_A_frac_wve[nump] + frp_cont_landc_B_frac_wve[nump])
							killwaves frp_landc_wve_temp, frp_landc_wve_temp_histo 
																	
							wavestats/q frp_vpd_wve_temp 
							frp_cont_vpd_avg_wve[nump] = V_avg
							frp_cont_vpd_sdev_wve[nump] = V_sdev
							frp_cont_vpd_med_wve[nump] = median(frp_vpd_wve_temp)
							killwaves frp_vpd_wve_temp 
												
							string contour_frp_x_wve_name = "contour_frp_x_" + num2str(nump)
							string contour_frp_y_wve_name = "contour_frp_y_" + num2str(nump)
							duplicate/o contour_grid_sum_x_wve_temp, $contour_frp_x_wve_name
							duplicate/o contour_grid_sum_y_wve_temp, $contour_frp_y_wve_name
						
							wavestats/q contour_grid_sum_x_wve_temp
							variable long_min = V_min
							variable long_max = V_max
							wavestats/q contour_grid_sum_y_wve_temp
							variable lat_min = V_min
							variable lat_max = V_max
						
							if(long_min < sat_long_wve[0])
								long_min = sat_long_wve[0]
							endif
							if(long_max > sat_long_wve[numpnts(sat_long_wve)-1])
								long_max = sat_long_wve[numpnts(sat_long_wve)-1]
							endif
							if(lat_max > sat_lat_wve[0])
								lat_max = sat_lat_wve[0]
							endif
							if(lat_min < sat_lat_wve[numpnts(sat_lat_wve)-1])
								lat_min = sat_lat_wve[numpnts(sat_lat_wve)-1]
							endif
													
							duplicate/o/rmd=(long_min,long_max)(lat_max,lat_min) sat_long_matrix, sat_long_matrix_temp
							duplicate/o/rmd=(long_min,long_max)(lat_max,lat_min) sat_lat_matrix, sat_lat_matrix_temp
						
							make/o/d/n=(dimsize(sat_long_matrix_temp,0)*dimsize(sat_long_matrix_temp,1)) sat_long_cont_wve_1d=nan, sat_lat_cont_wve_1d=nan 
								
							variable col_num =dimsize(sat_long_matrix_temp,1) 
							for(i=0;i<dimsize(sat_long_matrix_temp,0);i+=1)
								for(j=0;j<dimsize(sat_long_matrix_temp,1);j+=1)
									sat_long_cont_wve_1d[i*col_num+j] = sat_long_matrix_temp[i][j]
									sat_lat_cont_wve_1d[i*col_num+j] = sat_lat_matrix_temp[i][j]
								endfor
							endfor	
						
							FindPointsInPoly sat_long_cont_wve_1d, sat_lat_cont_wve_1d, contour_grid_sum_x_wve_temp, contour_grid_sum_y_wve_temp
							wave W_inPoly
							wavestats/q W_inPoly
							frp_cont_grid_npnts_wve[nump] = V_sum
							killwaves W_inPoly, sat_long_cont_wve_1d,sat_lat_cont_wve_1d, sat_long_matrix_temp,sat_lat_matrix_temp 
						endif // ((majority_landc_min1_or_zero == 0) )
					endif	//wavestats/q W_inPoly; if(V_sum > frp_npnts_limit)
										
					killwaves frp_frp_wve_temp,frp_long_wve_temp,frp_lat_wve_temp,frp_landc_wve_temp,frp_vpd_wve_temp 			
					killwaves contour_grid_sum_x_wve_temp, contour_grid_sum_y_wve_temp
					counter_start = counter+1
								
				endif		//extracting one contour at time
					
			endfor // contour counter
			killwaves contour_grid_sum_x_wve, contour_grid_sum_y_wve					
			killwaves frp_grid_sum
			
			if(numpnts(frp_cont_lat_wve) == 0)
				killwaves frp_cont_lat_wve, frp_cont_long_wve
				killwaves frp_cont_avg_wve, frp_cont_sdev_wve, frp_cont_med_wve, frp_cont_sum_wve, frp_cont_max_wve, frp_cont_npnts_wve,frp_cont_grid_npnts_wve
				killwaves frp_cont_number_wve
				killwaves frp_cont_landc_A_wve, frp_cont_landc_A_frac_wve, frp_cont_landc_B_wve,frp_cont_landc_B_frac_wve, frp_cont_landc_rest_frac_wve
				killwaves frp_cont_vpd_avg_wve, frp_cont_vpd_sdev_wve, frp_cont_vpd_med_wve
			else
				frp_found = 1	
			
				//this sorting typically places the biggest fires at the top of the list
				SortColumns/r keyWaves={frp_cont_sum_wve,frp_cont_avg_wve,frp_cont_npnts_wve}, sortWaves={frp_cont_lat_wve,frp_cont_long_wve,frp_cont_avg_wve,frp_cont_sdev_wve,frp_cont_med_wve,frp_cont_sum_wve,frp_cont_max_wve,frp_cont_npnts_wve,frp_cont_grid_npnts_wve,frp_cont_number_wve,frp_cont_landc_A_wve,frp_cont_landc_A_frac_wve,frp_cont_landc_B_wve,frp_cont_landc_B_frac_wve,frp_cont_landc_rest_frac_wve,frp_cont_vpd_avg_wve,frp_cont_vpd_sdev_wve,frp_cont_vpd_med_wve}	
			
			endif
		endif //if(frp_start_found == 1)
	end	
		

//**********************************create_lat_long_1d_wve***********************************

function D_create_lat_long_1d_wve(input_matrix)
	wave input_matrix				
	
	
	//*****no changes below here *************************************************************************************
	
		string long_1d_wve_name = "long_wve_" + nameofwave(input_matrix) + "_1d"
		string lat_1d_wve_name = "lat_wve_" + nameofwave(input_matrix) + "_1d"
				
				duplicate/o input_matrix	,temp_matrix
				make/o/d/n=(dimsize(temp_matrix,0)) long_wve_temp_matrix
				make/o/d/n=(dimsize(temp_matrix,1)) lat_wve_temp_matrix
				copyscales temp_matrix, long_wve_temp_matrix
				long_wve_temp_matrix = x
				matrixtranspose temp_matrix
				copyscales temp_matrix, lat_wve_temp_matrix
				lat_wve_temp_matrix = x
				killwaves temp_matrix
				
				make/o/d/n=(dimsize(input_matrix,0)*dimsize(input_matrix,1)) $long_1d_wve_name=nan,$lat_1d_wve_name=nan 
				wave long_1d_wve = $long_1d_wve_name
				wave lat_1d_wve = $lat_1d_wve_name 
				variable col_num =dimsize(input_matrix,1) 
				variable i,j
				for(i=0;i<dimsize(input_matrix,0);i+=1)
					for(j=0;j<dimsize(input_matrix,1);j+=1)
						long_1d_wve[i*col_num+j] = long_wve_temp_matrix[i]
						lat_1d_wve[i*col_num+j] = lat_wve_temp_matrix[j]
					endfor
				endfor
				killwaves long_wve_temp_matrix,lat_wve_temp_matrix 				
						
	end


//***********************************NO2 contouring and plume deliniation******************************

function 	[variable NO2_max_in_cont,variable NO2_cont_closed, variable cont_start_size, variable cont_grow_size]E_check_contour_for_frp_NO2_max_and_closedness(variable box_dim_long, variable box_dim_lat)
					
	wave no2_point_long_wve,	no2_point_lat_wve
	wave NO2_contour_x_wve, NO2_contour_y_wve
	
	// need to first find which NO2 contour within the analysis box containes the NO2 maximum belonging to
	// the currently anayzed FRP cluster 
	
	//*****no changes below here *************************************************************************************
	
		variable counter, counter_start=0
		//contours are separated by nans in lat and long waves
    	//adding nan at the end of the wave for easier search below
    	variable nump2 = numpnts(NO2_contour_x_wve)
    	insertpoints nump2,1,NO2_contour_x_wve,NO2_contour_y_wve 
    	NO2_contour_x_wve[nump2] = nan
    	NO2_contour_y_wve[nump2] = nan 
    					
    	for(counter=0;counter<numpnts(NO2_contour_x_wve);counter+=1)
    		
    		if(counter_start >= numpnts(NO2_contour_x_wve))
    			break
    		endif
    		 		    				
    		
    		if(numtype(NO2_contour_x_wve[counter]) == 2)
    					
    			//ignoring too little contours
    			if((counter-1-counter_start) < 3)
    				counter_start = counter+1	
    				continue
    			endif	
    			
    			duplicate/o/r=[counter_start,counter-1] NO2_contour_x_wve, NO2_contour_x_wve_temp
    			duplicate/o/r=[counter_start,counter-1] NO2_contour_y_wve, NO2_contour_y_wve_temp
    				    					    					   				
    			//no2 max in contour?
    			FindPointsInPoly no2_point_long_wve, no2_point_lat_wve, NO2_contour_x_wve_temp, NO2_contour_y_wve_temp
				wave W_inPoly
				wavestats/q W_inPoly
				killwaves W_inPoly
				if(V_sum == 0)
													
					killwaves NO2_contour_x_wve_temp, NO2_contour_y_wve_temp
    				counter_start = counter+1	
    				continue
    					
    			else
    				duplicate/o NO2_contour_x_wve_temp, NO2_contour_x_wve_cont
    				duplicate/o NO2_contour_y_wve_temp, NO2_contour_y_wve_cont
    				killwaves NO2_contour_x_wve_temp, NO2_contour_y_wve_temp
    				NO2_max_in_cont = 1
					break
    			
    			endif
    		
    		endif	// (numtype(NO2_contour_x_wve[counter]) == 2)	
    	endfor // all NO2 contours within plume box	
			

		if(NO2_max_in_cont == 1)
			
			variable endpoint_x_diff = abs(NO2_contour_x_wve_cont[0]-NO2_contour_x_wve_cont[numpnts(NO2_contour_x_wve_cont)-1])
    		variable endpoint_y_diff = abs(NO2_contour_y_wve_cont[0]-NO2_contour_y_wve_cont[numpnts(NO2_contour_y_wve_cont)-1])
    				
    		if( (endpoint_x_diff == 0) && (endpoint_y_diff == 0) )
				
				NO2_cont_closed = 1
			
			endif
		
		endif //(NO2_max_in_cont == 1)			
		
		if( (NO2_max_in_cont == 1) && (NO2_cont_closed == 1)	 )
			cont_grow_size = numpnts(NO2_contour_x_wve_cont) - cont_start_size
			cont_start_size = numpnts(NO2_contour_x_wve_cont) 
		endif	


end


//**************************************create_merged_frp_info***************************************

function F_create_merged_frp_info(frp_counter,W_inPoly,nump)
	variable frp_counter
	wave W_inPoly	
	variable nump
			
	wave frp_cont_number_wve, frp_cont_long_wve, frp_cont_lat_wve,frp_cont_grid_npnts_wve 
	wave frp_long_wve_sat_day, frp_lat_wve_sat_day	,frp_frp_wve_sat_day,frp_landc_wve_sat_day, vpd_wve
	svar results_wve_name
	nvar load_fail_vpd	
			
	//*****no changes below here *************************************************************************************
		wave results_wve = $results_wve_name	
		variable nump2
		
		make/o/d/n=1 merge_contour_num_wve_temp				
		//this is the current frp contour	
		merge_contour_num_wve_temp[0] = frp_cont_number_wve[frp_counter]	
		frp_cont_number_wve[frp_counter] = nan // to not double analyze
		frp_cont_long_wve[frp_counter] = nan // to not double analyze
		frp_cont_lat_wve[frp_counter] = nan // to not double analyze
								
			
		//if current plume outline does contain other frp points,those are identified
		variable i
		for(i=0;i<numpnts(W_inPoly);i+=1)
			
			if( (W_inPoly[i] == 1) && (i != frp_counter) ) // this would be the current one  
							
				if(i < frp_counter)
					//labeling frp point that has been processed before but failed - indicated by numtype(results_wve[ii][%plume_npnts]) == 2
					// will be merged here and later deleted from result table
					variable ii, frp_old_fail=0
					for(ii=0;ii<dimsize(results_wve,0);ii+=1)
						if( (results_wve[ii][%frp_lat] == frp_cont_lat_wve[i]) && (numtype(results_wve[ii][%plume_npnts]) == 2) )
							results_wve[ii][%frp_merged] = -1
							frp_old_fail=1
							break
						endif
					endfor			
				endif
				if( (i > frp_counter) || (frp_old_fail == 1) )
					nump2=dimsize(merge_contour_num_wve_temp,0)
					insertpoints/M=0 nump2,1,merge_contour_num_wve_temp	
					merge_contour_num_wve_temp[nump2] = frp_cont_number_wve[i]
					results_wve[nump][%frp_grid_npnts] = results_wve[nump][%frp_grid_npnts] + frp_cont_grid_npnts_wve[i] 
					frp_cont_number_wve[i] = nan // to not double analyze
					frp_cont_long_wve[i] = nan // to not double analyze
					frp_cont_lat_wve[i] = nan // to not double analyze
				endif	
			endif
		endfor
		killwaves W_inPoly
		
		if(numpnts(merge_contour_num_wve_temp) > 1) //can have 1 when it found a prior frp point that was successfully analyzed 
			
			make/o/d/n=0 frp_frp_wve_temp_merge,frp_long_wve_temp_merge,frp_lat_wve_temp_merge,frp_landc_wve_temp_merge,frp_vpd_wve_temp_merge
					
			variable counter
			for(counter=0;counter<numpnts(merge_contour_num_wve_temp);counter+=1)
				wave frp_contour_x_wve_temp = $("contour_frp_x_" + num2str(merge_contour_num_wve_temp[counter]))
				wave frp_contour_y_wve_temp = $("contour_frp_y_" + num2str(merge_contour_num_wve_temp[counter]))
												
				FindPointsInPoly frp_long_wve_sat_day, frp_lat_wve_sat_day, frp_contour_x_wve_temp, frp_contour_y_wve_temp
				wave W_inPoly
				wavestats/q W_inPoly
						
				for(i=0;i<dimsize(W_inPoly,0);i+=1)
					if(W_inPoly[i] == 1)
						nump2=dimsize(frp_frp_wve_temp_merge,0)
						insertpoints/M=0 nump2,1,frp_frp_wve_temp_merge,frp_long_wve_temp_merge,frp_lat_wve_temp_merge,frp_landc_wve_temp_merge,frp_vpd_wve_temp_merge
						frp_frp_wve_temp_merge[nump2] = frp_frp_wve_sat_day[i]
						frp_long_wve_temp_merge[nump2] = frp_long_wve_sat_day[i]
						frp_lat_wve_temp_merge[nump2] = frp_lat_wve_sat_day[i]
						frp_landc_wve_temp_merge[nump2] = frp_landc_wve_sat_day[i]
						if(load_fail_vpd == 0)
							variable plume_long_point = ScaleToIndex(vpd_wve,frp_long_wve_sat_day[i],0)
							variable plume_lat_point = ScaleToIndex(vpd_wve,frp_lat_wve_sat_day[i],1) 
							frp_vpd_wve_temp_merge[nump2] = vpd_wve[plume_long_point][plume_lat_point]
						endif
					endif
				endfor
				killwaves W_inPoly		 
			
									
			endfor
		
			make/o/d/n=1 frp_cont_landc_A_merge, frp_cont_landc_A_frac_merge
			make/o/d/n=1 frp_cont_landc_B_merge, frp_cont_landc_B_frac_merge
			make/o/d/n=1 frp_cont_landc_rest_frac_merge, frp_cont_landc_npnts_merge
		
					
			wavestats/q	frp_landc_wve_temp_merge
			variable landc_points = V_npnts
			frp_cont_landc_npnts_merge[0] = V_npnts
						
			histogram/B={-1,1,18}/dest=frp_landc_wve_temp_histo frp_landc_wve_temp_merge
						
			wavestats/q frp_landc_wve_temp_histo
			frp_cont_landc_A_merge[0] = V_maxloc
			frp_cont_landc_A_frac_merge[0] = V_max/landc_points
			frp_landc_wve_temp_histo[V_maxRowLoc] = nan
			wavestats/q frp_landc_wve_temp_histo
			if(V_max > 0)
				frp_cont_landc_B_merge[0] = V_maxloc
			endif	
			frp_cont_landc_B_frac_merge[0] = V_max/landc_points
						
			frp_cont_landc_rest_frac_merge[0] = 1 - (frp_cont_landc_A_frac_merge[0] + frp_cont_landc_B_frac_merge[0])
			killwaves frp_landc_wve_temp_merge, frp_landc_wve_temp_histo 
						
			//in case landc_A is now 0 or -1, then switching to landc_B
			if( (frp_cont_landc_A_merge[0] == 0) || (frp_cont_landc_A_merge[0] == -1) )
				variable landc_A_temp = frp_cont_landc_A_merge[0]
				variable landc_A_temp_frac = frp_cont_landc_A_frac_merge[0]
				frp_cont_landc_A_merge[0] = frp_cont_landc_B_merge[0]
				frp_cont_landc_A_frac_merge[0] = frp_cont_landc_B_frac_merge[0]
				frp_cont_landc_B_merge[0] = landc_A_temp
				frp_cont_landc_B_frac_merge[] = landc_A_temp_frac
			endif	
		
			results_wve[nump][%frp_merged] = numpnts(merge_contour_num_wve_temp)
			killwaves merge_contour_num_wve_temp 
					
			wavestats/q frp_long_wve_temp_merge
			results_wve[nump][%frp_long] = V_avg
			wavestats/q frp_lat_wve_temp_merge
			results_wve[nump][%frp_lat] = V_avg
			killwaves frp_long_wve_temp_merge,frp_lat_wve_temp_merge 
																
			wavestats/q frp_frp_wve_temp_merge 
			results_wve[nump][%frp_avg] = V_avg
			results_wve[nump][%frp_sdev] = V_sdev
			results_wve[nump][%frp_med] = median(frp_frp_wve_temp_merge)
			results_wve[nump][%frp_sum] = V_sum
			results_wve[nump][%frp_npnts] = V_npnts
			killwaves frp_frp_wve_temp_merge  
															
			results_wve[nump][%frp_landc_A] = frp_cont_landc_A_merge[0]
			results_wve[nump][%frp_landc_A_frac] = frp_cont_landc_A_frac_merge[0]
			results_wve[nump][%frp_landc_B] = frp_cont_landc_B_merge[0]
			results_wve[nump][%frp_landc_B_frac] = frp_cont_landc_B_frac_merge[0]
			results_wve[nump][%frp_landc_rest_frac] = frp_cont_landc_rest_frac_merge[0]
			killwaves frp_cont_landc_A_merge, frp_cont_landc_A_frac_merge
			killwaves frp_cont_landc_B_merge, frp_cont_landc_B_frac_merge
			killwaves frp_cont_landc_rest_frac_merge, frp_cont_landc_npnts_merge
				
			if(load_fail_vpd == 0)
				wavestats/q frp_vpd_wve_temp_merge
				results_wve[nump][%frp_vpd_avg] = V_avg
				results_wve[nump][%frp_vpd_sdev] = V_sdev
				results_wve[nump][%frp_vpd_med] = median(frp_vpd_wve_temp_merge)
			endif
			killwaves frp_vpd_wve_temp_merge
		
		endif //if(numpnts(merge_contour_num_wve_temp) > 1)
		killwaves/z merge_contour_num_wve_temp 
						
	end	
		
					
//*********************************************G_populate_stats_and_fit_wves******************************

function 	[variable no2_co_stats_fail,variable aer_stats_fail,variable plume_npnts]G_populate_stats_and_fit_wves()
	
	
	nvar NO2_plume_threshold, CO_plume_threshold, aod_plume_threshold
		
	nvar plume_npnts_limit, plume_frac_limit, bg_npnts_limit
	
	wave long_wve_NO2_wve_box_1d, lat_wve_NO2_wve_box_1d, NO2_contour_x_wve_cont, NO2_contour_y_wve_cont			
	wave frp_contour_x_wve, frp_contour_y_wve
	wave NO2_wve_box, CO_wve_box, aod_wve_box,ssa_wve_box
	wave NO2_wve, CO_wve, aod_wve, ssa_wve
	
	
	//*****no changes below here *************************************************************************************
	
		//waves for plume stats
      	make/o/d/n=(dimsize(NO2_wve_box,0)*dimsize(NO2_wve_box,1)) no2_wve_plume_1d=nan, co_wve_plume_1d=nan
   		make/o/d/n=(dimsize(NO2_wve_box,0)*dimsize(NO2_wve_box,1)) aod_wve_plume_1d=nan, ssa_wve_plume_1d=nan
   		   		   		      
      make/o/d/n=(dimsize(NO2_wve_box,0)*dimsize(NO2_wve_box,1)) no2_wve_bg_1d=nan,co_wve_bg_1d=nan
   		make/o/d/n=(dimsize(NO2_wve_box,0)*dimsize(NO2_wve_box,1)) aod_wve_bg_1d=nan,ssa_wve_bg_1d=nan
            
      make/o/d/n=0 no2_co_wve_fit_1d=nan, co_no2_wve_fit_1d=nan
                 
      	variable i,j
      	
      	make/o/d/n=(numpnts(NO2_contour_x_wve_cont)) CO_threshold_wve_temp=nan, aod_threshold_wve_temp=nan
		
		for(i=0;i<numpnts(NO2_contour_x_wve_cont);i+=1)
			CO_threshold_wve_temp[i] = CO_wve(NO2_contour_x_wve_cont[i])(NO2_contour_y_wve_cont[i])
			aod_threshold_wve_temp[i] = aod_wve(NO2_contour_x_wve_cont[i])(NO2_contour_y_wve_cont[i])
		endfor
		
		CO_plume_threshold = median(CO_threshold_wve_temp)
		killwaves CO_threshold_wve_temp
		
		aod_plume_threshold = median(aod_threshold_wve_temp)
		killwaves aod_threshold_wve_temp
		
		
		if(numtype(CO_plume_threshold) == 0)
			
      		FindPointsInPoly long_wve_NO2_wve_box_1d, lat_wve_NO2_wve_box_1d,  NO2_contour_x_wve_cont, NO2_contour_y_wve_cont
			wave W_inPoly
			wavestats/q W_inPoly
			plume_npnts = V_sum	//number of pixels in plume
	 	 			
			variable col_num =dimsize(NO2_wve_box,1) 
			variable nump2
			for(i=0;i<dimsize(NO2_wve_box,0);i+=1)
				for(j=0;j<dimsize(NO2_wve_box,1);j+=1)
 				
 					//reversing nans set to 0 for contour lines
 					if(NO2_wve_box[i][j] == 0)
 						NO2_wve_box[i][j] = nan
 					endif			
 					//inside plume
					if(W_inPoly[i*col_num+j] == 1)
							
						no2_wve_plume_1d[i*col_num+j] = NO2_wve_box[i][j]
						co_wve_plume_1d[i*col_num+j] = co_wve_box[i][j]
						aod_wve_plume_1d[i*col_num+j] = aod_wve_box[i][j]
						ssa_wve_plume_1d[i*col_num+j] = ssa_wve_box[i][j]
																	
						if( (numtype(NO2_wve_box[i][j]) == 0) && (numtype(co_wve_box[i][j]) == 0) )
							nump2 = dimsize(no2_co_wve_fit_1d,0)
							insertpoints/M=0 nump2,1,no2_co_wve_fit_1d,co_no2_wve_fit_1d
							no2_co_wve_fit_1d[nump2] = NO2_wve_box[i][j]
							co_no2_wve_fit_1d[nump2] = co_wve_box[i][j]
						endif
																	
						//deleting plume from orbit NO2, CO, and aer to not interfere with later analyses
						variable plume_long_point = ScaleToIndex(NO2_wve,long_wve_NO2_wve_box_1d[i*col_num+j],0)
						variable plume_lat_point = ScaleToIndex(NO2_wve,lat_wve_NO2_wve_box_1d[i*col_num+j],1) 
						NO2_wve[plume_long_point][plume_lat_point] = nan
						CO_wve[plume_long_point][plume_lat_point] = nan
						aod_wve[plume_long_point][plume_lat_point] = nan
						ssa_wve[plume_long_point][plume_lat_point] = nan
																
									
					//outside plume
					else
					
						//BGs
						//Filtering ALL BGs by NO2 threshold
						if( (numtype(NO2_wve_box[i][j]) == 0) && (NO2_wve_box[i][j] < NO2_plume_threshold) )		
							no2_wve_bg_1d[i*col_num+j] = NO2_wve_box[i][j]
							
							//Filtering CO and AER BGs by CO threshold
							if( (numtype(CO_wve_box[i][j]) == 0) && (CO_wve_box[i][j] < CO_plume_threshold) )		
								co_wve_bg_1d[i*col_num+j] = co_wve_box[i][j]
																
								//Filtering AER BGs by AOD threshold
								if( (numtype(aod_wve_box[i][j]) == 0) && (aod_wve_box[i][j] < aod_plume_threshold) )	
									aod_wve_bg_1d[i*col_num+j] = aod_wve_box[i][j]
									ssa_wve_bg_1d[i*col_num+j] = ssa_wve_box[i][j]
								endif						
							
							endif //co filter
						
						endif //no2 filter
						
						//Filtering CO BG average wave
						if( (numtype(CO_wve_box[i][j]) == 0) && (CO_wve_box[i][j] > CO_plume_threshold) )	
							plume_long_point = ScaleToIndex(NO2_wve,long_wve_NO2_wve_box_1d[i*col_num+j],0)
							plume_lat_point = ScaleToIndex(NO2_wve,lat_wve_NO2_wve_box_1d[i*col_num+j],1) 
						endif	
							
						if( (numtype(NO2_wve_box[i][j]) == 0) && (numtype(co_wve_box[i][j]) == 0) )
							if( (NO2_wve_box[i][j] < NO2_plume_threshold) && (CO_wve_box[i][j] < CO_plume_threshold) ) 
								nump2 = dimsize(no2_co_wve_fit_1d,0)
								insertpoints/M=0 nump2,1,no2_co_wve_fit_1d,co_no2_wve_fit_1d
								no2_co_wve_fit_1d[nump2] = NO2_wve_box[i][j]
								co_no2_wve_fit_1d[nump2] = co_wve_box[i][j]
							endif
						endif							
														
					endif //inside or outside plume
								
				endfor	//j
			endfor	//i
			killwaves W_inPoly	
			
			wavestats/q no2_wve_plume_1d
			if( (V_npnts <= plume_npnts_limit) || ((V_npnts/plume_npnts) <= plume_frac_limit) )
				no2_co_stats_fail = 1
			endif	
			wavestats/q co_wve_plume_1d
			if( (V_npnts <= plume_npnts_limit) || ((V_npnts/plume_npnts) <= plume_frac_limit) )
				no2_co_stats_fail = 1
			endif
								
			if( (numpnts(no2_wve_bg_1d) <= bg_npnts_limit) || (numpnts(co_wve_bg_1d) <= bg_npnts_limit) )  
				no2_co_stats_fail = 1
			endif
		
		else
		
			no2_co_stats_fail = 1
		
		endif //if(numtype(CO_plume_threshold) == 0)
		
		if(no2_co_stats_fail == 1)
			
			killwaves	 no2_wve_plume_1d, co_wve_plume_1d
			killwaves aod_wve_plume_1d, ssa_wve_plume_1d
			killwaves no2_wve_bg_1d, co_wve_bg_1d
			killwaves aod_wve_bg_1d, ssa_wve_bg_1d
			killwaves no2_co_wve_fit_1d, co_no2_wve_fit_1d
					
		else
			     
      		wavestats/q aod_wve_plume_1d
			if( (V_npnts <= plume_npnts_limit) || ((V_npnts/plume_npnts) <= plume_frac_limit) )
				aer_stats_fail = 1
			endif	
			wavestats/q ssa_wve_plume_1d
			if( (V_npnts <= plume_npnts_limit) || ((V_npnts/plume_npnts) <= plume_frac_limit) )
				aer_stats_fail = 1
			endif
			wavestats/q aod_wve_bg_1d
			if(V_npnts <= bg_npnts_limit)
				aer_stats_fail = 1
			endif	
						
			if(aer_stats_fail == 1)
				killwaves aod_wve_plume_1d,ssa_wve_plume_1d,aod_wve_bg_1d,ssa_wve_bg_1d
			endif	   
			
							
		endif // (no2_co_stats == 1)	
					
	end												
				

