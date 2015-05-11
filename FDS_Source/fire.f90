MODULE FIRE
 
! Compute combustion
 
USE PRECISION_PARAMETERS
USE GLOBAL_CONSTANTS
USE MESH_POINTERS
USE COMP_FUNCTIONS, ONLY: SECOND
 
IMPLICIT NONE
PRIVATE
   
CHARACTER(255), PARAMETER :: fireid='$Id$'
CHARACTER(255), PARAMETER :: firerev='$Revision$'
CHARACTER(255), PARAMETER :: firedate='$Date$'

TYPE(REACTION_TYPE), POINTER :: RN=>NULL()
LOGICAL :: EXTINCT = .FALSE.

PUBLIC COMBUSTION, GET_REV_fire

CONTAINS
 
SUBROUTINE COMBUSTION(NM)

INTEGER, INTENT(IN) :: NM
REAL(EB) :: TNOW

IF (EVACUATION_ONLY(NM)) RETURN

TNOW=SECOND()

IF (INIT_HRRPUV) RETURN

CALL POINT_TO_MESH(NM)

! Upper bounds on local HRR per unit volume

Q_UPPER = HRRPUA_SHEET/CELL_SIZE + HRRPUV_AVERAGE

! Call combustion ODE solver

CALL COMBUSTION_GENERAL

TUSED(10,NM)=TUSED(10,NM)+SECOND()-TNOW

END SUBROUTINE COMBUSTION


SUBROUTINE COMBUSTION_GENERAL

! Generic combustion routine for multi-step reactions

USE PHYSICAL_FUNCTIONS, ONLY: GET_SPECIFIC_GAS_CONSTANT,GET_MASS_FRACTION_ALL,GET_SPECIFIC_HEAT,GET_MOLECULAR_WEIGHT, &
                              GET_SENSIBLE_ENTHALPY_Z,GET_SENSIBLE_ENTHALPY,IS_REALIZABLE
INTEGER :: I,J,K,NS,NR,II,JJ,KK,IIG,JJG,KKG,IW,N
REAL(EB):: ZZ_GET(1:N_TRACKED_SPECIES),DZZ(1:N_TRACKED_SPECIES),CP,H_S_ALPHA
LOGICAL :: Q_EXISTS
TYPE (REACTION_TYPE), POINTER :: RN
TYPE (SPECIES_MIXTURE_TYPE), POINTER :: SM
LOGICAL :: DO_REACTION,REALIZABLE

Q          = 0._EB
D_REACTION = 0._EB
Q_EXISTS   = .FALSE.

IF (TRANSPORT_UNMIXED_FRACTION .AND. &
    COMPUTE_ZETA_SOURCE_TERM   .AND. &
    TRANSPORT_ZETA_SCHEME==1         ) CALL ZETA_PRODUCTION ! scheme 1: zeta production before mixing

DO K=1,KBAR
   DO J=1,JBAR
      ILOOP: DO I=1,IBAR
         ! Check to see if a reaction is possible
         IF (SOLID(CELL_INDEX(I,J,K))) CYCLE ILOOP
         ZZ_GET = ZZ(I,J,K,1:N_TRACKED_SPECIES)
         IF (CHECK_REALIZABILITY) THEN
            REALIZABLE=IS_REALIZABLE(ZZ_GET)
            IF (.NOT.REALIZABLE) THEN
               WRITE(LU_ERR,*) I,J,K
               WRITE(LU_ERR,*) ZZ_GET
               WRITE(LU_ERR,*) SUM(ZZ_GET)
               WRITE(LU_ERR,*) 'ERROR: Unrealizable mass fractions input to COMBUSTION_MODEL'
               STOP_STATUS=REALIZABILITY_STOP
            ENDIF
         ENDIF
         CALL CHECK_REACTION
         IF (.NOT.DO_REACTION) CYCLE ILOOP ! Check whether any reactions are possible.
         DZZ = ZZ_GET ! store old ZZ for divergence term
         ! Call combustion integration routine
         CALL COMBUSTION_MODEL(I,J,K,ZZ_GET,Q(I,J,K))
         IF (CHECK_REALIZABILITY) THEN
            REALIZABLE=IS_REALIZABLE(ZZ_GET)
            IF (.NOT.REALIZABLE) THEN
               WRITE(LU_ERR,*) ZZ_GET,SUM(ZZ_GET)
               WRITE(LU_ERR,*) 'ERROR: Unrealizable mass fractions after COMBUSTION_MODEL'
               STOP_STATUS=REALIZABILITY_STOP
            ENDIF
         ENDIF
         DZZ = ZZ_GET - DZZ
         ! Update RSUM and ZZ
         DZZ_IF: IF ( ANY(ABS(DZZ) > TWO_EPSILON_EB) ) THEN
            IF (ABS(Q(I,J,K)) > TWO_EPSILON_EB) Q_EXISTS = .TRUE.
            CALL GET_SPECIFIC_GAS_CONSTANT(ZZ_GET,RSUM(I,J,K)) 
            TMP(I,J,K) = PBAR(K,PRESSURE_ZONE(I,J,K))/(RSUM(I,J,K)*RHO(I,J,K))
            ZZ(I,J,K,1:N_TRACKED_SPECIES) = ZZ_GET
            CP_IF: IF (.NOT.CONSTANT_SPECIFIC_HEAT_RATIO) THEN
               ! Divergence term
               CALL GET_SPECIFIC_HEAT(ZZ_GET,CP,TMP(I,J,K))
               DO N=1,N_TRACKED_SPECIES
                  SM => SPECIES_MIXTURE(N)
                  CALL GET_SENSIBLE_ENTHALPY_Z(N,TMP(I,J,K),H_S_ALPHA)
                  D_REACTION(I,J,K) = D_REACTION(I,J,K) + (SM%RCON/RSUM(I,J,K) - H_S_ALPHA/(CP*TMP(I,J,K)) )*DZZ(N)/DT
               ENDDO
            ENDIF CP_IF
         ENDIF DZZ_IF
      ENDDO ILOOP
   ENDDO
ENDDO

IF (TRANSPORT_UNMIXED_FRACTION .AND. &
    COMPUTE_ZETA_SOURCE_TERM   .AND. &
    TRANSPORT_ZETA_SCHEME==2         ) CALL ZETA_PRODUCTION ! scheme 2: zeta production after mixing

IF (.NOT.Q_EXISTS) RETURN

! Set Q in the ghost cell, just for better visualization.

DO IW=1,N_EXTERNAL_WALL_CELLS
   IF (WALL(IW)%BOUNDARY_TYPE/=INTERPOLATED_BOUNDARY .AND. WALL(IW)%BOUNDARY_TYPE/=OPEN_BOUNDARY) CYCLE
   II  = WALL(IW)%ONE_D%II
   JJ  = WALL(IW)%ONE_D%JJ
   KK  = WALL(IW)%ONE_D%KK
   IIG = WALL(IW)%ONE_D%IIG
   JJG = WALL(IW)%ONE_D%JJG
   KKG = WALL(IW)%ONE_D%KKG
   Q(II,JJ,KK) = Q(IIG,JJG,KKG)
ENDDO

CONTAINS

SUBROUTINE CHECK_REACTION

! Check whether any reactions are possible.

LOGICAL :: REACTANTS_PRESENT

DO_REACTION = .FALSE.
REACTION_LOOP: DO NR=1,N_REACTIONS
   RN=>REACTION(NR)
   REACTANTS_PRESENT = .TRUE.
   DO NS=1,N_TRACKED_SPECIES
      IF (RN%NU(NS)<0._EB .AND. ZZ_GET(NS) < ZZ_MIN_GLOBAL) THEN
         REACTANTS_PRESENT = .FALSE.
         EXIT
      ENDIF
   ENDDO
    DO_REACTION = REACTANTS_PRESENT
    IF (DO_REACTION) EXIT REACTION_LOOP
ENDDO REACTION_LOOP

END SUBROUTINE CHECK_REACTION

