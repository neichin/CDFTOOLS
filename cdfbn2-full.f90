PROGRAM cdfbn2_full
  !!-------------------------------------------------------------------
  !!                 ***  PROGRAM cdfbn2_full  ***
  !!
  !!  **  Purpose: Compute the Brunt Vaissala frequency
  !!               using same algoritm than OPA9
  !!              FULL STEP VERSION
  !!  
  !!  **  Method: Try to avoid 3 d arrays : work with 2 levels a a time
  !!              The brunt-vaisala frequency is computed using the
  !!              polynomial expression of McDougall (1987):
  !!              N^2 = grav * beta * ( alpha/beta*dk[ t ] - dk[ s ] )/e3w
  !!              N2 is then insterpolated at T levels
  !!
  !! history:
  !!     Original : J.M. Molines Nov 2004  
  !!                J.M. Molines Apr 2005 : introduction of module cdfio
  !!--------------------------------------------------------------------
  !!  $Rev$
  !!  $Date$
  !!  $Id$
  !!--------------------------------------------------------------

  !! * Modules used
  USE cdfio
  USE eos

  !! * Local variables
  IMPLICIT NONE
  INTEGER   :: jk                                  !: dummy loop index
  INTEGER   :: ierr                                !: working integer
  INTEGER   :: narg, iargc                         !: 
  INTEGER   :: npiglo,npjglo, npk                  !: size of the domain
  INTEGER   :: iup = 1 , idown = 2, itmp
  INTEGER, DIMENSION(2) ::  ipk, id_varout
  REAL(KIND=4) , DIMENSION (:,:,:), ALLOCATABLE :: ztemp, zsal,zwk    !: Array to read 2 layer of data
  REAL(KIND=4) , DIMENSION (:,:), ALLOCATABLE ::       &
       zn2 , &              !:  Brunt Vaissala Frequency (N2)
       zmask,  e3w,gdepw
  REAL(KIND=4) , DIMENSION (:), ALLOCATABLE :: e3k
  REAL(KIND=4),DIMENSION(1)                   ::  tim
  REAL(KIND=4),DIMENSION(:), ALLOCATABLE      ::  gdep

  CHARACTER(LEN=256) :: cfilet ,cfileout='bn2.nc', cdum, cdep   !:
  CHARACTER(LEN=256) :: coordzgr='mesh_zgr.nc' !:
  TYPE(variable), DIMENSION (1) :: typvar

  INTEGER    :: ncout
  INTEGER    :: istatus
  REAL(KIND=4)   ::  zpi
  LOGICAL :: l_w=.false.

  !!  Read command line
  narg= iargc()
  IF ( narg == 0 ) THEN
     PRINT *,' Usage : cdfbn2-full  gridT [W]'
     PRINT *,' Output on bn2.nc, variable vobn2'
     PRINT *,' With option W specified, the output is on W points'
     PRINT *,' By default it is on T points'
     PRINT *,' Need mesh_zgr.nc and mesh_hgr.nc '
     PRINT *,' FULL STEP CASE '
     STOP
  ENDIF

  CALL getarg (1, cfilet)
  IF (narg == 2 ) THEN
    CALL getarg(2,cdum)
    SELECT CASE (cdum)
    CASE ('W','w') ; l_w=.true.
    CASE DEFAULT ; PRINT *,' Option not understood :', TRIM(cdum) ; STOP
    END SELECT
  ENDIF

  npiglo= getdim (cfilet,'x')
  npjglo= getdim (cfilet,'y')
  npk   = getdim (cfilet,'depth')

  ipk(1)= npk  !  3D
  typvar(1)%name='vobn2'
  typvar(1)%units='s-1'
  typvar(1)%missing_value=-1000.
  typvar(1)%valid_min=0.
  typvar(1)%valid_max=50000.
  typvar(1)%long_name='Brunt_Vaissala_Frequency'
  typvar(1)%short_name='vobn2'
  typvar(1)%online_operation='N/A'
  typvar(1)%axis='TZYX'
  


  PRINT *, 'npiglo=', npiglo
  PRINT *, 'npjglo=', npjglo
  PRINT *, 'npk   =', npk

  ALLOCATE (ztemp(npiglo,npjglo,2), zsal(npiglo,npjglo,2), zwk(npiglo,npjglo,2) ,zmask(npiglo,npjglo))
  ALLOCATE (zn2(npiglo,npjglo) ,e3w(npiglo,npjglo),gdepw(1,1),e3k(npk) ,gdep(npk) )

  cdep='gdept'
  IF (l_w) cdep='gdepw'
  DO jk=1,npk
    gdepw(:,:)= getvar(coordzgr, cdep, jk, 1,1) ; gdep(jk)= gdepw(1,1)
  ENDDO


  ! create output fileset

  ncout =create(cfileout, cfilet, npiglo,npjglo,npk)

  ierr= createvar(ncout ,typvar,1, ipk,id_varout )
  ierr= putheadervar(ncout, cfilet,npiglo,npjglo,npk,pdep=gdep)

  zpi=ACOS(-1.)

  !  2 levels of T and S are required : iup,idown (with respect to W level)
  !  Compute from bottom to top (for vertical integration)
  ztemp(:,:,idown) = getvar(cfilet, 'votemper',  npk-1  ,npiglo, npjglo)
  zsal( :,:,idown) = getvar(cfilet, 'vosaline',  npk-1  ,npiglo, npjglo)

  tim=getvar1d(cfilet,'time_counter',1)
  ierr=putvar1d(ncout,tim,1,'T')
  e3k(:) = getvare3(coordzgr, 'e3w', npk)

  DO jk = npk-1, 2, -1 
     PRINT *,'level ',jk
     zmask(:,:)=1.
     ztemp(:,:,iup)= getvar(cfilet, 'votemper',  jk-1 ,npiglo, npjglo)
     WHERE(ztemp(:,:,idown) == 0 ) zmask = 0
     zsal(:,:,iup) = getvar(cfilet, 'vosaline',  jk-1 ,npiglo,npjglo)

     gdepw(:,:) = getvar(coordzgr, 'gdepw', jk, 1,1)
     e3w(:,:)=e3k(jk)

     zwk(:,:,iup) = eosbn2 ( ztemp,zsal,gdepw(1,1),e3w, npiglo,npjglo ,iup,idown)* zmask(:,:)

     IF ( .NOT. l_w ) THEN
     ! now put zn2 at T level (k )
     WHERE ( zwk(:,:,idown) == 0 ) 
        zn2(:,:) =  zwk(:,:,iup)
     ELSEWHERE
        zn2(:,:) = 0.5 * ( zwk(:,:,iup) + zwk(:,:,idown) ) * zmask(:,:)
     END WHERE
     ELSE
       zn2(:,:) = zwk(:,:,iup)
     ENDIF

     ierr = putvar(ncout, id_varout(1) ,zn2, jk, npiglo, npjglo )
     itmp = idown ; idown = iup ; iup = itmp

  END DO  ! loop to next level

  istatus = closeout(ncout)

END PROGRAM cdfbn2_full