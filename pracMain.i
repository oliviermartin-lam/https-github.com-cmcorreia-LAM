include, "pracDm.i"; 
include, "pracBwfit.i"; 
include, "pracTomography.i";
include, "pracLmfit.i";
include, "pracLearn.i";
include, "pracErrorbreakdown.i";
include, "pracAtmosphere.i";

include, "telescopeUtils.i"; 
include, "noiseUtils.i";
include, "imageUtils.i";
include, "contextUtils.i";
include, "fitsUtils.i";
include, "mathUtils.i";
include, "displayUtils.i";
include, "constantUtils.i";
include, "zernikeUtils.i";


pldefault,font="times";
pldefault,palette="earth.gp";
pltitle_font = "times";

func pracMain(timedata,averageMode=,Dir=,verb=,disp=)
/*DOCUMENT p = pracMain("02h31m34s",verb=1,disp=0); p = pracMain("02h30m48s",verb=1,disp=1);p = pracMain("02h31m11s",verb=1,disp=1);
 
 */
{

  tic,10;
  include, "pracConfig.i",1;
  if(Dir){
    procDir = Dir;
    dataDirRoot = dataDir + procDir;
  }

  geometry = "square";

  /////////////////////
  //.... Initializing the data struct
  //////////////////////////////////////////////////////////
  
  include, "pracStructConfig.i",1;
  define_structs,timedata,verb=verb;

  /////////////////////
  // .... perfect telescope OTF
  //////////////////////////////////////////////////////////
  
  OTF_tel = OTF_telescope(tel.diam,tel.obs,tel.nPixels,tel.pixSize);

  /////////////////////
  // .... OTF from response delay time of the system
  //////////////////////////////////////////////////////////
  
  OTF_bw = computeOTFbandwidth(geometry,rtc.obsMode,verb=verb);

  /////////////////////
  // .... OTF from fitting error
  //////////////////////////////////////////////////////////
  
  OTF_fit = computeOTFfitting(geometry,verb=verb);

  /////////////////////
  // .... OTF from static aberration except NCPA
  //////////////////////////////////////////////////////////
  
  OTF_telstats  =  computeOTFstatic(PSF_stats);//telescope and ncpa included

  /////////////////////
  // .... OTF from tomographic residue, mode = "Uij", "Vii" or "intersample"
  //////////////////////////////////////////////////////////////////////////////
  
  OTF_tomo = computeOTFtomographic(averageMode,verb=verb);

  /////////////////////
  // .... OTF at the TS location
  //////////////////////////////////////////////////////////
  
  OTF_ts = OTF_fit * OTF_bw * OTF_tomo * OTF_telstats ; //telescope included into OTF_stats

  /////////////////////
  // .... OTF from NCPA
  //////////////////////////////////////////////////////////
  oncpa = getOTFncpa(cam.nPixelsCropped,procDir,SR_best,PSF_ncpa,disp=disp);
  budget.SRncpa = SR_best;
  psf.ncpa     = &PSF_ncpa;
  
  //computing a fake ncpa without telescope contribution
  OTF_ncpa = computeFakeOTFncpa(budget.SRncpa);

  // multiplying by NCPA OTF
  OTF_res  = OTF_ts * OTF_ncpa;


  /////////////////////
  // ..... Reconstructed PSF
  //////////////////////////////////////////////////////////

  PSF_res  = roll( fft(OTF_res).re );

  //cropping
  nm = (tel.nPixels - cam.nPixelsCropped)/2+1;
  np = (tel.nPixels +  cam.nPixelsCropped)/2;
  PSF_res =  PSF_res(nm:np,nm:np);
  psf.res  = &PSF_res;
  otf.res  = &roll(fft(roll(*psf.res)).re);
  
  /////////////////////
  // .... Processing the sky PSF
  //////////////////////////////////////////////////////////

  //to fixe the maximum Intensity at the middle
  OTF_sky = roll(*otf.sky);
  PSF_sky = roll(fft(OTF_sky).re);
  
  //normalization
  PSF_sky /= sum(PSF_sky);
  PSF_sky /= tel.airyPeak;
  psf.sky  = &PSF_sky;
  
  // ... differential PSF
  
  PSF_diff = abs(PSF_sky - PSF_res);
  diffPSF = sum(PSF_diff(*)^2)/sum(PSF_sky(*)^2);
  psf.diff  = &PSF_diff;
  
  /////////////////////
  // .... Error breakdown computation
  //////////////////////////////////////////////////////////
  
  SR_tomo  = sum(OTF_tomo * OTF_tel);
  SR_bw    = sum(OTF_bw * OTF_tel);
  SR_fit   = sum(OTF_fit * OTF_tel);
  SR_stats = sum(OTF_telstats);
  SR_cpa   = sum(OTF_ts);
  SR_sky   = max(PSF_sky);
  SR_res   = max(PSF_res);
  
  budget.ncpa  = sr2var(SR_best,cam.lambda);
  budget.SRsky = 100*SR_sky;
  
  PRAC_errorbreakdown,verb=verb;

  psf.SR_tomo  = 100*SR_tomo;
  psf.SR_bw    = 100*SR_bw;
  psf.SR_fit   = 100*SR_fit;
  psf.SR_stats = 100*SR_stats;
  psf.SR_cpa   = 100*SR_cpa;
  
  /////////////////////
  // .... storaging otf in structs
  //////////////////////////////////////////////////////////
  
  otf.tel    = &roll(OTF_tel);
  otf.fit    = &roll(OTF_fit);
  otf.bw     = &roll(OTF_bw);
  otf.tomo   = &roll(OTF_tomo);
  otf.ncpa   = &roll(OTF_ncpa);
  otf.static = &roll(OTF_telstats);
  otf.ts     = &roll(OTF_ts);
  otf.cpa    = &roll(OTF_cpa);
  otf.ts_cropped = &roll(OTF_ts_cropped);
  
  otel = roll(OTF_telescope(tel.diam,tel.obs,cam.nPixelsCropped,tel.pixSize*tel.nPixels/cam.nPixelsCropped));
  
  /////////////////////
  // ..... Getting Ensquared Energy and FWHM on both reconstructed/sky PSF
  //////////////////////////////////////////////////////////
  
  boxsize = EE = EE_sky = span(1,cam.nPixelsCropped-3.,cam.nPixelsCropped) * cam.pixSize;
  for(i=1; i<=cam.nPixelsCropped; i++){
    EE(i) = getEE( 100*PSF_res/sum(PSF_res), cam.pixSize, boxsize(i));
    EE_sky(i) = getEE(100*PSF_sky/sum(PSF_sky), cam.pixSize, boxsize(i));
  }

  psfsky = PSF_sky(cam.nPixelsCropped/2+1:,cam.nPixelsCropped/2+1);
  fwhmSky = getFWHM(psfsky/max(psfsky),tel.pixSize);
  psfres = PSF_res(cam.nPixelsCropped/2+1:,cam.nPixelsCropped/2+1);
  fwhmRes = getFWHM(psfres/max(psfres),tel.pixSize);

    
  psf.EE_res   = &EE;
  psf.EE_sky   = &EE_sky;
  psf.SR_res   = SR_res;
  psf.SR_sky   = SR_sky;
  psf.FWHM_sky = fwhmSky;
  psf.FWHM_res = fwhmRes;

  
  /////////////////////
  // .... Display and verbose
  //////////////////////////////////////////////////////////
  if(disp){
    l = cam.nPixelsCropped * cam.pixSize;
    window,0; clr;logxy,0,0; pli, *psf.ncpa,-l/2,-l/2,l/2,l/2,cmin=0;
    pltitle,"Best bench PSF with SR = " + var2str(arrondi(100*SR_best,1))+"%";
    xytitles,"Arcsec","Arcsec";
  
    window,1; clr;pli, *psf.res,-l/2,-l/2,l/2,l/2,cmin=0,cmax = SR_sky;
    pltitle,"Reconstructed PSF with SR = " + var2str(arrondi(100*SR_res,1))+"%";
    xytitles,"Arcsec","Arcsec";
  
    window,2; clr;pli, *psf.sky,-l/2,-l/2,l/2,l/2,cmin=0,cmax = SR_sky;
    pltitle,"On-sky PSF with SR = " + var2str(arrondi(100*SR_sky,1)) +"%";
    xytitles,"Arcsec","Arcsec";
  
    window,3; clr; pli, *psf.diff,-l/2,-l/2,l/2,l/2,cmin=0,cmax = SR_sky;
    pltitle,"Residual of the reconstruction ";
    xytitles,"Arcsec","Arcsec";
  
    winkill,4;window,4,style="aanda.gs",dpi=90;clr;
    y = [budget.res,
         budget.tomo,
         budget.alias,
         budget.noise,
         budget.bw,
         budget.fit,
         budget.ol,
         budget.static,
         budget.ncpa];
    labs = ["!s_IR",
            "!s_tomo",
            "!s_alias",
            "!s_noise",
            "!s_bw",
            "!s_fit",
            "!s_ol",
            "!s_static",
            "!s_ncpa"];

    plotsBarDiagram,y,labs,col1=[char(241)],title=1;
  
    winkill,5;window,5,style="aanda.gs",dpi=90;clr;
    plg, *psf.EE_res, boxsize,color=[128,128,128];
    plg, *psf.EE_sky, boxsize;
    plg, [100,100],[-0.1,max(boxsize)*1.05],type=2,marks=0;
    xytitles,"Angular separation from center (arcsec)","Ensquared Energy (%)";
    plt,"A: Reconstructed PSF",0.5,30,tosys=1,color=[128,128,128];
    plt,"B: On-sky PSF",0.5,25,tosys=1;
    range,0,105;
    limits,-0.1,max(boxsize)*1.05;

    winkill,6;window,6,style="aanda.gs",dpi=90;clr;
    dl =  indgen(cam.nPixelsCropped/2) * tel.foV/tel.nPixels;
    plg,(*otf.sky)(cam.nPixelsCropped/2+1,cam.nPixelsCropped/2+1:)/max(*otf.sky),dl;
    plg,(*otf.res)(cam.nPixelsCropped/2+1,cam.nPixelsCropped/2+1:)/max(*otf.res),dl;
    plg,otel(cam.nPixelsCropped/2+1,cam.nPixelsCropped/2+1:)/max(otel),dl,type=2,marks=0;
    xytitles,"D/!l","Normalized OTF";
    plt,"Dashed line: Perfect telescope",1,1,tosys=1;
    plt,"A: Sky OTF",1,0.8,tosys=1;
    plt,"B: reconstructed OTF",1,0.6,tosys=1;
    range,-.1,1.1;
  }

  tf = tac(10);
  
  if(verb){
    write,format="SR on-sky           = %.3g%s\n", 100*SR_sky,"%";
    write,format="SR reconstructed    = %.3g%s\n", 100*SR_res,"%";
    write,format="SR Mar. from budget = %.3g%s\n", 100*budget.SRmar,"%";
    write,format="SR Par. from budget = %.3g%s\n", 100*budget.SRpar,"%";
    write,format="SR Bor. from budget = %.3g%s\n", 100*budget.SRborn,"%";
    write,format="SR fit              = %.3g%s\n", 100*SR_fit,"%";
    write,format="SR bw               = %.3g%s\n", 100*SR_bw,"%";
    write,format="SR tomo+alias+noise = %.3g%s\n", 100*SR_tomo,"%";
    write,format="SR static           = %.3g%s\n", 100*SR_stats,"%";
    write,format="SR cpa              = %.3g%s\n", 100*SR_cpa,"%";
    write,format="SR ncpa             = %.3g%s\n", 100*SR_best,"%";
    write,format="Diff of psf         = %.3g%s\n", 100*diffPSF,"%";
    write,format="Residual error      = %.4g nm rms\n", budget.res;
    write,format="Tomographic error   = %.4g nm rms\n", budget.tomo;
    write,format="Aliasing error      = %.4g nm rms\n", budget.alias;
    write,format="Noise error         = %.4g nm rms\n", budget.noise;
    write,format="Bandwidth error     = %.4g nm rms\n", budget.bw;
    write,format="Fitting error       = %.4g nm rms\n", budget.fit;
    write,format="Go-to error         = %.4g nm rms\n", budget.ol;
    write,format="Static error        = %.4g nm rms\n", budget.static;
    write,format="NCPA error          = %.4g nm rms\n", budget.ncpa;
    write,format="PSF reconstruction done on %.3g s\n",tf;
  }

  pracResults = concatenatePracResults(procDir);
  
  return pracResults;
}


