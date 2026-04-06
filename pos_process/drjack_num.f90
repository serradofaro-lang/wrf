
!*** FUNCTION TO CALCULATE W MAX/MIN IN BL (cm/sec) - linfo>0 returns height of Wmax/min
!***           LINFO 0=w[cm/s] 1=z[m] 2=z-zsfc[m] 3=(z-zsfc)/hbl[%]
!*    only looks at values at grid points using _z-averaged_ w as input
!!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
SUBROUTINE calc_wblmaxmin( isize,jsize,ksize, linfo, wa, z, ter, pblh, bparam )
implicit none
 INTEGER:: isize, jsize, ksize
 REAL,DIMENSION(isize,jsize,ksize),intent(in):: wa, z
 REAL,DIMENSION(isize,jsize),intent(in):: ter, pblh
 INTEGER,intent(in):: linfo
 REAL,intent(out):: bparam(isize,jsize)
 INTEGER:: ii, jj, kk
 INTEGER:: kmin, kmax
 REAL:: wmax, wmin
 REAL:: zwmax, zwmin
 REAL:: zbltop
DO jj=1,jsize
   DO ii=1,isize
      ! below values used if bl top below bottom level
      wmax = 0.0
      wmin = 0.0
      kmax = 0
      kmin = 0
      zwmax = ter(ii,jj)
      zwmin = ter(ii,jj)
      ! initialize for loop
      kk=1
      zbltop = ter(ii,jj)+pblh(ii,jj)
      ! if lowest grid pt above bltop then result is zero
      DO WHILE ( z(ii,jj,kk) < zbltop .AND. kk < ksize )
         IF( wa(ii,jj,kk) > wmax ) THEN
            wmax = wa(ii,jj,kk)
            zwmax = z(ii,jj,kk)
            kmax = kk
            !old zwmax = 100*((z(ii,jj,kk)-ter(ii,jj))/pblh(ii,jj))
         END IF
         !4test print *, "II,JJ,KK,Z,W,max= "+ii+" "+jj+" "+" "+kk+" "+z(ii,jj,kk)+" "+wa(ii,jj,kk)+" = "+wmax+" "+zbltop
         IF( wa(ii,jj,kk) < wmin ) THEN
            wmin = wa(ii,jj,kk)
            zwmin = z(ii,jj,kk)
            kmin = kk
            !old zwmin = 100*((z(ii,jj,kk)-ter(ii,jj))/pblh(ii,jj))
         END IF
         ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL TOP
         kk=kk+1
      END DO
      ! set parameter based on linfo - use cm/sec for vertical velocity
      ! SELECT CASE (linfo)
      !    CASE (0)
      !       IF ( wmax > -wmin ) THEN
      !          bparam(ii,jj) = 100.*wmax
      !       ELSE
      !          bparam(ii,jj) = 100.*wmin
      !       END IF
      !    CASE (1)
      !       IF ( wmax > -wmin ) THEN
      !          bparam(ii,jj) = zwmax
      !       ELSE
      !          bparam(ii,jj) = zwmin
      !       END IF
      !    CASE (2)
      !       IF ( wmax > -wmin ) THEN
      !          bparam(ii,jj) = zwmax-ter(ii,jj)
      !       ELSE
      !          bparam(ii,jj) = zwmin-ter(ii,jj)
      !       END IF
      !    CASE (3)
      !       IF ( wmax > -wmin ) THEN
      !          bparam(ii,jj) = 100.*((zwmax-ter(ii,jj))/pblh(ii,jj))
      !       ELSE
      !          bparam(ii,jj) = 100.*((zwmin-ter(ii,jj))/pblh(ii,jj))
      !       END IF
      ! END SELECT
      !!! set parameter based on linfo - use cm/sec for vertical velocity
      IF ( wmax > -wmin ) THEN
         IF ( linfo == 0 ) THEN
            bparam(ii,jj) = 100.*wmax
         ELSEIF ( linfo == 1 ) THEN
            bparam(ii,jj) = zwmax
         ELSEIF ( linfo == 2 ) THEN
            bparam(ii,jj) = zwmax-ter(ii,jj)
         ELSEIF ( linfo == 3 ) THEN
            bparam(ii,jj) = 100.*((zwmax-ter(ii,jj))/pblh(ii,jj))
         END IF
      ELSE
         IF ( linfo == 0 ) THEN
            bparam(ii,jj) = 100.*wmin
         ELSEIF ( linfo == 1 ) THEN
            bparam(ii,jj) = zwmin
         ELSEIF ( linfo == 2 ) THEN
            bparam(ii,jj) = zwmin-ter(ii,jj)
         ELSEIF ( linfo == 3 ) THEN
            bparam(ii,jj) = 100.*((zwmin-ter(ii,jj))/pblh(ii,jj))
         END IF
      END IF
      !unused !!! enfore a max/min limit
      !unused if (  bparam(ii,jj  .lt. -50. ) then
      !unused   bparam(ii,jj) = -50. 
      !unused end if
      !unused if (  bparam(ii,jj) .gt.  50. ) then
      !unused   bparam(ii,jj) = 50. 
      !unused end if
      !4test        print *, "WBLMAXMIN II,JJ,BPARAM= ",ii,jj,bparam(ii,jj) 
   END DO
END DO
END SUBROUTINE calc_wblmaxmin



!*** FUNCTION TO FIND LOWEST NON-ZERO CLOUD LEVEL IN BL
!*** ala subroutine calc_cloudbase but with added bltop dependency
!*** PROBLEM is how to treat "no cloud base" cases
!***    since use of model top produces extreme contours at cloud edge AND contour intervals too coarse to be useful
!***    yet "0" or "-1" should mean a _low_ cloud base = unflyable!
!***  DECIDED TO USE NEGATIVE VALUE (-999) WHICH IS A "MISSING" VALUE IN NCL PROGRAM
!!! INPUT PARAMETERS
!   cloudbasecriteria = cloud mixing ratio used for cloud/no-cloud criteria
!   valuemax = imposed cutoff max. to allow reasonable contour intervals
!   lagl=1 returns agl value instead of msl
SUBROUTINE calc_blcloudbase(isize,jsize,ksize, a,z,ter,pblh,cloudbasecriteria,valuemax,lagl,bparam)
implicit none
 INTEGER:: isize,jsize,ksize
 REAL,DIMENSION(isize,jsize,ksize),intent(in):: a, z
 REAL,DIMENSION(isize,jsize),intent(in):: ter, pblh
 REAL,intent(in):: cloudbasecriteria, valuemax 
 REAL,DIMENSION(isize,jsize),intent(out):: bparam
 INTEGER,intent(in):: lagl
 INTEGER:: lfound, ii,jj,kk
!!! set missing value - must agree with that used for bparam@_FillValue
!!! to make "no cloud base" missing values in calling program, use   bparam@_FillValue = -999.
!!! set initial value here
bparam = -999.
DO jj=1,jsize
   DO ii=1,isize
      !!! start from 1st model level
      kk=1
      lfound = 0
      !!! DO NOT GO TO TOP SINCE QCLOUD HAS UNDEF VALUES THERE
      DO WHILE ( kk < ksize .AND. z(ii,jj,kk) <= pblh(ii,jj) )
      !4testprint: if( ii.eq.12 .and. jj.eq.7 ) then
      !4testprint:    print *,'CALC_BLCLOUDBASE: ',ii,jj,kk,z(ii,jj,kk),a(ii,jj,kk)
      !4testprint: end if
         IF ( a(ii,jj,kk) >= cloudbasecriteria ) THEN
            !!! will keep re-setting bparam so long as above cloudbasecritera
            bparam(ii,jj) = z(ii,jj,kk)
            lfound = 1
            ! NOTE THAT EXITING KK IS LEVEL OF CLOUDBASE
            EXIT
         END IF
         kk=kk+1
      END DO
      IF( lfound == 1 ) THEN
         !!! IF FLAG SET, RETURN AGL VALUE
         IF( lagl == 1 ) THEN
            bparam(ii,jj) = bparam(ii,jj) - ter(ii,jj)
         END IF
!!! alternate treatment of  "no cloud base" case ??
!unused           if( kk.ge.ksize ) then
!unused             bparam(ii,jj) = -999.
!unused           end if
!!! impose maximum to allow reasonable contour intervals
!   (do prior to max cutoff so plotting not affected by terrain)
         IF( bparam(ii,jj) > valuemax ) THEN
            bparam(ii,jj) = valuemax
         END IF
      END IF
      !4test        print *, "II,JJ,KK,CLOUDBASE= ",ii,jj,kk,bparam(ii,jj) 
      !4test              print *, "II,JJ,KK,PBLH,TER= ",ii,jj,kk,pblh(ii,jj),ter(ii,jj)
   END DO
END DO
END SUBROUTINE calc_blcloudbase



!!! used internally to get plcl - from http://www.srh.noaa.gov/elp/wxcalc/dewpointsc.html
!!!
SUBROUTINE ptlcl( p,tc,tdc, plcl,tlclc )
implicit none
! calculate the TLCL(C) and PLCL from input T(C),Tc(C) - in/out press.units identical
!    does not give exactly same results as nlc function ptlcl_skewt but close enough
!    (slightly larger - example: ncl_max=14944ft fort_max=15231ft)
!data cpoRd /  3.4978 /                ! Rd = 287.04 cp = 1004
 REAL,intent(in):: p, tc, tdc
 REAL,intent(out):: plcl, tlclc
 REAL,parameter:: cpoRd=3.4978
tlclc = tdc - (.212 + .001571 * tdc - .000436 * tc) * ( tc -tdc )
plcl = p * ( (tlclc+273.16)/(tc+273.16) )**(cpoRd) 
END SUBROUTINE ptlcl



!*** FUNCTION TO CALCULATE HEIGHT OF SFC.LCL
! use lowest pt humidity as "sfc" value
SUBROUTINE calc_sfclclheight(isize,jsize,ksize, p,tc,tdc,z,ter,pblh, bparam )
implicit none
 INTEGER:: isize,jsize,ksize
 REAL,DIMENSION(isize,jsize,ksize),intent(in):: p, tc, tdc, z
 REAL,DIMENSION(isize,jsize),intent(in):: ter, pblh
 REAL,DIMENSION(isize,jsize),intent(out):: bparam
 REAL:: plcl, tlclc
 INTEGER:: ii,jj,kk
DO jj=1,jsize
   DO ii=1,isize
      !!!! use lowest pt values as sfc values to compute lcl
      !!! start of calc of plcl extracted from skewt_func.ncl
      plcl = -999.             ! p (hPa) Lifting Condensation Lvl (lcl)
      tlclc = -999.             ! temperature (C) of lcl
      !shea-skewt  ptlclskewt( p(1,ii,jj),tc(1,ii,jj),tdc(1,ii,jj), plcl,tlcl )
      ! created internal fortran function ptlcl to mimic ncl function
      call ptlcl(p(ii,jj,1),tc(ii,jj,1),tdc(ii,jj,1), plcl,tlclc)
      !!! end of calc of plcl extracted from skewt_func.ncl
      bparam(ii,jj) =  z(ii,jj,1)
      kk=1
      DO WHILE( p(ii,jj,kk) >= plcl .AND. kk <= ksize )
         ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ LCL
         kk=kk+1
      END DO
      !4test print ( "II,JJ,,KK,PLCL= "+ii+" "+jj+" "+plcl )
      IF ( kk == ksize ) THEN
         ! while loop went to end
         bparam(ii,jj) =  z( ii,jj,ksize )
      ELSE
         IF ( kk /= 1 ) THEN
            bparam(ii,jj) = z(ii,jj,kk)-(p(ii,jj,kk)-plcl)*(z(ii,jj,kk)-z(ii,jj,kk-1))/(p(ii,jj,kk)-p(ii,jj,kk-1))
         END IF
      END IF
      !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" "+bparam(ii,jj) )
   END DO
END DO
END SUBROUTINE calc_sfclclheight




!*** FUNCTION TO CALCULATE BL-AVG  (based on z avg, not mass avg)
!    input array a must be at mass point (as z is)
!    avg to bl top  (interpolation to actual non-grid-pt bl top z IS done)
!    sum based on gridpt-to-gridpt depth, using parameter avg over that layer
!    starts from bottom grid-pt value over depth 0.5*(zbottom-terrain) so there is never an undefined value
!      (and eliminates need for sfc. value, since that not known and probably not representative of bl)
!!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
SUBROUTINE calc_blavg(isize,jsize,ksize, a, z, ter, pblh, bparam )
implicit none
 INTEGER:: isize,jsize,ksize
 REAL,DIMENSION(isize,jsize,ksize),intent(in):: a, z
 REAL,DIMENSION(isize,jsize),intent(in):: ter, pblh
 REAL,DIMENSION(isize,jsize),intent(out):: bparam
 REAL:: zsum, zdepth, zbltop, asum
 INTEGER:: ii, jj, kk
DO jj=1,jsize
   DO ii=1,isize
      !!! below values used if bl top below bottom level
      zdepth = 0.5*( z(ii,jj,1) - ter(ii,jj) )
      asum = a(ii,jj,1) * zdepth
      zsum = zdepth
      kk=2
      ! ensure that lowest layer included, even if lowest grid pt below zbltop
      !   but ignore lowest half-layer, so tends to ignore surface influence
      zbltop = pblh(ii,jj) + ter(ii,jj)
      DO WHILE( z(ii,jj,kk) <= zbltop .AND. kk <= ksize )
         ! ( note that ksize is last array element ! )
         zdepth =  z(ii,jj,kk) - z(ii,jj,kk-1)
         asum = asum + 0.5*( a(ii,jj,kk-1)+a(ii,jj,kk) ) * zdepth
         zsum = zsum + zdepth
         ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL TOP
         kk=kk+1
      END DO
      !!! add layer to bl top, assuming linear interpolation
      !   (note that kk now array element above bl top due to kk=kk+1 above)
      !   and must allow for bl top below lowest gridpt
      IF(  zbltop > z(ii,jj,kk-1) .AND. kk <= ksize ) THEN
      !old if(  kk.le.(ksize-1) .and. zbltop .gt. z(ii,jj,kk-1) ) then
         zdepth =  zbltop-z(ii,jj,kk-1)
         asum = asum +  a(ii,jj,kk-1)*zdepth+0.5*((a(ii,jj,kk)-a(ii,jj,kk-1))/(z(ii,jj,kk)-z(ii,jj,kk-1)))*zdepth**2
         zsum = zsum + zdepth
      END IF
      bparam(ii,jj) = asum / zsum
      !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" => "+bparam(ii,jj) )
   END DO
END DO
END SUBROUTINE calc_blavg


!*** FUNCTION TO CALCULATE WSTAR (in mks - convert to wfpm outside routine)
!!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
SUBROUTINE calc_wstar( isize,jsize, hfx, pblh, wstar )
implicit none
 INTEGER:: isize,jsize
 REAL,DIMENSION(isize,jsize),intent(in):: hfx, pblh
 REAL,DIMENSION(isize,jsize),intent(out):: wstar
 INTEGER:: ii,jj
 REAL,parameter:: cmult = (9.81/290.)/1004.
DO jj=1,jsize
   DO ii=1,isize
      IF( hfx(ii,jj) > 0.0 .AND. pblh(ii,jj) > 0.0 ) THEN
         wstar(ii,jj) = ( cmult*hfx(ii,jj)*pblh(ii,jj) )**0.333333
      ELSE
         wstar(ii,jj) = 0.0
      END IF
      !4test print ( "II,JJ,HFX,PBLH,WSTAR= "+ii+" "+jj+" "+hfx(ii,jj)+" "+pblh(ii,jj)+" = "+wstar(ii,jj) )
   END DO
END DO
END SUBROUTINE calc_wstar



!*** FUNCTION TO CALCULATE MAX IN BL at mass point
! use lowest pt value if lowest grid pt above bltop
SUBROUTINE calc_blmax( isize,jsize,ksize, a,z,ter,pblh, bparam )
implicit none
 INTEGER:: isize,jsize,ksize
 REAL,DIMENSION(isize,jsize,ksize),intent(in):: a, z
 REAL,DIMENSION(isize,jsize),intent(in):: ter, pblh
 REAL,DIMENSION(isize,jsize),intent(out):: bparam
 REAL:: amax, zbltop
 INTEGER:: ii,jj,kk, kmax
DO jj=1,jsize
   DO ii=1,isize
      !!! below values used if bl top below bottom level
      ! use lowest pt value if lowest grid pt above bltop
      amax = a(ii,jj,1)
      !unused zmax = 0.0
      kk=1
      kmax = 0
      zbltop = ter(ii,jj)+pblh(ii,jj)
      ! if lowest grid pt above bltop then result is zero
      DO WHILE( z(ii,jj,kk) <= zbltop .AND. kk <= ksize )
         IF( a(ii,jj,kk) > amax ) THEN
            amax = a(ii,jj,kk)
            kmax = kk
            !unused zmax = z(ii,jj,kk)
         END IF
         !4test print ( "II,JJ,KK,Z,A,max= "+ii+" "+jj+" "+" "+kk+" "+z(ii,jj,kk)+" "+a(ii,jj,kk)+" = "+amax+" "+zbltop )
         ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL TOP
         kk=kk+1
      END DO
      bparam(ii,jj) = amax
      !4test           print *,"calc_blmax: ",ii,jj," BPARAM= ",kmax,bparam(ii,jj)
   END DO
END DO
END SUBROUTINE calc_blmax





!*** FUNCTION TO CALCULATE "CRITICAL HEIGHT" WHERE EST. W<225fpm = 4km/h?
!    input wstar in mks
SUBROUTINE calc_hcrit( isize,jsize, wstar,ter,pblh, wcritfpm, bparam )
implicit none
 INTEGER:: isize,jsize
 REAL,intent(in):: wcritfpm
 REAL,DIMENSION(isize,jsize),intent(in):: wstar,ter, pblh
 REAL,DIMENSION(isize,jsize),intent(out):: bparam
 REAL:: wfpm, wratio, hwcritft
 INTEGER:: ii,jj
