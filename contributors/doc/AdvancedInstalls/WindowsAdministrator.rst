.. _Advanced - Windows Administrator:

Windows Administrator Installation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The *Diskuv OCaml* distribution includes a `setup-machine.ps1 <https://github.com/diskuv/diskuv-ocaml/blob/main/installtime/windows/setup-machine.ps1>`_
PowerShell script that will ask for elevated
Administrator permissions to install the Microsoft C compiler (the "MSBuild" components of Visual Studio).
As an Administrator you can run that PowerShell script once, and the non-Administrator users on your PCs will be able
to read and complete the same *Diskuv OCaml* instructions as everybody else.

The Administrator portion takes 2GB of disk space while each user can take up to 25GB of disk space in their User
Profiles (``$env:USERPROFILE\Programs\DiskuvOCaml`` and ``$env:USERPROFILE\.opam``) just for the basic *Diskuv OCaml*
distribution. Please plan accordingly.

