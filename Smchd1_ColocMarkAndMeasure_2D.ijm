#@ String (visibility=MESSAGE, value="Script Parameters") asdf
#@ File (label="Input directory", style=directory) dir1
#@ String (label="Annotate or Analyse", choices={"Annotate","Analyse"}, style="radioButtonVertical") annotateOrAnalyse
#@ int (label="Alexa647 (smchd1) Channel", style=slider, min=1,max=3,stepSize=1) a647
#@ int (label="Alexa488 Channel", style=slider, min=1,max=3,stepSize=1) a488
#@ Boolean (label="Debug mode",default=false) debugMode



Table_Heading = "Nuclear Intensity Measures";
columns = "Filename, ROI Number, Mean Smchd1 Region Intensity, Mean Cell Region Instensity";
columns = split(columns,",");
table = generateTable(Table_Heading,columns);

//sanity check
if(a647==a488){
	exit("Alexa647 and Alexa488 can't be in the same channel");
}
if(a647==0 || a488==0){
	exit("Channels not set correctly - channels index from 1");
}

run("Close All");
print("\\Clear");

dir1 = dir1 + File.separator();

dir2 = dir1 + "output" + File.separator();
if(!File.exists(dir2)){
	File.makeDirectory(dir2);
}

if(annotateOrAnalyse == "Annotate"){
	print("Annotate");
	annotate(dir1);
	
}else{
	print("Analyse like a mofo");
	analyse(dir1);	
}

function analyse(dir1){
	setBackgroundColor(0,0,0);
	flist = getFileList(dir1);
	for(i=0;i<flist.length;i++){
		if(endsWith(flist[i],"czi")){
			fpath = dir1+flist[i];
			run("Bio-Formats Importer", "open=["+fpath+"] color_mode=Default rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT");
			fname = getTitle();
			roiFile = dir2+flist[i]+"_rois.zip";
			if(File.exists(roiFile)){
				closeRoiManager();
				run("ROI Manager...");
				roiManager("Open",roiFile);
				for(r=0;r<roiManager("Count");r++){
					roiManager("Select",r);
					run("Duplicate...","duplicate title=toProcess");					
					run("Clear Outside","stack");
					
					//This is the image that gets measured - a488
					run("Duplicate...","duplicate title=toMeasure channels="+a488);
					selectWindow("toProcess");
					smchd = findSmchdRegion();	
					
					selectWindow("toProcess");
					wholeCell = findWholeCellRegion();
							
					selectWindow(flist[i]);
					res = newArray(fname,r,smchd,wholeCell);
					logResults(table,res);
					
					print(smchd +", \t " + wholeCell);
					selectWindow("toProcess");
					run("Z Project...", "projection=[Max Intensity]");
					for(c=1;c<=2;c++){Stack.setChannel(c);resetMinAndMax();}
					run("Make Composite");
					run("RGB Color");
					run("Merge Channels...", "c1=maxSmchd c2=wholeCellMask create");
					run("RGB Color");
									
					run("Combine...", "stack1=[MAX_toProcess (RGB)] stack2=[Composite (RGB)]");
					saveAs("Jpeg",dir2+fname+"_region"+r+".jpg");
					
					selectWindow(fname);
					close("\\Others");
					closeRoiManager();
					run("ROI Manager...");
					roiManager("Open",roiFile);
					
					
				}
			}
		}
	}
}


function findWholeCellRegion(){
	//uses all channels to create cell mask
	run("Duplicate...","title=tmp channels=1-3 duplicate");
	run("Split Channels");
	run("Image Expression Parser (Macro)", "expression=A+B+C a=C1-tmp b=C2-tmp c=C3-tmp d=None e=None f=None g=None h=None");
	run("Duplicate...","title=asdf duplicate");
	run("Z Project...","projection=[Max Intensity]");
	run("Median...","radius=3");
	
	setAutoThreshold("Default dark");

	//measurements redirecte to "toMeasure" image - created above using a488 channel
	run("Set Measurements...", "mean redirect=toMeasure decimal=3");
	run("Analyze Particles...", "size=100-Infinity pixel show=Masks display clear add stack");
	rename("wholeCellMask");
	if(nResults()==1){
		wholeCell = getResult("Mean");
	}else{
		run("Summarize");
		wholeCell = getResult("Mean",nResults()-4);
	}
	run("Grays");
	
	close("C*");
	close("tmp");
	close("asdf");
	close("Parsed*");
	
	return wholeCell;



	
}

