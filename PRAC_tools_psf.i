func PRAC_OTF_stats(mca,&PSF_stats)
{
  
  //computes static aberrations
  stats = (*data.slopes_res)(slrange(data.its),avg);
  F = calc_TTMatFilt_1(data.wfs(data.its).nssp);
  stats_noTT = F(,+)*stats(+);
  //computes the offset on the voltages
  voffset = mca(,+) * stats_noTT(+);
  //derives the phase from the influence functions of the DM
  phi = pupille = array(0.,data.fourier.npix,data.fourier.npix);
  x = (indgen(data.fourier.npix) - data.fourier.npix/2)(,-:1:data.fourier.npix)*data.fourier.ud/(data.tel.diam/2.);
  y = transpose(x);
  //loop on actuators
  for(i=1;i<=data.dm.nactu;i++){
    //metric in pupil radius
    xx = x - (*data.dm.csX)(i);
    yy = y - (*data.dm.csY)(i);
    phi += voffset(i) * funcInflu(xx,yy,data.dm.x0)*(2*pi/data.camir.lambda_ir);
  }
  //FTO of the telescope + abstats
  pupille( where( abs(x,y)<= 1 & abs(x,y)> data.tel.obs) ) = 1;
  PSF_stats = abs(fft(exp(1i*phi)*pupille))^2;
  OTF_stats = fft(PSF_stats).re;
  
  return OTF_stats;

}

func PRAC_OTF_ncpa(timedata,npix,&SR_bench,&PSF_ncpa,disp=)
{

  PSF_ncpa = processOnePSF(timedata,SR_bench,box=npix,disp=disp);
  OTF_ncpa = fft(roll(PSF_ncpa)).re;

  return OTF_ncpa;

}

func computesOTFFromDPHI(DPHI)
{
  return exp(-0.5*DPHI);
}

func processOnePSF(date,&SRIR,&snr,pathPsf=,setmax=,click=,box=,disp=)
  /* DOCUMENT



 */
  
{
  
  //Size of the box
  if(is_void(box))
    box=70;
  //date
  timePsf = decoupe(date,'_')(0);
 
  //..... Load raw image ......//
  imageRaw = restorefits("ir",timePsf,path_ir);
  //load bg
  suff_bg = readFitsKey(path_ir,"BGNAME");
  bg2im = restorefits("irbg",suff_bg);
  //PSF
  if(dimsof(imageRaw)(1)==3){
    imageRaw = imageRaw(,,avg);
  }
  if(dimsof(bg2im)(1)==3){
    bg2im = bg2im(,,avg);
  }
  psf_ir = (imageRaw - bg2im);

  if(dimsof(psf_ir)(1) == 3){
    psf_ir = psf_ir(,,avg);
  }

  xPsf = str2int(readFitsKey(path_ir,"X0PSF"));
  yPsf = str2int(readFitsKey(path_ir,"Y0PSF"));
  uld = str2flt(readFitsKey(path_ir,"NPIXLD"));
  if(click){
    winkill,0;
    posPsf = findPsfPosition( psf_ir, box, 0);
    if(sum(posPsf) == -1){return -1;}//to go to the next file
    if(sum(posPsf) == -10){return -10;}//to finish the automatic process
    xPsf = posPsf(1);
    yPsf = posPsf(2);
    replaceFitsKey,path_ir,"X0PSF",xPsf;
    replaceFitsKey,path_ir,"Y0PSF",yPsf;
    write,format="Image is located at %d,%d \n",posPsf(1),posPsf(2);
  }
    
  //load dead pixels map
  pixelMap = CreateDeadPixFrame(readfits("locateDeadPixels"+data.camir.camName+".fits"));
  
  //Shretl ratio
  SRIR = computeStrehlFromPsf(psf_ir,xPsf,yPsf,*data.camir.deadPixIndex,uld,box, psf2, snr);
  SRnorm = arrondi(100*SRIR,1)/100.;
  cutmax = SRIR;
  if(setmax) cutmax = setmax;
 
  if(disp){
    uz = data.camir.uz;
    window,0; clr;
    pli,psf2,-box*uz/2,-box*uz/2,box*uz/2,box*uz/2,cmin = 0,cmax=cutmax;
    xytitles,"Arcsecs","Arcsecs";
  }

  return psf2;

}