END SUBROUTINE COMBUSTION_GENERAL


SUBROUTINE COMBUSTION_MODEL(I,J,K,ZZ_GET,Q_OUT)
USE COMP_FUNCTIONS, ONLY: SHUTDOWN
USE PHYSICAL_FUNCTIONS, ONLY: LES_FILTER_WIDTH_FUNCTION,GET_AVERAGE_SPECIFIC_HEAT,GET_SPECIFIC_GAS_CONSTANT
INTEGER, INTENT(IN) :: I,J,K
REAL(EB), INTENT(OUT) :: Q_OUT
REAL(EB), INTENT(INOUT) :: ZZ_GET(1:N_TRACKED_SPECIES)
REAL(EB) :: ERR_EST,ERR_TOL,ZZ_TEMP(1:N_TRACKED_SPECIES),&
            A1(1:N_TRACKED_SPECIES),A2(1:N_TRACKED_SPECIES),A4(1:N_TRACKED_SPECIES),Q_SUM,Q_CUM,ZETA,ZETA_0,&
            DT_SUB,DT_SUB_NEW,DT_ITER,ZZ_STORE(1:N_TRACKED_SPECIES,1:4),TV(1:3,1:N_TRACKED_SPECIES),CELL_VOLUME,CELL_MASS,&
            ZZ_DIFF(1:3,1:N_TRACKED_SPECIES),ZZ_MIXED(1:N_TRACKED_SPECIES),ZZ_UNMIXED(1:N_TRACKED_SPECIES),&
            ZZ_MIXED_NEW(1:N_TRACKED_SPECIES),TAU_D,TAU_G,TAU_U,TAU_MIX,DELTA,TMP_MIXED,DT_SUB_MIN,RHO_HAT,PBAR_0,VEL_RMS
INTEGER :: NR,NS,ITER,TVI,RICH_ITER,TIME_ITER,SR
INTEGER, PARAMETER :: TV_ITER_MIN=5,RICH_ITER_MAX=5
LOGICAL :: TV_FLUCT(1:N_TRACKED_SPECIES)
TYPE(REACTION_TYPE), POINTER :: RN=>NULL()
REAL(EB), PARAMETER :: C_U = 0.4_EB*0.1_EB*SQRT(1.5_EB) ! C_U*C_DEARDORFF/SQRT(2/3)

DELTA = LES_FILTER_WIDTH_FUNCTION(DX(I),DY(J),DZ(K))
VEL_RMS = 0._EB
IF (FIXED_MIX_TIME>0._EB) THEN
   MIX_TIME(I,J,K)=FIXED_MIX_TIME
ELSE
   TAU_D=0._EB
   DO NR =1,N_REACTIONS
      RN => REACTION(NR)
      TAU_D = MAX(TAU_D,D_Z(MIN(4999,NINT(TMP(I,J,K))),RN%FUEL_SMIX_INDEX))
   ENDDO
   TAU_D = DELTA**2/MAX(TAU_D,TWO_EPSILON_EB) ! FDS Tech Guide (5.21)
   IF (LES) THEN
      TAU_U = C_U*RHO(I,J,K)*DELTA**2/MAX(MU(I,J,K),TWO_EPSILON_EB)     ! FDS Tech Guide (5.22)
      TAU_G = SQRT(2._EB*DELTA/(GRAV+1.E-10_EB))                        ! FDS Tech Guide (5.23)
      MIX_TIME(I,J,K)= MAX(TAU_CHEM,MIN(TAU_D,TAU_U,TAU_G,TAU_FLAME))   ! FDS Tech Guide (5.20)
      VEL_RMS = SQRT(TWTH)*MU(I,J,K)/(RHO(I,J,K)*C_DEARDORFF*DELTA)
   ELSE
      MIX_TIME(I,J,K)= MAX(TAU_CHEM,TAU_D)
   ENDIF
ENDIF

DT_SUB_MIN = DT/REAL(MAX_CHEMISTRY_ITERATIONS,EB)
ZZ_STORE(:,:) = 0._EB
Q_OUT = 0._EB
Q_CUM = 0._EB
Q_SUM = 0._EB
ITER= 0
DT_ITER = 0._EB
DT_SUB = DT 
DT_SUB_NEW = DT
ZZ_UNMIXED = ZZ_GET
ZZ_TEMP = ZZ_GET
ZZ_MIXED = ZZ_GET
A1 = ZZ_GET
A2 = ZZ_GET
A4 = ZZ_GET
IF (TRANSPORT_UNMIXED_FRACTION) THEN
   ZETA_0 = ZZ(I,J,K,ZETA_INDEX)
ELSE
   ZETA_0 = INITIAL_UNMIXED_FRACTION
ENDIF
ZETA = ZETA_0
CELL_VOLUME = DX(I)*DY(J)*DZ(K)
CELL_MASS = RHO(I,J,K)*CELL_VOLUME
RHO_HAT = RHO(I,J,K)
TMP_MIXED = TMP(I,J,K)
TAU_MIX = MIX_TIME(I,J,K)
EXTINCT = .FALSE.
PBAR_0 = PBAR(K,PRESSURE_ZONE(I,J,K))