!!! set criterion value
! wcritfpm = 225.   ! feet per minute... like a barbarian
DO jj=1,jsize
   DO ii=1,isize
      !!! convert to pilot units (english)
      wfpm = 196.85 * wstar(ii,jj) ! in ft/min
      !!! start of code converted from blip 
      IF ( wfpm > wcritfpm ) THEN
         !!! least.sq. fit to lenschow eqn giving  max w/w*=0.4443 @ z/zi=0.1515
         ! use 0.463 so w/w*=1 at z/zi=0.15
         wratio =  0.463 * ( wcritfpm/ wfpm )
         !!! calc $hwcritft downward from Hft so works for normal & elevadjust calcs
         hwcritft =  ter(ii,jj) + pblh(ii,jj)* ( (0.1125602+sqrt(0.012669816+1.3673686*(0.4549031-wratio))) ) 
!pre_elevadj: $hwcritft = nint( $$zarrays[$$jjBOT[$jpt]]/0.3048 + $$Dft[$jpt]*0.1125602+sqrt(0.012669816+1.3673686*(0.4549031-$wratio))) )!
!older $hwcritft = nint( $$zarrays[$$jjBOT[$jpt]] + $$Dft[$jpt] * ( 1 - &asin($wcritfpm/$wfpm)/$pi ) )!
      ELSE
         hwcritft = ter(ii,jj)
      END IF
      ! kludge to require hwcritft>0
      IF ( hwcritft < 0 ) THEN
         hwcritft = 0
      END IF
!!! end of code converted from blip
      bparam(ii,jj) = hwcritft
      !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" => "+bparam(ii,jj) )
   END DO
END DO
END SUBROUTINE calc_hcrit



!*** FUNCTION TO CALCULATE "CRITICAL HEIGHT" WHERE EST. WCRIT IS INPUT (fpm)
!    input wstar in mks
SUBROUTINE calc_hlift( isize,jsize, wcritfpm, wstar,ter,pblh, bparam )
implicit none
 INTEGER isize,jsize
 REAL,DIMENSION(isize,jsize),intent(in):: wstar, ter, pblh
 REAL,DIMENSION(isize,jsize),intent(out):: bparam
 REAL:: wfpm, wratio, hwcritft
 REAL:: wcritfpm
 INTEGER:: ii,jj
!old   !!! set criterion value
!old   wcritfpm = 225.
DO jj=1,jsize
   DO ii=1,isize
      !!! convert to pilot units (english)
      wfpm = 196.85 * wstar(ii,jj) ! in ft/min
      !!! start of code converted from blip
      IF ( wfpm > wcritfpm ) THEN
         !!! least.sq. fit to lenschow eqn giving  max w/w*=0.4443 @ z/zi=0.1515
         ! use 0.463 so w/w*=1 at z/zi=0.15
         wratio =  0.463 * ( wcritfpm/ wfpm )
         !!! calc $hwcritft downward from Hft so works for normal & elevadjust calcs
         hwcritft =  ter(ii,jj) + pblh(ii,jj)*( (0.1125602+sqrt(0.012669816+1.3673686*(0.4549031-wratio))) ) 
!pre_elevadj: $hwcritft = nint( $$zarrays[$$jjBOT[$jpt]]/0.3048 + $$Dft[$jpt]*0.1125602+sqrt(0.012669816+1.3673686*(0.4549031-$wratio))) )!
!older $hwcritft = nint( $$zarrays[$$jjBOT[$jpt]] + $$Dft[$jpt] * ( 1 - &asin($wcritfpm/$wfpm)/$pi ) )!
      ELSE
         hwcritft = ter(ii,jj)
      END IF
      ! kludge to require hwcritft>0
      IF ( hwcritft < 0 ) THEN
         hwcritft = 0
      END IF 
!!! end of code converted from blip 
      bparam(ii,jj) = hwcritft
      !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" => "+bparam(ii,jj) )
      END DO
   END DO
END SUBROUTINE calc_hlift



!*** FUNCTION TO CALCULATE WIND AT BL TOP
!    input array a must be at mass point (as z is)
!    interpolation to actual non-grid-pt bl top z
!!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
SUBROUTINE calc_bltopwind( isize,jsize,ksize, u, v, z, ter, pblh, ubltop,vbltop )
implicit none
 INTEGER isize,jsize,ksize
 REAL,DIMENSION(isize,jsize,ksize),intent(in):: u, v, z
 REAL,DIMENSION(isize,jsize),intent(in):: ter, pblh
 REAL,DIMENSION(isize,jsize),intent(out):: ubltop, vbltop
 REAL:: zbltop
 INTEGER:: ii, jj, kk
DO jj=1,jsize
   DO ii=1,isize
      kk=1
      zbltop = pblh(ii,jj) + ter(ii,jj)
      !!! find bl top
      DO WHILE( z(ii,jj,kk) <= zbltop .AND. kk <=ksize )
         !   ( note that ksize is last array element ! )
         kk=kk+1
      END DO
      !   (note that kk now array element above bl top due to kk=kk+1 above)
      !   and must allow for bl top below lowest gridpt
      IF(  zbltop <= z(ii,jj,1) .OR. kk > ksize ) THEN
         ubltop(ii,jj)= u(ii,jj,1)
         vbltop(ii,jj)= v(ii,jj,1)
      ELSE
         ubltop(ii,jj)= u(ii,jj,kk-1) +(u(ii,jj,kk)-u(ii,jj,kk-1))*(zbltop-z(ii,jj,kk-1))/(z(ii,jj,kk)-z(ii,jj,kk-1))
         vbltop(ii,jj)= v(ii,jj,kk-1) +(v(ii,jj,kk)-v(ii,jj,kk-1))*(zbltop-z(ii,jj,kk-1))/(z(ii,jj,kk)-z(ii,jj,kk-1))
      END IF
      !4test      print *,"II,JJ,KK,U,V= ",ii,jj,kk,ubltop(ii,jj),vbltop(ii,jj)
      !4test      print *,z(ii,jj,1),zbltop
   END DO
END DO
END SUBROUTINE calc_bltopwind



!*** FUNCTION TO CALCULATE MAX SUBGRID CLOUD COVER WITHIN BL (0-100%)
!*** USING RIDICULOUSLY SIMPLE PARAMETERIZATION FROM MM5toGRADS (old MM5 plotting program)
!*** ( simply an offset linear relationship to maximum rh in bl => no clouds when maxRH<75% )
!    input arrays must be at mass point (as z is)
!    starts from bottom grid-pt value
!!!  could be more efficient since does esat calc for each point - eg by use of lookup tables ala module_ra_gfdleta.F
SUBROUTINE calc_subgrid_blcloudpct_grads( isize,jsize,ksize, qvapor, qcloud, tc,pmb, z, ter, pblh, cwbasecriteria, bparam )
implicit none
 INTEGER:: isize,jsize,ksize 
 REAL,DIMENSION(isize,jsize,ksize),intent(in):: qvapor, qcloud, tc, pmb, z
 REAL,DIMENSION(isize,jsize),intent(in):: ter, pblh
 REAL,intent(in):: cwbasecriteria
 REAL,DIMENSION(isize,jsize),intent(out):: bparam
 !!! HUMIDITY PARAMS
 REAL,parameter:: svp1=0.6112, svp2=17.67, svp3=29.65, svpt0=273.15
 REAL,parameter:: r_d=287., r_v=461.6
 REAL,parameter:: ep_2 = r_d/r_v
 REAL,parameter:: ep_3 = 0.622
 REAL:: cloudpctmax, tempc, zbltop, WV, RHUM, qvs, es, cloudpct
 INTEGER:: ii,jj,kk
!!! ADAPTING BELOW, IGNORE USE OF CLOUD FRACTION PART BUT THEN MAKE 100% IF "CLOUD" FOUND
!!! ORIGINAL MM5toGRADS CODE  where LO=970-800mb MID=800-450mb HI=>450mb
!mm5tograds do k=1,k1
!mm5tograds    IF(K.LE.KCLO.AND.K.GT.KCMD) clfrlo(i,j)=AMAX1(RH(i,j,k),clfrlo(i,j))
!mm5tograds    IF(K.LE.KCMD.AND.K.GT.KCHI) clfrmi(i,j)=AMAX1(RH(i,j,k),clfrmi(i,j))
!mm5tograds    IF(K.LE.KCHI) clfrhi(i,j)=AMAX1(RH(i,j,k),clfrhi(i,j))
!mm5tograds  enddo
!mm5tograds  clfrlo(i,j)=4.0*clfrlo(i,j)/100.-3.0
!mm5tograds  clfrmi(i,j)=4.0*clfrmi(i,j)/100.-3.0
!mm5tograds  clfrhi(i,j)=2.5*clfrhi(i,j)/100.-1.5
DO jj=1,jsize
   DO ii=1,isize
      !!! minimum value set here
      cloudpctmax = 0.0
      !4test          RHmax = 0.0
      ! start at lowest grid level
      kk=1
      !4test            kmax = 0
      zbltop = ter(ii,jj)+pblh(ii,jj)
      DO WHILE( z(ii,jj,kk) <= zbltop .AND. kk <= ksize )
         !   ( note that ksize is last array element ! )
         !!! calc saturation pressure (mb) & mixing ratio (kg/kg)
         tempc = tc(ii,jj,kk)
         es = 10.*svp1*exp((svp2*tempc)/(tempc+svpt0-svp3))
         qvs = ep_3 * es / (pmb(ii,jj,kk)-(1.-ep_3)*es)
         !!! allow for explicit cloud layer
         IF( qcloud(ii,jj,kk) > cwbasecriteria ) THEN
            ! Assume 100% cloud cover if cloud mixing ratio above criterion value
            cloudpct = 100.
         ELSE
            !!! copied from mm5tograds code but why WV used instead of qvapor ?
            !!! (but not important since great accuracy not important for such a crude parameterization !)
            WV = qvapor(ii,jj,kk)/(1.-qvapor(ii,jj,kk))
            RHUM = WV / qvs
         !  eqn gives: RHUM.le.300/400=0.75 => CC=0% - for RHNUM.ge.1.0 => CC=100%
            cloudpct = 400.0*RHUM -300.0
         END IF
         IF( cloudpctmax < cloudpct ) THEN
            cloudpctmax = cloudpct
            !4test               kmax = kk
            !4test               RHUMatkmax = RHUM
         END IF
         !old             cloudpctmax = max( cloudpctmax, cloudpct )
         !4test            RHmax = max( RHmax, RHUM )
         !4testprint:      if( (ii.eq.23.and.jj.eq.30) .or. (ii.eq.30.and.jj.eq.30) )
         !4testprint     & print *,ii,jj,kk,"> RHUM,cloud,vapor,cloudpct= ",
         !4testprint     &     RHUM,qcloud(ii,jj,kk),qvapor(ii,jj,kk),cloudpct
         kk=kk+1
      END DO
      !!! use maximum found in bl
      IF( cloudpctmax <= 100.0 ) THEN
         bparam(ii,jj) = cloudpctmax
      ELSE
         bparam(ii,jj) = 100.
      END IF
      !4testprint    print *, ii,jj,kk,"RHUMatkmax,qcloud,RHmax,BPARAM= ",
      !4testprint   &  kmax,RHUMatkmax,qcloud(ii,jj,kmax),RHmax,bparam(ii,jj)
   END DO
END DO
END SUBROUTINE calc_subgrid_blcloudpct_grads


!*** FUNCTION TO CALCULATE HEIGHT OF BL.CL
!    based on subroutine calc_sfclclheight
SUBROUTINE calc_blclheight( isize,jsize,ksize, pmb,tc,qvaporblavg, z,ter,pblh, bparam )
implicit none
 INTEGER:: isize,jsize,ksize
 REAL,DIMENSION(isize,jsize,ksize),intent(in):: pmb, tc, z
 REAL,DIMENSION(isize,jsize),intent(in):: ter, pblh, qvaporblavg
 REAL,DIMENSION(isize,jsize),intent(out):: bparam
 REAL:: rhold,rh
 INTEGER:: ii,jj,kk
DO jj=1,jsize
   DO ii=1,isize
      !!! use blavg q value for blcl calc (with predicted p,t)
      !!! below values used if bl top below bottom level
      bparam(ii,jj) = z(ii,jj,1)
      kk=0
      rh = 0.
      DO WHILE( rh<100. .AND. kk<=ksize )
         ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL CL
         kk=kk+1
         rhold = rh
         call calc_rh1( qvaporblavg(ii,jj), pmb(ii,jj,kk), tc(ii,jj,kk), rh )
      END DO
      !4test:       print *, "II,JJ,KK,RH,RHOLD= ",ii,jj,kk,rh,rhold
      IF ( kk == ksize ) THEN
         ! while loop went to end
         bparam(ii,jj) =  z( ii,jj,ksize )
      ELSE
         IF ( kk /= 1 ) THEN
            bparam(ii,jj) = z(ii,jj,kk)-(100.-rhold)*(z(ii,jj,kk)-z(ii,jj,kk-1))/(rh-rhold)
         END IF
      END IF
      !4test:       print *, "II,JJ,BPARAM= ",ii,jj,bparam(ii,jj)
   END DO
END DO
END SUBROUTINE calc_blclheight


!*** FUNCTION TO CALCULATE RELATIVE HUMIDITY FOR SINGLE GRIDPT
!jack: input qv= water vapor mix.ratio (km/km), pmb= pressure (mb), tc= temperature (C)
!jack: output rh= relative humidity (%) - can be >100%
!!! calc of rh based on compute_rh in wrf_user_fortran_util_0.f  
SUBROUTINE calc_rh1 ( qv, pmb, tc, rh )
implicit none
 REAL, parameter:: svp1=0.6112, svp2=17.67, svp3=29.65, svpt0=273.15
 REAL,intent(in):: qv,pmb,tc
 REAL,intent(out):: rh
 REAL:: qvs, es
 REAL,parameter:: r_d=287., r_v=461.6, ep_2=r_d/r_v
 REAL,parameter:: ep_3=0.622
es  = 10.* svp1 * exp( (svp2*tc)/(tc+SVPT0-svp3) )
qvs = ep_3 * es / (pmb-(1.-ep_3)*es) 
! allow RH > 100        rh = 100.*AMAX1( AMIN1(qv/qvs,1.0),0.0 )
rh = 100.*AMAX1( (qv/qvs), 0.0 )
END SUBROUTINE calc_rh1




