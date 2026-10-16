! shear.f90: does MPI-IO get the interior of a halo-padded array, or the raw memory around it?
!
! MFC stores every field with halo (ghost) cells around the interior and gives its MPI-IO calls
! a pointer to the interior only (MPI_IO_DATA%var(i)%sf => q_cons_vf(i)%sf(0:m,0:n,0:p)). That
! interior is not contiguous in memory. If the compiler hands the pointer to MPI without packing
! it first, MPI reads and writes plain memory from the start of the whole padded array, halo
! included: the file holds halo values and displaced interior values ("sheared"), and reading
! a file back puts the values into the wrong cells, halo cells included.
!
! This program does the same with a tiny array (8 x 6 x 4 interior, halo of 2 cells) whose
! interior cells hold a value computed from their own index, so every value can be checked.
! It tries six ways of passing the interior to MPI:
!   A  write through the pointer, as MFC does today
!   B  write a contiguous copy of the interior
!   C  write the array section q(0:m,0:n,0:p) directly
!   D  read a correct file back through the pointer, as MFC reads its restart data
!   E  write through a section of the pointer, sf(:,:,:), the fix in this PR
!   F  read back through sf(:,:,:)
! Each line of output counts the correct values and ends in "correct" or "SHEARED".
!
! Build and run (one process is enough, no GPU needed):
!   mpifort -O2 -o shear shear.f90 && mpirun -n 1 ./shear
! With nvfortran 25.7 and Open MPI 5.0.10 built with it: A and D SHEARED, B, C, E, F correct.
program shear
    use mpi
    use iso_fortran_env, only: compiler_version
    implicit none
    integer, parameter :: m = 7, n = 5, p = 3, b = 2          ! interior 0:m,0:n,0:p; halo b
    integer, parameter :: nint = (m + 1)*(n + 1)*(p + 1)
    real(8), parameter :: fill = -1.0d-6                       ! MFC's ghost-cell filler
    real(8), allocatable, target :: q(:, :, :)
    real(8), pointer :: interior(:, :, :)
    real(8), allocatable :: copy(:, :, :)
    integer :: ierr, nproc, i, j, k, ftype, fh, sizes(3), starts(3), nright, nhalo, len
    character(len=MPI_MAX_LIBRARY_VERSION_STRING) :: libver

    call MPI_INIT(ierr)
    call MPI_COMM_SIZE(MPI_COMM_WORLD, nproc, ierr)
    if (nproc /= 1) stop "run this with ONE process"
    call MPI_GET_LIBRARY_VERSION(libver, len, ierr)
    print '(a)', "compiler: "//trim(compiler_version())
    print '(a)', "MPI:      "//trim(libver(1:min(len, 60)))
    print '(a,i0,a)', "interior ", nint, " cells, each holding its own index; halo cells hold -1e-6"
    print *

    allocate (q(-b:m + b, -b:n + b, -b:p + b))
    call fill_interior()

    sizes = [m + 1, n + 1, p + 1]
    starts = 0
    call MPI_TYPE_CREATE_SUBARRAY(3, sizes, sizes, starts, MPI_ORDER_FORTRAN, &
                                  MPI_DOUBLE_PRECISION, ftype, ierr)
    call MPI_TYPE_COMMIT(ftype, ierr)

    ! ---- A: the pointer to the interior, MFC's way
    interior => q(0:m, 0:n, 0:p)
    call open_for_writing("A.dat")
    call MPI_FILE_WRITE_ALL(fh, interior, nint, MPI_DOUBLE_PRECISION, MPI_STATUS_IGNORE, ierr)
    call MPI_FILE_CLOSE(fh, ierr)
    call check_file("A.dat", "A  pointer to the interior (MFC's way)   ")

    ! ---- B: a contiguous copy
    allocate (copy(0:m, 0:n, 0:p))
    copy = q(0:m, 0:n, 0:p)
    call open_for_writing("B.dat")
    call MPI_FILE_WRITE_ALL(fh, copy, nint, MPI_DOUBLE_PRECISION, MPI_STATUS_IGNORE, ierr)
    call MPI_FILE_CLOSE(fh, ierr)
    call check_file("B.dat", "B  contiguous copy of the interior       ")

    ! ---- C: the array section itself
    call open_for_writing("C.dat")
    call MPI_FILE_WRITE_ALL(fh, q(0:m, 0:n, 0:p), nint, MPI_DOUBLE_PRECISION, MPI_STATUS_IGNORE, ierr)
    call MPI_FILE_CLOSE(fh, ierr)
    call check_file("C.dat", "C  the array section as the argument     ")

    ! ---- D: read B's (correct) file back through the pointer, as the simulation does
    q = fill
    call MPI_FILE_OPEN(MPI_COMM_WORLD, "B.dat", MPI_MODE_RDONLY, MPI_INFO_NULL, fh, ierr)
    call MPI_FILE_SET_VIEW(fh, 0_MPI_OFFSET_KIND, MPI_DOUBLE_PRECISION, ftype, 'native', MPI_INFO_NULL, ierr)
    call MPI_FILE_READ_ALL(fh, interior, nint, MPI_DOUBLE_PRECISION, MPI_STATUS_IGNORE, ierr)
    call MPI_FILE_CLOSE(fh, ierr)
    nright = 0
    nhalo = 0
    do k = 0, p; do j = 0, n; do i = 0, m
        if (q(i, j, k) == expected(i, j, k)) nright = nright + 1
    end do; end do; end do
    nhalo = count(q /= fill) - count(q(0:m, 0:n, 0:p) /= fill)
    print '(a,i0,a,i0,a,i0,a)', "D  reading back through the pointer       : ", nright, " of ", nint, &
        " interior cells correct, ", nhalo, " halo cells overwritten" // verdict(nright == nint .and. nhalo == 0)


    ! ---- E: a whole-array section of the pointer, the smallest change MFC could make
    call fill_interior()
    call open_for_writing("E.dat")
    call MPI_FILE_WRITE_ALL(fh, interior(:, :, :), nint, MPI_DOUBLE_PRECISION, MPI_STATUS_IGNORE, ierr)
    call MPI_FILE_CLOSE(fh, ierr)
    call check_file("E.dat", "E  section of the pointer, sf(:,:,:)     ")

    ! ---- F: reading back through a section of the pointer
    q = fill
    call MPI_FILE_OPEN(MPI_COMM_WORLD, "B.dat", MPI_MODE_RDONLY, MPI_INFO_NULL, fh, ierr)
    call MPI_FILE_SET_VIEW(fh, 0_MPI_OFFSET_KIND, MPI_DOUBLE_PRECISION, ftype, 'native', MPI_INFO_NULL, ierr)
    call MPI_FILE_READ_ALL(fh, interior(:, :, :), nint, MPI_DOUBLE_PRECISION, MPI_STATUS_IGNORE, ierr)
    call MPI_FILE_CLOSE(fh, ierr)
    nright = 0
    do k = 0, p; do j = 0, n; do i = 0, m
        if (q(i, j, k) == expected(i, j, k)) nright = nright + 1
    end do; end do; end do
    nhalo = count(q /= fill) - count(q(0:m, 0:n, 0:p) /= fill)
    print '(a,i0,a,i0,a,i0,a)', "F  reading back through sf(:,:,:)         : ", nright, " of ", nint, &
        " interior cells correct, ", nhalo, " halo cells overwritten" // verdict(nright == nint .and. nhalo == 0)

    call MPI_FINALIZE(ierr)