INTEGRATION_LOOP: DO TIME_ITER = 1,MAX_CHEMISTRY_ITERATIONS

   IF (SUPPRESSION .AND. TIME_ITER==1) EXTINCT = FUNC_EXTINCT(ZZ_MIXED,TMP_MIXED)

   INTEGRATOR_SELECT: SELECT CASE (COMBUSTION_ODE_SOLVER)

      CASE (EXPLICIT_EULER) ! Simple chemistry

         DO SR=0,N_SERIES_REACTIONS
            CALL FIRE_FORWARD_EULER(ZZ_MIXED_NEW,ZETA,ZZ_MIXED,ZETA_0,DT_SUB,TMP_MIXED,RHO_HAT,ZZ_UNMIXED,CELL_MASS,TAU_MIX,&
                                    PBAR_0,DELTA,VEL_RMS)
            ZZ_MIXED = ZZ_MIXED_NEW
         ENDDO         
         IF (TIME_ITER > 1) CALL SHUTDOWN('ERROR: Error in Simple Chemistry')

      CASE (RK2_RICHARDSON) ! Finite-rate (or mixed finite-rate/fast) chemistry

         ERR_TOL = RICHARDSON_ERROR_TOLERANCE
         RICH_EX_LOOP: DO RICH_ITER = 1,RICH_ITER_MAX
            DT_SUB = MIN(DT_SUB_NEW,DT-DT_ITER)

            ! FDS Tech Guide (E.3), (E.4), (E.5)
            CALL FIRE_RK2(A1,ZETA,ZZ_MIXED,ZETA_0,DT_SUB,1,TMP_MIXED,RHO_HAT,ZZ_UNMIXED,CELL_MASS,TAU_MIX,PBAR_0,DELTA,VEL_RMS)
            CALL FIRE_RK2(A2,ZETA,ZZ_MIXED,ZETA_0,DT_SUB,2,TMP_MIXED,RHO_HAT,ZZ_UNMIXED,CELL_MASS,TAU_MIX,PBAR_0,DELTA,VEL_RMS)
            CALL FIRE_RK2(A4,ZETA,ZZ_MIXED,ZETA_0,DT_SUB,4,TMP_MIXED,RHO_HAT,ZZ_UNMIXED,CELL_MASS,TAU_MIX,PBAR_0,DELTA,VEL_RMS)

            ! Species Error Analysis
            ERR_EST = MAXVAL(ABS((4._EB*A4-5._EB*A2+A1)))/45._EB ! FDS Tech Guide (E.7)
            DT_SUB_NEW = MIN(MAX(DT_SUB*(ERR_TOL/(ERR_EST+TWO_EPSILON_EB))**(0.25_EB),DT_SUB_MIN),DT-DT_ITER) ! (E.8)
            IF (RICH_ITER == RICH_ITER_MAX) EXIT RICH_EX_LOOP
            IF (ERR_EST <= ERR_TOL) EXIT RICH_EX_LOOP
         ENDDO RICH_EX_LOOP
         ZETA_0 = ZETA
         ZZ_MIXED = (4._EB*A4-A2)*ONTH ! FDS Tech Guide (E.6)

   END SELECT INTEGRATOR_SELECT

   ZZ_GET =  ZETA*ZZ_UNMIXED + (1._EB-ZETA)*ZZ_MIXED ! FDS Tech Guide (5.30)
   IF (TRANSPORT_UNMIXED_FRACTION) ZZ(I,J,K,ZETA_INDEX) = ZETA

   DT_ITER = DT_ITER + DT_SUB
   ITER = ITER + 1
   IF (OUTPUT_CHEM_IT) THEN
      CHEM_SUBIT(I,J,K) = ITER
   ENDIF

   ! Compute heat release rate
   
   Q_SUM = 0._EB
   IF (MAXVAL(ABS(ZZ_GET-ZZ_TEMP)) > TWO_EPSILON_EB) THEN
      Q_SUM = Q_SUM - RHO(I,J,K)*SUM(SPECIES_MIXTURE%H_F*(ZZ_GET-ZZ_TEMP)) ! FDS Tech Guide (5.14)
   ENDIF
   IF (Q_CUM + Q_SUM > Q_UPPER*DT) THEN
      Q_OUT = Q_UPPER
      ZZ_GET = ZZ_TEMP + (Q_UPPER*DT/(Q_CUM + Q_SUM))*(ZZ_GET-ZZ_TEMP)
      EXIT INTEGRATION_LOOP
   ELSE
      Q_CUM = Q_CUM+Q_SUM
      Q_OUT = Q_CUM/DT
   ENDIF
   
   ! Total Variation (TV) scheme (accelerates integration for finite-rate equilibrium calculations)
   ! See FDS Tech Guide Appendix E
   
   IF (COMBUSTION_ODE_SOLVER==RK2_RICHARDSON .AND. N_REACTIONS > 1) THEN
      DO NS = 1,N_TRACKED_SPECIES
         DO TVI = 1,3
            ZZ_STORE(NS,TVI)=ZZ_STORE(NS,TVI+1)
         ENDDO
         ZZ_STORE(NS,4) = ZZ_GET(NS)
      ENDDO
      TV_FLUCT(:) = .FALSE.
      IF (ITER >= TV_ITER_MIN) THEN
         SPECIES_LOOP_TV: DO NS = 1,N_TRACKED_SPECIES
            DO TVI = 1,3
               TV(TVI,NS) = ABS(ZZ_STORE(NS,TVI+1)-ZZ_STORE(NS,TVI))
               ZZ_DIFF(TVI,NS) = ZZ_STORE(NS,TVI+1)-ZZ_STORE(NS,TVI)
            ENDDO
            IF (SUM(TV(:,NS)) < ERR_TOL .OR. SUM(TV(:,NS)) >= ABS(2.9_EB*SUM(ZZ_DIFF(:,NS)))) THEN ! FDS Tech Guide (E.10)
               TV_FLUCT(NS) = .TRUE.
            ENDIF
            IF (ALL(TV_FLUCT)) EXIT INTEGRATION_LOOP
         ENDDO SPECIES_LOOP_TV
      ENDIF
   ENDIF

   ZZ_TEMP = ZZ_GET
   IF ( DT_ITER > (DT-TWO_EPSILON_EB) ) EXIT INTEGRATION_LOOP

ENDDO INTEGRATION_LOOP

IF (REAC_SOURCE_CHECK) REAC_SOURCE_TERM(I,J,K,:) = (ZZ_UNMIXED-ZZ_GET)*CELL_MASS/DT ! store special output quantity

END SUBROUTINE COMBUSTION_MODEL


SUBROUTINE FIRE_FORWARD_EULER(ZZ_OUT,ZETA_OUT,ZZ_IN,ZETA_IN,DT_LOC,TMP_MIXED,RHO_HAT,ZZ_UNMIXED,CELL_MASS,TAU_MIX,&
                              PBAR_0,DELTA,VEL_RMS)
USE COMP_FUNCTIONS, ONLY:SHUTDOWN
USE PHYSICAL_FUNCTIONS, ONLY: GET_REALIZABLE_MF,GET_AVERAGE_SPECIFIC_HEAT
USE RADCONS, ONLY: RADIATIVE_FRACTION
REAL(EB), INTENT(IN) :: ZZ_IN(1:N_TRACKED_SPECIES),ZETA_IN,DT_LOC,RHO_HAT,ZZ_UNMIXED(1:N_TRACKED_SPECIES),CELL_MASS,TAU_MIX,&
                        PBAR_0,DELTA,VEL_RMS
REAL(EB), INTENT(OUT) :: ZZ_OUT(1:N_TRACKED_SPECIES),ZETA_OUT
REAL(EB), INTENT(INOUT) :: TMP_MIXED
REAL(EB) :: ZZ_0(1:N_TRACKED_SPECIES),ZZ_NEW(1:N_TRACKED_SPECIES),DZZ(1:N_TRACKED_SPECIES),UNMIXED_MASS_0(1:N_TRACKED_SPECIES),&
            BOUNDEDNESS_CORRECTION,MIXED_MASS(1:N_TRACKED_SPECIES),MIXED_MASS_0(1:N_TRACKED_SPECIES),TOTAL_MIXED_MASS,Q_TEMP,CPBAR
INTEGER :: SR
INTEGER, PARAMETER :: INFINITELY_FAST=1,FINITE_RATE=2
LOGICAL :: TEMPERATURE_DEPENDENT_REACTION=.FALSE.

ZETA_OUT = ZETA_IN*EXP(-DT_LOC/TAU_MIX) ! FDS Tech Guide (5.29)
IF (ZETA_OUT < TWO_EPSILON_EB) ZETA_OUT = 0._EB
MIXED_MASS_0 = CELL_MASS*ZZ_IN
UNMIXED_MASS_0 = CELL_MASS*ZZ_UNMIXED
MIXED_MASS = MAX(0._EB,MIXED_MASS_0 - (ZETA_OUT - ZETA_IN)*UNMIXED_MASS_0) ! FDS Tech Guide (5.37)
TOTAL_MIXED_MASS = SUM(MIXED_MASS)
ZZ_0 = MIXED_MASS/MAX(TOTAL_MIXED_MASS,TWO_EPSILON_EB) ! FDS Tech Guide (5.35)

IF (ANY(REACTION(:)%FAST_CHEMISTRY)) THEN
   DO SR = 0,N_SERIES_REACTIONS
      CALL REACTION_RATE(DZZ,ZZ_0,DT_LOC,RHO_HAT,TMP_MIXED,INFINITELY_FAST,PBAR_0,DELTA,VEL_RMS)
      ZZ_NEW = ZZ_0 + DZZ ! test Forward Euler step (5.53)
      BOUNDEDNESS_CORRECTION = FUNC_BCOR(ZZ_0,ZZ_NEW) ! Reaction rate boundedness correction
      ZZ_NEW = ZZ_0 + DZZ*BOUNDEDNESS_CORRECTION ! corrected FE step for all species (5.54)
      ZZ_0 = ZZ_NEW
   ENDDO
ENDIF

IF (.NOT.ALL(REACTION(:)%FAST_CHEMISTRY)) THEN
   CALL REACTION_RATE(DZZ,ZZ_0,DT_LOC,RHO_HAT,TMP_MIXED,FINITE_RATE,PBAR_0,DELTA,VEL_RMS)
   ZZ_NEW = ZZ_0 + DZZ
   BOUNDEDNESS_CORRECTION = FUNC_BCOR(ZZ_0,ZZ_NEW)
   ZZ_NEW = ZZ_0 + DZZ*BOUNDEDNESS_CORRECTION
   IF (TEMPERATURE_DEPENDENT_REACTION) THEN
      Q_TEMP = SUM(SPECIES_MIXTURE(1:N_TRACKED_SPECIES)%H_F*DZZ*BOUNDEDNESS_CORRECTION)
      CALL GET_AVERAGE_SPECIFIC_HEAT(ZZ_NEW,CPBAR,TMP_MIXED)
      TMP_MIXED = TMP_MIXED + DT_LOC*(1._EB-RADIATIVE_FRACTION)*Q_TEMP/CPBAR
   ENDIF