func concatenatePracResults(void)
/* DOCUMENT

 */
{
  pracResults = array(pointer,11);

  /////////////////////
  // ..... DATA IDENTITY + PARAMETERS IDENTIFICATION
  //////////////////////////////////////////////////////////
  
  //Data identity
  pracResults(1) = &strchar([timedata,rtc.aoMode,rtc.obsMode,rtc.recType]);
  //global parameters
  pracResults(2) = &[atm.r0,atm.L0,atm.v,tf];
  //turbulence profile
  pracResults(3) = &[atm.cnh,atm.altitude,atm.l0h,atm.vh];
  //tracking
  pracResults(4) = &[sys.tracking];
  //system parameters
  pracResults(5) = &[wfs.x,wfs.y,sys.xshift,sys.yshift,sys.magnification,sys.theta,sys.centroidGain];


  /////////////////////
  // ..... IMAGES
  //////////////////////////////////////////////////////////

  //PSFs
  pracResults(6) = &[*psf.sky,*psf.res,*psf.diff,*psf.ncpa];
  //Ensquared Energy
  pracResults(7) = &[*psf.EE_sky,*psf.EE_res];
  //OTFs
  pracResults(8) = &[*otf.fit,*otf.bw,*otf.tomo,*otf.ncpa,*otf.static,*otf.ts];
  
  /////////////////////
  // ..... PERFORMANCE
  //////////////////////////////////////////////////////////
  
  //error budget
  pracResults(9) = &[budget.res,budget.fit,budget.bw,budget.tomo,budget.noise,budget.alias,budget.static,budget.ncpa,budget.ol];
  //VED
  pracResults(10) = &budget.ved;
  //Strehl ratios
  pracResults(11) = &(100*[psf.SR_sky,psf.SR_res,budget.SRmar,budget.SRpar,budget.SRborn,psf.SR_tomo,psf.SR_fit,psf.SR_bw,psf.SR_stats,psf.SR_cpa,budget.SRncpa,diffPSF]);

  writefits,"results/pracResults_" + strpart(procDir,1:10) + "_" + timedata + ".fits",pracResults;
  
  return pracResults;
}
