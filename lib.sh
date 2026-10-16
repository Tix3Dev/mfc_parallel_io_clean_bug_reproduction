# Shared by demo.sh and sanity_check_openmpi4.sh. Everything runs on the CPU, compiled with nvfortran 25.7.

OPENMPI5=/opt/openmpi-5.0.10                                 # upstream Open MPI 5.0.10, built by build_openmpi.sh
OPENMPI4=/opt/openmpi-4.1.6                                  # upstream Open MPI 4.1.6, built the same way
BUNDLED=/opt/nvidia/hpc_sdk/Linux_x86_64/25.7/comm_libs/mpi  # the MPI bundled with NVHPC 25.7 (HPC-X, Open MPI 4.1.7)
MASTER=47568a0f92559bd6965dee7bfcdb39e446d621e7              # MFC master, the base of PR #2085
FIX=9e6ef09aa7ad177becdcc268db6804a61b86b231                 # MFC PR #2085
export CC=nvc CXX=nvc++ FC=nvfortran

section() {
    echo
    echo
    echo "=============================================================================="
    echo "  $1"
    echo "=============================================================================="
    echo
}

# How each upstream Open MPI's `use mpi` declares choice buffers, as its configure decided.
show_buffer_declarations() {
    for prefix in "$OPENMPI4" "$OPENMPI5"; do
        echo "${prefix#/opt/}: $(grep "Fortran compiler ignore TKR syntax\.\.\. 1:" "$prefix-configure.log")"
    done
}

# The minimal example, built and run with the MPI in <prefix>, in /repro/runs/<name>: the program, the files it wrote
# (A, B, C, E; D and F read B back) and output.txt.
mwe() {   # <name> <MPI prefix>
    mkdir -p /repro/runs/$1
    cd /repro/runs/$1
    "$2/bin/mpifort" -O2 -o shear /repro/shear.f90
    "$2/bin/mpirun" -n 1 ./shear | tee output.txt
}

# MFC at <commit>, pre_process and simulation built with the MPI in <prefix>, in /repro/builds/<name>.
# For the upstream Open MPIs, the scripts pass -Wl,-rpath,<prefix>/lib as linker flags: Open MPI 4.1.6's wrapper hands
# nvfortran its library path as "-rpath <dir>", which MFC's CMake build does not carry over, so MFC's binaries would not
# find libmpi. 5.0.10 works without; both get the flag so that both are built the same way. The bundled MPI's wrapper
# passes its path in a form CMake keeps.
build_mfc() {   # <name> <commit> <MPI prefix> [<linker flags>]
    git -C /repro/MFC worktree add -q --detach /repro/builds/$1 $2
    cd /repro/builds/$1
    echo "building $1 (log: /repro/builds/$1/build.log)"
    PATH=$3/bin:$PATH LDFLAGS=$4 ./mfc.sh build -t pre_process simulation -j "$(nproc)" > build.log 2>&1 \
        || { tail -n 50 build.log; exit 1; }
}

# One MFC run in /repro/runs/<name>: the example, shrunk to a 32^3 grid and 10 steps (one save at the end), with any
# further parameters changed as given. The folder holds case.json, the run's log and MFC's output (D/, p_all/ or
# restart_data/).
run_mfc() {   # <name> <build> <MPI prefix> <example> [<key=value> ...]
    local name=$1 dir=/repro/runs/$1 build=/repro/builds/$2 mpi=$3 example=$4
    shift 4
    mkdir -p "$dir"
    python3 "$build/examples/$example/case.py" | python3 -c '
import json, sys
case = json.load(sys.stdin)
for arg in sys.argv[1:]:
    key, value = arg.split("=", 1)
    case[key] = json.loads(value) if value[0].isdigit() else value
print(json.dumps(case))' m=31 n=31 p=31 t_step_start=0 t_step_stop=10 t_step_save=10 "$@" > "$dir/case.json"
    cd "$build"
    if PATH=$mpi/bin:$PATH ./mfc.sh run "$dir/case.json" -t pre_process simulation -n 1 --no-build > "$dir/log" 2>&1; then
        echo "$name: MFC finished (log: $dir/log)"
    else
        echo "$name: MFC FAILED, end of $dir/log:"
        tail -n 40 "$dir/log" | sed 's/^/    /'
    fi
}

# An MFC run with MPI-IO (as both examples ship), compared with the serial-I/O reference run of the same example.
mfc_case() {   # <name> <build> <MPI prefix> <example> [<key=value> ...]
    run_mfc "$@"
    echo
    python3 /repro/compare.py /repro/runs/serial_$4 /repro/runs/$1 0 || true    # initial condition (pre_process)
    echo
    python3 /repro/compare.py /repro/runs/serial_$4 /repro/runs/$1 10 || true   # after 10 steps (simulation)
}

# The MFC checkout, and one serial-I/O reference run (parallel_io = F) per example, on MFC master.
clone_mfc() {
    git clone -q https://github.com/MFlowCode/MFC.git /repro/MFC
    git -C /repro/MFC fetch -q origin pull/2085/head
}

reference_runs() {   # <build of MFC master> <its MPI prefix>
    run_mfc serial_3D_IGR_jet "$1" "$2" 3D_IGR_jet parallel_io=F
    run_mfc serial_3D_TaylorGreenVortex "$1" "$2" 3D_TaylorGreenVortex parallel_io=F
}