ENDIF

! Enforce realizability on mass fractions

CALL GET_REALIZABLE_MF(ZZ_NEW)

ZZ_OUT = ZZ_NEW

END SUBROUTINE FIRE_FORWARD_EULER


REAL(EB) FUNCTION FUNC_BCOR(ZZ_0,ZZ_NEW)
! This function finds a correction for reaction rates such that all species remain bounded.

REAL(EB), INTENT(IN) :: ZZ_0(1:N_TRACKED_SPECIES),ZZ_NEW(1:N_TRACKED_SPECIES)
REAL(EB) :: BCOR,DZ_IB,DZ_OB
INTEGER :: NS

BCOR = 1._EB
DO NS=1,N_TRACKED_SPECIES
   IF (ZZ_NEW(NS)<0._EB) THEN ! FDS Tech Guide (5.55)
      DZ_IB=ZZ_0(NS)        ! DZ "in bounds"
      DZ_OB=ABS(ZZ_NEW(NS)) ! DZ "out of bounds"
      BCOR = MIN( BCOR, DZ_IB/MAX(DZ_IB+DZ_OB,TWO_EPSILON_EB) )
   ENDIF
   IF (ZZ_NEW(NS)>1._EB) THEN ! FDS Tech Guide (5.55)
      DZ_IB=1._EB-ZZ_0(NS)
      DZ_OB=ZZ_NEW(NS)-1._EB
      BCOR = MIN( BCOR, DZ_IB/MAX(DZ_IB+DZ_OB,TWO_EPSILON_EB) )
   ENDIF
ENDDO
FUNC_BCOR = BCOR

END FUNCTION FUNC_BCOR


SUBROUTINE FIRE_RK2(ZZ_OUT,ZETA_OUT,ZZ_IN,ZETA_IN,DT_SUB,N_INC,TMP_MIXED,RHO_HAT,ZZ_UNMIXED,CELL_MASS,TAU_MIX,&
                    PBAR_0,DELTA,VEL_RMS)

! This function uses RK2 to integrate ZZ_O from t=0 to t=DT_SUB in increments of DT_LOC=DT_SUB/N_INC

REAL(EB), INTENT(IN) :: ZZ_IN(1:N_TRACKED_SPECIES),DT_SUB,ZETA_IN,RHO_HAT,ZZ_UNMIXED(1:N_TRACKED_SPECIES),CELL_MASS,&
                        TAU_MIX,PBAR_0,DELTA,VEL_RMS
REAL(EB), INTENT(OUT) :: ZZ_OUT(1:N_TRACKED_SPECIES),ZETA_OUT
REAL(EB), INTENT(INOUT) :: TMP_MIXED
INTEGER, INTENT(IN) :: N_INC
REAL(EB) :: DT_LOC,ZZ_0(1:N_TRACKED_SPECIES),ZZ_1(1:N_TRACKED_SPECIES),ZZ_2(1:N_TRACKED_SPECIES),ZETA_0,ZETA_1,ZETA_2
INTEGER :: N

DT_LOC = DT_SUB/REAL(N_INC,EB)
ZZ_0 = ZZ_IN
ZETA_0 = ZETA_IN
DO N=1,N_INC
   CALL FIRE_FORWARD_EULER(ZZ_1,ZETA_1,ZZ_0,ZETA_0,DT_LOC,TMP_MIXED,RHO_HAT,ZZ_UNMIXED,CELL_MASS,TAU_MIX,PBAR_0,DELTA,VEL_RMS) 
   CALL FIRE_FORWARD_EULER(ZZ_2,ZETA_2,ZZ_1,ZETA_1,DT_LOC,TMP_MIXED,RHO_HAT,ZZ_UNMIXED,CELL_MASS,TAU_MIX,PBAR_0,DELTA,VEL_RMS)  
   ZZ_OUT = 0.5_EB*(ZZ_0 + ZZ_2)
   ZZ_0 = ZZ_OUT
   ZETA_OUT = ZETA_1
   ZETA_0 = ZETA_OUT
ENDDO

END SUBROUTINE FIRE_RK2


SUBROUTINE REACTION_RATE(DZZ,ZZ_0,DT_LOC,RHO_0,TMP_0,KINETICS,PBAR_0,DELTA,VEL_RMS)
USE PHYSICAL_FUNCTIONS, ONLY : GET_MASS_FRACTION_ALL,GET_SPECIFIC_GAS_CONSTANT,GET_GIBBS_FREE_ENERGY,GET_MOLECULAR_WEIGHT
REAL(EB), INTENT(OUT) :: DZZ(1:N_TRACKED_SPECIES)
REAL(EB), INTENT(IN) :: ZZ_0(1:N_TRACKED_SPECIES),DT_LOC,RHO_0,TMP_0,PBAR_0,DELTA,VEL_RMS
INTEGER, INTENT(IN) :: KINETICS
REAL(EB) :: DZ_F(1:N_REACTIONS),YY_PRIMITIVE(1:N_SPECIES),DG_RXN,MW,MOLPCM3,DTHETA
INTEGER :: I,NS
INTEGER, PARAMETER :: INFINITELY_FAST=1,FINITE_RATE=2
TYPE(REACTION_TYPE),POINTER :: RN=>NULL()

DZ_F = 0._EB
DZZ = 0._EB

KINETICS_SELECT: SELECT CASE(KINETICS)
   
   CASE(INFINITELY_FAST)
      IF (EXTINCT) RETURN
      REACTION_LOOP_1: DO I=1,N_REACTIONS
         RN => REACTION(I)
         IF (.NOT.RN%FAST_CHEMISTRY) CYCLE REACTION_LOOP_1
         DTHETA = FLAME_SPEED_FACTOR(ZZ_0,DT_LOC,RHO_0,TMP_0,PBAR_0,I,DELTA,VEL_RMS)
         DZ_F(I) = ZZ_0(RN%FUEL_SMIX_INDEX)*DTHETA
         DZZ = DZZ + RN%NU_MW_O_MW_F*DZ_F(I)
      ENDDO REACTION_LOOP_1

   CASE(FINITE_RATE) 
      REACTION_LOOP_2: DO I=1,N_REACTIONS
         RN => REACTION(I)
         IF (RN%FAST_CHEMISTRY .OR. ZZ_0(RN%FUEL_SMIX_INDEX) < ZZ_MIN_GLOBAL) CYCLE REACTION_LOOP_2
         IF (RN%AIR_SMIX_INDEX > -1) THEN
            IF (ZZ_0(RN%AIR_SMIX_INDEX) < ZZ_MIN_GLOBAL) CYCLE REACTION_LOOP_2 ! no expected air
         ENDIF
         CALL GET_MASS_FRACTION_ALL(ZZ_0,YY_PRIMITIVE)
         DO NS=1,N_SPECIES
            IF(RN%N_S(NS)>= -998._EB .AND. YY_PRIMITIVE(NS) < ZZ_MIN_GLOBAL) CYCLE REACTION_LOOP_2
         ENDDO
         DZ_F(I) = RN%A_PRIME*RHO_0**RN%RHO_EXPONENT*TMP_0**RN%N_T*EXP(-RN%E/(R0*TMP_0)) ! FDS Tech Guide, Eq. (5.49)
         DO NS=1,N_SPECIES
            IF(RN%N_S(NS)>= -998._EB)  DZ_F(I) = YY_PRIMITIVE(NS)**RN%N_S(NS)*DZ_F(I)
         ENDDO
         IF (RN%THIRD_BODY) THEN
            CALL GET_MOLECULAR_WEIGHT(ZZ_0,MW)
            MOLPCM3 = RHO_0/MW*0.001_EB ! mol/cm^3
            DZ_F(I) = DZ_F(I) * MOLPCM3
         ENDIF
         IF(RN%REVERSE) THEN ! compute equilibrium constant
            CALL GET_GIBBS_FREE_ENERGY(DG_RXN,RN%NU,TMP_0)
            RN%K = EXP(-DG_RXN/(R0*TMP_0))
         ENDIF
         DZZ = DZZ + RN%NU_MW_O_MW_F*DZ_F(I)*DT_LOC/RN%K
      ENDDO REACTION_LOOP_2      