func computeStrehlFromPsf(Psf,x0,y0, pixelsMap,nLDpix,box, &processedPsf, &snr)
/*
 */
{
  if( is_void(nLDpix) || nLDpix==0 ) {
    write,"give me a fucking pixarc of the IR cam !"
  }
  
  // deadpixels correction (the "dead pixel frame" global variable  *irData.deadPixIndex
  // is defined at the end of widget_loop.i)
  im = CorrDeadPixFrame( pixelsMap, Psf);
  
  // FIRST ROUGH ITERATION ..............
  imBase = cropImage(im, x0, y0,box); 
  airyPeak = (pi/4) * (1-data.tel.obs^2) * (nLDpix)^2;
  im = evalBg( imBase, dead=2 );        // remove background (evaluated on image edges)
  sumim = sum(im);
  if( sumim<=0 ) {
    write,format="WARNING : Somme de l image = %g\n",sumim;
    return 0.00;
  }
  im /= sumim;
  SR = max(im) / airyPeak;
  
  // TAKING DECISIONS ..........
  if( SR>0.50 ) {
    // If Strehl is good then the background can be evaluated by fitting
    // the central part of the FTM
    // No corr of dead pixels because the peak may be taken for a deadpix
    im = adjustBgWithFTM( imBase, dead=0 );
  } else if( SR>0.40 ) {
    im = adjustBgWithFTM( imBase, dead=1 );
    im = filterPsf(im, nLDpix);
  } else if( SR>0.1 ) {
    // If Strehl is not so good then the background can be evaluated by fitting
    // the central part of the FTM
    im = evalBg( imBase, dead=2 );
    im = filterPsf(im, nLDpix);
  } else {
    im = evalBg( imBase, dead=4 );
    im = filterPsf(im, nLDpix);
  }
  
  // Image normalization
  sumim = sum(im);
  if( sumim<0 ) {
    write,format="WARNING : Somme de l image = %g\n",sum(im);
    return 0.00;
  }
  im /= sumim;

  // Strehl conversion
  im /= airyPeak;
  // image recentering
  posmax = where2( max(im)==im )(,1);
  processedPsf = roll(im, (box/2+1)-posmax);
  // Strehl !
  SR = max(processedPsf);
  // SNR estimation, and Strehl robustness
  snr = strehlSNR(processedPsf);
    
  return SR;

}

func getEE(a,z,boxsize)
/* DOCUMENT getEE(a,z,boxsize)

   Returns the ensquared energy from image <a> in a box of side
   <boxsize>. The image is assumed to be symmetric, centered in n/2+1
   (Fourier-like).
   The variable <z> is the pixel size, expressed in same units as
   <boxsize>.
   
   SEE ALSO:
 */
{
  n = dimsof(a)(2); // taille image
  center = n/2 + 1;
  k1 = center - boxsize / z / 2;
  k2 = center + boxsize / z / 2;
  k1 = long(k1);
  i1 = k1+1;
  i2 = long(k2); 
  k2 = i2+1;

  ek = sum(a(k1:k2, k1:k2));
  ei = sum(a(i1:i2, i1:i2));
  bi = (i2-i1)*z;
  bk = (k2-k1)*z;

  ee = (boxsize-bi)/(bk-bi)*(ek-ei)+ei;
  return ee;
  
}

/*

 _____ ___   ___  _     ____  
|_   _/ _ \ / _ \| |   / ___| 
  | || | | | | | | |   \___ \ 
  | || |_| | |_| | |___ ___) |
  |_| \___/ \___/|_____|____/ 
                           
 */

func wavelength2Band(lambda)
/* DOCUMENT

   returns the band according to the wavelength in microns
 */

{
  if( typeof(lambda) == "double") lambda = long(lambda);
  if( typeof(lambda) != "long") {
    return "Please enter the wavelength in microns";
  }

  FILTER = "I don't know";
  
  if(lambda >= 1500 && lambda <= 1900){
    FILTER = "H band";
  }

  if(lambda == 1650){
    FILTER = "Narrow H band";
  }
  
  if(lambda >= 2000 && lambda <= 2350){
    FILTER = "K band";
  }
  
  if(lambda >= 1000 && lambda <= 1450){
    FILTER = "J band";
  }

  return FILTER;

}


