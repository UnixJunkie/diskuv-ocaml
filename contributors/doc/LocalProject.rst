.. _Local Projects:

Local Projects
==============

By now you have entered some OCaml code into ``utop`` but some key features
were missing that you can get by creating/using a local project.

A local project is a folder that contains your source code, one or more sets
of packages (other people's code) and one or more build directories to store
your compiled code and applications.

By using a local project you will be able to:

* Install other people's code packages    
* Edit your source code in an IDE
* Build your source code into applications or libraries

This is easiest to see with an example.

1. Open PowerShell (press the Windows key ⊞, type "PowerShell" and then Open ``Windows PowerShell``).
2. Run the following in PowerShell:

   .. code-block:: ps1con

      PS1> cd ~\DiskuvOCamlProjects

      PS1> git clone https://gitlab.com/diskuv/diskuv-ocaml-starter.git

You now have a local project in ``~\DiskuvOCamlProjects\diskuv-ocaml-starter``.

We can compile the source code by running the ``build-dev`` target:

    .. code-block:: ps1con

       PS1> cd ~\DiskuvOCamlProjects\diskuv-ocaml-starter

       PS1> ./make build-dev

but many OCaml programs
will need to install more packages.  and/or compile C code.

We recommend you use a Diskuv OCaml
local project to do so. Here is a starter project that does that ...

*TODO*. This section needs to go into the "starter" project and work it through example or tutorial.

.. sidebar:: Visual Studio Code is optional.

  Using Visual Studio Code is optional but strongly recommended! The only other development environment
  that supports OCaml well is Emacs.

*TODO*. Be sure to include VS Code plugin. Include instructions to install VS Code (optional but strongly recommend) as well.

*TODO*. Be sure to open the terminal and do a build.

At this point you can do the first N chapters of Real World OCaml.

Finished? It is time to create your own projects and look at the starter project.


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

.. code-block:: ps1con

    PS1> .\vendor\diskuv-ocaml\runtime\windows\upgrade.ps1

If there is an upgrade of ``Diskuv OCaml`` available it will automate as much as possible,
and if necessary give you further instructions to complete the upgrade.