END SELECT KINETICS_SELECT

END SUBROUTINE REACTION_RATE


LOGICAL FUNCTION FUNC_EXTINCT(ZZ_MIXED_IN,TMP_MIXED)
REAL(EB), INTENT(IN) :: ZZ_MIXED_IN(1:N_TRACKED_SPECIES),TMP_MIXED

FUNC_EXTINCT = .FALSE.
IF (ANY(REACTION(:)%FAST_CHEMISTRY)) THEN
   SELECT CASE (EXTINCT_MOD)
      CASE(EXTINCTION_1)
         FUNC_EXTINCT = EXTINCT_1(ZZ_MIXED_IN,TMP_MIXED)
      CASE(EXTINCTION_2)
         FUNC_EXTINCT = EXTINCT_2(ZZ_MIXED_IN,TMP_MIXED)
      CASE(EXTINCTION_3)
         FUNC_EXTINCT = .FALSE.
   END SELECT
ENDIF

END FUNCTION FUNC_EXTINCT


LOGICAL FUNCTION EXTINCT_1(ZZ_IN,TMP_MIXED)
USE PHYSICAL_FUNCTIONS,ONLY:GET_AVERAGE_SPECIFIC_HEAT
REAL(EB),INTENT(IN)::ZZ_IN(1:N_TRACKED_SPECIES),TMP_MIXED
REAL(EB):: Y_O2,Y_O2_CRIT,CPBAR
INTEGER :: NR
TYPE(REACTION_TYPE),POINTER :: RN=>NULL()

EXTINCT_1 = .FALSE.
REACTION_LOOP: DO NR=1,N_REACTIONS
   RN => REACTION(NR)
   IF (.NOT.RN%FAST_CHEMISTRY) CYCLE REACTION_LOOP
   AIT_IF: IF (TMP_MIXED < RN%AUTO_IGNITION_TEMPERATURE) THEN
      EXTINCT_1 = .TRUE.
   ELSE AIT_IF
      CALL GET_AVERAGE_SPECIFIC_HEAT(ZZ_IN,CPBAR,TMP_MIXED)
      Y_O2 = ZZ_IN(RN%AIR_SMIX_INDEX)
      Y_O2_CRIT = CPBAR*(RN%CRIT_FLAME_TMP-TMP_MIXED)/RN%EPUMO2
      IF (Y_O2 < Y_O2_CRIT) EXTINCT_1 = .TRUE.
   ENDIF AIT_IF
ENDDO REACTION_LOOP

END FUNCTION EXTINCT_1


LOGICAL FUNCTION EXTINCT_2(ZZ_MIXED_IN,TMP_MIXED)
USE PHYSICAL_FUNCTIONS,ONLY:GET_SENSIBLE_ENTHALPY
REAL(EB),INTENT(IN)::ZZ_MIXED_IN(1:N_TRACKED_SPECIES),TMP_MIXED
REAL(EB):: ZZ_F,ZZ_HAT_F,ZZ_GET_F(1:N_TRACKED_SPECIES),ZZ_A,ZZ_HAT_A,ZZ_GET_A(1:N_TRACKED_SPECIES),ZZ_P,ZZ_HAT_P,&
           ZZ_GET_P(1:N_TRACKED_SPECIES),H_F_0,H_A_0,H_P_0,H_F_N,H_A_N,H_P_N
INTEGER :: NR
TYPE(REACTION_TYPE),POINTER :: RN=>NULL()

EXTINCT_2 = .FALSE.
REACTION_LOOP: DO NR=1,N_REACTIONS
   RN => REACTION(NR)
   IF (.NOT.RN%FAST_CHEMISTRY) CYCLE REACTION_LOOP
   AIT_IF: IF (TMP_MIXED < RN%AUTO_IGNITION_TEMPERATURE) THEN
      EXTINCT_2 = .TRUE.
   ELSE AIT_IF
      ZZ_F = ZZ_MIXED_IN(RN%FUEL_SMIX_INDEX)
      ZZ_A = ZZ_MIXED_IN(RN%AIR_SMIX_INDEX)
      ZZ_P = 1._EB - ZZ_F - ZZ_A

      ZZ_HAT_F = MIN(ZZ_F,ZZ_MIXED_IN(RN%AIR_SMIX_INDEX)/RN%S) ! burned fuel, FDS Tech Guide (5.16)
      ZZ_HAT_A = ZZ_HAT_F*RN%S ! FDS Tech Guide (5.17)
      ZZ_HAT_P = (ZZ_HAT_A/(ZZ_A+TWO_EPSILON_EB))*(ZZ_F - ZZ_HAT_F + ZZ_P) ! reactant diluent concentration, FDS Tech Guide (5.18)

      ! "GET" indicates a composition vector.  Below we are building up the masses of the constituents in the various
      ! mixtures.  At this point these composition vectors are not normalized.

      ZZ_GET_F = 0._EB
      ZZ_GET_A = 0._EB
      ZZ_GET_P = ZZ_MIXED_IN

      ZZ_GET_F(RN%FUEL_SMIX_INDEX) = ZZ_HAT_F ! fuel in reactant mixture composition
      ZZ_GET_A(RN%AIR_SMIX_INDEX)  = ZZ_HAT_A ! air  in reactant mixture composition
   
      ZZ_GET_P(RN%FUEL_SMIX_INDEX) = MAX(ZZ_GET_P(RN%FUEL_SMIX_INDEX)-ZZ_HAT_F,0._EB) ! remove burned fuel from product composition
      ZZ_GET_P(RN%AIR_SMIX_INDEX)  = MAX(ZZ_GET_P(RN%AIR_SMIX_INDEX) -ZZ_A,0._EB) ! remove all air from product composition
   
      ! Normalize concentrations
      ZZ_GET_F = ZZ_GET_F/(SUM(ZZ_GET_F)+TWO_EPSILON_EB)
      ZZ_GET_A = ZZ_GET_A/(SUM(ZZ_GET_A)+TWO_EPSILON_EB)
      ZZ_GET_P = ZZ_GET_P/(SUM(ZZ_GET_P)+TWO_EPSILON_EB)

      ! Get the specific heat for the fuel and diluent at the current and critical flame temperatures
      CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_F,H_F_0,TMP_MIXED)
      CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_A,H_A_0,TMP_MIXED)
      CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_P,H_P_0,TMP_MIXED) 
      CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_F,H_F_N,RN%CRIT_FLAME_TMP)
      CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_A,H_A_N,RN%CRIT_FLAME_TMP)
      CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_P,H_P_N,RN%CRIT_FLAME_TMP)  
   
      ! See if enough energy is released to raise the fuel and required "air" temperatures above the critical flame temp. 
      IF ( ZZ_HAT_F*(H_F_0 + RN%HEAT_OF_COMBUSTION) + ZZ_HAT_A*H_A_0 + ZZ_HAT_P*H_P_0 < &
         ZZ_HAT_F*H_F_N  + ZZ_HAT_A*H_A_N + ZZ_HAT_P*H_P_N ) EXTINCT_2 = .TRUE. ! FDS Tech Guide (5.19)
   ENDIF AIT_IF
ENDDO REACTION_LOOP

END FUNCTION EXTINCT_2


