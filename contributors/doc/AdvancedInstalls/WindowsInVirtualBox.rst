.. _Advanced - Windows in VirtualBox:

Windows 10 on macOS/Linux with VirtualBox
=========================================

    Even if you don't have a Windows PC you can use a virtual machine to run a "evaluation" Microsoft licensed copy of
    Windows. It requires some effort on your part: you will be able to use the virtual machine for approximately one month,
    and then you will need reinstall the virtual machine with a new evaluation license. But this is a great method
    if you have a Linux or macOS computer and need to test out whether your source code compiles and runs correctly on
    a Windows (virtual) machine.

.. sidebar:: macOS with Apple M1 chips is not supported

    You will need to have an Intel chip for macOS.
    As of August 2021 neither VirtualBox nor VMWare Fusion support 64-bit Windows on M1 chips. 
    Only Parallels 17 nominally supports Windows on M1 chips, but that is for
    the little-used Windows 10 ARM which is not supported by Diskuv.

1. Install `VirtualBox <https://www.virtualbox.org/wiki/Downloads>`_ if you have not done so already.

   * Version 6.1.26 of VirtualBox has been tested.

2. Go to `Microsoft's Get a Windows 10 development environment webpage <https://developer.microsoft.com/en-us/windows/downloads/virtual-machines/>`_
   and download the **VirtualBox** VM:

   .. image:: microsoft-vm.png
        :width: 600

   Then extract the contents of the downloaded ``.zip`` file. It will contain a single file named ``WinDevXXXXEval.ova``.

3. Open / double-click the ``WinDevXXXXEval.ova`` file. It should automatically launch VirtualBox in an "Import Virtual Appliance"
   window. You can proceed to step 4.

   If VirtualBox doesn't automatically open, then launch VirtualBox, press **Import** virtual machine
   in the screen below, and select the ``WinDevXXXXEval.ova`` file:

    .. image:: virtualbox1.png
        :width: 400

4. Accept all the defaults and press **Import**:

    .. image:: virtualbox2.png
        :width: 400

After starting the virtual machine, you can complete the :ref:`How to Install` instructions.
