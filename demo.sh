#!/bin/bash
# The demo: MFC's MPI-IO with upstream Open MPI 5.0.10, compared with the MPI bundled with NVHPC. Runs in the container.
set -e
source /repro/lib.sh

section "How each upstream Open MPI declares the buffers of use mpi (from its configure)"
show_buffer_declarations

section "1. Minimal example, the MPI bundled with NVHPC 25.7"
mwe 1_mwe_bundled "$BUNDLED"

section "2. Minimal example, upstream Open MPI 5.0.10"
mwe 2_mwe_openmpi5 "$OPENMPI5"

section "Building MFC: master and PR #2085 with upstream Open MPI 5.0.10, PR #2085 with the bundled MPI"
clone_mfc
build_mfc master_openmpi5 "$MASTER" "$OPENMPI5" -Wl,-rpath,$OPENMPI5/lib
build_mfc pr2085_openmpi5 "$FIX" "$OPENMPI5" -Wl,-rpath,$OPENMPI5/lib
build_mfc pr2085_bundled "$FIX" "$BUNDLED"

section "Reference runs: serial I/O (parallel_io = F), MFC master"
reference_runs master_openmpi5 "$OPENMPI5"

section "3. 3D_IGR_jet, master, upstream Open MPI 5.0.10"
mfc_case 3_IGR_jet_master_openmpi5 master_openmpi5 "$OPENMPI5" 3D_IGR_jet

section "4. 3D_IGR_jet, PR #2085, upstream Open MPI 5.0.10"
mfc_case 4_IGR_jet_pr2085_openmpi5 pr2085_openmpi5 "$OPENMPI5" 3D_IGR_jet

section "5. 3D_IGR_jet, PR #2085, the bundled MPI"
mfc_case 5_IGR_jet_pr2085_bundled pr2085_bundled "$BUNDLED" 3D_IGR_jet

section "6. 3D_TaylorGreenVortex, master, upstream Open MPI 5.0.10"
mfc_case 6_TGV_master_openmpi5 master_openmpi5 "$OPENMPI5" 3D_TaylorGreenVortex

section "7. 3D_TaylorGreenVortex, PR #2085, upstream Open MPI 5.0.10"
mfc_case 7_TGV_pr2085_openmpi5 pr2085_openmpi5 "$OPENMPI5" 3D_TaylorGreenVortex

section "8. 3D_TaylorGreenVortex, PR #2085, the bundled MPI"
mfc_case 8_TGV_pr2085_bundled pr2085_bundled "$BUNDLED" 3D_TaylorGreenVortex

section "9. 3D_TaylorGreenVortex, master, upstream Open MPI 5.0.10, run_time_info = F"
mfc_case 9_TGV_master_openmpi5_run_time_info_F master_openmpi5 "$OPENMPI5" 3D_TaylorGreenVortex run_time_info=F

section "Done. Every run's files are in /repro/runs, every MFC build in /repro/builds"
ls /repro/runs
