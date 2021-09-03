<#
.Synopsis
    Set up all programs and data folders that are shared across
    all users on the machine.
.Description
    Installs Git for Windows 2.33.0.
    Installs the MSBuild component of Visual Studio.
.Parameter $ParentProgressId
    The PowerShell progress identifier. Optional, defaults to -1.
    Use when embedding this script within another setup program
    that reports its own progress.
.Parameter $SkipAutoUpgradeGitWhenOld
    Ordinarily if Git for Windows is installed on the machine but
    it is less than version 1.7.2 then Git for Windows 2.33.0 is
    installed which will replace the old version.

    Git 1.7.2 includes supports for git submodules that are necessary
    for Diskuv OCaml to work.

    Git for Windows is detected by running `git --version` from the
    PATH and checking to see if the version contains ".windows."
    like "git version 2.32.0.windows.2". Without this switch
    this script may detect a Git installation that is not Git for
    Windows, and you will end up installing an extra Git for Windows
    2.33.0 installation instead of upgrading the existing Git for
    Windows to 2.33.0.

    Even with this switch is selected, Git 2.33.0 will be installed
    if there is no Git available on the PATH.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [int]
    $ParentProgressId = -1,
    [switch]
    $SkipAutoInstallMsBuild
)

$ErrorActionPreference = "Stop"

$HereScript = $MyInvocation.MyCommand.Path
$HereDir = (get-item $HereScript).Directory
$DkmlPath = $HereDir.Parent.Parent.FullName
if (!(Test-Path -Path $DkmlPath\.dkmlroot)) {
    throw "Could not locate where this script was in the project. Thought DkmlPath was $DkmlPath"
}

$env:PSModulePath += ";$HereDir"
Import-Module Deployers
Import-Module Project
Import-Module Machine

# ----------------------------------------------------------------
# Progress Reporting

$global:ProgressStep = 0
$global:ProgressActivity = $null
$ProgressTotalSteps = 2
$ProgressId = $ParentProgressId + 1
function Write-ProgressStep {
    if (!$global:SkipProgress) {
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
    }
    $global:ProgressStep += 1
}
function Write-ProgressCurrentOperation {
    param(
        $CurrentOperation
    )
    if (!$global:SkipProgress) {
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -Status $global:ProgressStatus `
            -CurrentOperation $CurrentOperation `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
    }
}

# ----------------------------------------------------------------
# QUICK EXIT if already current version already deployed


# ----------------------------------------------------------------
# BEGIN Start deployment

$global:ProgressActivity = "Starting ..."
$global:ProgressStatus = "Starting ..."

# We use "deployments" for any temporary directory we need since the
# deployment process handles an aborted setup and the necessary cleaning up of disk
# space (eventually).
$TempParentPath = "$Env:temp\diskuvocaml\setupmachine"
$TempPath = Start-BlueGreenDeploy -ParentPath $TempParentPath -DeploymentId $MachineDeploymentId -LogFunction ${function:\Write-ProgressCurrentOperation}

# END Start deployment
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# BEGIN Visual Studio Setup PowerShell Module

$global:ProgressActivity = "Install Visual Studio Setup PowerShell Module"
Write-ProgressStep

Import-VSSetup -TempPath "$TempPath\vssetup"
$ExistingVisualStudio = Get-CompatibleVisualStudio -ErrorIfNotFound:$(-not $SkipAutoInstallMsBuild)

# END Visual Studio Setup PowerShell Module
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# BEGIN Visual Studio Build Tools

# MSBuild 2015+ is the command line tools of Visual Studio.
#
# > Visual Studio Code is a very different product from Visual Studio 2015+. Do not confuse
# > the products if you need to install it! They can both be installed, but for this section
# > we are talking abobut Visual Studio 2015+ (ex. Visual Studio Community 2019).
#
# > Why MSBuild / Visual Studio 2015+? Because [vcpkg](https://vcpkg.io/en/getting-started.html) needs
# > Visual Studio 2015 Update 3 or newer as of July 2021.
#
# It is generally safe to run multiple MSBuild and Visual Studio installations on the same machine.
# The one in `C:\DiskuvOCaml\BuildTools` is **reserved** for our build system as it has precise
# versions of the tools we need.
#
# You can **also** install Visual Studio 2015+ which is the full GUI.
#
# Much of this section was adapted from `C:\Dockerfile.opam` while running
# `docker run --rm -it ocaml/opam:windows-msvc`.
#
# Key modifications:
# * We do not use C:\BuildTools but $env:SystemDrive\DiskuvOCaml\BuildTools instead
#   because C:\ may not be writable and avoid "BuildTools" since it is a known directory
#   that can create conflicts with other
#   installations (confer https://docs.microsoft.com/en-us/visualstudio/install/build-tools-container?view=vs-2019)
# * This is meant to be idempotent so we "modify" and not just install.
# * We've added/changed some components especially to get <stddef.h> C header (actually, we should inform
#   ocaml-opam so they can mimic the changes)

$global:ProgressActivity = "Install Visual Studio Build Tools"
Write-ProgressStep

