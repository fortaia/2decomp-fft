#=======================================================================
# Makefile for 2DECOMP&FFT
#=======================================================================

# generate a Git version string
GIT_VERSION := $(shell git describe --tag --long --always)

LCL = local# local,lad,sdu,archer
### Compiler specified in the FCOMP variable of the build.conf file (options:intel,gnu,nagfor,cray,nvhpc)
FFT ?= fftw3_f03# fftw3,fftw3_f03,generic,mkl,cufft
FFTW3_PATH ?= /usr# rooot path if the FFT=fftw3,fftw3_f03
PARAMOD = mpi # multicore,gpu
PROFILER ?= none# none, caliper

BUILD ?= Release # debug can be used with gcc
FCFLAGS ?=# user can set default compiler flags
LDFLAGS ?=# user can set default linker flags
LFLAGS = $(LDFLAGS)
MODFLAG = -J 

LIBDECOMP = decomp2d

AR = ar
LIBOPT = rcs

#######Compilation settings###########
CODE_DIR=../..
include $(CODE_DIR)/build.conf

CMPINC = Makefile.comp

include $(CMPINC)

### List of files for the main code
SRCDECOMP = decomp_2d_constants.f90 decomp_2d_mpi.f90 profiler_none.f90 factor.f90 decomp_2d.f90 log.f90 interp.f90 io_utilities.f90 io_adios_none.f90 \
            io_object_mpi.f90 io_mpi.f90 transpose_x_to_y.f90 transpose_y_to_x.f90 transpose_y_to_z.f90 transpose_z_to_y.f90

#######FFT settings##########
ifeq ($(FFT),fftw3)
  FFTW3_PATH_INCLUDE ?= $(FFTW3_PATH)/include
  FFTW3_PATH_LIB ?= $(FFTW3_PATH)/lib/x86_64-linux-gnu
  INC=-I$(FFTW3_PATH_INCLUDE)
  LIBFFT=-L$(FFTW3_PATH_LIB) -lfftw3 -lfftw3f
else ifeq ($(FFT),fftw3_f03)
  FFTW3_PATH_INCLUDE ?= $(FFTW3_PATH)/include
  FFTW3_PATH_LIB ?= $(FFTW3_PATH)/lib/x86_64-linux-gnu
  INC=-I$(FFTW3_PATH_INCLUDE)
  LIBFFT=-L$(FFTW3_PATH_LIB) -lfftw3 -lfftw3f
else ifeq ($(FFT),generic)
  SRCDECOMP += ./glassman.f90
  INC=
  LIBFFT=
else ifeq ($(FFT),mkl)
  SRCDECOMP += $(MKLROOT)/include/mkl_dfti.f90
  LIBFFT=-Wl,--start-group $(MKLROOT)/lib/intel64/libmkl_intel_lp64.a $(MKLROOT)/lib/intel64/libmkl_sequential.a $(MKLROOT)/lib/intel64/libmkl_core.a -Wl,--end-group -lpthread
  INC=-I$(MKLROOT)/include
else ifeq ($(FFT),cufft)
  CUFFT_PATH ?= $(NVHPC)/Linux_x86_64/$(EBVERSIONNVHPC)/compilers
  INC=-I$(CUFFT_PATH)/include
endif

### IO Options ###
LIBIO :=
OPTIO :=
INCIO :=
ADIOS2DIR :=
ifeq ($(IO),adios2)
  ifeq ($(ADIOS2DIR),)
    $(error Set ADIOS2DIR=/path/to/adios2/install/)
  endif
  OPTIO := -DADIOS2 $(OPT)
  INCIO := $(INC) $(shell $(ADIOS2DIR)/bin/adios2-config --fortran-flags) #$(patsubst $(shell $(ADIOS2DIR)/bin/adios2-config --fortran-libs),,$(shell $(ADIOS2DIR)/bin/adios2-config -f))
  LIBIO := $(shell $(ADIOS2DIR)/bin/adios2-config --fortran-libs)
endif

### Add the profiler if needed
ifneq ($(PROFILER),none)
  DEFS += -DPROFILER
endif
ifeq ($(PROFILER),caliper)
  CALIPER_PATH ?= xxxxxxxxx/caliper/caliper_2.8.0
  SRCDECOMP := $(SRCDECOMP) profiler_caliper.f90
  INC := $(INC) -I$(CALIPER_PATH)/include/caliper/fortran
  LFLAGS := $(LFLAGS) -L$(CALIPER_PATH)/lib -lcaliper
endif

#######OPTIONS settings###########
OPT =
LINKOPT = $(FCFLAGS)
#-----------------------------------------------------------------------
# Normally no need to change anything below

OBJDIR = obj
SRCDIR = src
DECOMPINC = mod
FCFLAGS += $(MODFLAG)$(DECOMPINC) -I$(DECOMPINC) 

SRCDECOMP := $(SRCDECOMP) fft_$(FFT).f90 fft_log.f90
SRCDECOMP_ = $(patsubst %.f90,$(SRCDIR)/%.f90,$(filter-out %/mkl_dfti.f90,$(SRCDECOMP)))
SRCDECOMP_ += $(filter %/mkl_dfti.f90,$(SRCDECOMP))
OBJDECOMP_MKL_ = $(patsubst $(MKLROOT)/include/%.f90,$(OBJDIR)/%.f90,$(filter %/mkl_dfti.f90,$(SRCDECOMP_)))
OBJDECOMP_MKL = $(OBJDECOMP_MKL_:%.f90=%.o)
OBJDECOMP = $(SRCDECOMP_:$(SRCDIR)/%.f90=$(OBJDIR)/%.o)

OPT += $(OPTIO)
INC += $(INCIO)

-include Makefile.settings

all: $(DECOMPINC) $(OBJDIR) $(LIBDECOMP)

$(DECOMPINC):
	mkdir $(DECOMPINC)

$(LIBDECOMP) : Makefile.settings lib$(LIBDECOMP).a

lib$(LIBDECOMP).a: $(OBJDECOMP_MKL) $(OBJDECOMP)
	$(AR) $(LIBOPT) $@ $^

$(OBJDIR):
	mkdir $(OBJDIR)

$(OBJDECOMP) : $(OBJDIR)/%.o : $(SRCDIR)/%.f90
	$(FC) $(FCFLAGS) $(OPT) $(DEFS) $(INC) -c $< -o $@

$(OBJDECOMP_MKL) : $(OBJDIR)/%.o : $(MKLROOT)/include/%.f90
	$(FC) $(FCFLAGS) $(OPT) $(DEFS) $(INC) -c $(MKLROOT)/include/mkl_dfti.f90 -o $(OBJDIR)/mkl_dfti.o

examples: $(LIBDECOMP)
	$(MAKE) -C examples

.PHONY: check

check: examples
	$(MAKE) -C examples $@

.PHONY: clean

clean:
	rm -rf $(OBJDIR) $(DECOMPINC) lib$(LIBDECOMP).a
	rm -f ./*.o ./*.mod ./*.smod # Ensure old files are removed
	rm -f Makefile.settings lib$(LIBDECOMP).a

.PHONY: Makefile.settings

Makefile.settings:
	echo "FC = $(FC)" > $@
	echo "FCFLAGS = $(FCFLAGS)" >> $@
	echo "OPT = $(OPT)" >> $@
	echo "DEFS = $(DEFS)" >> $@
	echo "INC = $(INC)" >> $@
	echo "LIBOPT = $(LIBOPT)" >> $@
	echo "LIBFFT = ${LIBFFT}" >> $@
	echo "LFLAGS = $(LFLAGS)" >> $@

export

