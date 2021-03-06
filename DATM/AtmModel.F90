module AtmModel

#include "LocalDefs.F90"

  use ESMF
  !use AtmInternalFields, only : atmlonc, atmlatc, atmlonq, atmlatq
  use AtmInternalFields, only : hfwd, hbak, nfhout
  use AtmFieldUtils,     only : AtmForceFwd2Bak, AtmBundleCheck
  use AtmFieldUtils,     only : AtmBundleIntp
#ifdef coupled
  use AtmImportFields,   only : land_mask
#endif

  implicit none

  private

  ! called by Cap
  public :: AtmInit, AtmRun, AtmFinal

  contains

  subroutine AtmInit(gcomp, importState, exportState, externalClock, rc)

    use AtmInternalFields

    type(ESMF_GridComp)  :: gcomp
    type(ESMF_State)     :: importState
    type(ESMF_State)     :: exportState
    type(ESMF_Clock)     :: externalClock
    integer, intent(out) :: rc

    ! Local variables
    type(ESMF_Grid)                :: grid
    type(ESMF_Field)               :: field
    type(ESMF_Array)               :: array2d

    integer(kind=ESMF_KIND_I4), pointer  :: i4Ptr(:,:)
    character(len=ESMF_MAXSTR) :: msgString
    
    integer :: lbnd1,ubnd1,lbnd2,ubnd2

    rc = ESMF_SUCCESS

    call ESMF_LogWrite("User run routine AtmInit started", ESMF_LOGMSG_INFO)

    ! Get the Grid
    call ESMF_GridCompGet(gcomp, grid=grid, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, &
      file=__FILE__)) &
      return  ! bail out

    ! Get the mask from the grid
    !call ESMF_GridGetItem(grid, &
    !                      itemFlag=ESMF_GRIDITEM_MASK, &
    !                      farrayPtr=i4Ptr, rc=rc)
    call ESMF_GridGetItem(grid, &
                          itemFlag=ESMF_GRIDITEM_MASK, &
                          array=array2d, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, &
      file=__FILE__)) &
      return  ! bail out

    !a pointer to the mask
    !call ESMF_ArrayGet(array2d, farrayPtr=i4Ptr, localDE=0, rc = rc)
    call ESMF_ArrayGet(array2d, farrayPtr=i4Ptr, rc = rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, &
      file=__FILE__)) &
      return  ! bail out

    lbnd1 = lbound(i4Ptr,1); ubnd1 = ubound(i4Ptr,1)
    lbnd2 = lbound(i4Ptr,2); ubnd2 = ubound(i4Ptr,2)
    iprnt = lbnd1 + ((ubnd1 - lbnd1)+1)/2
    jprnt = lbnd2 + ((ubnd2 - lbnd2)+1)/2

    write(msgString,*)'AtmInit: print at ',iprnt,jprnt,&
                      i4Ptr(iprnt,jprnt)
    call ESMF_LogWrite(trim(msgString), ESMF_LOGMSG_INFO, rc=rc)
#ifdef test
    ! The land_mask import array from the grid mask
    call ESMF_StateGet(importState, &
                       itemName=trim('LandMask'), &
                       field=field, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, &
      file=__FILE__)) &
      return  ! bail out
 
    call ESMF_FieldGet(field,farrayPtr=land_mask,rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, &
      file=__FILE__)) &
      return  ! bail out
  
    do j = lbound(i4Ptr,2),ubound(i4Ptr,2)
     do i = lbound(i4Ptr,1),ubound(i4Ptr,1)
      land_mask(i,j) = real(i4Ptr(i,j),8)
     enddo
    enddo