LOGICAL FUNCTION EXTINCT_3(ZZ_MIXED_IN,TMP_MIXED)
USE PHYSICAL_FUNCTIONS,ONLY:GET_SENSIBLE_ENTHALPY
REAL(EB),INTENT(IN)::ZZ_MIXED_IN(1:N_TRACKED_SPECIES),TMP_MIXED
REAL(EB):: H_F_0,H_A_0,H_P_0,H_P_N,Z_F,Z_A,Z_P,Z_A_STOICH,ZZ_HAT_F,ZZ_HAT_A,ZZ_HAT_P,&
           ZZ_GET_F(1:N_TRACKED_SPECIES),ZZ_GET_A(1:N_TRACKED_SPECIES),ZZ_GET_P(1:N_TRACKED_SPECIES),ZZ_GET_F_REAC(1:N_REACTIONS),&
           ZZ_GET_PFP(1:N_TRACKED_SPECIES),DZ_F(1:N_REACTIONS),DZ_FRAC_F(1:N_REACTIONS),DZ_F_SUM,&
           HOC_EXTINCT,AIT_EXTINCT,CFT_EXTINCT
INTEGER :: NS,NR
TYPE(REACTION_TYPE),POINTER :: RN=>NULL()

EXTINCT_3 = .FALSE.
Z_F = 0._EB
Z_A = 0._EB
Z_P = 0._EB
DZ_F = 0._EB
DZ_F_SUM = 0._EB
Z_A_STOICH = 0._EB
ZZ_GET_F = 0._EB
ZZ_GET_A = 0._EB
ZZ_GET_P = ZZ_MIXED_IN
ZZ_GET_PFP = 0._EB
HOC_EXTINCT = 0._EB
AIT_EXTINCT = 0._EB
CFT_EXTINCT = 0._EB

DO NS=1,N_TRACKED_SPECIES
   SUM_FUEL_LOOP: DO NR = 1,N_REACTIONS
      RN => REACTION(NR)
      IF (RN%FAST_CHEMISTRY .AND. RN%HEAT_OF_COMBUSTION > 0._EB .AND. NS == RN%FUEL_SMIX_INDEX) THEN
         Z_F = Z_F + ZZ_MIXED_IN(NS)
         EXIT SUM_FUEL_LOOP
      ENDIF
   ENDDO SUM_FUEL_LOOP
   SUM_AIR_LOOP: DO NR = 1,N_REACTIONS
      RN => REACTION(NR)
      IF (RN%FAST_CHEMISTRY .AND. RN%HEAT_OF_COMBUSTION > 0._EB .AND. RN%NU(NS) < 0._EB .AND. NS /= RN%FUEL_SMIX_INDEX) THEN
         Z_A = Z_A + ZZ_MIXED_IN(NS)
         ZZ_GET_P(NS) = MAX(ZZ_GET_P(NS) - ZZ_MIXED_IN(NS),0._EB)
         EXIT SUM_AIR_LOOP
      ENDIF
   ENDDO SUM_AIR_LOOP
ENDDO
Z_P = 1._EB - Z_F - Z_A
DO NR = 1,N_REACTIONS
   RN => REACTION(NR)
   IF (RN%FAST_CHEMISTRY .AND. RN%HEAT_OF_COMBUSTION > 0._EB) THEN
      DZ_F(NR) = 1.E10_EB
      DO NS = 1,N_TRACKED_SPECIES
         IF (RN%NU(NS) < 0._EB) THEN
            DZ_F(NR) = MIN(DZ_F(NR),-ZZ_MIXED_IN(NS)/RN%NU_MW_O_MW_F(NS))
         ENDIF
         IF (RN%NU(NS) < 0._EB .AND. NS /= RN%FUEL_SMIX_INDEX) THEN
            Z_A_STOICH = Z_A_STOICH + ZZ_MIXED_IN(RN%FUEL_SMIX_INDEX)*RN%S
         ENDIF
      ENDDO
   ENDIF
ENDDO
IF (Z_A_STOICH > Z_A) DZ_F_SUM = SUM(DZ_F)
DO NR = 1,N_REACTIONS
   RN => REACTION(NR) 
   IF (Z_A_STOICH > Z_A .AND. RN%HEAT_OF_COMBUSTION > 0._EB) THEN 
      DZ_FRAC_F(NR) = DZ_F(NR)/MAX(DZ_F_SUM,TWO_EPSILON_EB)
      ZZ_GET_F(RN%FUEL_SMIX_INDEX) = DZ_F(NR)*DZ_FRAC_F(NR)
      ZZ_GET_P(RN%FUEL_SMIX_INDEX) = ZZ_GET_P(RN%FUEL_SMIX_INDEX) - ZZ_GET_F(RN%FUEL_SMIX_INDEX)
      ZZ_GET_PFP(RN%FUEL_SMIX_INDEX) = ZZ_GET_P(RN%FUEL_SMIX_INDEX)
      DO NS = 1,N_TRACKED_SPECIES
         IF (RN%NU(NS)< 0._EB .AND. NS/=RN%FUEL_SMIX_INDEX) THEN
            ZZ_GET_A(NS) = RN%S*ZZ_GET_F(RN%FUEL_SMIX_INDEX)
!            ZZ_GET_P(NS) = ZZ_GET_P(NS) - ZZ_GET_A(NS)
            ZZ_GET_PFP(NS) = ZZ_GET_P(NS)
         ELSEIF (RN%NU(NS) >= 0._EB ) THEN
            ZZ_GET_PFP(NS) = ZZ_GET_P(NS) + ZZ_GET_F(RN%FUEL_SMIX_INDEX)*RN%NU_MW_O_MW_F(NS)
         ENDIF
      ENDDO
   ELSE
      ZZ_GET_F(RN%FUEL_SMIX_INDEX) = DZ_F(NR)
      ZZ_GET_P(RN%FUEL_SMIX_INDEX) = ZZ_GET_P(RN%FUEL_SMIX_INDEX) - ZZ_GET_F(RN%FUEL_SMIX_INDEX)
      ZZ_GET_PFP(RN%FUEL_SMIX_INDEX) = ZZ_GET_P(RN%FUEL_SMIX_INDEX)
      DO NS = 1,N_TRACKED_SPECIES
         IF (RN%NU(NS) < 0._EB .AND. NS/=RN%FUEL_SMIX_INDEX) THEN
            ZZ_GET_A(NS) = RN%S*ZZ_GET_F(RN%FUEL_SMIX_INDEX)
!            ZZ_GET_P(NS) = ZZ_GET_P(NS) - ZZ_GET_A(NS)
            ZZ_GET_PFP(NS) = ZZ_GET_P(NS)
         ELSEIF (RN%NU(NS) >= 0._EB ) THEN
            ZZ_GET_PFP(NS) = ZZ_GET_P(NS) + ZZ_GET_F(RN%FUEL_SMIX_INDEX)*RN%NU_MW_O_MW_F(NS)
         ENDIF
      ENDDO
   ENDIF
   ZZ_GET_F_REAC(NR) = ZZ_GET_F(RN%FUEL_SMIX_INDEX)
ENDDO

ZZ_HAT_F = SUM(ZZ_GET_F)
ZZ_HAT_A = SUM(ZZ_GET_A)
ZZ_HAT_P = (ZZ_HAT_A/(Z_A+TWO_EPSILON_EB))*(Z_F-ZZ_HAT_F+SUM(ZZ_GET_P))
!M_P_ST = SUM(ZZ_GET_P)

! Normalize compositions
ZZ_GET_F = ZZ_GET_F/(SUM(ZZ_GET_F)+TWO_EPSILON_EB)
ZZ_GET_F_REAC = ZZ_GET_F_REAC/(SUM(ZZ_GET_F_REAC)+TWO_EPSILON_EB)
ZZ_GET_A = ZZ_GET_A/(SUM(ZZ_GET_A)+TWO_EPSILON_EB)
ZZ_GET_P = ZZ_GET_P/(SUM(ZZ_GET_P)+TWO_EPSILON_EB)
ZZ_GET_PFP = ZZ_GET_PFP/(SUM(ZZ_GET_PFP)+TWO_EPSILON_EB)