func findPsfPosition( im, box, localwin)
/* DOCUMENT [x0,y0] = findPsfPosition( im, box, localwin)

   im is the image of the psf, box (in pixels) defines the zoom and localwin is the window in which you want to plot the psf. Returns the position of the maximum value of the Psf. You must click twice on the image for defining where the psf is.

   Olivier Martin.

 */
{
  failed=1;
  
  while( failed==1 ) {
    popup, localwin;
    //....first display....//
    pli,im,cmin=0,cmax=3000;
    write,"Click approximately at the center of the PSF";
    pltitle,"Click approximately at the center of the PSF";
    //click
    res = mouse(-1,0,"");
    if(res(0)==4) return -10;
    x0 = int(ceil(res(1)));//ceil function returns a double...
    y0 = int(ceil(res(2)));
    if((x0 == 1 & y0 == 1) | x0==dimsof(im)(2) | y0==dimsof(im)(3) | x0==0 | y0==0){

      write,"No processed image";
      return -1;
    }
 
    //check if we are too close from the image' board
    hb=5;
    if( (x0-box/2)<1 || (y0-box/2)<1 ){
      x0; y0;
      write,format="Je vais tuer la window %d ..........\n",localwin;
      winkill, localwin;
    }
    else {failed=0;}  
  }

  //.....second display with a zoom.....//
  xmin = x0 - box/2;
  xmax = x0 + box/2;
  ymin = y0 - box/2;
  ymax = y0 + box/2;
  clr;
  //plot
  im_trunc = im(xmin:xmax,ymin:ymax);
  pli,im_trunc,cmin=0,cmax=max(im_trunc);
  write,"Give me a fucking click at the center of the PSF";
  pltitle, "Give me a fucking click at the center of the PSF";
  //click
  res = mouse(-1,0,"");
  x0 = int(res(1));
  y0 = int(res(2));
    
  PetitCarreTresJoli,y0,x0,10,color="red";

  xmin2 = x0 - hb;
  xmax2 = x0 + hb;
  ymin2 = y0 - hb;
  ymax2 = y0 + hb;
  //find the maximun value of the psf
  tmp = im_trunc(xmin2:xmax2,ymin2:ymax2);
  //position of the maximun on tmp
  posMaxtmp = where2(tmp == max(tmp));
  //position of the max on im_trunc
  posMaxtrunc = posMaxtmp + [xmin2,ymin2]-1;
  //position of the max on the total image
  posMaxim = posMaxtrunc + [xmin,ymin]-1;

  return posMaxim;
}

func cropImage(im,x0,y0,n)
/* DOCUMENT res = cropImage(im,x0,y0,n)
     Cuts an image, taking LOTS of care not over
   SEE ALSO:
 */
{
  dims = dimsof(im);
  ix = dims(2);
  iy = dims(3);
  k = n/2;           // half-size of the image
  tmp = im( findlim(ix,x0,k) , findlim(iy,y0,k) , ..);
  return tmp;
}


func findlim(nima,x,k)
/* DOCUMENT rr = findlim(nima,x,k)
   Returns a range of indexes centred on value x, ranging from
   [x-k,x+k-1] (2*k values), but limited/saturated to the range [1,nima].
   SEE ALSO:
 */
{
  if((x-k)<1) {
    return 1:min(nima,2*k);
  } else {
    if( (x+k-1)>nima )
      return max(1,nima-2*k+1):nima;
    else
      return (x-k):(x+k-1);
  }
}


func evalBg( im , dead=)
/* DOCUMENT imnobg = evalBg( im, dead= )
     Remove the background of an image, based of an evaluation of
     the background inthe corners of the image (out a disk centred
     on the image)
   SEE ALSO:
 */
{
  local dead;
  if( is_void(dead) ) dead=0;
  
  // First, remove dead pixels with glith function.
  // glitch() can be called several times, when image is very noisy.
  for(i=1;i<=dead;i++)
    im = glitch(im,1.);
  
  nx = dimsof(im)(2);     // size of the image
  ny = dimsof(im)(3);     // size of the image
  // creates a circular mask of diameter n
  x=span(-1,1,nx);
  y=span(-1,1,ny);
  msk = (x(,-)^2 + y(-,)^2) >= 1;
  // identifies points out of this mask
  nnbg = where(msk);
  // substract the median of each column !!!
  im1 = im // - median(im,2);
  // computes median val
  cstBg = median(im1(nnbg));
  im2 = im1-cstBg;
  return im2;
}

func glitch(image, sh)
/* DOCUMENT glitch(image, shannon)

 <image>     is the input image
 <shannon>   is the ratio between the D/lambda frequency, and
             the shannon frequency

*/
{
  a = image;
  // calcul du masque
  s = dimsof(a);
  mask = gdist(s(2),s(3)) / (s(2)/2);
  mask = mask > sh;

  // filtrage de l'image pour virer la psf
  u = fft( fft(a,1)*mask , -1).re / double(numberof(a));

  // essai de definition d'un critere ...
  seuil = u(rms) * 3;
  u = abs(u);

  // calcul de la psf du glitch apres filtrage
  gl = a * 0;
  gl(1)=1;
  gl = roll(gl);
  psfgl = abs( fft( fft(gl,1)*mask , -1).re );
  psfgl /= max(psfgl);
  psfgl = roll(psfgl);

  // listpos = array(1,n,2)
  i=0;
  go_on=1;
  while( go_on ) {
    i++;
    // if( 0==(i%10) ) write,format="%d ",i;
    maxu = max(u);
    if( maxu<seuil ) go_on=0;
    pos = where2(maxu==u)(,1);
    //  listpos(i,) = pos
    xx = pos(1); yy=pos(2);
    if( xx==1 & yy==1 )
      u -= psfgl * u(xx,yy);
    else
      u -= iroll(psfgl,pos-1) * u(xx,yy);

    pix=0;
    kk=0;
    xu=xx-1; yu=yy;
    if( xu>0 & xu<=s(2) & yu>0 & yu<=s(3) ) { pix+=a(xu,yu); kk++; }
    xu=xx+1; yu=yy;
    if( xu>0 & xu<=s(2) & yu>0 & yu<=s(3) ) { pix+=a(xu,yu); kk++; }
    xu=xx; yu=yy-1;
    if( xu>0 & xu<=s(2) & yu>0 & yu<=s(3) ) { pix+=a(xu,yu); kk++; }
    xu=xx; yu=yy+1;
    if( xu>0 & xu<=s(2) & yu>0 & yu<=s(3) ) { pix+=a(xu,yu); kk++; }
    pix /= kk;

    a(xx,yy) = pix;
  }
  // write,format="%d dead pixels replaced.\n",i;
  return a;

}

