Local Projects
==============

Standard Layout
---------------

The ``diskuv-ocaml-starter`` is an example of the standard layout that looks like:

::

    TODO - Add in a ``tree`` diagram.

    dune-project

Setting Up An Existing Git Repository As a Local Project
--------------------------------------------------------

The directory structure does _not_ need to look like the standard layout.

The requirements are:

1. There must be a ``dune-project`` in an ancestor directory of the ``diskuv-ocaml-starter`` Git submodule.
   For example, it is fine to have:

   ::

        .git/
        .gitmodules
        a/
            b/
                dune-project
                src/
                    c/
                        d/
                            diskuv-ocaml-starter/

2. 

Upgrading
---------

Run:

.. code-block:: PowerShell

    .\vendor\diskuv-ocaml\runtime\windows\upgrade.ps1

If there is an upgrade of ``Diskuv OCaml`` available it will automate as much as possible,
and if necessary give you further instructions to complete the upgrade.