DO NR = 1,N_REACTIONS
   RN => REACTION(NR)
   AIT_EXTINCT = AIT_EXTINCT+ZZ_GET_F_REAC(NR)*RN%AUTO_IGNITION_TEMPERATURE
   CFT_EXTINCT = CFT_EXTINCT+ZZ_GET_F_REAC(NR)*RN%CRIT_FLAME_TMP
   HOC_EXTINCT = HOC_EXTINCT+ZZ_GET_F_REAC(NR)*RN%HEAT_OF_COMBUSTION
ENDDO
   
IF (TMP_MIXED < AIT_EXTINCT) THEN
   EXTINCT_3 = .TRUE.
ELSE     
   ! Get the specific heat for the fuel and diluent at the current and critical flame temperatures
   CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_F,H_F_0,TMP_MIXED)
   CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_A,H_A_0,TMP_MIXED)
   CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_P,H_P_0,TMP_MIXED)  
   CALL GET_SENSIBLE_ENTHALPY(ZZ_GET_PFP,H_P_N,CFT_EXTINCT)
   
   ! See if enough energy is released to raise the fuel and required "air" temperatures above the critical flame temp. 
   IF (ZZ_HAT_F*(H_F_0+HOC_EXTINCT) + ZZ_HAT_A*H_A_0 + ZZ_HAT_P*H_P_0 < &
      (ZZ_HAT_F+ZZ_HAT_A+ZZ_HAT_P)*H_P_N) EXTINCT_3 = .TRUE. ! FED Tech Guide (5.19)
ENDIF

END FUNCTION EXTINCT_3


REAL(EB) FUNCTION FLAME_SPEED_FACTOR(ZZ_0,DT_LOC,RHO_0,TMP_0,PBAR_0,NR,DELTA,VEL_RMS)
USE PHYSICAL_FUNCTIONS, ONLY : GET_AVERAGE_SPECIFIC_HEAT,GET_SPECIFIC_GAS_CONSTANT
USE RADCONS, ONLY: RADIATIVE_FRACTION
REAL(EB), INTENT(IN) :: ZZ_0(1:N_TRACKED_SPECIES),RHO_0,TMP_0,PBAR_0,DT_LOC,DELTA,VEL_RMS
INTEGER, INTENT(IN) :: NR
TYPE(REACTION_TYPE),POINTER :: RN=>NULL()
REAL(EB) :: DZ_F,ZZ_B(1:N_TRACKED_SPECIES),TMP_B,CPBAR_B,RHO_B,CPBAR_0,RSUM_B,PHI,S_L,S_T
INTEGER :: IT
! REAL(EB) :: DPHI ! debug

FLAME_SPEED_FACTOR = 1._EB

RN=>REACTION(NR)
IF (RN%FLAME_SPEED<0._EB) RETURN

! equivalence ratio of unburnt mixture
PHI = RN%S*ZZ_0(RN%FUEL_SMIX_INDEX)/ZZ_0(RN%AIR_SMIX_INDEX)

! burnt composition
DZ_F = MIN(ZZ_0(RN%FUEL_SMIX_INDEX),ZZ_0(RN%AIR_SMIX_INDEX)/RN%S)
ZZ_B = ZZ_0 + RN%NU_MW_O_MW_F*DZ_F
ZZ_B = MIN(1._EB,MAX(0._EB,ZZ_B))

! find burnt zone temperature
CALL GET_AVERAGE_SPECIFIC_HEAT(ZZ_0,CPBAR_0,TMP_0)
TMP_B = TMP_0
DO IT=1,2
   CALL GET_AVERAGE_SPECIFIC_HEAT(ZZ_B,CPBAR_B,TMP_B)
   TMP_B = ( CPBAR_0*TMP_0 + (1._EB-RADIATIVE_FRACTION)*DZ_F*RN%HEAT_OF_COMBUSTION ) / CPBAR_B
   !print *,TMP_B ! 2 iterations is sufficient
ENDDO

! compute burnt zone density
CALL GET_SPECIFIC_GAS_CONSTANT(ZZ_B,RSUM_B)
RHO_B = PBAR_0/(RSUM_B*TMP_B)

! get turbulent flame speed

! ! (debug) check laminar flame speed ramp
! PHI = 0._EB
! DPHI = .1_EB
! DO IT=1,20
!    PHI = PHI+DPHI
!    S_L = LAMINAR_FLAME_SPEED(TMP_0,PHI,NR)
!    print *,PHI,S_L
! ENDDO
! stop

S_L = LAMINAR_FLAME_SPEED(TMP_0,PHI,NR)

IF (S_L<TWO_EPSILON_EB) THEN
   FLAME_SPEED_FACTOR = 0._EB
ELSE
   S_T = MAX( S_L, S_L*( 1._EB + RN%TURBULENT_FLAME_SPEED_ALPHA*(VEL_RMS/S_L)**RN%TURBULENT_FLAME_SPEED_EXPONENT ) )
   FLAME_SPEED_FACTOR = RHO_B/RHO_0 * S_T * DT_LOC/DELTA
ENDIF

END FUNCTION FLAME_SPEED_FACTOR


REAL(EB) FUNCTION LAMINAR_FLAME_SPEED(TMP,EQ,NR)
USE MATH_FUNCTIONS, ONLY: EVALUATE_RAMP, INTERPOLATE2D
REAL(EB), INTENT(IN) :: TMP,EQ
INTEGER, INTENT(IN) :: NR
TYPE(REACTION_TYPE),POINTER :: RN=>NULL()

RN=>REACTION(NR)

IF (RN%TABLE_FS_INDEX>0) THEN
   CALL INTERPOLATE2D(RN%TABLE_FS_INDEX,EQ,TMP,LAMINAR_FLAME_SPEED)
ELSE
   LAMINAR_FLAME_SPEED = RN%FLAME_SPEED*(TMP/RN%FLAME_SPEED_TEMPERATURE)**RN%FLAME_SPEED_EXPONENT &
                         *EVALUATE_RAMP(EQ,0._EB,RN%RAMP_FS_INDEX)
ENDIF

END FUNCTION LAMINAR_FLAME_SPEED


SUBROUTINE ZETA_PRODUCTION
USE MASS, ONLY: SCALAR_FACE_VALUE

INTEGER :: I,J,K,IIG,JJG,KKG,IOR,IW,II,JJ,KK
REAL(EB) :: Z_F,DENOM,ZZZ(1:4),DZDX,DZDY,DZDZ
REAL(EB), POINTER, DIMENSION(:,:,:) :: ZFX=>NULL(),ZFY=>NULL(),ZFZ=>NULL(),ZZP=>NULL(),UU=>NULL(),VV=>NULL(),WW=>NULL()
TYPE(WALL_TYPE), POINTER :: WC=>NULL()

ZFX =>WORK1
ZFY =>WORK2
ZFZ =>WORK3
ZZP =>WORK4

UU=>U
VV=>V
WW=>W

!$OMP PARALLEL PRIVATE(ZZZ)
!$OMP DO SCHEDULE(STATIC)
DO K=0,KBP1
   DO J=0,JBP1
      DO I=0,IBP1
         ZZP(I,J,K) = ZZ(I,J,K,REACTION(1)%FUEL_SMIX_INDEX)
      ENDDO
   ENDDO
ENDDO
!$OMP END DO

! Compute scalar face values

!$OMP DO SCHEDULE(STATIC)
DO K=1,KBAR
   DO J=1,JBAR
      DO I=1,IBM1
         ZZZ(1:4) = ZZP(I-1:I+2,J,K)
         ZFX(I,J,K) = SCALAR_FACE_VALUE(UU(I,J,K),ZZZ,FLUX_LIMITER)
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

