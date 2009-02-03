@echo off
Rem
Rem Copyright  (C) 1985-2008 Intel Corporation. All rights reserved.
Rem
Rem The information and source code contained herein is the exclusive property
Rem of Intel Corporation and may not be disclosed, examined, or reproduced in
Rem whole or in part without explicit written authorization from the Company.
Rem


if {%1} EQU {ia32} (
  @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\bin\ia32\ifortvars_ia32.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\tbb\ia32\vc8\bin\tbbvars.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\tbb\ia32\vc8\bin\tbbvars.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvars32.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvars32.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\ia32\tools\env\ippenv.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\ia32\tools\env\ippenv.bat"
  exit /B 0
)

if {%1} EQU {ia32_intel64} (
  @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\bin\ia32_intel64\ifortvars_ia32_intel64.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\tbb\em64t\vc8\bin\tbbvars.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\tbb\em64t\vc8\bin\tbbvars.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvarsem64t.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvarsem64t.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\em64t\tools\env\ippenvem64t.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\em64t\tools\env\ippenvem64t.bat"
  exit /B 0
)

if {%1} EQU {intel64} (
  @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\bin\intel64\ifortvars_intel64.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\tbb\em64t\vc8\bin\tbbvars.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\tbb\em64t\vc8\bin\tbbvars.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvarsem64t.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvarsem64t.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\em64t\tools\env\ippenvem64t.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\em64t\tools\env\ippenvem64t.bat"
  exit /B 0
)

if {%1} EQU {ia32_ia64} (
  @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\bin\ia32_ia64\ifortvars_ia32_ia64.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvars64.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvars64.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\ia64\tools\env\ippenv64.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\ia64\tools\env\ippenv64.bat"
  exit /B 0
)

if {%1} EQU {ia64} (
  @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\bin\ia64\ifortvars_ia64.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvars64.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\mkl\tools\environment\mklvars64.bat"
  if exist "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\ia64\tools\env\ippenv64.bat" @call "C:\Program Files\Intel\Compiler\11.0\066\fortran\ipp\ia64\tools\env\ippenv64.bat"
  exit /B 0
)

@echo ERROR: Unknown switch '%1'
@echo Accepted values: ia32, ia32_intel64, intel64, ia32_ia64, ia64
exit /B 1
