#!/bin/bash
# Sanity check: the same build of Open MPI, at version 4.1.6, and the MPI bundled with NVHPC, both with unmodified MFC
# master. Runs in the container.
set -e
source /repro/lib.sh

section "How each upstream Open MPI declares the buffers of use mpi (from its configure)"
show_buffer_declarations

section "1. Minimal example, the MPI bundled with NVHPC 25.7 (Open MPI 4.1.7)"
mwe 1_mwe_bundled "$BUNDLED"

section "2. Minimal example, upstream Open MPI 4.1.6"
mwe 2_mwe_openmpi4 "$OPENMPI4"

section "Building MFC master, with upstream Open MPI 4.1.6 and with the bundled MPI"
clone_mfc
build_mfc master_openmpi4 "$MASTER" "$OPENMPI4" -Wl,-rpath,$OPENMPI4/lib
build_mfc master_bundled "$MASTER" "$BUNDLED"

section "Reference runs: serial I/O (parallel_io = F), MFC master"
reference_runs master_openmpi4 "$OPENMPI4"

section "3. 3D_IGR_jet, master, upstream Open MPI 4.1.6"
mfc_case 3_IGR_jet_master_openmpi4 master_openmpi4 "$OPENMPI4" 3D_IGR_jet

section "4. 3D_IGR_jet, master, the bundled MPI"
mfc_case 4_IGR_jet_master_bundled master_bundled "$BUNDLED" 3D_IGR_jet

section "5. 3D_TaylorGreenVortex, master, upstream Open MPI 4.1.6"
mfc_case 5_TGV_master_openmpi4 master_openmpi4 "$OPENMPI4" 3D_TaylorGreenVortex

section "6. 3D_TaylorGreenVortex, master, the bundled MPI"
mfc_case 6_TGV_master_bundled master_bundled "$BUNDLED" 3D_TaylorGreenVortex

section "Done. Every run's files are in /repro/runs, every MFC build in /repro/builds"
ls /repro/runs