contains

    real(8) function expected(i, j, k)
        integer, intent(in) :: i, j, k
        expected = i + 100*j + 10000*k
    end function expected

    subroutine fill_interior()
        q = fill
        do k = 0, p; do j = 0, n; do i = 0, m
            q(i, j, k) = expected(i, j, k)
        end do; end do; end do
    end subroutine fill_interior

    subroutine open_for_writing(name)
        character(len=*), intent(in) :: name
        call MPI_FILE_OPEN(MPI_COMM_WORLD, name, MPI_MODE_CREATE + MPI_MODE_WRONLY, MPI_INFO_NULL, fh, ierr)
        call MPI_FILE_SET_VIEW(fh, 0_MPI_OFFSET_KIND, MPI_DOUBLE_PRECISION, ftype, 'native', MPI_INFO_NULL, ierr)
    end subroutine open_for_writing

    ! Read the file as a plain stream of doubles and compare with the interior in
    ! Fortran order, which is what the subarray view promises.
    subroutine check_file(name, label)
        character(len=*), intent(in) :: name, label
        real(8) :: got(nint)
        integer :: u, idx, right, filler
        open (newunit=u, file=name, access='stream', form='unformatted', status='old')
        read (u) got
        close (u)
        right = 0
        filler = 0
        idx = 0
        do k = 0, p; do j = 0, n; do i = 0, m
            idx = idx + 1
            if (got(idx) == expected(i, j, k)) right = right + 1
            if (got(idx) == fill) filler = filler + 1
        end do; end do; end do
        print '(a,a,i0,a,i0,a,i0,a)', label, ": ", right, " of ", nint, " values correct, ", filler, &
            " are halo filler" // verdict(right == nint)
    end subroutine check_file

    function verdict(ok) result(text)
        logical, intent(in) :: ok
        character(len=16) :: text
        if (ok) then
            text = "   -> correct"
        else
            text = "   -> SHEARED"
        end if
    end function verdict

end program shear
