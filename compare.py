"""Compare MFC's MPI-IO output (parallel_io = T) with the serial-I/O output (parallel_io = F) of the same case.

Usage: compare.py <serial run dir> <MPI-IO run dir> <step>
"""

import sys
from array import array
from pathlib import Path

serial, mpiio, step = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
print(f"step {step}, MPI-IO vs serial I/O:")

mpiio_file = mpiio / "restart_data" / f"lustre_{step}.dat"
if not mpiio_file.exists():
    sys.exit(f"  {mpiio_file} was never written")

# MPI-IO writes one file with all variables one after another; serial I/O writes one file per variable,
# as a Fortran record (4-byte length, data, 4-byte length).
mpiio_data = array("d", mpiio_file.read_bytes())
nvars = len(list((serial / "p_all" / "p0" / step).glob("q_cons_vf*.dat")))
cells = len(mpiio_data) // nvars
wrong_vars = 0
for i in range(nvars):
    ref = array("d", (serial / "p_all" / "p0" / step / f"q_cons_vf{i + 1}.dat").read_bytes()[4:-4])
    got = mpiio_data[i * cells : (i + 1) * cells]
    wrong = sum(a != b for a, b in zip(ref, got))
    wrong_vars += wrong > 0
    # pre_process fills every cell, halo cells included, with -1e-6 before setting up the interior.
    filler = sum(a != b and b == -1e-6 for a, b in zip(ref, got))
    if not wrong:
        print(f"  variable {i + 1}: identical")
    elif filler:
        print(f"  variable {i + 1}: {wrong} of {cells} cells differ, {filler} of them hold -1e-6 (pre_process's halo filler)")
    else:
        print(f"  variable {i + 1}: {wrong} of {cells} cells differ")
sys.exit(1 if wrong_vars else 0)