func gdist( n , m,  c=)
/* DOCUMENT  d = gdist(256);
              d = gdist(256, c=1);
              d = gdist(320, 256);
              d = gdist(320, 256, c=1);
              
     gdist() creates the "dist" function, with 0 at the corners of the array, to be
     directly compatible with fft()
     
     gdist(,c=1) creates the same but with the 0 at the image centre.
     
     gdist() takes 1 or 2 arguments : the image may not be a square.
     
   SEE ALSO:
 */
{
  if( m==n ) m=[];
  if( is_void(m) ) {
    if(c==1) {
      x = indgen(n)-(n/2+1);   // permet de tout bien gerer mm pour n impair. Mieux que indgen(-n/2:n/2-1). 
      x *= x;
      return sqrt(x(,-)+x(-,));
    } else  {
      x = indgen(0:n-1);
      x(n/2+2:) = n - x(n/2+2:);  // sorte de roll, sans le roll.
      x *= x;
      return sqrt(x(,-)+x(-,));
    }
  } else {
    if(c==1) {
      x = indgen(n)-(n/2+1);
      y = indgen(m)-(m/2+1);
      x *= x;
      y *= y;
      return sqrt(x(,-)+y(-,));
    } else  {
      x = indgen(0:n-1);
      x(n/2+2:) = n - x(n/2+2:);  // sorte de roll, sans le roll.
      y = indgen(0:m-1);
      y(m/2+2:) = m - y(m/2+2:);  // sorte de roll, sans le roll.
      x *= x;
      y *= y;
      return sqrt(x(,-)+y(-,));
    }

  }
}

func adjustBgWithFTM( im, dead= )
/* DOCUMENT newim = adjustBgWithFTM( im, dead= )
     
   SEE ALSO:
 */
{
  local dead;
  if( is_void(dead) ) dead=0;
  
  // remove dead pixels
  for(i=1;i<=dead;i++)
    im = glitch(im,1.);
  
  // compute OTF
  ftm = roll(abs(fft(im)),[2,2]);  // shifts it by 2 pixels so that center=at (3,3)
  cc = sum(im);   // real central value, with right SIGN (ftm(3,3) is the abs(central_value))
  x = (indgen(5)-3)(,-:1:5);
  y = transpose(x);
  r= sqrt(x^2+y^2);
  nn = where( r>0.01 & r<2.5);
  top = ftm(1:5,1:5)(nn);
  x = r(nn);
  ab = regress(top,x,ab=1);
  im += (ab(2)-cc)/(dimsof(im)(2)^2.);
  return im;
}

func strehlSNR(im)
/* DOCUMENT  strehlSNR(im)
 
 Computes the amplitude E of the error bar on the Strehl ratio,
 expressed as a fraction of it.
 
 If E=0.5, the error bar of a SR=0.10 will range from 0.05 to 0.015
 SEE ALSO
 */
{
  n = dimsof(im)(2);
  msk = gdist(n) > n/2;
  ibg = where(msk);  // pupil indexes pointing on background-only area
  noise = im(ibg)(*)(rms);
  if(noise==0) return 0;
  if( max(im)==0 ) return 2;
  fbg = n*noise / sqrt(sum(msk));
  fpeak = noise / max(im);
  //  write,format="Normalisation fluctuation = %g  (SR*(1+/-x))\n",fbg
  // write,format="Noise direct impact       = %g  (SR*(1+/-y))\n",fpeak;
  return abs(fbg,fpeak);
}

func filterPsf(ima, nbLDpix)
/* DOCUMENT im = filterPsf(ima, nbLDpix)
     
   SEE ALSO:
 */
{
  n = dimsof(ima)(2);
  mask = gdist(n)<(double(n) * nbLDpix);
  im = fft(fft(ima)*mask,-1).re / (n*n);
  return im;
}