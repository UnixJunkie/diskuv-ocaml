OPAM Integration
================

Repositories
------------

Each Opam switch created by *Diskuv OCaml* uses the following repositories *in order*:

1. diskuv-0.2.0
2. fdopen-mingw-0.2.0 *only for Windows*
3. default

The ``diskuv-0.2.0`` repository has all the patches required for third-party OCaml packages
to support the Microsoft compiler. Any switch that is created by *Diskuv OCaml* will have
pinned versions for each package in this repository. That means you will always get the
*Diskuv OCaml* patched versions and reproducible behavior.

The ``fdopen-mingw-0.2.0`` repository has all the MinGW patches for _many_ third-party OCaml packages
to work with MinGW (an alternative compiler popular on Linux). Unlike ``diskuv-0.2.0`` the packages
are not pinned, so it is possible that a newer package version is introduced into your switch
that has no MinGW patches.

.. note::

    If you suspect a stale fdopen repository is causing you problems, run ``opam repository list``
    to find where the repository is physically located and then look in its ``packages/`` subdirectory
    to see what versions of your problematic package are supported by the fdopen repository.
    ``opam list`` will tell you which versions you are currently using. An issue can be filed at
    https://gitlab.com/diskuv/diskuv-ocaml/-/issues to move the package into an upcoming
    ``diskuv-*`` repository.

The ``default`` repository is the central Opam repository. Most of your packages are unpatched and
will come directly from this repository.

opam root
---------

Each `Opam root <http://opam.ocaml.org/doc/Manual.html#opam-root>`_ created by *Diskuv OCaml* includes
a plugin directory ``OPAMROOT/plugins/diskuvocaml/``.

For Unix systems it is empty.

For Windows systems it contains `pkg-config <https://en.wikipedia.org/wiki/Pkg-config>`_
necessary for a few OCaml packages with C bindings.

Global Variables
----------------

.. note::

    Refer to the `Opam Manual "Variables" documentation <http://opam.ocaml.org/doc/Manual.html#Variables>`_
    if you are not familiar with Opam variables.

The global variables that will be present in a Diskuv OCaml installation are:

.. code-block:: text

    <><> Global opam variables ><><><><><><><><><><><><><><><><><><><><><><><><><><>
    arch              x86_64                                                     # Inferred from system
    exe               .exe                                                       # Suffix needed for executable filenames (Windows)
    jobs              11                                                         # The number of parallel jobs set up in opam configuration
    make              make                                                       # The 'make' command to use
    opam-version      2.1.0                                                      # The currently running opam version
    os                win32                                                      # Inferred from system
    os-distribution   win32                                                      # Inferred from system
    os-family         windows                                                    # Inferred from system
    os-version        10.0.22000                                                 # Inferred from system
    root              C:\Users\you\.opam                                         # The current opam root directory
    switch            C:\Users\you\AppData\Local\Programs\DiskuvOCaml\1\system   # The identifier of the current switch
    sys-ocaml-arch    x86_64                                                     # Target architecture of the OCaml compiler present on your system
    sys-ocaml-cc      msvc                                                       # Host C Compiler type of the OCaml compiler present on your system
    sys-ocaml-libc    msvc                                                       # Host C Runtime Library type of the OCaml compiler present on your system
    sys-ocaml-version 4.12.0                                                     # OCaml version present on your system independently of opam, if any

.. note::

    Stay tuned; we need a consult with the Opam team to figure out what to put into ``os-distribution`` (``msys2`` or ``diskuvocaml``?).
    Apparently ``cygwinports`` is a thing and used a filter in
    `ctypes-foreign <https://github.com/ocamllabs/ocaml-ctypes/blob/261fe071fad17ab323d8d2b82df2aec593e64e3f/ctypes-foreign.opam#L13>`_.
    Something similar may be good for you.

Working with Native Windows
---------------------------

.. note::

    This section of the documentation is for OCaml package maintainers (anyone who creates an OCaml package
    for public consumption).

As an OCaml package maintainer you may want to customize the way your package builds if you are on native
Windows. Native Windows installations differ from Cygwin Windows installations because Cygwin is a reasonably
complete POSIX environment. You may need a few tweaks including but not limited to:

* translating Windows paths into Unix paths (usually only a problem if you are using absolute paths)
* use Windows libraries rather than Unix libraries
* use ``LOCALAPPDATA`` rather than ``HOME`` to locate the user's home directory

Typically you will customize your package build behavior with either
`Opam Filters <https://opam.ocaml.org/doc/Manual.html#Filters>`_ (the topic of this section)
or with `Dune Configuration <https://dune.readthedocs.io/en/stable/dune-libs.html>`_.

In this section we try to be distribution-agnostic. That means we will present
techniques you can use even if your native Windows users are not using *Diskuv OCaml*.

Use the following Opam filter in your ``*.opam`` files to detect **native Windows** installations:

.. code-block:: text

    { os-family = "win32" & sys-ocaml-cc = "msvc" }
