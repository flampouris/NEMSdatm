subroutine AtmForce(gcomp,exportState,externalClock,initmode,rc)

#include "LocalDefs.F90"

  use ESMF

  use AtmInternalFields

  implicit none

  type(ESMF_GridComp)  :: gcomp
  type(ESMF_State)     :: exportState
  type(ESMF_Clock)     :: externalClock
  integer, intent(out) :: rc
  integer, intent( in) :: initmode

  ! Local variables
  type(ESMF_Field)              :: field
  type(ESMF_Time)               :: currTime
  type(ESMF_Time)               :: nextTime
  type(ESMF_TimeInterval)       :: timeStep

  integer(kind=ESMF_KIND_I4)    :: year, month, day, hour, jday

  integer :: ii,nfields

  character(len=ESMF_MAXSTR) :: varname
  character(len=ESMF_MAXSTR) :: filename 
  character(len=ESMF_MAXSTR) :: msgString

  character(len=4) :: cyear
  character(len=3) ::  chour
  character(len=2) :: cmon, cday

  character(len=8) :: i2fmt = '(i2.2)'
  character(len=8) :: i4fmt = '(i4.4)'

  ! Set initial values

  rc = ESMF_SUCCESS

  call ESMF_LogWrite("User routine AtmForce started", ESMF_LOGMSG_INFO)

  ! at initialization, get the current forecast hour file, not the forward 
  ! forecast hour 
  if(initmode .eq. 0)then

   call ESMF_ClockGet(externalClock, currTime=currTime, rc=rc)
   call ESMF_TimeGet(currTime,yy=year,mm=month,dd=day,h=hour,dayOfYear=jday,rc=rc)
   write(cyear, i4fmt)year
   write( cmon, i2fmt)month
   write( cday, i2fmt)day
   write(chour, i2fmt)hour
   filename = trim(dirpath)//trim(filename_base)//trim(cyear)//trim(cmon)//trim(cday)//trim(chour)//'.nc'

   call ESMF_TimeGet(currTime,h_r8=hfwd,rc=rc)
  else
   ! set the time interval to the forecast file interval
   call ESMF_TimeIntervalSet(timeStep, h=nfhout, rc=rc)
   if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
     line=__LINE__, &
     file=__FILE__)) &
     return  ! bail out

   ! find the time at the currtime + nfhout
   call ESMF_ClockGetNextTime(externalClock, nextTime, timestep=timeStep, rc=rc)
   if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
     line=__LINE__, &
     file=__FILE__)) &
     return  ! bail out

   call ESMF_TimeGet(nextTime,yy=year,mm=month,dd=day,h=hour,dayOfYear=jday,rc=rc)
   write(cyear, i4fmt)year
   write( cmon, i2fmt)month
   write( cday, i2fmt)day
   write(chour, i2fmt)hour
   filename = trim(dirpath)//trim(filename_base)//trim(cyear)//trim(cmon)//trim(cday)//trim(chour)//'.nc'
   
   call ESMF_TimeGet(nextTime,h_r8=hfwd,rc=rc)
  endif
  write(msgString,'(3a,f12.3)')'using ',trim(filename),' at fwd clock hour ',real(hfwd,4)
  call ESMF_LogWrite(trim(msgString), ESMF_LOGMSG_INFO, rc=rc)

  ! read the Atm field data into the Fwd bundle
  nfields = size(AtmBundleFields)
  do ii = 1,nfields
   if(AtmBundleFields(ii)%isPresent)then
    varname = trim(AtmBundleFields(ii)%file_varname)

    ! get the '_fwd' field
    call ESMF_FieldBundleGet(AtmBundleFwd, &
                             fieldName=trim(AtmBundleFields(ii)%field_name)//'_fwd', &
                             field=field, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, &
      file=__FILE__)) &
      return  ! bail out

    call ESMF_FieldRead(field, &
                        fileName=trim(filename), &
                        variableName = trim(varname), &
                        rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, &
      file=__FILE__)) &
      return  ! bail out

    call ESMF_FieldGet(field,farrayPtr=AtmBundleFields(ii)%farrayPtr_fwd,rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, &
      file=__FILE__)) &
      return  ! bail out

     write(msgString,'(i6,2a18,f14.5)')ii,' inside AtmForce  ',trim(varname), &
                             AtmBundleFields(ii)%farrayPtr_fwd(iprnt,jprnt)
     call ESMF_LogWrite(trim(msgString), ESMF_LOGMSG_INFO, rc=rc)
   endif !isPresent
  enddo

  call ESMF_LogWrite("User routine AtmForce finished", ESMF_LOGMSG_INFO)
end  subroutine AtmForce
