#!/bin/bash
# Builds an official Open MPI release with the NVHPC compilers into /opt/openmpi-<version>. Every Open MPI in this image
# is built by this script, with the same configure line; only the version differs.
#   build_openmpi.sh <version> <SHA-256 of the release tarball, as published on open-mpi.org>
set -eo pipefail
version=$1
cd /tmp
curl -LO "https://download.open-mpi.org/release/open-mpi/v${version%.*}/openmpi-$version.tar.gz"   # 4.1.6 -> v4.1/
echo "$2  openmpi-$version.tar.gz" | sha256sum -c
tar xf "openmpi-$version.tar.gz"
cd "openmpi-$version"

# CFLAGS=-mno-hle: nvc compiles for the CPU it runs on. On a CPU with Intel's HLE ("hle" in /proc/cpuinfo) it defines
# __HLE__, so Open MPI uses its HLE locks (opal/include/opal/sys/gcc_builtin/atomic.h), but not the __ATOMIC_HLE_*
# constants they need, and the build fails ("identifier "__ATOMIC_HLE_ACQUIRE" is undefined"). Both versions.
# FCFLAGS=-fPIC: Open MPI 4.1.6 does not pass -fPIC to nvfortran itself, and linking its shared mpi_f08 library then
# fails ("relocation R_X86_64_32S ... recompile with -fPIC"). 5.0.10 passes it on its own.
# Both change code generation only, not how `use mpi` declares buffers. configure's output is kept: its "Fortran
# compiler ignore TKR syntax" line shows that declaration.
./configure CC=nvc CXX=nvc++ FC=nvfortran CFLAGS=-mno-hle FCFLAGS=-fPIC --prefix="/opt/openmpi-$version" \
    | tee "/opt/openmpi-$version-configure.log"
make -j"$(nproc)" install

cd /tmp
rm -rf "openmpi-$version" "openmpi-$version.tar.gz"