!$OMP DO SCHEDULE(STATIC)
DO K=1,KBAR
   DO J=1,JBM1
      DO I=1,IBAR
         ZZZ(1:4) = ZZP(I,J-1:J+2,K)
         ZFY(I,J,K) = SCALAR_FACE_VALUE(VV(I,J,K),ZZZ,FLUX_LIMITER)
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

!$OMP DO SCHEDULE(STATIC)
DO K=1,KBM1
   DO J=1,JBAR
      DO I=1,IBAR
         ZZZ(1:4) = ZZP(I,J,K-1:K+2)
         ZFZ(I,J,K) = SCALAR_FACE_VALUE(WW(I,J,K),ZZZ,FLUX_LIMITER)
      ENDDO
   ENDDO
ENDDO
!$OMP END DO
!$OMP END PARALLEL

WALL_LOOP_2: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
   WC=>WALL(IW)
   IF (WC%BOUNDARY_TYPE==NULL_BOUNDARY) CYCLE WALL_LOOP_2

   II  = WC%ONE_D%II 
   JJ  = WC%ONE_D%JJ
   KK  = WC%ONE_D%KK
   IIG = WC%ONE_D%IIG 
   JJG = WC%ONE_D%JJG
   KKG = WC%ONE_D%KKG
   IOR = WC%ONE_D%IOR

   Z_F = WC%ZZ_F(REACTION(1)%FUEL_SMIX_INDEX)

   SELECT CASE(IOR)
      CASE( 1); ZFX(IIG-1,JJG,KKG) = Z_F
      CASE(-1); ZFX(IIG,JJG,KKG)   = Z_F
      CASE( 2); ZFY(IIG,JJG-1,KKG) = Z_F
      CASE(-2); ZFY(IIG,JJG,KKG)   = Z_F
      CASE( 3); ZFZ(IIG,JJG,KKG-1) = Z_F
      CASE(-3); ZFZ(IIG,JJG,KKG)   = Z_F
   END SELECT

   ! Overwrite first off-wall advective flux if flow is away from the wall and if the face is not also a wall cell

   OFF_WALL_IF_2: IF (WC%BOUNDARY_TYPE/=INTERPOLATED_BOUNDARY .AND. WC%BOUNDARY_TYPE/=OPEN_BOUNDARY) THEN

      OFF_WALL_SELECT_2: SELECT CASE(IOR)
         CASE( 1) OFF_WALL_SELECT_2
            !      ghost          FX/UU(II+1)
            ! ///   II   ///  II+1  |  II+2  | ...
            !                       ^ WALL_INDEX(II+1,+1)
            IF ((UU(II+1,JJ,KK)>0._EB) .AND. .NOT.(WALL_INDEX(CELL_INDEX(II+1,JJ,KK),+1)>0)) THEN
               ZZZ(1:3) = (/Z_F,ZZP(II+1:II+2,JJ,KK)/)
               ZFX(II+1,JJ,KK) = SCALAR_FACE_VALUE(UU(II+1,JJ,KK),ZZZ,FLUX_LIMITER)
            ENDIF
         CASE(-1) OFF_WALL_SELECT_2
            !            FX/UU(II-2)     ghost
            ! ... |  II-2  |  II-1  ///   II   ///
            !              ^ WALL_INDEX(II-1,-1)
            IF ((UU(II-2,JJ,KK)<0._EB) .AND. .NOT.(WALL_INDEX(CELL_INDEX(II-1,JJ,KK),-1)>0)) THEN
               ZZZ(2:4) = (/ZZP(II-2:II-1,JJ,KK),Z_F/)
               ZFX(II-2,JJ,KK) = SCALAR_FACE_VALUE(UU(II-2,JJ,KK),ZZZ,FLUX_LIMITER)
            ENDIF
         CASE( 2) OFF_WALL_SELECT_2
            IF ((VV(II,JJ+1,KK)>0._EB) .AND. .NOT.(WALL_INDEX(CELL_INDEX(II,JJ+1,KK),+2)>0)) THEN
               ZZZ(1:3) = (/Z_F,ZZP(II,JJ+1:JJ+2,KK)/)
               ZFY(II,JJ+1,KK) = SCALAR_FACE_VALUE(VV(II,JJ+1,KK),ZZZ,FLUX_LIMITER)
            ENDIF
         CASE(-2) OFF_WALL_SELECT_2
            IF ((VV(II,JJ-2,KK)<0._EB) .AND. .NOT.(WALL_INDEX(CELL_INDEX(II,JJ-1,KK),-2)>0)) THEN
               ZZZ(2:4) = (/ZZP(II,JJ-2:JJ-1,KK),Z_F/)
               ZFY(II,JJ-2,KK) = SCALAR_FACE_VALUE(VV(II,JJ-2,KK),ZZZ,FLUX_LIMITER)
            ENDIF
         CASE( 3) OFF_WALL_SELECT_2
            IF ((WW(II,JJ,KK+1)>0._EB) .AND. .NOT.(WALL_INDEX(CELL_INDEX(II,JJ,KK+1),+3)>0)) THEN
               ZZZ(1:3) = (/Z_F,ZZP(II,JJ,KK+1:KK+2)/)
               ZFZ(II,JJ,KK+1) = SCALAR_FACE_VALUE(WW(II,JJ,KK+1),ZZZ,FLUX_LIMITER)
            ENDIF
         CASE(-3) OFF_WALL_SELECT_2
            IF ((WW(II,JJ,KK-2)<0._EB) .AND. .NOT.(WALL_INDEX(CELL_INDEX(II,JJ,KK-1),-3)>0)) THEN
               ZZZ(2:4) = (/ZZP(II,JJ,KK-2:KK-1),Z_F/)
               ZFZ(II,JJ,KK-2) = SCALAR_FACE_VALUE(WW(II,JJ,KK-2),ZZZ,FLUX_LIMITER)
            ENDIF
      END SELECT OFF_WALL_SELECT_2
      
   ENDIF OFF_WALL_IF_2

ENDDO WALL_LOOP_2

! Production term

DO K=1,KBAR
   DO J=1,JBAR
      DO I=1,IBAR
         IF (SOLID(CELL_INDEX(I,J,K))) CYCLE

         DZDX = (ZFX(I,J,K)-ZFX(I-1,J,K))*RDX(I)
         DZDY = (ZFY(I,J,K)-ZFY(I,J-1,K))*RDY(J)
         DZDZ = (ZFZ(I,J,K)-ZFZ(I,J,K-1))*RDZ(K)

         DENOM = RHO(I,J,K)*( ZZP(I,J,K) - ZZP(I,J,K)**2 )

         IF (DENOM>TWO_EPSILON_EB) THEN
            ! scale sgs variance production
            ZETA_SOURCE_TERM(I,J,K) = 2._EB*MU(I,J,K)/SC*( DZDX**2 + DZDY**2 + DZDZ**2 ) / DENOM
         ELSE
            ! cell is pure, unmix
            ZETA_SOURCE_TERM(I,J,K) = (1._EB - ZZ(I,J,K,ZETA_INDEX))/DT
         ENDIF

         ZZ(I,J,K,ZETA_INDEX) = MIN( 1._EB, ZZ(I,J,K,ZETA_INDEX) + DT*ZETA_SOURCE_TERM(I,J,K) )
      ENDDO
   ENDDO
ENDDO

END SUBROUTINE ZETA_PRODUCTION


SUBROUTINE GET_REV_fire(MODULE_REV,MODULE_DATE)
INTEGER,INTENT(INOUT) :: MODULE_REV
CHARACTER(255),INTENT(INOUT) :: MODULE_DATE
INTEGER :: IERR

WRITE(MODULE_DATE,'(A)') firerev(INDEX(firerev,':')+2:LEN_TRIM(firerev)-2)
READ (MODULE_DATE,'(I5)',IOSTAT=IERR) MODULE_REV
IF (IERR/=0) MODULE_REV = 0
WRITE(MODULE_DATE,'(A)') firedate

END SUBROUTINE GET_REV_fire

 
END MODULE FIRE

