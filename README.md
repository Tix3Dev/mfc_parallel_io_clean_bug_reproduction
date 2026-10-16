# MFC parallel I/O: clean reproduction

This repo provides detailed information for [MFC PR #2085](https://github.com/MFlowCode/MFC/pull/2085). Additionally, it provides a docker file to fully reproduce the problem.

## TL;DR

- The PR solves exactly *one* problem: Incorrect passing of contiguous buffers to MPI-IO
- It only occurs when using Open MPI 5 + nvfortran
- It does not occur when using
  - Open MPI 5 + gfortran
  - Open MPI 4 + nvfortran
  - Open MPI 4 + gfortran (MFC current default in CI)
- The fix is compatible with all of the above build processes
- Crucially, this means *it does not negatively effect anything, rather it adds more support*, giving users of MFC more freedom and control - Choosing the right build process is an *important step when optimizing HPC applications for a given hardware setup*

## The bug and the fix

As part of configuring how to run a specific task in MFC, users may choose to set `"parallel_io": "T"` in the corresponding `case.py` file. This has massive benefits, allowing for drastically shorter runtimes and storage needs, compared to the sequential alternative provided by `"parallel_io": "F"`.

However, when using Open MPI 5 + nvfortran, `"parallel_io": "T"` leads to incorrect passing of contiguous buffers to MPI-IO. This causes wrong initial conditions for the simulation. Although the root cause is the same, the problem may show up at different stages of the execution. Concretely, we observed that when `"run_time_info": "F"` is set, the problem shows up early. As demonstrated with `3D_TaylorGreenVortex`, this leads to `VCFL is greater than 1.0`. On the contrary, with `"run_time_info": "F"`, it leads to `NaN(s) in timestep output`.

The underlying problem is that MFC passes MPI-IO a pointer to just the interior of a halo-padded field, which is not contiguous in memory ([example](https://github.com/MFlowCode/MFC/blob/47568a0f92559bd6965dee7bfcdb39e446d621e7/src/pre_process/m_data_output.fpp#L593)). Whether that works depends on how Open MPI's `use mpi` declares the buffer argument. Configure picks that declaration per compiler, and for nvfortran:

- **Open MPI 4** ([`ompi_fortran_check_ignore_tkr.m4`](https://github.com/open-mpi/ompi/blob/v4.1.6/config/ompi_fortran_check_ignore_tkr.m4)): `!DIR$ IGNORE_TKR` with `real, dimension(*)`. The buffer is an array, so nvfortran passes a contiguous copy of the interior, and the call works.
- **Open MPI 5** ([`ompi_fortran_check_ignore_tkr.m4`](https://github.com/open-mpi/ompi/blob/v5.0.10/config/ompi_fortran_check_ignore_tkr.m4)): `!DIR$ IGNORE_TKR` with `type(*)`. The buffer is a scalar, so nvfortran passes only the address of the first interior cell. MPI then reads and writes the consecutive memory from there, halo cells included.

The fix is to pass `sf(:,:,:)` instead of `sf`. With both Open MPI 4 and 5, nvfortran then copies the interior into a contiguous buffer before the call. Open MPI 4 already got that copy, so the change is backwards compatible and the results stay the same.

## Reproduction

For all MFC examples, we use serial I/O as ground truth, as it always works.

This section demonstrates the fundamental issue using a minimal working example which is independent of MFC, and then also demonstrate two examples (`3D_IGR_jet` and `3D_TaylorGreenVortex`) of how it concretely manifests itself in MFC. More precisely, it shows the failure in stock MFC (master), the resolution using the fix (PR #2085), and proof that the fix does not break the default MFC bundled MPI approach.

Note that all MFC examples are stock (both use `"parallel_io": "T"`, `3D_IGR_jet` uses `"run_time_info": "F"` and `3D_TaylorGreenVortex` uses `"run_time_info": "T"`), except for case 9, which uses `"run_time_info": "F"`.

To reproduce the required environment:
```
docker build -t mfc-pio-repro .
```

### Demo

To reproduce the demo:
```
docker run -it --name mfc-pio-demo mfc-pio-repro
```

This will leave you in the shell inside the container, where you can find all the logs and saved data:
```
/repro/
  MFC/                     the MFC checkout
  builds/<name>/           one MFC build each, with its build.log
  runs/
    1_mwe_.../             minimal example: output.txt, A.dat B.dat C.dat E.dat
    serial_<example>/      serial-I/O reference runs: case.json, log, D/, p_all/
    3_IGR_jet_.../         one MFC run each: case.json, log, D/, restart_data/
    ...
```

Concretely, these are the results:

| # | Case | MFC | MPI | Result |
| --- | --- | --- | --- | --- |
| 1 | minimal example | | bundled | all six variants correct |
| 2 | minimal example | | Open MPI 5.0.10 | A and D (MFC's way) `SHEARED`; E and F (`sf(:,:,:)`) correct |
| 3 | `3D_IGR_jet` | master | Open MPI 5.0.10 | initial condition wrong; `NaN(s) in timestep output` at the save |
| 4 | `3D_IGR_jet` | PR #2085 | Open MPI 5.0.10 | identical to serial I/O |
| 5 | `3D_IGR_jet` | PR #2085 | bundled | identical to serial I/O |
| 6 | `3D_TaylorGreenVortex` | master | Open MPI 5.0.10 | initial condition wrong; `VCFL is greater than 1.0` at step 1 |
| 7 | `3D_TaylorGreenVortex` | PR #2085 | Open MPI 5.0.10 | identical to serial I/O |
| 8 | `3D_TaylorGreenVortex` | PR #2085 | bundled | identical to serial I/O |
| 9 | `3D_TaylorGreenVortex`, changed to `run_time_info = F` | master | Open MPI 5.0.10 | initial condition wrong; `NaN(s) in timestep output` at the save |


### Sanity check

To prove that the bug is not an artifact resulting from incorrectly setting up the build system, we ensured `build_openmpi.sh` is agnostic to the version, so the exact same script to build Open MPI 4 and 5 is used (`$version` is the only parameter that is changed).

In other words, the exact same build system that builds Open MPI 4 from scratch, and that behaves exactly like bundled Open MPI 4, is also used for Open MPI 5, where the problem occurs.

To reproduce the sanity check:
```
docker run -it --name mfc-pio-sanity mfc-pio-repro sanity_check_openmpi4.sh
```

Concretely, these are the results:

| # | Case | MPI | Result |
| --- | --- | --- | --- |
| 1 | minimal example | bundled | all six variants correct |
| 2 | minimal example | Open MPI 4.1.6 | all six variants correct, A and D (MFC's way) included |
| 3 | `3D_IGR_jet`, master | Open MPI 4.1.6 | identical to serial I/O |
| 4 | `3D_IGR_jet`, master | bundled | identical to serial I/O |
| 5 | `3D_TaylorGreenVortex`, master | Open MPI 4.1.6 | identical to serial I/O |
| 6 | `3D_TaylorGreenVortex`, master | bundled | identical to serial I/O |

## Acknowledgments

The fix was developed by Team RACKlette (ETH Zürich) as part of the Student Cluster Competition (SCC) at SC26.