!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO FIND LOWEST NON-ZERO CLOUD LEVEL (ALL LEVELS)
!!     !*** PROBLEM is how to treat "no cloud base" cases
!!     !***    since use of model top produces extreme contours at cloud edge AND contour intervals too coarse to be useful
!!     !***    yet "0" or "-1" should mean a _low_ cloud base = unflyable!
!!     !***  DECIDED TO USE NEGATIVE VALUE (-999) WHICH IS A "MISSING" VALUE IN NCL PROGRAM
!!     !!! INPUT PARAMETERS
!!     !   cloudbasecriteria = cloud mixing ratio used for cloud/no-cloud criteria
!!     !   valuemax = imposed cutoff max. to allow reasonable contour intervals
!!     !   lagl=1 returns agl value instead of msl
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!            subroutine calc_cloudbase( a,z,ter, cloudbasecriteria, valuemax,
!!          &       lagl, isize,jsize,ksize, bparam )
!!            real a(isize,jsize,ksize), z(isize,jsize,ksize)
!!            real ter(isize,jsize)
!!            real bparam(isize,jsize)
!!            real cloudbasecriteria, valuemax 
!!           integer lagl, isize,jsize,ksize
!!     C NCLEND
!!             !!! set missing value - must agree with that used for bparam@_FillValue
!!             !!! to make "no cloud base" missing values in calling program, use   bparam@_FillValue = -999.
!!             amissingvalue = -999.
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 !ncl for some ncl code reason does not like "bparam(ii,jj)=ter(ii,jj)" !?
!!                 !ncl    since get warning:VarVarWrite: lhs has dimension name and rhs doesn't
!!                 !ncl    but use of dummy variable eliminates warning message !?
!!                 !ncl  dummy = ter(ii,jj)
!!                 !ncl  bparam(ii,jj) = dummy
!!                 !!! set initial value here
!!                 bparam(ii,jj) = amissingvalue
!!                 kk=1
!!                lfound = 0
!!                !!! DO NOT GO TO TOP SINCE QCLOUD HAS UNDEF VALUES THERE
!!                 do while ( kk.lt.ksize )
!!                   if ( a(ii,jj,kk) .ge. cloudbasecriteria ) then
!!                     !!! will keep re-setting bparam so long as above cloudbasecritera
!!                     bparam(ii,jj) = z(ii,jj,kk)
!!                     lfound = 1
!!                    ! NOTE THAT EXITING KK IS LEVEL OF CLOUDBASE
!!                    exit
!!                   end if  
!!                   kk=kk+1
!!                 end do
!!                 if( lfound.eq.1 ) then
!!                   !!! IF FLAG SET, RETURN AGL VALUE
!!                   if( lagl .eq. 1 ) then
!!                     bparam(ii,jj) = bparam(ii,jj) - ter(ii,jj)
!!                   end if
!!     !!! alternate treatment of  "no cloud base" case ??
!!     !unused           if( kk.ge.ksize ) then
!!     !unused             bparam(ii,jj) = -999.
!!     !unused           end if
!!     !!! impose maximum to allow reasonable contour intervals
!!     !   (do prior to max cutoff so plotting not affected by terrain)
!!                   if( bparam(ii,jj) .gt. valuemax ) then
!!                     bparam(ii,jj) = valuemax 
!!                   end if
!!                 end if
!!                 !4test        print *, "II,JJ,KK,CLOUDBASE= ",ii,jj,kk,bparam(ii,jj) 
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO FIND LOWEST NON-ZERO CLOUD LEVEL IN BL
!!     !*** ala subroutine calc_cloudbase but with added bltop dependency
!!     !*** PROBLEM is how to treat "no cloud base" cases
!!     !***    since use of model top produces extreme contours at cloud edge AND contour intervals too coarse to be useful
!!     !***    yet "0" or "-1" should mean a _low_ cloud base = unflyable!
!!     !***  DECIDED TO USE NEGATIVE VALUE (-999) WHICH IS A "MISSING" VALUE IN NCL PROGRAM
!!     !!! INPUT PARAMETERS
!!     !   cloudbasecriteria = cloud mixing ratio used for cloud/no-cloud criteria
!!     !   valuemax = imposed cutoff max. to allow reasonable contour intervals
!!     !   lagl=1 returns agl value instead of msl
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!            subroutine calc_blcloudbase( a,z, ter,pblh,
!!          &       cloudbasecriteria, valuemax,
!!          &       lagl, isize,jsize,ksize, bparam )
!!            real a(isize,jsize,ksize), z(isize,jsize,ksize)
!!            real ter(isize,jsize), pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!            real cloudbasecriteria, valuemax 
!!           integer lagl, isize,jsize,ksize
!!     Cf2py intent(out) bparam
!!     C NCLEND
!!             !!! set missing value - must agree with that used for bparam@_FillValue
!!             !!! to make "no cloud base" missing values in calling program, use   bparam@_FillValue = -999.
!!             amissingvalue = -999.
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 !ncl for some ncl code reason does not like "bparam(ii,jj)=ter(ii,jj)" !?
!!                 !ncl    since get warning:VarVarWrite: lhs has dimension name and rhs doesn't
!!                 !ncl    but use of dummy variable eliminates warning message !?
!!                 !ncl  dummy = ter(ii,jj)
!!                 !ncl  bparam(ii,jj) = dummy
!!                 !!! set initial value here
!!                 bparam(ii,jj) = amissingvalue
!!                !!! start from 1st model level
!!                 kk=1
!!                 lfound = 0
!!                 !!! DO NOT GO TO TOP SINCE QCLOUD HAS UNDEF VALUES THERE
!!                 do while ( kk.lt.ksize .and. z(ii,jj,kk).le.pblh(ii,jj) )
!!     !4testprint:        if( ii.eq.12 .and. jj.eq.7 ) then
!!     !4testprint:           print *,'CALC_BLCLOUDBASE: ',ii,jj,kk,z(ii,jj,kk),a(ii,jj,kk)
!!     !4testprint:         end if
!!                   if ( a(ii,jj,kk) .ge. cloudbasecriteria ) then
!!                     !!! will keep re-setting bparam so long as above cloudbasecritera
!!                     bparam(ii,jj) = z(ii,jj,kk)
!!                    lfound = 1
!!                    ! NOTE THAT EXITING KK IS LEVEL OF CLOUDBASE
!!                    exit
!!                   end if  
!!                   kk=kk+1
!!                 end do
!!                 if( lfound.eq.1 ) then
!!                   !!! IF FLAG SET, RETURN AGL VALUE
!!                   if( lagl .eq. 1 ) then
!!                     bparam(ii,jj) = bparam(ii,jj) - ter(ii,jj)
!!                   end if
!!     !!! alternate treatment of  "no cloud base" case ??
!!     !unused           if( kk.ge.ksize ) then
!!     !unused             bparam(ii,jj) = -999.
!!     !unused           end if
!!     !!! impose maximum to allow reasonable contour intervals
!!     !   (do prior to max cutoff so plotting not affected by terrain)
!!                   if( bparam(ii,jj) .gt. valuemax ) then
!!                     bparam(ii,jj) = valuemax 
!!                   end if
!!                 end if
!!                 !4test        print *, "II,JJ,KK,CLOUDBASE= ",ii,jj,kk,bparam(ii,jj) 
!!                 !4test              print *, "II,JJ,KK,PBLH,TER= ",ii,jj,kk,pblh(ii,jj),ter(ii,jj) 
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE HEIGHT OF SFC.LCL
!!     ! use lowest pt humidity as "sfc" value
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           subroutine calc_sfclclheight( p,tc,tdc,z,ter,pblh,
!!          &         isize,jsize,ksize, bparam )
!!            real p(isize,jsize,ksize),tc(isize,jsize,ksize),
!!          &    tdc(isize,jsize,ksize),z(isize,jsize,ksize)
!!            real ter(isize,jsize),pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!           integer isize,jsize,ksize
!!     Cf2py intent(out) bparam
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 !!!! use lowest pt values as sfc values to compute lcl
!!                 !!! start of calc of plcl extracted from skewt_func.ncl
!!                 plcl = -999.             ! p (hPa) Lifting Condensation Lvl (lcl)
!!                 tlclc = -999.             ! temperature (C) of lcl
!!                 !shea-skewt  ptlclskewt( p(1,ii,jj),tc(1,ii,jj),tdc(1,ii,jj), plcl,tlcl )
!!                 ! created internal fortran function ptlcl to mimic ncl function
!!                 call ptlcl(p(ii,jj,1),tc(ii,jj,1),tdc(ii,jj,1), plcl,tlclc)
!!                 !!! end of calc of plcl extracted from skewt_func.ncl
!!                 bparam(ii,jj) =  z(ii,jj,1)
!!                 kk=1
!!                 do while( p(ii,jj,kk).ge.plcl .and. kk.le.ksize )
!!                   ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ LCL
!!                   kk=kk+1
!!                 end do
!!                 !4test print ( "II,JJ,,KK,PLCL= "+ii+" "+jj+" "+plcl )
!!                 if ( kk.eq. ksize ) then
!!                   ! while loop went to end
!!                   bparam(ii,jj) =  z( ii,jj,ksize )
!!                 else
!!                   if ( kk.ne.1 ) then
!!                     bparam(ii,jj) = z(ii,jj,kk)-(p(ii,jj,kk)-plcl)*
!!          &           (z(ii,jj,kk)-z(ii,jj,kk-1))/(p(ii,jj,kk)-p(ii,jj,kk-1))   
!!                   end if
!!                 end if
!!                 !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" "+bparam(ii,jj) )
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!! used internally to get plcl - from http://www.srh.noaa.gov/elp/wxcalc/dewpointsc.html
!!     !!! 
!!           subroutine  ptlcl( p,tc,tdc, plcl,tlclc )
!!           ! calculate the TLCL(C) and PLCL from input T(C),Tc(C) - in/out press.units identical
!!           !    does not give exactly same results as nlc function ptlcl_skewt but close enough
!!           !    (slightly larger - example: ncl_max=14944ft fort_max=15231ft)
!!           data cpoRd /  3.4978 /                ! Rd = 287.04 cp = 1004
!!           tlclc = tdc - (.212 + .001571 * tdc - .000436 * tc) * ( tc -tdc )
!!           plcl = p * ( (tlclc+273.16)/(tc+273.16) )**(cpoRd) 
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE HEIGHT OF BL.CL
!!     !    based on subroutine calc_sfclclheight
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           subroutine calc_blclheight( pmb,tc,qvaporblavg, z,ter,pblh,
!!          &         isize,jsize,ksize, bparam )
!!            real pmb(isize,jsize,ksize),tc(isize,jsize,ksize)
!!            real qvaporblavg(isize,jsize)
!!            real z(isize,jsize,ksize)
!!            real ter(isize,jsize),pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!           integer isize,jsize,ksize
!!     Cf2py intent(out) bparam
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 !!! use blavg q value for blcl calc (with predicted p,t)
!!                 !!! below values used if bl top below bottom level
!!                 bparam(ii,jj) = z(ii,jj,1)
!!                 kk=0
!!                 rh = 0.
!!                 do while( rh.lt.100. .and. kk.le.ksize )
!!                   ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL CL
!!                   kk=kk+1
!!                   rhold = rh
!!                   call calc_rh1( qvaporblavg(ii,jj), pmb(ii,jj,kk),
!!          &                      tc(ii,jj,kk), rh )
!!                 end do
!!                 !4test:       print *, "II,JJ,KK,RH,RHOLD= ",ii,jj,kk,rh,rhold
!!                 if ( kk.eq. ksize ) then
!!                   ! while loop went to end
!!                   bparam(ii,jj) =  z( ii,jj,ksize )
!!                 else
!!                   if ( kk.ne.1 ) then
!!                     bparam(ii,jj) = z(ii,jj,kk)-(100.-rhold)*
!!          &           (z(ii,jj,kk)-z(ii,jj,kk-1))/(rh-rhold)   
!!                   end if
!!                 end if
!!                 !4test:       print *, "II,JJ,BPARAM= ",ii,jj,bparam(ii,jj)
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE BL-AVG  (based on z avg, not mass avg)
!!     !    input array a must be at mass point (as z is)
!!     !    avg to bl top  (interpolation to actual non-grid-pt bl top z IS done)
!!     !    sum based on gridpt-to-gridpt depth, using parameter avg over that layer
!!     !    starts from bottom grid-pt value over depth 0.5*(zbottom-terrain) so there is never an undefined value
!!     !      (and eliminates need for sfc. value, since that not known and probably not representative of bl)
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           subroutine calc_blavg( a, z, ter, pblh, 
!!          &         isize,jsize,ksize, bparam )
!!            real a(isize,jsize,ksize), z(isize,jsize,ksize)
!!            real ter(isize,jsize), pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!           integer isize,jsize,ksize
!!     Cf2py intent(out) bparam
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 !!! below values used if bl top below bottom level
!!                 zdepth = 0.5*( z(ii,jj,1) - ter(ii,jj) )
!!                 asum = a(ii,jj,1) * zdepth
!!                 zsum = zdepth
!!                 kk=2
!!                 ! ensure that lowest layer included, even if lowest grid pt below zbltop
!!                 !   but ignore lowest half-layer, so tends to ignore surface influence
!!                 zbltop = pblh(ii,jj) + ter(ii,jj)
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )            !   ( note that ksize is last array element ! )
!!                   zdepth =  z(ii,jj,kk)-z(ii,jj,kk-1) 
!!                   asum = asum + 0.5*( a(ii,jj,kk-1)+a(ii,jj,kk) ) * zdepth
!!                   zsum = zsum + zdepth
!!                   ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL TOP
!!                   kk=kk+1
!!                 end do
!!                 !!! add layer to bl top, assuming linear interpolation
!!                 !   (note that kk now array element above bl top due to kk=kk+1 above)
!!                 !   and must allow for bl top below lowest gridpt
!!                 if(  zbltop .gt. z(ii,jj,kk-1) .and. kk.le.ksize ) then
!!                 !old if(  kk.le.(ksize-1) .and. zbltop .gt. z(ii,jj,kk-1) ) then
!!                   zdepth =  zbltop-z(ii,jj,kk-1) 
!!                   asum = asum +  a(ii,jj,kk-1)*zdepth
!!          &                      +0.5*((a(ii,jj,kk)-a(ii,jj,kk-1))
!!          &                       /(z(ii,jj,kk)-z(ii,jj,kk-1)))*zdepth**2
!!                   zsum = zsum + zdepth
!!                 end if
!!                 bparam(ii,jj) = asum / zsum
!!                 !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" => "+bparam(ii,jj) )
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE WSTAR (in mks - convert to wfpm outside routine)
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           subroutine calc_wstar( hfx, pblh,
!!          &         isize,jsize,ksize, wstar )
!!            real hfx(isize,jsize), pblh(isize,jsize)
!!            real wstar(isize,jsize)
!!           integer isize,jsize,ksize
!!     Cf2py intent(out) wstar
!!     C NCLEND
!!     ccc use consts for simplicity
!!               cmult = (9.81/290.)/1004.
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 if( hfx(ii,jj).gt.0.0 .and. pblh(ii,jj).gt.0.0 ) then
!!                   wstar(ii,jj) = ( cmult*hfx(ii,jj)*pblh(ii,jj) )**0.333333
!!                 else
!!                   wstar(ii,jj) = 0.0
!!                 end if
!!                 !4test print ( "II,JJ,HFX,PBLH,WSTAR= "+ii+" "+jj+" "+hfx(ii,jj)+" "+pblh(ii,jj)+" = "+wstar(ii,jj) )
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !alt=with_vaporflux !*** FUNCTION TO CALCULATE CONVECTIVE VELOCITY WSTAR (in mks)
!!     !alt=with_vaporflux !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     !alt=with_vaporflux C NCLFORTSTART
!!     !alt=with_vaporflux       subroutine calc_wstar( tfx,vfx, pblh,
!!     !alt=with_vaporflux      &         isize,jsize,ksize, wstar )
!!     !alt=with_vaporflux ccc tfx=sfc.turb.temp.flux  vfx=sfc.turb.watervapor.flux  pblh=PBL_depth_
!!     !alt=with_vaporflux        real tfx(isize,jsize), vfx(isize,jsize), pblh(isize,jsize)
!!     !alt=with_vaporflux        real wstar(isize,jsize)
!!     !alt=with_vaporflux       integer isize,jsize,ksize
!!     !alt=with_vaporflux C NCLEND
!!     !alt=with_vaporflux ccc use consts for simplicity
!!     !alt=with_vaporflux           tmult = (9.81/290.)/1004.
!!     !alt=with_vaporflux           vmult = (0.61*290.)*tmult
!!     !alt=with_vaporflux           do jj=1,jsize
!!     !alt=with_vaporflux           do ii=1,isize
!!     !alt=with_vaporflux             if( tfx(ii,jj).gt.0.0 .and. pblh(ii,jj).gt.0.0 ) then
!!     !alt=with_vaporflux               wstar(ii,jj) = ( ( tmult*tfx(ii,jj) + vmult*vfx(ii,jj) )*pblh(ii,jj) )**0.333333
!!     !alt=with_vaporflux             else
!!     !alt=with_vaporflux               wstar(ii,jj) = 0.0
!!     !alt=with_vaporflux             end if
!!     !alt=with_vaporflux             !4test print ( "II,JJ,TFX,PBLH,WSTAR= "+ii+" "+jj+" "+tfx(ii,jj)+" "+pblh(ii,jj)+" = "+wstar(ii,jj) )
!!     !alt=with_vaporflux           end do
!!     !alt=with_vaporflux           end do
!!     !alt=with_vaporflux       return
!!     !alt=with_vaporflux       end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE MAX IN BL at mass point
!!     ! use lowest pt value if lowest grid pt above bltop
!!     C NCLFORTSTART
!!           subroutine calc_blmax( a,z,ter,pblh, 
!!          &         isize,jsize,ksize, bparam )
!!            real a(isize,jsize,ksize), z(isize,jsize,ksize)
!!            real ter(isize,jsize), pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!           integer isize,jsize,ksize
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 !!! below values used if bl top below bottom level
!!                 ! use lowest pt value if lowest grid pt above bltop
!!                 amax = a(ii,jj,1)
!!                 !unused zmax = 0.0
!!                 kk=1
!!                 kmax = 0
!!                 zbltop = ter(ii,jj)+pblh(ii,jj)
!!                 ! if lowest grid pt above bltop then result is zero
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )
!!                   if( a(ii,jj,kk).gt.amax ) then
!!                    amax = a(ii,jj,kk)
!!                    kmax = kk       
!!                    !unused zmax = z(ii,jj,kk)
!!                   end if
!!                   !4test print ( "II,JJ,KK,Z,A,max= "+ii+" "+jj+" "+" "+kk+" "+z(ii,jj,kk)+" "+a(ii,jj,kk)+" = "+amax+" "+zbltop )
!!                   ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL TOP
!!                   kk=kk+1
!!                 end do
!!                 bparam(ii,jj) = amax
!!                 !4test           print *,"calc_blmax: ",ii,jj," BPARAM= ",kmax,bparam(ii,jj) 
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE "CRITICAL HEIGHT" WHERE EST. W<225fpm
!!     !    input wstar in mks
!!     C NCLFORTSTART
!!           subroutine calc_hcrit( wstar,ter,pblh,
!!          &         isize,jsize, bparam )
!!            real wstar(isize,jsize),ter(isize,jsize), pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!           integer isize,jsize
!!     Cf2py intent(out) bparam
!!     C NCLEND
!!             !!! set criterion value
!!             wcritfpm = 225.
!!               do jj=1,jsize
!!               do ii=1,isize
!!             !!! convert to pilot units (english)
!!             wfpm = 196.85 * wstar(ii,jj) ! in ft/min
!!     !!! start of code converted from blip 
!!           if ( wfpm .gt. wcritfpm ) then
!!             !!! least.sq. fit to lenschow eqn giving  max w/w*=0.4443 @ z/zi=0.1515
!!             ! use 0.463 so w/w*=1 at z/zi=0.15
!!             wratio =  0.463 * ( wcritfpm/ wfpm )
!!             !!! calc $hwcritft downward from Hft so works for normal & elevadjust calcs
!!             hwcritft =  ter(ii,jj) + pblh(ii,jj)*
!!          &    ( (0.1125602+sqrt(0.012669816+1.3673686*(0.4549031-wratio))) ) 
!!             !pre_elevadj: $hwcritft = nint( $$zarrays[$$jjBOT[$jpt]]/0.3048 + $$Dft[$jpt]*0.1125602+sqrt(0.012669816+1.3673686*(0.4549031-$wratio))) )!
!!             !older $hwcritft = nint( $$zarrays[$$jjBOT[$jpt]] + $$Dft[$jpt] * ( 1 - &asin($wcritfpm/$wfpm)/$pi ) )! 
!!           else
!!               hwcritft = ter(ii,jj) 
!!           end if
!!           ! kludge to require hwcritft>0
!!           if ( hwcritft .lt. 0 ) then
!!               hwcritft = 0
!!           end if 
!!     !!! end of code converted from blip 
!!                 bparam(ii,jj) = hwcritft
!!                 !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" => "+bparam(ii,jj) )
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE "CRITICAL HEIGHT" WHERE EST. WCRIT IS INPUT (fpm)
!!     !    input wstar in mks
!!     C NCLFORTSTART
!!           subroutine calc_hlift( wcritfpm, wstar,ter,pblh,
!!          &         isize,jsize, bparam )
!!            real wstar(isize,jsize),ter(isize,jsize), pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!           integer isize,jsize
!!     C NCLEND
!!     !old        !!! set criterion value
!!     !old        wcritfpm = 225.
!!               do jj=1,jsize
!!               do ii=1,isize
!!             !!! convert to pilot units (english)
!!             wfpm = 196.85 * wstar(ii,jj) ! in ft/min
!!     !!! start of code converted from blip 
!!           if ( wfpm .gt. wcritfpm ) then
!!             !!! least.sq. fit to lenschow eqn giving  max w/w*=0.4443 @ z/zi=0.1515
!!             ! use 0.463 so w/w*=1 at z/zi=0.15
!!             wratio =  0.463 * ( wcritfpm/ wfpm )
!!             !!! calc $hwcritft downward from Hft so works for normal & elevadjust calcs
!!             hwcritft =  ter(ii,jj) + pblh(ii,jj)*
!!          &    ( (0.1125602+sqrt(0.012669816+1.3673686*(0.4549031-wratio))) ) 
!!             !pre_elevadj: $hwcritft = nint( $$zarrays[$$jjBOT[$jpt]]/0.3048 + $$Dft[$jpt]*0.1125602+sqrt(0.012669816+1.3673686*(0.4549031-$wratio))) )!
!!             !older $hwcritft = nint( $$zarrays[$$jjBOT[$jpt]] + $$Dft[$jpt] * ( 1 - &asin($wcritfpm/$wfpm)/$pi ) )! 
!!           else
!!               hwcritft = ter(ii,jj) 
!!           end if
!!           ! kludge to require hwcritft>0
!!           if ( hwcritft .lt. 0 ) then
!!               hwcritft = 0
!!           end if 
!!     !!! end of code converted from blip 
!!                 bparam(ii,jj) = hwcritft
!!                 !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" => "+bparam(ii,jj) )
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE MAX IN CHOSEN 3D BOX
!!     !!! *NB* input/output array coords must start from 0 !!!
!!     !!! returns array: value,imax,jmax,kmax
!!     !!! *NB* CROSS-SECTION PLOT PTS OFFSET HORIZ> FROM W LOCATIONS
!!     C NCLFORTSTART
!!           subroutine find_boxmax3d( a, ibox1in,ibox2in,jbox1in,
!!          &                             jbox2in,kbox1in,kbox2in,
!!          &         isize,jsize,ksize, amax,imaxout,jmaxout,kmaxout )
!!            real a(isize,jsize,ksize)
!!            integer ibox1in,ibox2in,jbox1in,jbox2in,kbox1in,kbox2in
!!            integer isize,jsize,ksize
!!            real amax
!!            integer imaxout,jmaxout,kmaxout
!!     C NCLEND
!!     !!! if error in input, fail with error message
!!             if( ibox1in.gt.ibox2in .or. jbox1in.gt.jbox2in
!!          &       .or. kbox1in.gt.kbox2in ) then
!!               print *,'find_boxmax3d ERROR: bad box indexs =',
!!          &   ibox1in,ibox2in, jbox1in,jbox2in, kbox1in,kbox2in
!!               !old amax = 0.0
!!               !old imaxout = ibox1in
!!               !old jmaxout = jbox1in
!!               !old kmaxout = kbox1in
!!               return
!!             end if
!!     !!! convert input ncl indexs to fortran indexs
!!             ibox1 = ibox1in +1
!!             ibox2 = ibox2in +1
!!             jbox1 = jbox1in +1
!!             jbox2 = jbox2in +1
!!             kbox1 = kbox1in +1
!!             kbox2 = kbox2in +1
!!               amax = -999999.
!!               imax = -1
!!               jmax = -1
!!               kmax = -1
!!               do kk=kbox1,kbox2
!!               do jj=jbox1,jbox2
!!               do ii=ibox1,ibox2
!!                  if( a(ii,jj,kk).gt.amax ) then
!!                     amax = a(ii,jj,kk)
!!                     imax = ii
!!                     jmax = jj
!!                     kmax = kk
!!                  end if
!!                  !4test print ( "II,JJ,KK,A,max= "+ii+" "+jj+" "+" "+kk+" "+a(ii,jj,kk)+" = "+amax )
!!               end do
!!               end do
!!               end do
!!     !!! convert fortran indexs to output ncl indexs
!!             imaxout = imax -1
!!             jmaxout = jmax -1
!!             kmaxout = kmax -1
!!           !example_output: print ( "MAX= "+array(0)+" @"+array(1)+","+array(2)+","+array(3) )
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO LIMIT MAX FOR ARRAY
!!     C NCLFORTSTART
!!           subroutine maxlimit2d( adata, upperlimit,
!!          &         isize,jsize )
!!           real adata(isize,jsize)
!!           real upperlimit
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 if( adata(ii,jj) .gt. upperlimit ) then
!!                   adata(ii,jj) = upperlimit
!!                 end if
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO LIMIT MIN FOR ARRAY
!!     C NCLFORTSTART
!!           subroutine minlimit2d( adata, lowerlimit,
!!          &         isize,jsize )
!!           real adata(isize,jsize)
!!           real lowerlimit
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 if( adata(ii,jj) .lt. lowerlimit ) then
!!                   adata(ii,jj) = lowerlimit
!!                 end if
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO INTEGRATE MIXING RATIO WITHIN BL  (mass-based)
!!     !    input array a must be at mass point (as z is)
!!     !    interpolation to actual non-grid-pt bl top z IS done
!!     !    sum based on gridpt-to-gridpt mass depths, using parameter avg over that layer
!!     !    starts from bottom grid-pt value over depth 0.5*(zbottom-psfc) so there is never an undefined value
!!     !      (and eliminates need for sfc. value, since that not known and probably not representative of bl)
!!     !!! *** UNTESTED SINCE CONVERTED FROM NCL TO FORTRAN *** !!!
!!     C NCLFORTSTART
!!           subroutine calc_blinteg_mixratio( a, ptot, psfc, z, ter, pblh,
!!          &         isize,jsize,ksize, bparam )
!!           real a(isize,jsize,ksize),ptot(isize,jsize,ksize),
!!          &     z(isize,jsize,ksize)
!!           real psfc(isize,jsize),ter(isize,jsize),pblh(isize,jsize)
!!           real bparam(isize,jsize)
!!           integer isize,jsize,ksize 
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 pdepth = 0.5*( psfc(ii,jj) - ptot(ii,jj,1) )
!!                 asum = a(ii,jj,1) * pdepth
!!                 kk=2
!!                 zbltop = ter(ii,jj)+pblh(ii,jj)
!!                 ! ensure that lowest layer included, even if lowest grid pt below zbltop
!!                 !   but ignore lowest half-layer, so tends to ignore surface influence
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )            !   ( note that ksize is last array element ! )
!!                   pdepth =  ptot(ii,jj,kk-1)-ptot(ii,jj,kk) 
!!                   asum = asum + 0.5*( a(ii,jj,kk-1)+a(ii,jj,kk) ) * pdepth
!!                   ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL TOP
!!                   kk=kk+1
!!                 end do
!!                 !!! add layer to bl top, assuming linear interpolation
!!                 !   (note that kk now array element above bl top due to kk=kk+1 above)
!!                 !   and must allow for bl top below lowest gridpt
!!                 if(  zbltop .gt. z(ii,jj,kk-1) .and. kk.le.ksize ) then
!!                   pdepth =  (ptot(ii,jj,kk-1)-ptot(ii,jj,kk))*
!!          &                   (zbltop-z(ii,jj,kk-1))
!!          &                   /(z(ii,jj,kk)-z(ii,jj,kk-1))
!!                   !ok asum = asum +  a(ii,jj,kk-1)*pdepth +0.5*((a(ii,jj,kk)-a(ii,jj,kk-1))/(ptot(ii,jj,kk-1)-ptot(ii,jj,kk)))*pdepth**2
!!                   asum = asum + ( a(ii,jj,kk-1)
!!          &               +0.5*((a(ii,jj,kk)-a(ii,jj,kk-1))
!!          &               /(ptot(ii,jj,kk-1)-ptot(ii,jj,kk)))*pdepth )*pdepth
!!                 end if
!!                 bparam(ii,jj) = (1000./9.8) * asum
!!                 !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" => "+bparam(ii,jj) )
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO INTEGRATE MIXING RATIO *ABOVE* BL  (mass-based)
!!     !    input array a must be at mass point (as z is)
!!     !    interpolation above actual non-grid-pt bl top z IS done
!!     !    sum based on gridpt-to-gridpt mass depths, using parameter avg over that layer
!!     !!! *** UNTESTED SINCE CONVERTED FROM NCL TO FORTRAN *** !!!
!!     C NCLFORTSTART
!!           subroutine calc_aboveblinteg_mixratio( a, ptot, z, ter, pblh,
!!          &         isize,jsize,ksize, bparam )
!!           real a(isize,jsize,ksize),ptot(isize,jsize,ksize),
!!          &     z(isize,jsize,ksize)
!!           real ter(isize,jsize),pblh(isize,jsize)
!!           real bparam(isize,jsize)
!!           integer isize,jsize,ksize 
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 asum = 0.0
!!                 kk=2
!!                !! determine first index above bl top 
!!                 zbltop = ter(ii,jj)+pblh(ii,jj)
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )            !   note that ksize is last array element ! 
!!                   ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL TOP
!!                   kk=kk+1
!!                 end do
!!                 !!! add layer from bl top up to the full layer, assuming linear interpolation
!!                 !   (note that kk now array element above bl top due to kk=kk+1 above)
!!                 !   and must allow for bl top below lowest gridpt
!!                 ! NB - use of (ksize-1)
!!                 if( zbltop .gt. z(ii,jj,kk-1) .and. kk.le.ksize ) then
!!                 !old if(  zbltop .gt. z(ii,jj,kk-1) .and. kk.le.ksize ) then
!!                   pdepth =  (ptot(ii,jj,kk-1)-ptot(ii,jj,kk))
!!          &               *(zbltop-z(ii,jj,kk-1))/(z(ii,jj,kk)-z(ii,jj,kk-1))
!!                   !ok asum = asum +  a(ii,jj,kk-1)*pdepth +0.5*((a(ii,jj,kk)-a(ii,jj,kk-1))/(ptot(ii,jj,kk-1)-ptot(ii,jj,kk)))*pdepth^2
!!                   ! for clarity, first calc portion below bl top ala routine blinteg_mixratio
!!                     asum = ( a(ii,jj,kk-1) +0.5*((a(ii,jj,kk)-a(ii,jj,kk-1))
!!          &               /(ptot(ii,jj,kk-1)-ptot(ii,jj,kk)))*pdepth )*pdepth
!!                   ! now subtract from full layer integraion
!!                    asum = 0.5*(a(ii,jj,kk)+a(ii,jj,kk-1))*
!!          &                (ptot(ii,jj,kk-1)-ptot(ii,jj,kk)) - asum
!!                 end if
!!                 kklayertop1 = kk+1
!!                do kk=kklayertop1,ksize            ! note that kk is at top of layer here
!!                   pdepth =  ptot(ii,jj,kk-1)-ptot(ii,jj,kk) 
!!                   asum = asum + 0.5*( a(ii,jj,kk-1)+a(ii,jj,kk) ) * pdepth
!!                end do
!!                 bparam(ii,jj) = (1000./9.8) * asum
!!                 !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" => "+bparam(ii,jj) )
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE BL CLOUD-PRODUCTION EQUIV. HEAT FLUX  (based on z avg, not mass avg)
!!     !*** theory: effective bl heat flux resulting from condensation = (heat_of_cond./cp)*(BLdepth)*BLintegralof_dqc/dt
!!     !            (obtained from BL integral of d(theta)/dt = -d(temp.flux)/dz + (heat_of_cond./cp)*dqc/dt
!!     !    input array a must be at mass point (as z is)
!!     !    input RQCBLTEN from wrfout is multiplied by mu = column.mass (2d) so must divide by it here
!!     !    integrate to bl top  (interpolation to actual non-grid-pt bl top z IS done)
!!     !    sum based on gridpt-to-gridpt depth, using parameter avg over that layer
!!     !    starts from bottom grid-pt value over depth 0.5*(zbottom-terrain) so there is never an undefined value
!!     !      (and eliminates need for sfc. value, since that not known and probably not representative of bl)
!!     !    modified from calc_blavg
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           subroutine calc_qcblhf( a,totmu, z, ter, pblh, 
!!          &         isize,jsize,ksize, bparam )
!!            real a(isize,jsize,ksize), z(isize,jsize,ksize)
!!            real totmu(isize,jsize), ter(isize,jsize), pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!           integer isize,jsize,ksize
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 !!! below values used if bl top below bottom level
!!                 zdepth = 0.5*( z(ii,jj,1) - ter(ii,jj) )
!!                 asum = a(ii,jj,1) * zdepth
!!                 zsum = zdepth
!!                 kk=2
!!                 ! ensure that lowest layer included, even if lowest grid pt below zbltop
!!                 !   but ignore lowest half-layer, so tends to ignore surface influence
!!                 zbltop = pblh(ii,jj) + ter(ii,jj)
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )            !   ( note that ksize is last array element ! )
!!                   zdepth =  z(ii,jj,kk)-z(ii,jj,kk-1) 
!!                   asum = asum +
!!          &           0.5*(a(ii,jj,kk-1)+a(ii,jj,kk)) * zdepth
!!                   zsum = zsum + zdepth
!!                   ! NOTE THAT EXITING KK IS LEVEL _ABOVE_ BL TOP
!!                   kk=kk+1
!!                 end do
!!                 !!! add layer to bl top, assuming linear interpolation
!!                 !   (note that kk now array element above bl top due to kk=kk+1 above)
!!                 !   and must allow for bl top below lowest gridpt
!!                 if(  zbltop .gt. z(ii,jj,kk-1) .and. kk.le.ksize ) then
!!                 !old if(  kk.le.(ksize-1) .and. zbltop .gt. z(ii,jj,kk-1) ) then
!!                   zdepth =  zbltop-z(ii,jj,kk-1) 
!!                   asum = asum +  ( a(ii,jj,kk-1)*zdepth
!!          &                         +0.5*((a(ii,jj,kk)-a(ii,jj,kk-1))
!!          &                         /(z(ii,jj,kk)-z(ii,jj,kk-1)))*zdepth**2 )
!!                   zsum = zsum + zdepth
!!                 end if
!!     !!! multiply by heat of condensation over cp (2.50e6/1004.) - divide by column mass
!!                 bparam(ii,jj) = asum * pblh(ii,jj) * 2.49e3 / totmu(ii,jj)
!!                 !4test print ( "II,JJ,BPARAM= "+ii+" "+jj+" => "+bparam(ii,jj) )
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO OUTPUT DATA FILE FOR SINGLE PARAMETER - input array is REAL - lformat= decimal places (0=>INTEGER)
!!     C NCLFORTSTART
!!           subroutine output_mapdatafile( qfilename, qtitle1,qtitle2,qtitle3,
!!          &                               amap, NNX,NNY, lformat )
!!     c
!!     ccc Function "output_mapdatafile" has following arguments:
!!     ccc (see its usage in rasp.ncl for an example)
!!     ccc   qfilename = full-path filename (string)
!!     ccc   qtitle1 = first title line (string)
!!     ccc   qtitle2 = second title line (string)
!!     ccc   qtitle3 = third title line (string)
!!     ccc   amap = parameter values (2D fortran-ordered array)
!!     ccc   nnx = number of x values (columns) in array (integer)
!!     ccc   nny = number of y values (rows) in array (integer)
!!     ccc   lformat = humber of decimal places (integer) 0 => use nearest integer
!!     c
!!     ccc Note that qtitle1 is expected to provide a parameter name
!!     ccc Note that qtitle2 is expected to provide grid & projection information
!!     ccc Note that qtitle3 is expected to provide time & parameter information
!!     ccc (see datafiles normally produced by rasp.ncl for datafile examples)
!!     c
!!           character*(*) qfilename,qtitle1,qtitle2,qtitle3
!!           real amap(NNX,NNY)
!!           integer NNX,NNY, lformat
!!     C NCLEND
!!            integer map(NNX,NNY)
!!            character qminmaxinfo*80, qformat*80, qline*36000
!!     !preUSAactualtopo=       character qminmaxinfo*80, qformat*80, qline*16000
!!     !!! OUTPUT ALA XYPLOT INPUT - modified from blip perl routine
!!             !!! COONVERT TO INTEGER
!!             !!! DETERMINE MIN/MAX FOR PRINTING 
!!             amin = +987654.
!!             amax = -987654.
!!             do j=1,NNY
!!             do i=1,NNX
!!     ! USE NEAREST INTEGER FOR LFORMAT=0
!!               if( lformat.eq.0 ) then
!!                 map(i,j) = nint( amap(i,j) )
!!               end if
!!               if ( amin .gt. amap(i,j) ) amin = amap(i,j)
!!               if ( amax .lt. amap(i,j) ) amax = amap(i,j)
!!             end do
!!             end do
!!     ! USE NEAREST INTEGER FOR LFORMAT=0
!!     !4test:       print *,'AMIN,AMAX= ',amin,amax      
!!            if( lformat.eq.0 ) then
!!              write( qminmaxinfo, '( "Min= ",i6," Max= ", i6 )' )
!!          &          nint(amin),nint(amax)
!!            elseif ( lformat.gt.0 ) then
!!              write( qformat, 9100 )
!!          &        '("Min= ",f16.', lformat, '," Max= ",f16.', lformat, ')'
!!      9100    format( a13,i1,a14,i1,a1 ) 
!!              !4test:       print *,'QFORMAT= ',qformat,' ='
!!              write( qminmaxinfo, qformat ) amin,amax
!!              !4test:       print *,'QMINMAXINFO= ',qminmaxinfo,' ='
!!            end if
!!             call squeeze_blanks ( qminmaxinfo )
!!           !!! OPEN OUTPUT FILE
!!           !f77:  
!!             open ( 1, FILE=qfilename, STATUS="replace" )
!!           !f90only:  open ( 1, FILE=qfilename, ACTION="write", STATUS="replace" )
!!           !!! PRINT 1st LINE OF HEADER = NOT model_dependent
!!             write( 1, '( "---" )' ) 
!!             write( 1, '( a )' ) qtitle1(1:Len_Trim(qtitle1))
!!           !!! PRINT 2nd LINE OF HEADER - model dependent
!!           ! note that cplot uses '=' to separate grid index limits for reading
!!             write( 1, '( a )' ) qtitle2(1:Len_Trim(qtitle2))
!!           !!! PRINT 3rd LINE OF HEADER
!!             write( 1, '( a," ",a )' ) qtitle3(1:Len_Trim(qtitle3)),
!!          &                      qminmaxinfo(1:Len_Trim(qminmaxinfo))
!!           !!! USE SIMPLE PRINT, ALL ROW VALUES IN A SINGLE LINE
!!           ! need to print values for each row separately for xyplot
!!     ! USE NEAREST INTEGER FOR LFORMAT=0
!!             if( lformat.eq.0 ) then
!!               write( qformat, 8000 ) '(', NNX, 'i8)'
!!      8000          format( a1,i4,a3 )
!!               do j=1,NNY
!!                 write( qline,qformat ) (map(i,j),i=1,NNX)
!!     cold            write( qline,'( 400i8 )' ) (map(i,j),i=1,NNX)
!!                 call squeeze_blanks ( qline )
!!                 write( 1,'( a )' ) qline(1:Len_Trim(qline))
!!               end do
!!             else
!!               write( qformat, 8100 ) '(', NNX, 'f16.', lformat, ')'
!!      8100         format( a1,i4,a4,i1,a1 )
!!     cold write( qformat, 9200 ) '(200f16.', lformat, ')'
!!     cold 9200    format( a8,i1,a1 ) 
!!     ccc TEST THAT LENGTH OF QFORMAT IS SUFFICIENT
!!               lentest = 16 * NNX
!!               if( lentest .gt. 36000 ) then
!!     !preUSAactualtopo          if( lentest .gt. 16000 ) then
!!            print *,'qformat too short - 16 * ',NNX,' > 36000'
!!     !preUSAactualtopo       print *,'qformat too short - 16 * ',NNX,' > 16000'
!!            stop 'ncl_jack_fortran.f output_mapdatafile : qformat too short'
!!               end if
!!               do j=1,NNY
!!     ccc         get "internal write error" below if qformal too short for data (so now test for this above) 
!!                 write( qline,qformat ) (amap(i,j),i=1,NNX)
!!                 !old write( qline,'( 200f16.8 )' ) (amap(i,j),i=1,NNX)
!!                 call squeeze_blanks ( qline )
!!                 write( 1,'( a )' ) qline(1:Len_Trim(qline))
!!               end do
!!             end if
!!             close (1)
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!           subroutine squeeze_blanks ( qin )
!!     !!! remove extra blanks, including at start of string (blank string becomes null string)
!!           character qin*(*)
!!           character qlastnew*1
!!           inew = 0
!!           qlastnew = ' '
!!           do iold=1,len(qin)
!!             if( qin(iold:iold).ne.' ' .or. qlastnew.ne.' ' ) then
!!               inew = inew + 1
!!               qlastnew = qin(iold:iold)
!!               qin(inew:inew) = qlastnew
!!               !4test:     print *,'IOLD,INEW,QLASTNEW= ',iold,inew,qlastnew
!!             end if
!!           end do
!!           if( inew.eq.0 .or. qin(1:1).eq.' ' ) then
!!             ! treat blank string case
!!             qin = ''
!!           elseif( qin(inew:inew).ne.' ' ) then
!!             ! treat non-blank at end of string case
!!             qin = qin(1:inew)
!!           else
!!             ! treat non-blank at end of string case
!!             qin = qin(1:inew-1)
!!           end if
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE TEMPERATURE VARIABILITY AT BL TOP = HEIGHT WHERE POT.TEMP. 4degF WARMER THAN AT BL TOP
!!     !    input array a must be at mass point (as z is)
!!     !    note that input theta happens to be degC (but only differences matter)
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           subroutine calc_bltop_pottemp_variability( theta, z, ter, pblh,
!!          &         isize,jsize,ksize, criteriondegc, bparam )
!!            real theta(isize,jsize,ksize),z(isize,jsize,ksize)
!!            real ter(isize,jsize), pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!           integer isize,jsize,ksize
!!     Cf2py intent(out) bparam
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 zbltop = pblh(ii,jj) + ter(ii,jj)
!!                 kk=2
!!                 !   if bltop below level1, use level 1 instead 
!!                 if(  zbltop .lt. z(ii,jj,1) )  zbltop = z(ii,jj,1)
!!                 !!! find bl top         
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )            !   ( note that ksize is last array element ! )
!!                   kk=kk+1
!!                 end do
!!                 if( kk.le.ksize ) then
!!                   thetabltop = theta(ii,jj,kk-1)
!!          &              + (theta(ii,jj,kk)-theta(ii,jj,kk-1))
!!          &               *(zbltop-z(ii,jj,kk-1))/(z(ii,jj,kk)-z(ii,jj,kk-1))
!!                   !!! now find level where pot.temp is 4degF higher
!!                   thetatiplus = thetabltop + criteriondegc
!!     !old=4degF              thetatiplus = thetabltop + 4.0* 0.555555 
!!                   do while( theta(ii,jj,kk).le.thetatiplus
!!          &                  .and. kk.le.ksize )            !   ( note that ksize is last array element ! )
!!                     kk=kk+1
!!                   end do
!!                   if(  kk.le.ksize ) then
!!                     bparam(ii,jj) = z(ii,jj,kk-1)
!!          &              + (z(ii,jj,kk)-z(ii,jj,kk-1))
!!          &                 *(thetatiplus-theta(ii,jj,kk-1))
!!          &                /(theta(ii,jj,kk)-theta(ii,jj,kk-1))
!!          &             - zbltop
!!                   else
!!                     !!! if top reached, do calc to there
!!                     bparam(ii,jj) = z(ii,jj,ksize) - zbltop
!!                   end if
!!                 else
!!                   !!! if zbltop above model top, set to zero
!!                    bparam(ii,jj) = 0.0
!!                 end if
!!                 !4test          print *,"II,JJ,KK,BPARAM= ",ii,jj,kk,bparam(ii,jj)
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE WIND DIFFERENCE ACROSS BL
!!     !    input array a must be at mass point (as z is)
!!     !    value bewteen bottom-most grid pt and interpolation to actual non-grid-pt bl top z
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           subroutine calc_blwinddiff( u, v, z, ter, pblh, 
!!          &         isize,jsize,ksize, bparam )
!!            real u(isize,jsize,ksize),v(isize,jsize,ksize),
!!          &      z(isize,jsize,ksize)
!!            real ter(isize,jsize), pblh(isize,jsize)
!!            real bparam(isize,jsize)
!!           integer isize,jsize,ksize
!!     Cf2py intent(out) bparam
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 kk=1
!!                 zbltop = pblh(ii,jj) + ter(ii,jj)
!!                 !!! find bl top         
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )            !   ( note that ksize is last array element ! )
!!                   kk=kk+1
!!                 end do
!!                 !   (note that kk now array element above bl top due to kk=kk+1 above)
!!                 !   and must allow for bl top below lowest gridpt
!!                 if(  zbltop .le. z(ii,jj,1) .or. kk.gt.ksize ) then
!!                   bparam(ii,jj) = 0.0
!!                 else
!!                   ubltop = u(ii,jj,kk-1) + (u(ii,jj,kk)-u(ii,jj,kk-1))*
!!          &                   (zbltop-z(ii,jj,kk-1))
!!          &                   /(z(ii,jj,kk)-z(ii,jj,kk-1))
!!                   vbltop = v(ii,jj,kk-1) + (v(ii,jj,kk)-v(ii,jj,kk-1))*
!!          &                   (zbltop-z(ii,jj,kk-1))
!!          &                   /(z(ii,jj,kk)-z(ii,jj,kk-1))
!!                   udiff = ubltop - u(ii,jj,1)
!!                   vdiff = vbltop - v(ii,jj,1)
!!                   ! just use windspeed difference between bl top and bottom
!!                   bparam(ii,jj) = sqrt( udiff**2 + vdiff**2 )
!!                   !true_windshear bparam(ii,jj) = sqrt( udiff**2 + vdiff**2 )/ ( zbltop - z(ii,jj,1) )
!!                 end if
!!                 !4test          print *,"II,JJ,KK,BPARAM= ",ii,jj,kk,bparam(ii,jj)
!!                 !4test          print *,z(ii,jj,1),zbltop,udiff,vdiff
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE WIND AT BL TOP
!!     !    input array a must be at mass point (as z is)
!!     !    interpolation to actual non-grid-pt bl top z
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           subroutine calc_bltopwind( u, v, z, ter, pblh, 
!!          &         isize,jsize,ksize, ubltop,vbltop )
!!            real u(isize,jsize,ksize),v(isize,jsize,ksize),
!!          &      z(isize,jsize,ksize)
!!            real ter(isize,jsize), pblh(isize,jsize)
!!            real ubltop(isize,jsize),vbltop(isize,jsize)
!!           integer isize,jsize,ksize
!!     Cf2py intent(out) ubltop
!!     Cf2py intent(out) vbltop
!!     C NCLEND
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 kk=1
!!                 zbltop = pblh(ii,jj) + ter(ii,jj)
!!                 !!! find bl top         
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )            !   ( note that ksize is last array element ! )
!!                   kk=kk+1
!!                 end do
!!                 !   (note that kk now array element above bl top due to kk=kk+1 above)
!!                 !   and must allow for bl top below lowest gridpt
!!                 if(  zbltop .le. z(ii,jj,1) .or. kk.gt.ksize ) then
!!                   ubltop(ii,jj)= u(ii,jj,1)
!!                   vbltop(ii,jj)= v(ii,jj,1)
!!                 else
!!                   ubltop(ii,jj)= u(ii,jj,kk-1) +(u(ii,jj,kk)-u(ii,jj,kk-1))*
!!          &                   (zbltop-z(ii,jj,kk-1))
!!          &                   /(z(ii,jj,kk)-z(ii,jj,kk-1))
!!                   vbltop(ii,jj)= v(ii,jj,kk-1) +(v(ii,jj,kk)-v(ii,jj,kk-1))*
!!          &                   (zbltop-z(ii,jj,kk-1))
!!          &                   /(z(ii,jj,kk)-z(ii,jj,kk-1))
!!                 end if
!!                 !4test          print *,"II,JJ,KK,U,V= ",ii,jj,kk,ubltop(ii,jj),vbltop(ii,jj)
!!                 !4test          print *,z(ii,jj,1),zbltop
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE RELATIVE HUMIDITY FOR SINGLE GRIDPT
!!     !jack: input qv= water vapor mix.ratio (km/km), pmb= pressure (mb), tc= temperature (C)
!!     !jack: output rh= relative humidity (%) - can be >100%
!!     !!! calc of rh based on compute_rh in wrf_user_fortran_util_0.f  
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           SUBROUTINE calc_rh1 ( qv, pmb, tc, rh )
!!           IMPLICIT NONE
!!     C NCLEND
!!           REAL    svp1, svp2, svp3, svpt0
!!           parameter (SVP1=0.6112,SVP2=17.67,SVP3=29.65,SVPT0=273.15)
!!           real qvs, es, qv,pmb,tc,rh
!!           REAL    ep_2, r_d, r_v
!!           PARAMETER (r_d=287.,r_v=461.6, EP_2=R_d/R_v)
!!           REAL    ep_3
!!           PARAMETER (ep_3=0.622)
!!             es  = 10.* svp1 * exp( (svp2*tc)/(tc+SVPT0-svp3) )
!!             qvs = ep_3 * es / (pmb-(1.-ep_3)*es) 
!!     ! allow RH > 100        rh = 100.*AMAX1( AMIN1(qv/qvs,1.0),0.0 )
!!             rh = 100.*AMAX1( (qv/qvs), 0.0 )
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO TRUNCATE ANY ARRAY VALUES BELOW SPECIFIED MINIMUM
!!     !jack: input a= array, NNX,NNY=array_sizes, amin=specified minimum 
!!     !jack: output a= truncated array
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           SUBROUTINE trunc_2darray_min ( a, NNX,NNY, amin )
!!           IMPLICIT NONE
!!             real a(NNX,NNY), amin
!!             integer NNX,NNY
!!     C NCLEND
!!             integer ii,jj
!!             do jj=1,NNY
!!             do ii=1,NNX
!!               if( a(ii,jj).lt.amin ) a(ii,jj)=amin 
!!             end do
!!             end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO TRUNCATE ANY ARRAY VALUES ABOVE SPECIFIED MAXIMUM
!!     !jack: input a= array, NNX,NNY=array_sizes, amax=specified maximum 
!!     !jack: output a= truncated array
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!           SUBROUTINE trunc_2darray_max ( a, NNX,NNY, amax )
!!           IMPLICIT NONE
!!             real a(NNX,NNY), amax
!!             integer NNX,NNY
!!     C NCLEND
!!             integer ii,jj
!!             do jj=1,NNY
!!             do ii=1,NNX
!!               if( a(ii,jj).gt.amax ) a(ii,jj)=amax 
!!             end do
!!             end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE MAX SUBGRID CLOUD COVER WITHIN BL (0-100%)
!!     !*** USING RIDICULOUSLY SIMPLE PARAMETERIZATION FROM MM5toGRADS (old MM5 plotting program)
!!     !*** ( simply an offset linear relationship to maximum rh in bl => no clouds when maxRH<75% )
!!     !    input arrays must be at mass point (as z is)
!!     !    starts from bottom grid-pt value
!!     !!!  could be more efficient since does esat calc for each point - eg by use of lookup tables ala module_ra_gfdleta.F
!!     C NCLFORTSTART
!!           subroutine calc_subgrid_blcloudpct_grads(
!!          &         qvapor, qcloud, tc,pmb, z,
!!          &         ter, pblh, cwbasecriteria,
!!          &         isize,jsize,ksize, bparam )
!!           real qvapor(isize,jsize,ksize),qcloud(isize,jsize,ksize),
!!          &     tc(isize,jsize,ksize),pmb(isize,jsize,ksize),
!!          &     z(isize,jsize,ksize)
!!           real ter(isize,jsize),pblh(isize,jsize)
!!           real cwbasecriteria
!!           real bparam(isize,jsize)
!!           integer isize,jsize,ksize 
!!     Cf2py intent(out) bparam
!!     C NCLEND
!!            !!! HUMIDITY PARAMS 
!!            REAL    svp1, svp2, svp3, svpt0
!!            parameter (SVP1=0.6112,SVP2=17.67,SVP3=29.65,SVPT0=273.15)
!!            REAL    ep_2, r_d, r_v
!!            PARAMETER (r_d=287.,r_v=461.6, EP_2=R_d/R_v)
!!            REAL    ep_3
!!            PARAMETER (ep_3=0.622)
!!            !!! ADAPTING BELOW, IGNORE USE OF CLOUD FRACTION PART BUT THEN MAKE 100% IF "CLOUD" FOUND
!!            !!! ORIGINAL MM5toGRADS CODE  where LO=970-800mb MID=800-450mb HI=>450mb
!!            !mm5tograds do k=1,k1
!!            !mm5tograds    IF(K.LE.KCLO.AND.K.GT.KCMD) clfrlo(i,j)=AMAX1(RH(i,j,k),clfrlo(i,j))
!!            !mm5tograds    IF(K.LE.KCMD.AND.K.GT.KCHI) clfrmi(i,j)=AMAX1(RH(i,j,k),clfrmi(i,j))
!!            !mm5tograds    IF(K.LE.KCHI) clfrhi(i,j)=AMAX1(RH(i,j,k),clfrhi(i,j))
!!            !mm5tograds  enddo
!!            !mm5tograds  clfrlo(i,j)=4.0*clfrlo(i,j)/100.-3.0
!!            !mm5tograds  clfrmi(i,j)=4.0*clfrmi(i,j)/100.-3.0
!!            !mm5tograds  clfrhi(i,j)=2.5*clfrhi(i,j)/100.-1.5
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 !!! minimum value set here
!!                 cloudpctmax = 0.0
!!                 !4test          RHmax = 0.0
!!                 ! start at lowest grid level 
!!                 kk=1
!!                 !4test            kmax = 0
!!                 zbltop = ter(ii,jj)+pblh(ii,jj)
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )            !   ( note that ksize is last array element ! )
!!                   !!! calc saturation pressure (mb) & mixing ratio (kg/kg)
!!                   tempc = tc(ii,jj,kk)
!!                   es  =10.*svp1*exp((svp2*tempc)/(tempc+SVPT0-svp3))
!!                   qvs = ep_3 * es / (pmb(ii,jj,kk)-(1.-ep_3)*es) 
!!                   !!! allow for explicit cloud layer
!!                   IF( qcloud(ii,jj,kk) .gt. cwbasecriteria ) THEN
!!                     ! Assume 100% cloud cover if cloud mixing ratio above criterion value
!!                     cloudpct = 100.
!!                   ELSE
!!                     !!! copied from mm5tograds code but why WV used instead of qvapor ?
!!                     !!! (but not important since great accuracy not important for such a crude parameterization !)
!!                     WV = qvapor(ii,jj,kk)/(1.-qvapor(ii,jj,kk))
!!                     RHUM = WV / qvs
!!     ccc  eqn gives: RHUM.le.300/400=0.75 => CC=0% - for RHNUM.ge.1.0 => CC=100%
!!                     cloudpct = 400.0*RHUM -300.0
!!                   END IF
!!                   if( cloudpctmax < cloudpct ) then
!!                     cloudpctmax = cloudpct
!!                     !4test               kmax = kk
!!                     !4test               RHUMatkmax = RHUM
!!                   end if
!!                   !old             cloudpctmax = max( cloudpctmax, cloudpct )
!!                  !4test            RHmax = max( RHmax, RHUM )
!!                  !4testprint:      if( (ii.eq.23.and.jj.eq.30) .or. (ii.eq.30.and.jj.eq.30) )
!!                  !4testprint     & print *,ii,jj,kk,"> RHUM,cloud,vapor,cloudpct= ",
!!                  !4testprint     &     RHUM,qcloud(ii,jj,kk),qvapor(ii,jj,kk),cloudpct
!!                   kk=kk+1
!!                 end do
!!                 !!! use maximum found in bl
!!                 if( cloudpctmax .le. 100.0 ) then
!!                   bparam(ii,jj) = cloudpctmax 
!!                 else
!!                   bparam(ii,jj) = 100.
!!                 end if
!!                 !4testprint      print *, ii,jj,kk,"RHUMatkmax,qcloud,RHmax,BPARAM= ",
!!                 !4testprint     &  kmax,RHUMatkmax,qcloud(ii,jj,kmax),RHmax,bparam(ii,jj) 
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO CALCULATE MAX SUBGRID CLOUD COVER WITHIN BL (0-100%)
!!     !*** BASED ON WRF module_ra_gfdleta.F BUT GIVES ~0% OR ~100% WITH LITTLE IN-BETWEEN
!!     !    input arrays must be at mass point (as z is)
!!     !    starts from bottom grid-pt value
!!     !!!  could be more efficient since does esat calc for each point - eg by use of lookup tables ala module_ra_gfdleta.F
!!     C NCLFORTSTART
!!           subroutine calc_subgrid_blcloudpct_gfdleta(
!!          &         qvapor, qcloud, tc,pmb, z,
!!          &         ter, pblh, gridspacing,
!!          &         isize,jsize,ksize, bparam )
!!           real qvapor(isize,jsize,ksize),qcloud(isize,jsize,ksize),
!!          &     tc(isize,jsize,ksize),pmb(isize,jsize,ksize),
!!          &     z(isize,jsize,ksize)
!!           real ter(isize,jsize),pblh(isize,jsize)
!!           real gridspacing
!!           real bparam(isize,jsize)
!!           integer isize,jsize,ksize 
!!     C NCLEND
!!           real RHGRID, zbltop, es,qvs, WV,RHUM,ARV, cloudpct
!!           integer ii, jj, kk
!!           !!! HUMIDITY PARAMS 
!!           REAL    svp1, svp2, svp3, svpt0
!!           parameter (SVP1=0.6112,SVP2=17.67,SVP3=29.65,SVPT0=273.15)
!!           REAL    ep_2, r_d, r_v
!!           PARAMETER (r_d=287.,r_v=461.6, EP_2=R_d/R_v)
!!           REAL    ep_3
!!           PARAMETER (ep_3=0.622)
!!           !!! CLOUD COVER PARAMETERIZATION PARAMETERS
!!           real GAMMA,H69,ALPHA0,PEXP
!!           parameter (GAMMA=0.49, H69=-6.9, ALPHA0=100., PEXP=0.25) 
!!           parameter (RHGRID0 = 0.90) 
!!           !!! SIMPLE RH CRITRION (grid length dependent)
!!           ! from module_mp_etanew.F:  RHgrd=0.90 for dx=100 km, 0.98 for dx=5 km, where RHgrd=0.90+0.08*[(100.-dX)/95.]**.5
!!           !!! except that subtracts rain from cloud water mixing ratio - not done here for simplicity
!!           if( gridspacing .ge. 100000. ) then
!!             RHGRID = RHGRID0
!!           else
!!             RHGRID = RHGRID0 +0.08*((100.-(gridspacing/1000.))/95.)**0.5
!!           end if
!!           RHGRIDPCT = RHGRID *100.
!!           !4testprint:      print *, "gridspacing,RHGRID= ",gridspacing,RHGRID
!!               do jj=1,jsize
!!               do ii=1,isize
!!                 cloudpctmax = 0.0
!!                 !4test          RHmax = 0.0
!!                 ! start at lowest grid level 
!!                 kk=1
!!                 !4test            kmax = 0
!!                 zbltop = ter(ii,jj)+pblh(ii,jj)
!!                 do while( z(ii,jj,kk).le.zbltop .and. kk.le.ksize )            !   ( note that ksize is last array element ! )
!!                   !!! calc saturation pressure (mb) & mixing ratio (kg/kg)
!!                   tempc = tc(ii,jj,kk)
!!                   es  =10.*svp1*exp((svp2*tempc)/(tempc+SVPT0-svp3))
!!                   qvs = ep_3 * es / (pmb(ii,jj,kk)-(1.-ep_3)*es) 
!!                   !!! simple cloud cover calc ala WRF module_ra_gfdleta.F
!!                   !--- Adaptation of original algorithm (Randall, 1994; Zhao, 1995)
!!                   !    modified based on assumed grid-scale saturation at RH=RHgrid.
!!                   !jack - NB if qcloud=0 then cloudpct=0 ! 
!!                   !jack - seems very dependent up qcloud value
!!                   WV = qvapor(ii,jj,kk)/(1.-qvapor(ii,jj,kk))
!!                   RHUM = WV / qvs
!!                   IF( RHUM.GE.RHGRID ) THEN
!!                     !--- Assume cloud fraction of unity if near saturation and the cloud
!!                     !    mixing ratio is at or above the minimum threshold
!!                     cloudpct = 100.
!!                   ELSE
!!                     DENOM = (RHGRID*qvs-WV)**GAMMA
!!                     ARG = MAX( -6.9, -ALPHA0*qcloud(ii,jj,kk)/DENOM )              ! <-- EXP(-6.9)=.001
!!                     cloudpct = 100.*(RHUM/RHGRID)**PEXP*(1.-EXP(ARG))
!!                   END IF
!!                   if( cloudpctmax < cloudpct ) then
!!                     cloudpctmax = cloudpct
!!                     !4test               kmax = kk
!!                     !4test               RHUMatkmax = RHUM
!!                   end if
!!                   !old             cloudpctmax = max( cloudpctmax, cloudpct )
!!                  !4test            RHmax = max( RHmax, RHUM )
!!                  !4testprint:      if( (ii.eq.23.and.jj.eq.30) .or. (ii.eq.30.and.jj.eq.30) )
!!                  !4testprint    & print *,ii,jj,kk,"> RHUM,cloud,vapor,cloudpct= ",
!!                  !4testprint    &     RHUM,qcloud(ii,jj,kk),qvapor(ii,jj,kk),cloudpct
!!                   kk=kk+1
!!                 end do
!!                 !!! use maximum found in bl
!!                 if( cloudpctmax .le. RHGRIDPCT ) then
!!                   bparam(ii,jj) = cloudpctmax 
!!                 else
!!                   bparam(ii,jj) = 100.
!!                 end if
!!                 !4testprint      print *, ii,jj,kk,"RHUMatkmax,qcloud,RHmax,BPARAM= ",
!!                 !4testprint     &  kmax,RHUMatkmax,qcloud(ii,jj,kmax),RHmax,bparam(ii,jj) 
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO READ BLIP ARAY SIZE FROM DATA FILE
!!     ccc if qfilename a zipped file, create tmp unzipped file
!!     C NCLFORTSTART
!!           subroutine read_blip_data_size( qfilename, NNX,NNY )
!!           character*(*) qfilename
!!           integer NNX,NNY
!!     C NCLEND
!!           character qdatafile*120
!!           character qline*180
!!     ccc open file
!!             inunit = 2
!!             close(inunit)
!!     ccc return name qdatafile based on whether qfilename is text or zipped
!!             call datafile_unzip( qfilename, qdatafile )
!!     ccc open text data file
!!             open(inunit,status='old',form='formatted',
!!          &       file=qdatafile,iostat=iostat)
!!             if ( iostat.ne.0 ) then
!!               print *,'ERROR - read_blip_data_size open: ',iostat,qfilename
!!     !old=preGfortran          CALL EXIT( 'read_blip_data_size ERROR EXIT - opening file' )
!!               CALL EXIT
!!             endif
!!     ccc find start of data set
!!             do ii=1,10000
!!               read(inunit,5100,iostat=iostat) qline
!!      5100     format(a180)
!!               if ( iostat .ne. 0 ) then
!!                 print *,'ERROR - read_blip_data_size data not found: ',
!!          &            iostat,qfilename
!!     !old=preGfortran            CALL EXIT('read_blip_data_size ERROR EXIT - data not found')
!!                 CALL EXIT
!!               endif
!!               if( qline(2:3 ).eq.'--' ) goto 1010
!!             enddo
!!      1010   continue
!!     ccc read 2 header lines
!!             read(inunit,5100,iostat=ier1) qline
!!             read(inunit,5100,iostat=ier2) qline
!!     c4testprint:          print *,'header2=',qline
!!             if ( ier1.ne.0 .or. ier2.ne.0 ) then
!!               print *,'read_blip_data_size ERROR - header read: ',
!!          &            ier1,ier2,qfilename
!!     !old=preGfortran          CALL EXIT( 'ERROR EXIT - read_blip_data_size reading header' )
!!               CALL EXIT
!!             endif
!!     ccc extract array size from second header line
!!     ccc     find delimiter for grid indexs
!!     cold        do ichar=1,180
!!     ccc allow for old and new grid array index delimiter
!!     c-new_delimiter
!!                 iindex = index(qline,'Indexs= ') +8
!!     c-old_delimiter ' = '
!!                 if( iindex .le. 8 ) iindex = index(qline,' = ') +3
!!                 if( iindex .le. 3 ) then
!!     !old=preGfortran              CALL EXIT( 'ERROR EXIT - grid index delimiter not found' )
!!                   CALL EXIT
!!                 endif
!!     cold          if( qline(ichar:ichar+2) .eq. " = " ) then
!!     colder delimiter          if( qline(ichar:ichar) .eq. "=" ) then
!!     ccc read array indexs
!!                 read( qline(iindex:180),*) nnx1,nnx2,nny1,nny2
!!     cold            read( qline(ichar+3:180),*) nnx1,nnx2,nny1,nny2
!!     colder-delimiter          read( qline(ichar+1:180),*,iostat=iostat) nnx1,nnx2,nny1,nny2,
!!     c4testprint:            print *,'nnx1,nnx2,nny1,nny2= ',nnx1,nnx2,nny1,nny2
!!                 NNX = nnx2-nnx1+1
!!                 NNY = nny2-nny1+1
!!     cold          end if 
!!     cold        end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO READ BLIP ARAY SIZE AND PROJECTION DATA FROM DATA FILE
!!     ccc if qfilename a zipped file, create tmp unzipped file
!!     C NCLFORTSTART
!!           subroutine read_blip_data_info( qfilename,NNX,NNY,
!!          &  qprojection,dx,dy,plat1,plat2,plon,alat0,alon0 )
!!           character*(*) qfilename,qprojection
!!           integer NNX,NNY
!!           real dx,dy,plat1,plat2,plon,alat0,alon0
!!     C NCLEND
!!           character qline*180, qdum*10, qproj*4
!!     cold      character qprojection*7
!!           character qdatafile*120
!!     ccc open file
!!             inunit = 2
!!             close(inunit)
!!     ccc return name qdatafile based on whether qfilename is text or zipped
!!             call datafile_unzip( qfilename, qdatafile )
!!     ccc open text data file
!!             open(inunit,status='old',form='formatted',
!!          &       file=qdatafile,iostat=iostat)
!!             if ( iostat.ne.0 ) then
!!               print *,'ERROR - read_blip_data_info open: ',iostat,qfilename
!!     !old=preGfortran          CALL EXIT( 'read_blip_data_info ERROR EXIT - opening file' )
!!               CALL EXIT
!!             endif
!!     ccc find start of data set
!!             do ii=1,10000
!!               read(inunit,5100,iostat=iostat) qline
!!      5100     format(a180)
!!               if ( iostat .ne. 0 ) then
!!                 print *,'ERROR - read_blip_data_info data not found: ',
!!          &            iostat,qfilename
!!     !old=preGfortran            CALL EXIT('read_blip_data_info ERROR EXIT - data not found')
!!                 CALL EXIT
!!               endif
!!               if( qline(2:3 ).eq.'--' ) goto 1010
!!             enddo
!!      1010   continue
!!     ccc read 2 header lines
!!             read(inunit,5100,iostat=ier1) qline
!!             read(inunit,5100,iostat=ier2) qline
!!     c4testprint:          print *,'*** header2=',qline
!!             if ( ier1.ne.0 .or. ier2.ne.0 ) then
!!               print *,'read_blip_data_info ERROR - header read: ',
!!          &            ier1,ier2,qfilename
!!     !old=preGfortran          CALL EXIT( 'ERROR EXIT - read_blip_data_info reading header' )
!!               CALL EXIT
!!             endif
!!     ccc extract array size from second header line
!!     ccc     find delimiter for grid indexs
!!     colder        do ichar=1,180
!!     ccc allow for old and new grid array index delimiter
!!     c-new_delimiter
!!                 iindex = index(qline,'Indexs= ') +8
!!     c-old_delimiter ' = '
!!                 if( iindex .le. 8 ) iindex = index(qline,' = ') +3
!!                 if( iindex .le. 3 ) then
!!     !old=preGfortran              CALL EXIT( 'ERROR EXIT - grid index delimiter not found' )
!!                   CALL EXIT
!!                 endif
!!     colder          if( qline(ichar:ichar+2) .eq. " = " ) then
!!     colder-delimiter          if( qline(ichar:ichar) .eq. "=" ) then
!!     c4testprint:            print *,'*** iindex= ',iindex
!!     c4testprint:            print *,'*** iindex= ',iindex
!!     ccc read array indexs
!!     CCC "EOF" ERROR OCCURRED HERE WHEN NOT ENOUGH FIELDS SUPPLIED IN HEADER LINE
!!     CCC BUT LOSS OF BUFFER REQUIRED "CALL EXIT" STATEMENT TO GET ERROR MESSAGE
!!                 read( qline(iindex:180),FMT=*,ERR=6900) nnx1,nnx2,nny1,nny2,
!!     colder          read( qline(ichar+3:180),*,iostat=iostat) nnx1,nnx2,nny1,nny2,
!!     colder-delimiter          read( qline(ichar+1:180),*,iostat=iostat) nnx1,nnx2,nny1,nny2,
!!          &    qproj,qprojection,dx,dy,plat1,plat2,plon,alat0,alon0
!!     cold     &    qdum,qproj,dx,dy,plat1,plat2,plon,alat0,alon0
!!     c4testprint:            print *,'*** nnx1,nnx2,nny1,nny2= ',nnx1,nnx2,nny1,nny2
!!                 
!!                 NNX = nnx2-nnx1+1
!!                 NNY = nny2-nny1+1
!!     ccc   test for projection data !
!!                 if( qproj(1:4).ne.'PROJ' .and. qproj(1:4).ne.'Proj' )
!!     !old=preGfortran     & CALL EXIT('ERROR EXIT: PROJ id not found by read_blip_data_info')
!!          & CALL EXIT
!!     ccc   test for lambert data !
!!     Clatlongrid-            if( qprojection.ne.'lambert' ) CALL EXIT( 'ERROR EXIT -
!!     Clatlongrid-     & lambert data not found by read_blip_data_info' )
!!     colder          end if 
!!     colder        end do
!!           return
!!      6900 print *,  '*** ERROR: read_blip_data_info (ncl_jack_fortran.f) -
!!          & header line 2 missing proj. data'
!!           print *, '  file=',qdatafile
!!           print *, '  iindex,line=',iindex,qline
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO READ BLIP DATA FILE FOR SINGLE PARAMETER - output array is REAL
!!     ccc if qfilename a zipped file, create tmp unzipped file
!!     C NCLFORTSTART
!!           subroutine read_blip_datafile( qfilename, NNX,NNY, adata, qid )
!!           character*(*) qfilename,qid
!!           integer NNX,NNY
!!           real adata(NNX,NNY)
!!     C NCLEND
!!           character qdatafile*120
!!           character qline*180
!!           character qheader1*180, qdowtest*3
!!     c4testprint:          print *,'read_blip_datafile: ',qfilename
!!     ccc open file
!!             inunit = 2
!!             close(inunit)
!!     ccc return name qdatafile based on whether qfilename is text or zipped
!!             call datafile_unzip( qfilename, qdatafile )
!!     ccc open text data file
!!             open(inunit,status='old',form='formatted',
!!          &       file=qdatafile,iostat=iostat)
!!             if ( iostat.ne.0 ) then
!!               print *,'ERROR - read_blip_datafile open: ',iostat,qfilename
!!     !old=preGfortran          CALL EXIT( 'read_blip_datafile ERROR EXIT - opening file' )
!!               CALL EXIT
!!             endif
!!     ccc find start of data set
!!             do ii=1,10000
!!               read(inunit,5100,iostat=iostat) qline
!!      5100     format(a180)
!!               if ( iostat .ne. 0 ) then
!!                 print *,'ERROR - read_blip_datafile data not found: ',
!!          &            iostat,qfilename
!!     !old=preGfortran            CALL EXIT('read_blip_datafile ERROR EXIT - data not found')
!!                 CALL EXIT
!!               endif
!!               if( qline(2:3 ).eq.'--' ) goto 1010
!!             enddo
!!      1010   continue
!!     ccc read 3 header lines
!!             read(inunit,5100,iostat=ier1) qheader1
!!     c4testprint:          print *,'read_blip_datafile header1=',qheader1
!!             read(inunit,5100,iostat=ier2) qline
!!             read(inunit,5100,iostat=ier3) qline
!!             if ( ier1.ne.0 .or. ier2.ne.0 .or. ier3.ne.0 ) then
!!               print *,'read_blip_datafile ERROR - header read: ',
!!          &            ier1,ier2,ier3,qfilename
!!     !old=preGfortran          CALL EXIT( 'ERROR EXIT - read_blip_datafile reading header' )
!!               CALL EXIT
!!             endif
!!     ccc eliminate all prior to date (i.e. parameter name) and trailing blanks in returned qid 
!!     ccc (cannot eliminate trailing blanks here since qid length set by input qid)
!!           do ichar=1,180
!!     ccc [] brackets enclose units, mark beginning of time/data info to be extracted (but possibly with ncarg markups)
!!     ccc following for no ncarg markup
!!     c4testprint:       print *,'QHEADER1=',ichar,qheader1(ichar:ichar+1),qheader1
!!             if( qheader1(ichar:ichar+1) .eq. "] " ) then
!!               qid = qheader1(ichar+2:180)
!!     c-oldtitleorder        qdowtest = qheader1(ichar:ichar+2)
!!     c-oldtitleorder        if(  qdowtest.eq."SUN".or.qdowtest.eq."MON".or.qdowtest.eq."TUE"
!!     c-oldtitleorder     &   .or.qdowtest.eq."WED".or.qdowtest.eq."THU".or.qdowtest.eq."FRI"
!!     c-oldtitleorder     &   .or.qdowtest.eq."SAT" ) then
!!     c-oldtitleorder          qid = qheader1(ichar:180)
!!               goto 9999
!!     ccc following allow simple ncarg markup
!!             elseif( qheader1(ichar:ichar+1).eq."]~" .and.
!!          &          qheader1(ichar+3:ichar+4).eq."~ " ) then
!!     cold        elseif( qheader1(ichar:ichar+4) .eq. "]~P~ " ) then
!!               qid = qheader1(ichar+5:180)
!!               goto 9999
!!             end if
!!           end do
!!      9999 continue
!!     ccc read data - free-format
!!             do iiy=1,nny
!!               read(inunit,*,iostat=iostat) (adata(iix,iiy),iix=1,nnx)
!!     c4testprint:          print *,'  last value inr row=',iiy,' = ',adata(nnx,iiy)
!!             end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!           subroutine datafile_unzip( qfilename, qdatafile )
!!     ccc return name qdatafile of text datafile depending on whether qfilename is text or zipped
!!     ccc  if qdatafile is zipped (based on qfilename tail), unzip it to tmp file and return that filename
!!     ccc  if not zipped, if exists return that name, else unzip file qfilename.zip iof exists, else error exit
!!           character qfilename*(*),qdatafile*(*)
!!           character qtail4*4, qrand*4
!!     ccc call to SYSTEM,ACCESS requires integer declaration to avoid return error code = -2147483648
!!           integer system,access  
!!           len = Len_Trim( qfilename )
!!           qtail4 = qfilename(len-3:len)
!!           if( qtail4 .ne. '.zip' ) then
!!     ccc test for existence of non-zipped file - if so, return
!!             if( access(qfilename(1:len),'r') .eq. 0 ) then
!!               qdatafile = qfilename
!!               return
!!     ccc test for existence of zipped file  qfilename..zip - if not, exit
!!             else if( access(qfilename(1:len)//'.zip','r') .ne. 0 ) then
!!     ccc note this error occurs when _neither_ qfilename or qfilename.zip exist
!!               print *,'*** datafile_unzip ERROR EXIT: UN-ACCESSIBLE FILE:',
!!          &            ierr,qfilename
!!               call exit
!!             end if
!!     ccc if reach here, zipped file qfilename.zip exists so will use it
!!           end if
!!     ccc for zip file need name for unzipped tmp datafile
!!           call srand( int(secnds(0.0)) )
!!           krand = int( 1000*rand( int(secnds(0.0)) ) )
!!     cbad-time_gives_NaN+rand_arg_has_no_effect          krand = int( 1000*rand( time() ) )
!!           write( qrand,'(".",i3.3)' ) krand
!!           islash = +1
!!           ilastslash = -1
!!           do while ( islash .gt. 0 )        
!!             ilastslash = ilastslash + islash 
!!             islash = index( qfilename(ilastslash+1:len), '/' )
!!           end do
!!     c---  print *,'QDATAFILE=', qdatafile(1:Len_Trim(qdatafile))
!!     ccc unzip zip file to temp file
!!           if( qtail4 .eq. '.zip' ) then
!!     ccc if qfilename without .zip tail try to unzip qfilename.zip
!!             qdatafile = '/tmp/' // qfilename(ilastslash+1:len-4) // qrand
!!             ioerr = system( 'unzip -p ' // qfilename(1:len) // ' >| ' 
!!          &              // qdatafile(1:Len_Trim(qdatafile)) )
!!           else
!!     ccc unzip of input qfilename (already has .zip tail)
!!             qdatafile = '/tmp/' // qfilename(ilastslash+1:len) // qrand
!!             ioerr = system( 'unzip -p ' // qfilename(1:len) // '.zip >| ' 
!!          &              // qdatafile(1:Len_Trim(qdatafile)) )
!!           end if
!!           if( ioerr .ne. 0 ) then
!!             print *,'*** datafile_unzip ERROR EXIT: UNZIP FAILED:',
!!          &              ioerr, qfilename
!!             call exit
!!           end if
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !***  REPLACE U,V VELOCITY COMPONENTS (grid coords) TO DIRECTION(true),SPEED
!!     C NCLFORTSTART
!!           subroutine uv2wdws_4latlon(u,v, alat,alon, nx,ny, projlat,projlon) 
!!     ccc output wd in degrees (meteorological convention)
!!           real u(nx,ny),v(nx,ny), alat(nx,ny),alon(nx,ny)
!!           real projlat,projlon
!!           integer nx,ny
!!     C NCLEND
!!           real longca, longcb
!!     ccc below method ala wrf_user_fortran_util_0 :: compute_uvmet( u,v, uvmet, diff, alpha, longitude,latitude, cen_
!!           pi = 3.14159265
!!           DEG2RAD = pi/180.
!!           cone = cos( DEG2RAD*( 90. - projlat ) )
!!           do ix=1,nx 
!!           do iy=1,ny 
!!             if( alon(ix,iy) .gt. 180. ) then
!!               alon(ix,iy) = alon(ix,iy) - 360.
!!             end if
!!             longca = alon(ix,iy) - projlon
!!             if( alat(ix,iy) .lt. 0.0 ) then
!!               longcb = - longca * cone * DEG2RAD 
!!             else
!!               longcb =  longca * cone * DEG2RAD 
!!             end if
!!             coslong = cos( longcb ) 
!!             sinlong = sin( longcb ) 
!!             umet = v(ix,iy) * sinlong + u(ix,iy) * coslong 
!!             vmet = v(ix,iy) * coslong - u(ix,iy) * sinlong 
!!     ccc overwrite u with wd and v with ws
!!             v(ix,iy) = sqrt( u(ix,iy)**2 + v(ix,iy)**2 )
!!             u(ix,iy) = atan2( umet, vmet )/DEG2RAD + 180.0 
!!           end do
!!           end do    
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !** REPLACE WIND DIRECTION(true),SPEED BY VELOCITY COMPONENTS (grid coords)
!!     C NCLFORTSTART
!!           subroutine wdws2uv_4latlon( wd,ws, alat,alon, nx,ny, 
!!          &                   qprojection,projlat,projlon ) 
!!     ccc input wd in degrees (meteorological convention)
!!           real wd(nx,ny),ws(nx,ny), alat(nx,ny),alon(nx,ny)
!!           real projlat,projlon
!!           character*(*) qprojection
!!           integer nx,ny
!!     C NCLEND
!!           real longca, longcb
!!     ccc below method reverse of uv2wswd
!!           pi = 3.14159265
!!           DEG2RAD = pi/180.
!!           if( qprojection .eq. "lambert" ) then      
!!     clatlongridtestprint:      print *,'** LAMBERT GRID'   
!!             cone = cos( DEG2RAD*( 90. - projlat ) )
!!             do ix=1,nx 
!!             do iy=1,ny 
!!               if( alon(ix,iy) .gt. 180. ) then
!!                 alon(ix,iy) = alon(ix,iy) - 360.
!!               end if
!!               longca = alon(ix,iy) - projlon
!!               if( alat(ix,iy) .lt. 0.0 ) then
!!                 longcb = - longca * cone * DEG2RAD 
!!               else
!!                 longcb =  longca * cone * DEG2RAD 
!!               end if
!!               coslong = cos( longcb ) 
!!               sinlong = sin( longcb ) 
!!               umet = -ws(ix,iy)*sin( DEG2RAD * wd(ix,iy) ) 
!!               vmet =  ws(ix,iy)*cos( DEG2RAD * wd(ix,iy) ) 
!!     ccc overwrite wd with u and ws with v
!!               wd(ix,iy) = umet * coslong + vmet * sinlong
!!               ws(ix,iy) = umet * sinlong - vmet * coslong
!!     c-reverse:  umet = v(ix,iy) * sinlong + u(ix,iy) * coslong 
!!     c-reverse:  vmet = v(ix,iy) * coslong - u(ix,iy) * sinlong 
!!             end do
!!             end do    
!!           elseif( qprojection .eq. "latlong" ) then      
!!     clatlongridtestprint:      print *,'** LATLON GRID'   
!!             do ix=1,nx 
!!             do iy=1,ny 
!!               umet = -ws(ix,iy)*sin( DEG2RAD * wd(ix,iy) ) 
!!               vmet =  ws(ix,iy)*cos( DEG2RAD * wd(ix,iy) ) 
!!     ccc overwrite wd with u and ws with v
!!               wd(ix,iy) = umet 
!!               ws(ix,iy) = -vmet 
!!             end do
!!             end do
!!           else
!!     !old=preGfortran        CALL EXIT('ERROR EXIT - unknown projection in wdws2uv_4latlon')
!!             CALL EXIT
!!           end if
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !** CALC LAT/LONS FOR ARRAY using indexs relative to grid center
!!     !   *NB* center lat/lon is for data grid, not outer MOAD grid
!!     C NCLFORTSTART
!!           subroutine calc_latlon( NNX,NNY, dx,dy,
!!          & projlat1,projlat2,projlon,centlat,centlon, alat,alon )
!!           real alat(NNX,NNY),alon(NNX,NNY) 
!!           real dx,dy,projlat1,projlat2,projlon,centlat,centlon
!!           integer NNX,NNY
!!     C NCLEND
!!     !!! NEED ARRAYS FOR INPUT I,J VALUES
!!           real airel(NNX,NNY),ajrel(NNX,NNY) 
!!     cold-fullgridcentered      subroutine calc_latlon( NXMAX,NYMAX,nx1,nx2,ny1,ny2,dx,dy,
!!     cold-fullgridcentered      real alat(NXMAX,NYMAX),alon(NXMAX,NYMAX) 
!!     cold-fullgridcentered      integer NXMAX,NYMAX,nx1,nx2,ny1,ny2
!!           if( projlat1 .ne. projlat2 ) then
!!             print *,'*** calc_latlon ERROR EXIT: not tangent projection:',
!!          &              projlat1,projlat2
!!             call exit
!!           end if
!!     ccc need to use index relative to _center_ - here use array indexing starting with 1 (NOT nx1,ny1)  
!!           aicent = 0.5*(1.+NNX) 
!!           ajcent = 0.5*(1.+NNY) 
!!     cold-fullgridcentered ccc need to use index relative to _center_   
!!     cold-fullgridcentered       aicent = 0.5*(NXMAX+1) 
!!     cold-fullgridcentered       ajcent = 0.5*(NYMAX+1) 
!!     
!!     CCC create i,j arrays
!!     ccc here use array indexing starting with 1 (NOT nx1,ny1)  
!!           do ix=1,NNX
!!           do iy=1,NNY
!!     CCC  *NB* "CENTER" IS LAT,LON ASSOCIATED WITH PT (1,1) FOR W3FB12 !!!
!!             airel(ix,iy) = ix - aicent +1.
!!             ajrel(ix,iy) = iy - ajcent +1.
!!           end do
!!           end do    
!!     
!!     !!! INPUT I,J _ARRAYS_ TO ALTERED W3FB12
!!             call arrayW3FB12( airel,ajrel,
!!          &          ALAT,ALON, NNX,NNY, 
!!          &          centlat,centlon, dx,projlon,projlat1, ierr )
!!     
!!           if( IERR .ne. 0 ) then
!!             print *,'*** calc_latlon ERROR EXIT: non-zero W3FB12 exit=',ierr
!!             call exit
!!           end if
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!! jack - altered to allow array input instead of individual values
!!     !!! tested by comparing output to original version
!!     !!! complex calcs (sin,cos,atan,**): 11 outside loop, 2 inside loop (not counting add,mult,div,square)
!!     !!! so save considerable time by doing for array !
!!     C NCLFORTSTART
!!            SUBROUTINE arrayW3FB12( XI,XJ,
!!          &       latitude,longitude, nnx,nny,
!!          &       ALAT1,ELON1,DX,ELONV,ALATAN, IERR )
!!            REAL ALAT1,ELON1,DX,ELONV,ALATAN,ALAT,ELON
!!            INTEGER IERR
!!           real xi(nnx,nny),xj(nnx,nny),latitude(nnx,nny),longitude(nnx,nny) 
!!     C NCLEND
!!     C$$$   SUBPROGRAM  DOCUMENTATION  BLOCK
!!     C
!!     C SUBPROGRAM:  W3FB12        LAMBERT(I,J) TO LAT/LON FOR GRIB
!!     C   PRGMMR: STACKPOLE        ORG: NMC42       DATE:88-11-28
!!     C
!!     C ABSTRACT: CONVERTS THE COORDINATES OF A LOCATION ON EARTH GIVEN IN A
!!     C   GRID COORDINATE SYSTEM OVERLAID ON A LAMBERT CONFORMAL TANGENT
!!     C   CONE PROJECTION TRUE AT A GIVEN N OR S LATITUDE TO THE
!!     C   NATURAL COORDINATE SYSTEM OF LATITUDE/LONGITUDE
!!     C   W3FB12 IS THE REVERSE OF W3FB11.
!!     C   USES GRIB SPECIFICATION OF THE LOCATION OF THE GRID
!!     C
!!     C PROGRAM HISTORY LOG:
!!     C   88-11-25  ORIGINAL AUTHOR:  STACKPOLE, W/NMC42
!!     C
!!     C USAGE:  CALL W3FB12(XI,XJ,ALAT1,ELON1,DX,ELONV,ALATAN,ALAT,ELON,IERR,
!!     C                                   IERR)
!!     C   INPUT ARGUMENT LIST:
!!     C     XI       - I COORDINATE OF THE POINT  REAL*4
!!     C     XJ       - J COORDINATE OF THE POINT  REAL*4
!!     C     ALAT1    - LATITUDE  OF LOWER LEFT POINT OF GRID (POINT 1,1)
!!     C                LATITUDE <0 FOR SOUTHERN HEMISPHERE; REAL*4
!!     C     ELON1    - LONGITUDE OF LOWER LEFT POINT OF GRID (POINT 1,1)
!!     C                  EAST LONGITUDE USED THROUGHOUT; REAL*4
!!     C     DX       - MESH LENGTH OF GRID IN METERS AT TANGENT LATITUDE
!!     C     ELONV    - THE ORIENTATION OF THE GRID.  I.E.,
!!     C                THE EAST LONGITUDE VALUE OF THE VERTICAL MERIDIAN
!!     C                WHICH IS PARALLEL TO THE Y-AXIS (OR COLUMNS OF
!!     C                THE GRID) ALONG WHICH LATITUDE INCREASES AS
!!     C                THE Y-COORDINATE INCREASES.  REAL*4
!!     C                THIS IS ALSO THE MERIDIAN (ON THE OTHER SIDE OF THE
!!     C                TANGENT CONE) ALONG WHICH THE CUT IS MADE TO LAY
!!     C                THE CONE FLAT.
!!     C     ALATAN   - THE LATITUDE AT WHICH THE LAMBERT CONE IS TANGENT TO
!!     C                (TOUCHES OR OSCULATES) THE SPHERICAL EARTH.
!!     C                 SET NEGATIVE TO INDICATE A
!!     C                 SOUTHERN HEMISPHERE PROJECTION; REAL*4
!!     C
!!     C   OUTPUT ARGUMENT LIST:
!!     C     ALAT     - LATITUDE IN DEGREES (NEGATIVE IN SOUTHERN HEMI.)
!!     C     ELON     - EAST LONGITUDE IN DEGREES, REAL*4
!!     C     IERR     - .EQ. 0   IF NO PROBLEM
!!     C                .GE. 1   IF THE REQUESTED XI,XJ POINT IS IN THE
!!     C                         FORBIDDEN ZONE, I.E. OFF THE LAMBERT MAP
!!     C                         IN THE OPEN SPACE WHERE THE CONE IS CUT.
!!     C                  IF IERR.GE.1 THEN ALAT=999. AND ELON=999.
!!     C
!!     C   REMARKS: FORMULAE AND NOTATION LOOSELY BASED ON HOKE, HAYES,
!!     C     AND RENNINGER'S "MAP PROJECTIONS AND GRID SYSTEMS...", MARCH 1981
!!     C     AFGWC/TN-79/003
!!     C
!!     C ATTRIBUTES:
!!     C   LANGUAGE: IBM VS FORTRAN
!!     C   MACHINE:  NAS
!!     C
!!     C$$$
!!     C
!!              LOGICAL NEWMAP
!!              DATA  RERTH /6.3712E+6/, PI/3.14159/, OLDRML/99999./
!!     C
!!     C        PRELIMINARY VARIABLES AND REDIFINITIONS
!!     C
!!     C        H = 1 FOR NORTHERN HEMISPHERE; = -1 FOR SOUTHERN
!!     C
!!     
!!              SAVE
!!     
!!              BETA  = 1.
!!              IERR = 0
!!     
!!              IF(ALATAN.GT.0) THEN
!!                H = 1.
!!              ELSE
!!                H = -1.
!!     Cjack - fixup for S.Hemisphere
!!                XI = 2. - XI 
!!                XJ = 2. - XJ 
!!              ENDIF
!!     C
!!              PIBY2 = PI/2.
!!              RADPD = PI/180.0
!!              DEGPRD = 1./RADPD
!!              REBYDX = RERTH/DX
!!              ALATN1 = ALATAN * RADPD
!!              AN = H * SIN(ALATN1)
!!              COSLTN = COS(ALATN1)
!!     C
!!     C        MAKE SURE THAT INPUT LONGITUDE DOES NOT PASS THROUGH
!!     C        THE CUT ZONE (FORBIDDEN TERRITORY) OF THE FLAT MAP
!!     C        AS MEASURED FROM THE VERTICAL (REFERENCE) LONGITUDE
!!     C
!!              ELON1L = ELON1
!!              IF((ELON1-ELONV).GT.180.)
!!          &     ELON1L = ELON1 - 360.
!!              IF((ELON1-ELONV).LT.(-180.))
!!          &     ELON1L = ELON1 + 360.
!!     C
!!              ELONVR = ELONV * RADPD
!!     C
!!     C        RADIUS TO LOWER LEFT HAND (LL) CORNER
!!     C
!!              ALA1 =  ALAT1 * RADPD
!!              RMLL = REBYDX * ((COSLTN**(1.-AN))*(1.+AN)**AN) *
!!          &           (((COS(ALA1))/(1.+H*SIN(ALA1)))**AN)/AN
!!     C
!!     C        USE RMLL TO TEST IF MAP AND GRID UNCHANGED FROM PREVIOUS
!!     C        CALL TO THIS CODE.  THUS AVOID UNNEEDED RECOMPUTATIONS.
!!     C
!!              IF(RMLL.EQ.OLDRML) THEN
!!                NEWMAP = .FALSE.
!!              ELSE
!!                NEWMAP = .TRUE.
!!                OLDRML = RMLL
!!     C
!!     C          USE LL POINT INFO TO LOCATE POLE POINT
!!     C
!!                ELO1 = ELON1L * RADPD
!!                ARG = AN * (ELO1-ELONVR)
!!                POLEI = 1. - H * RMLL * SIN(ARG)
!!                POLEJ = 1. + RMLL * COS(ARG)
!!              ENDIF
!!     C
!!     
!!     !!! moved calc of THING outside of loop since invariant & costly
!!                IF(NEWMAP) THEN
!!                  ANINV = 1./AN
!!                  ANINV2 = ANINV/2.
!!                  THING = ((AN/REBYDX) ** ANINV)/
!!          &         ((COSLTN**((1.-AN)*ANINV))*(1.+ AN))
!!                ENDIF
!!     
!!     !!! ALTERED TO ALLOW ARRAY INPUT INSTEAD OF INDIVIDUAL VALUES
!!              do ix=1,nnx
!!              do iy=1,nny 
!!     
!!     C        RADIUS TO THE I,J POINT (IN GRID UNITS)
!!     C              YY REVERSED SO POSITIVE IS DOWN
!!     C
!!              XX = XI(ix,iy) - POLEI
!!              YY = POLEJ - XJ(ix,iy)
!!              R2 = XX*XX + YY*YY
!!     coriginal         R2 = XX**2 + YY**2
!!     C
!!     C        CHECK THAT THE REQUESTED I,J IS NOT IN THE FORBIDDEN ZONE
!!     C           YY MUST BE POSITIVE UP FOR THIS TEST
!!     C
!!              THETA = PI*(1.-AN)
!!              BETA = ABS(ATAN2(XX,-YY))
!!              IERR = 0
!!              IF(BETA.LE.THETA) THEN
!!                IERR = 1
!!                ALAT = 999.
!!                ELON = 999.
!!                IF(.NOT.NEWMAP)  RETURN
!!              ENDIF
!!     C
!!     C        NOW THE MAGIC FORMULAE
!!     C
!!              IF(R2.EQ.0) THEN
!!                ALAT = H * 90.
!!                ELON = ELONV
!!              ELSE
!!     C
!!     C          FIRST THE LONGITUDE
!!     C
!!                ELON = ELONV + DEGPRD * ATAN2(H*XX,YY)/AN
!!                ELON = AMOD(ELON+360., 360.)
!!     C
!!     C          NOW THE LATITUDE
!!     C          RECALCULATE THE THING ONLY IF MAP IS NEW SINCE LAST TIME
!!     C
!!     !!! old location of calc of THING
!!                ALAT = H*(PIBY2 - 2.*ATAN(THING*(R2**ANINV2)))*DEGPRD
!!              ENDIF
!!     C
!!     C        FOLLOWING TO ASSURE ERROR VALUES IF FIRST TIME THRU
!!     C         IS OFF THE MAP
!!     C
!!              IF(IERR.NE.0) THEN
!!                ALAT = 999.
!!                ELON = 999.
!!                IERR = 2
!!              ENDIF
!!     
!!     CJACK: CONVERT E.LON TO -180 to +180 range
!!              if( ELON .gt. 180. ) then
!!                ELON = ELON - 360.
!!              end if
!!     
!!     !!! ALTERED TO ALLOW ARRAY INPUT INSTEAD OF INDIVIDUAL VALUES
!!              latitude(ix,iy)  = ALAT
!!              longitude(ix,iy) = ELON
!!           end do
!!           end do
!!     
!!              RETURN
!!              END
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** FUNCTION TO NORMALIZE INPUT SFC SOLAR RAD BY CLOUDLESS SFC SOLAR RAD
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!            subroutine calc_sfcsunpct( jday,gmthr, alat,alon,ter,
!!          &            z,pmb,tc,qvapor, isize,jsize,ksize, bparam ) 
!!            real z(isize,jsize,ksize), pmb(isize,jsize,ksize),
!!          &      tc(isize,jsize,ksize), qvapor(isize,jsize,ksize)
!!            real alat(isize,jsize),alon(isize,jsize),ter(isize,jsize)
!!            real bparam(isize,jsize)
!!            real gmthr
!!           integer jday, isize,jsize,ksize
!!     C NCLEND
!!     ccc compute dz from input z
!!            real dz(100)
!!            if( ksize.gt.100 ) stop 'calc_sfcsunpct ERROR - max nnz exceeded'
!!               do jj=1,jsize
!!               do ii=1,isize
!!     ccc compute dz from input z - use simple extrapolation at top
!!                 do iz=2,(ksize-1)
!!                   dz(iz) = 0.5*(z(ii,jj,iz+1)-z(ii,jj,iz-1))
!!                 end do 
!!                 dz(ksize) = dz(ksize-1)
!!     ccc         use surface terrain as bottom-most z
!!                 dz(1) =  0.5*(z(ii,jj,1)+z(ii,jj,2)) - ter(ii,jj)
!!     cold            dz(1) = dz(2)
!!     c4test:      print *,'DZ1,2,top-1,top=', dz(1),dz(2),dz(ksize-1),dz(ksize)
!!     !!! Calculate constant for short wave radiation
!!                 degrad = 0.017453178
!!                 dpd = 365./360.
!!                 r = 287.
!!                 CALL radconst( DECLIN,SOLCON, gmthr,jday, DEGRAD,DPD )
!!     !========================================================================
!!     !======  START OF IN-LINE CLOUDLESS SOLAR RAD CALC  =====================
!!     !!! calculation placed in-line instead of calling as subroutine
!!     !!!    so can use 3d array indexing of tc,qvapor,pmb
!!     !!!    since passing ala  "CALL SWPARA_nocloud( ... tc(ii,jj,1), ..." fails to give correct values
!!     !!!!!!!!!!!!!!!!!  MODIFIED WRF ROUTINE FOLLOWS  !!!!!!!!!!!!!!!!!!!!!!!!
!!     !!! FROM phys/module_ra_sw.F
!!     cjack - altered to use input temp in degC instead of degK
!!     !!! JACK - modified to remove cloud and aerosol effects
!!     !!! JACK - modified to remove model run time (xtime)
!!     !------------------------------------------------------------------
!!     !     TO CALCULATE SHORT-WAVE ABSORPTION AND SCATTERING IN CLEAR
!!     !     AIR AND REFLECTION AND ABSORPTION IN CLOUD LAYERS (STEPHENS,1984)
!!     !------------------------------------------------------------------
!!           GSWdown=0.0
!!     cjack - for ncl use
!!           TLOCTM= gmthr +alon(ii,jj)/15.
!!     coriginal      TLOCTM=GMT +XLONG/15.
!!           HRANG=15.*(TLOCTM-12.)*DEGRAD
!!     cjack - for ncl use
!!           XXLAT=alat(ii,jj)*DEGRAD
!!     coriginal      XXLAT=XLAT*DEGRAD
!!           CSZA=SIN(XXLAT)*SIN(DECLIN)+COS(XXLAT)*COS(DECLIN)*COS(HRANG)
!!     !  RETURN IF NIGHT
!!           IF(CSZA.LE.1.E-9) GOTO 7
!!           XMU=CSZA
!!           SDOWNtop = SOLCON*XMU
!!           SDOWN = SDOWNtop
!!     !jack-sdownarray-      SDOWN(1)=SOLCON*XMU
!!     !  SET UV (G/M**2) WATER VAPOR PATH INTEGRATED DOWN
!!           UV=0.
!!           TOTABS=0.
!!     !  CONTRIBUTIONS DUE TO CLEAR AIR
!!           DSCA=0.
!!           DABS=0.
!!     !!! loop from top of atmosphere down
!!     cjack - for ncl use
!!           DO 200 K=ksize,1,-1
!!     coriginal      DO 200 K=kts,kte
!!     !jack - moved creation of ro,xwvp,xatp into main loop to eliminate need for internal arrays
!!     cjack - allow input in mb and degC
!!              RO = (100.*pmb(ii,jj,k))/(R*(tc(ii,jj,k)+273.16))
!!     coriginal         RO = P(K)/(R*T(K))
!!     cjack - for ncl use
!!              XWVP = RO*qvapor(ii,jj,k)*DZ(K)*1000.
!!     coriginal         XWVP = RO*QV(K)*DZ(K)*1000.
!!              XATP = RO*DZ(K)
!!     !jack - moved creation of ro,xwvp,xatp into main loop to eliminate need for internal arrays
!!              UV = UV +XWVP
!!     !original         UV=UV+XWVP(K)
!!     !jack     UGCM *WAS* UV/COS(THETA) (G/CM**2)
!!              UGCM=UV*0.0001/XMU
!!              OLDABS=TOTABS
!!     !     WATER VAPOR ABSORPTION AS IN LACIS AND HANSEN (1974)
!!              TOTABS=2.9*UGCM/((1.+141.5*UGCM)**0.635+5.925*UGCM)
!!     !     APPROXIMATE RAYLEIGH SCATTERING
!!     !jack - moved creation of ro,xwvp,xatp into main loop to eliminate need for internal arrays
!!              XSCA=1.E-5*XATP/XMU
!!     !original         XSCA=1.E-5*XATP(K)/XMU
!!     !     LAYER VAPOR ABSORPTION DONE FIRST
!!              XABS=(TOTABS-OLDABS)*(SDOWNtop-DSCA)/SDOWN
!!     !jack-sdownarray-         XABS=(TOTABS-OLDABS)*(SDOWN(1)-DSCA)/SDOWN(K)
!!              IF(XABS.LT.0.)XABS=0.
!!     !     LAYER ALBEDO AND ABSORPTION
!!              DSCA=DSCA+XSCA*SDOWN
!!              DABS=DABS+XABS*SDOWN
!!     !jack-sdownarray-         DSCA=DSCA+XSCA*SDOWN(K)
!!     !jack-sdownarray-         DABS=DABS+XABS*SDOWN(K)
!!     !     LAYER TRANSMISSIVITY
!!              TRANS0=100.*(1.0-XABS-XSCA)
!!     !original         TRANS0=100.-XABS*100.-XSCA*100.
!!              IF(TRANS0.LT.1.)THEN
!!                FF=99./(XABS*100.+XSCA*100.)
!!                XABS=XABS*FF
!!                XSCA=XSCA*FF
!!                TRANS0=1.
!!              ENDIF
!!              SDOWN=AMAX1(1.E-9,SDOWN*TRANS0*0.01)
!!     !jack-sdownarray-         SDOWN(K+1)=AMAX1(1.E-9,SDOWN(K)*TRANS0*0.01)
!!     c4test JACK - subroutine prints
!!     c4test      print *, 'k,sdown,t,p,q,dz=',k,sdown,t(k),p(k),qv(k),dz(k)
!!       200   CONTINUE
!!             GSWdown=SDOWN
!!     !jack-sdownarray-        GSWdown=SDOWN(kte+1)
!!         7 CONTINUE
!!     !======   END  OF IN-LINE CLOUDLESS SOLAR RAD CALC  =====================
!!     !========================================================================
!!     c4test:      print *,'SOLCON,GSWdown=', ii,jj,SOLCON,GSWdown
!!     ccc normalize input array - but set to missing value if GSWdown<=0
!!     ccc use lower limit to avoid very small number roundoff errors
!!                 if( GSWdown .gt. 0.001 ) then
!!     cold            if( GSWdown .gt. 0. ) then
!!                   bparam(ii,jj) =  100. * bparam(ii,jj) / GSWdown
!!     ccc set upper limit as time used for model calc not same as output time
!!                   if( bparam(ii,jj) .gt. 100. ) bparam(ii,jj)=100.
!!                 else
!!                   bparam(ii,jj) =  -999. 
!!                   !4test:       print *,'WARNING: sfcsunpct finds GSWdown<=0: ',ii,jj, GSWdown
!!                 end if
!!               end do
!!               end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!  MODIFIED WRF ROUTINE FOLLOWS  !!!!!!!!!!!!!!!!!!!!!!!!
!!     !!! FROM phys/module_radiation_driver.F
!!     !!! JACK - modified to remove model run time (xtime)
!!           SUBROUTINE radconst( DECLIN,SOLCON, GMT,JULDAY, DEGRAD,DPD )
!!     !  Compute terms used in radiation physics 
!!     !---------------------------------------------------------------------
!!           IMPLICIT NONE
!!           INTEGER JULDAY
!!           REAL GMT,DEGRAD,DPD
!!           REAL DECLIN,SOLCON
!!           REAL OBECL,SINOB,SXLONG,ARG,JULIAN,
!!          &     DECDEG,DJUL,RJUL,ECCFAC
!!     ! for short wave radiation
!!           DECLIN=0.
!!           SOLCON=0.
!!     !-----OBECL : OBLIQUITY = 23.5 DEGREE.
!!           OBECL=23.5*DEGRAD
!!           SINOB=SIN(OBECL)
!!     !-----CALCULATE LONGITUDE OF THE SUN FROM VERNAL EQUINOX:
!!           JULIAN=FLOAT(JULDAY-1)+(GMT)/24.
!!           IF(JULIAN.GE.80.)SXLONG=DPD*(JULIAN-80.)
!!           IF(JULIAN.LT.80.)SXLONG=DPD*(JULIAN+285.)
!!           SXLONG=SXLONG*DEGRAD
!!           ARG=SINOB*SIN(SXLONG)
!!           DECLIN=ASIN(ARG)
!!           DECDEG=DECLIN/DEGRAD
!!     !----SOLAR CONSTANT ECCENTRICITY FACTOR (PALTRIDGE AND PLATT 1976)
!!           DJUL=JULIAN*360./365.
!!           RJUL=DJUL*DEGRAD
!!           ECCFAC=1.000110+0.034221*COS(RJUL)+0.001280*SIN(RJUL)+0.000719*  
!!          &        COS(2*RJUL)+0.000077*SIN(2*RJUL)
!!           SOLCON=1370.*ECCFAC
!!           END
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** REPLACE 2D ARRAY a VALUE AT EACH GRIDPOINT WITH b IF b SMALLER
!!     !*** and if changed put constant bmark into array amark   
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!            subroutine min_2darrays( a,amark, b,bmark, isize,jsize ) 
!!            real a(isize,jsize),amark(isize,jsize),b(isize,jsize)
!!            real bmark
!!           integer isize,jsize
!!     C NCLEND
!!            do jj=1,jsize
!!            do ii=1,isize
!!              if( a(ii,jj) .ge. b(ii,jj) ) then
!!                a(ii,jj) = b(ii,jj)
!!                amark(ii,jj) = bmark
!!              end if 
!!            end do
!!            end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !*** COUNT VALUES WITHIN +/- delta of value  AT EACH GRIDPOINT OF 2D ARRAY a
!!     !*** and if changed put constant bmark into array amark   
!!     !!! FOLLOWING STARTS EMBEDDED NCL INTERFACE BLOCK
!!     C NCLFORTSTART
!!            subroutine count_2darray( a, value,delta, isize,jsize, ncount ) 
!!            real a(isize,jsize)
!!            real value,delta
!!           integer isize,jsize
!!           integer ncount
!!     C NCLEND
!!            ncount = 0
!!            do jj=1,jsize
!!            do ii=1,isize
!!              if( a(ii,jj) .ge. (value-delta) .and.
!!          &       a(ii,jj) .le. (value+delta) ) then
!!     c4test:       print *,ii,jj,value,a(ii,jj)
!!                ncount = ncount + 1
!!              end if 
!!            end do
!!            end do
!!           return
!!           end
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     