function findSmchdRegion(){
	//uses the a647 channel to find smchd1
	
	run("Duplicate...","title=tmp channels="+a647+" duplicate");
	run("Median 3D...", "x=3 y=3 z=1");
	run("Z Project...", "projection=[Max Intensity]");
	
	setAutoThreshold("Yen dark stack");
	
	run("Convert to Mask", "method=Yen background=Dark black");
	
	run("Median...","radius=3");
	rename("smchdRegion");
	//redirected measurements to a488 channel
	run("Set Measurements...", "mean redirect=toMeasure decimal=3");
	run("Analyze Particles...", "size=100-Infinity pixel display clear add stack");
	
	if(nResults==1){
		mSmchd = getResult("Mean");
	}else{
		run("Summarize");
		mSmchd = getResult("Mean",nResults()-4);
	}
	
	rename("maxSmchd");
	
	
	return mSmchd;	
}


function annotate(dir1){

	flist = getFileList(dir1);
	for(i=0;i<flist.length;i++){		
		if(endsWith(flist[i],"czi")){
			roiFile = dir2+flist[i]+"_rois.zip";
			fpath = dir1+flist[i];	
			if(!File.exists(roiFile)){			
				openAndDisplayMIP(fpath);
				setTool("polygon");
				waitForUser("Draw rois around cells, press t after each");	
				if(roiManager("Count")==0){
					roiManager("Add");		
				}
				roiManager("Save",dir2+flist[i]+"_rois.zip");
				closeRoiManager();
				run("Close All");
			}else{
				doMore = checkForMore(fpath,roiFile);
				if(doMore){
					setTool("polygon");
					waitForUser("Draw rois around cells, press t after each");			
					roiManager("Save",dir2+flist[i]+"_rois.zip");
					closeRoiManager();
					run("Close All");	
				}else{
					run("Close All");
				}						
			}
		}
	}
}


function checkForMore(fpath,roiFile){
	fname = File.getName(fpath);
	if(!isOpen(fname)){
		openAndDisplayMIP(fpath);
		mip = getTitle();
	}else{
		print("Image already open");		
	}
	if(!File.exists(roiFile)){
		print("No File");
	}else{
		print("Roi file found");
		closeRoiManager();
		run("ROI Manager...");
		roiManager("Open",roiFile);
	}

	selectWindow(mip);
	roiManager("Show All");

	more = 	getBoolean("Do More?");
	return more;



}

function openAndDisplayMIP(fpath){
	run("Bio-Formats Importer", "open=["+fpath+"] color_mode=Default rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT");
	fname = getTitle();
	run("Z Project...", "projection=[Max Intensity]");
	for(c=1;c<=3;c++){Stack.setChannel(c);resetMinAndMax();}
	run("Make Composite");
}

function extractRegions(fpath,roiFile){
	fname = File.getName(fpath);
	if(!isOpen(fname)){
		run("Bio-Formats Importer", "open=["+fpath+"] color_mode=Default rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT");		
	}else{
		print("Image already open");		
	}
	if(!File.exists(roiFile)){
		print("No File");
	}else{
		print("Roi file found");
		closeRoiManager();
		run("ROI Manager...");
		roiManager("Open",roiFile);
	}

	selectWindow(fname);
	roiManager("Select");
	


	
}


function closeRoiManager(){
	if(isOpen("ROI Manager")){
		selectWindow("ROI Manager");
		run("Close");
	}
}




//Generate a custom table
//Give it a title and an array of headings
//Returns the name required by the logResults function
function generateTable(tableName,column_headings){
	if(isOpen(tableName)){
		selectWindow(tableName);
		run("Close");
	}
	tableTitle=tableName;
	tableTitle2="["+tableTitle+"]";
	run("Table...","name="+tableTitle2+" width=600 height=250");
	newstring = "\\Headings:"+column_headings[0];
	for(i=1;i<column_headings.length;i++){
			newstring = newstring +" \t " + column_headings[i];
	}
	print(tableTitle2,newstring);
	return tableTitle2;
}


//Log the results into the custom table
//Takes the output table name from the generateTable funciton and an array of resuts
//No checking is done to make sure the right number of columns etc. Do that yourself
function logResults(tablename,results_array){
	resultString = results_array[0]; //First column
	//Build the rest of the columns
	for(i=1;i<results_array.length;i++){
		resultString = toString(resultString + " \t " + results_array[i]);
	}
	//Populate table
	print(tablename,resultString);
}