if (($ExistingVisualStudio | Measure-Object).Count -eq 1) {
    $VsInstallTempPath = "$TempPath\vsinstall"

    if (!(Test-Path -Path $env:SystemDrive\DiskuvOCaml\BuildTools\MSBuild\Current\Bin\MSBuild.exe) -or
        !(Test-Path -Path "${env:ProgramFiles(x86)}\Windows Kits\10\Include\*" -Include "10.*.$Windows10SdkVer.*" -PathType Container)) {
        # Download tools we need to install MSBuild
        if ([Environment]::Is64BitOperatingSystem) {
            $VsArch = "x64"
        } else {
            $VsArch = "x86"
        }
        if (!(Test-Path -Path $VsInstallTempPath)) { New-Item -Path $VsInstallTempPath -ItemType Directory | Out-Null }
        if (!(Test-Path -Path $VsInstallTempPath\vc_redist.$VsArch.exe)) { Invoke-WebRequest -Uri https://aka.ms/vs/16/release/vc_redist.$VsArch.exe -OutFile $VsInstallTempPath\vc_redist.$VsArch.exe }
        if (!(Test-Path -Path $VsInstallTempPath\collect.exe)) { Invoke-WebRequest -Uri https://aka.ms/vscollect.exe                   -OutFile $VsInstallTempPath\collect.exe }
        if (!(Test-Path -Path $VsInstallTempPath\VisualStudio.chman)) { Invoke-WebRequest -Uri https://aka.ms/vs/16/release/channel           -OutFile $VsInstallTempPath\VisualStudio.chman }
        if (!(Test-Path -Path $VsInstallTempPath\vs_buildtools.exe)) { Invoke-WebRequest -Uri https://aka.ms/vs/16/release/vs_buildtools.exe -OutFile $VsInstallTempPath\vs_buildtools.exe }

        if (!(Test-Path -Path $VsInstallTempPath\Install.orig.cmd)) { Invoke-WebRequest -Uri https://raw.githubusercontent.com/MisterDA/Windows-OCaml-Docker/d3a107132f24c05140ad84f85f187e74e83e819b/Install.cmd -OutFile $VsInstallTempPath\Install.orig.cmd }
        if (!(Test-Path -Path $VsInstallTempPath\Install.cmd) -or
            (Test-Path -Path $VsInstallTempPath\Install.orig.cmd -NewerThan (Get-Item $VsInstallTempPath\Install.cmd).LastWriteTime)) {
            $content = Get-Content -Path $VsInstallTempPath\Install.orig.cmd
            $content = $content -replace "C:\\TEMP", "$VsInstallTempPath"
            $content = $content -replace "C:\\vslogs.zip", "$VsInstallTempPath\vslogs.zip"
            $content | Set-Content -Path $VsInstallTempPath\Install.cmd
        }

        # Create destination directory
        if (!(Test-Path -Path $env:SystemDrive\DiskuvOCaml)) { New-Item -Path $env:SystemDrive\DiskuvOCaml -ItemType Directory | Out-Null }

        # See how to use vs_buildtools.exe at
        # https://docs.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2019

        # Components:
        # https://docs.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-build-tools?view=vs-2019
        #
        # * Microsoft.VisualStudio.Component.VC.Tools.x86.x64
        #   - VS 2019 C++ x64/x86 build tools (Latest)
        # * Microsoft.VisualStudio.Component.Windows10SDK.18362
        #   - Windows 10 SDK (10.0.18362.0)
        #   - Same version in ocaml-opam Docker image as of 2021-10-10
        $CommonArgs = @(
            "--wait",
            "--passive", "--norestart",
            "--nocache",
            "--installPath", "$env:SystemDrive\DiskuvOCaml\BuildTools",
            "--channelUri", "$VsInstallTempPath\VisualStudio.chman",
            "--installChannelUri", "$VsInstallTempPath\VisualStudio.chman",
            "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "--add", "Microsoft.VisualStudio.Component.Windows10SDK.$Windows10SdkVer"
        )
        if (Test-Path -Path $env:SystemDrive\DiskuvOCaml\BuildTools\MSBuild\Current\Bin\MSBuild.exe) {
            $proc = Start-Process -FilePath $VsInstallTempPath\Install.cmd -NoNewWindow -Wait -PassThru `
                -ArgumentList (@("$VsInstallTempPath\vs_buildtools.exe", "modify") + $CommonArgs)
        }
        else {
            $proc = Start-Process -FilePath $VsInstallTempPath\Install.cmd -NoNewWindow -Wait -PassThru `
                -ArgumentList (@("$VsInstallTempPath\vs_buildtools.exe") + $CommonArgs)
        }
        $exitCode = $proc.ExitCode
        if ($exitCode -eq 3010) {
            Write-Warning "Microsoft Visual Studio Build Tools installation succeeded but a reboot is required!"
            Start-Sleep 5
            Write-Host ''
            Write-Host 'Press any key to exit this script... You must reboot!';
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
            throw
        }
        elseif ($exitCode -ne 0) {
            Write-Error "Microsoft Visual Studio Build Tools installation failed! Exited with $exitCode."
            throw
        }
    }
}

# Reconfirm the install was detected
if (($ExistingVisualStudio | Measure-Object).Count -eq 0) {
    Write-Error (
        "No compatible Visual Studio installation detected after the Visual Studio installation! " +
        "Please file a Bug Report with https://gitlab.com/diskuv/diskuv-ocaml/-/issues"
    )
    exit 1
}


# END Visual Studio Build Tools
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# BEGIN Stop deployment

Stop-BlueGreenDeploy -ParentPath $TempParentPath -DeploymentId $MachineDeploymentId # no -Success so always delete the temp directory

# END Stop deployment
# ----------------------------------------------------------------

Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $global:ProgressActivity -Completed
