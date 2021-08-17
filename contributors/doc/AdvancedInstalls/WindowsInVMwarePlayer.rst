.. _Advanced - Windows in VMware Player:

Windows 10 on Linux with VMware Player
======================================

1. Install `VMware Player <https://www.vmware.com/products/workstation-player.html>`_ if you have not done so already.

   * Version 16.1.2 of VMware Player has been tested.
   * If you have WSL 2 on your PC, you may be asked on the "Compatible Setup" screen if you want to install
     Windows Hypervisor Platform (WHP) automatically. Click to enable it:

   .. image:: vmware-whp.png
        :width: 600


2. Go to `Microsoft's Get a Windows 10 development environment webpage <https://developer.microsoft.com/en-us/windows/downloads/virtual-machines/>`_
   and download the **VMWare** VM:

   .. image:: microsoft-vm.png
        :width: 600

   Then extract the contents of the downloaded ``.zip`` file. It will contain three (3) files named ``WinDevXXXXEval{.mf,.ovf,-disk1.vmdk}``.

3. Open / double-click the ``WinDevXXXXEval.ovf`` file. It should automatically launch VMware and ask you where to save virtual machine.

After starting the virtual machine, you can complete the :ref:`How to Install` instructions.
