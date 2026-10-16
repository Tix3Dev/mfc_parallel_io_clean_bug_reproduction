# MFC PR #2085: NVIDIA HPC SDK 25.7 plus upstream Open MPI 5.0.10 and 4.1.6, both built with it the same way.
FROM nvcr.io/nvidia/nvhpc:25.7-devel-cuda12.9-ubuntu24.04

# What MFC needs to build (the packages MFC's own NVHPC CI installs).
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        cmake python3 python3-venv python3-pip git curl libfftw3-dev

# The two Open MPI releases, each checked against the SHA-256 published on open-mpi.org.
COPY build_openmpi.sh /repro/
RUN bash /repro/build_openmpi.sh 5.0.10 5692cc80554a7117c99eaa725d35100edd8bbf73423a5e265ff867979192df7d \
 && bash /repro/build_openmpi.sh 4.1.6 44da277b8cdc234e71c62473305a09d63f4dcca292ca40335aab7c4bf0e6a566

# Containers run as root, which Open MPI refuses by default.
ENV OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

COPY shear.f90 compare.py lib.sh demo.sh sanity_check_openmpi4.sh start.sh /repro/
WORKDIR /repro
# NVIDIA's entry point (banner), then start.sh with the script to run: demo.sh unless another one is given.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh", "bash", "/repro/start.sh"]
CMD ["demo.sh"]
