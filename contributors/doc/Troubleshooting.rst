Troubleshooting
===============

Problem - vendor/diskuv-ocaml/runtime/unix/standard.mk: No such file or directory
---------------------------------------------------------------------------------

Root Cause
~~~~~~~~~~

This is typically an indication that your git repository was not cloned with
the recursive flag, as in:

.. code-block:: bash

    git clone https://github.com/diskuv/diskuv-ocaml-starter

instead of the correct:

.. code-block:: bash

    git clone --recursive https://github.com/diskuv/diskuv-ocaml-starter

When you leave out the ``--recursive`` option then Git will not fetch any
of the submodules. Diskuv OCaml requires that you load it as a Git submodule.

Solution
~~~~~~~~

Run:

.. code-block:: bash

    git submodule update --init --recursive