#endif
    ! Set up the fields in the AtmBundle 
    call AtmBundleSetUp

    ! Create and fill the AtmBundle 
    call    AtmBundleCreate(gcomp, importState, exportState, rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, &
      file=__FILE__)) &
      return  ! bail out

    ! initialize the fwd and bak fields as special case at initialzation
    call AtmForce(gcomp,exportState,externalClock,0,rc)
    call AtmBundleCheck('after AtmForce',rc)
    ! copy the fwd timestamp to the bak timestamp
    hbak = hfwd
    call AtmForceFwd2Bak(rc)
    call AtmBundleCheck('after Fwd2Bak',rc)
    ! reload the fwd 
    call AtmForce(gcomp,exportState,externalClock,0,rc)
    call AtmBundleCheck('after AtmForce',rc)
    !time interpolate between fwd & bak values
    call AtmBundleIntp(gcomp, importState, exportState, externalClock, 0.0d8, rc)

    call ESMF_LogWrite("User run routine AtmInit finished", ESMF_LOGMSG_INFO)
  end subroutine AtmInit

  !-----------------------------------------------------------------------------

  subroutine AtmRun(gcomp, importState, exportState, externalClock, rc)

    type(ESMF_GridComp)  :: gcomp
    type(ESMF_State)     :: importState
    type(ESMF_State)     :: exportState
    type(ESMF_Clock)     :: externalClock
    integer, intent(out) :: rc
   
    ! Local variables
    type(ESMF_Time)      :: currTime

      integer(kind=ESMF_KIND_I4) :: iyear,imonth,iday,ihour,iminut
         real(kind=ESMF_KIND_R8) :: hour,minut
    character(len=ESMF_MAXSTR)   :: msgString

    integer :: counter = 0

    rc = ESMF_SUCCESS

    call ESMF_LogWrite("User run routine AtmRun started", ESMF_LOGMSG_INFO)

    ! Increment counter
    counter = counter + 1

    ! get the current time of the model clock 
    call ESMF_ClockGet(externalClock, currTime=currTime, rc=rc)
    ! get the current time of the model clock
    ! returns minutes as whole number
    call ESMF_TimeGet(currTime,mm=imonth,h_r8=hour,m_r8=minut,rc=rc)

    ! new forcing increment
    if(mod(minut,real(nfhout)*60.0) .eq. 0)then
     ! move the current fwd values to bak
     call AtmForceFwd2Bak(rc)
     ! copy the fwd timestamp to the bak timestamp
     hbak = hfwd
     ! get new forcing data---always fills the _fwd values in AtmBundle
     call AtmForce(gcomp,exportState,externalClock,1,rc)
    endif
    ! get the current time of the model clock
    call ESMF_ClockGet(externalClock, currTime=currTime, rc=rc)
    call ESMF_TimeGet(currTime,yy=iyear,mm=imonth,dd=iday,h=ihour,m=iminut,rc=rc)
    !write(msgString,*)iyear,imonth,iday,ihour,iminut
    !call ESMF_LogWrite(trim(msgString), ESMF_LOGMSG_INFO, rc=rc)
    
    call ESMF_TimeGet(currTime,h_r8=hour,rc=rc)
    write(msgString,*)'AtmRun: hbkd,hour,hfwd ', hbak,hour,hfwd
    call ESMF_LogWrite(trim(msgString), ESMF_LOGMSG_INFO, rc=rc)
    
    call AtmBundleCheck('after AtmRun',rc)
    !time interpolate between fwd & bak values
    call AtmBundleIntp(gcomp, importState, exportState, externalClock, hour, rc)

    call ESMF_LogWrite("User run routine AtmRun finished", ESMF_LOGMSG_INFO)

  end subroutine AtmRun

  !-----------------------------------------------------------------------------

  subroutine AtmFinal(gcomp, importState, exportState, externalClock, rc)

    type(ESMF_GridComp)  :: gcomp
    type(ESMF_State)     :: importState
    type(ESMF_State)     :: exportState
    type(ESMF_Clock)     :: externalClock
    integer, intent(out) :: rc
 
    call ESMF_LogWrite("User finalize routine AtmFinal started", ESMF_LOGMSG_INFO)

    rc = ESMF_SUCCESS

    call ESMF_LogWrite("User finalize routine AtmFinal finished", ESMF_LOGMSG_INFO)
  end subroutine AtmFinal
end module AtmModel
