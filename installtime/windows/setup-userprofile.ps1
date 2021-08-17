<#
.Synopsis
    Set up all programs and data folders in $env:USERPROFILE.
.Description
    Blue Green Deployments
    ----------------------

    OCaml package directories, C header "include" directories and other critical locations are hardcoded
    into essential OCaml executables like `ocamlc.exe` during `opam switch create` and `opam install`.
    We are forced to create the Opam switch in its final resting place. But now we have a problem since
    we can never install a new Opam switch; it would have to be on top of the existing "final" Opam switch, right?
    Wrong, as long as we have two locations ... one to compile any new Opam switch and another to run
    user software; once the compilation is done we can change the PATH, OPAMSWITCH, etc. to use the new Opam switch.
    That old Opam switch can still be used; in fact OCaml applications like the OCaml Language Server may still
    be running. But once you logout all new OCaml applications will be launched using the new PATH environment
    variables, and it is safe to use that old location for the next compile.
    The technique above where we swap locations is called Blue Green deployments.

    We would use Blue Green deployments even if we didn't have that hard requirement because it is
    safe for you (the system is treated as one atomic whole).

    A side benefit is that the new system can be compiled while you are still working. Since
    new systems can take hours to build this is an important benefit.

    One last complication. Opam global switches are subdirectories of the Opam root; we cannot change their location
    use the swapping Blue Green deployment technique. So we _do not_ use an Opam global switch for `diskuv-system`.
    We use external (aka local) Opam switches instead.

    MSYS2
    -----

    After the script completes, you can launch MSYS2 directly with:

    & $env:DiskuvOCamlHome\tools\MSYS2\msys2_shell.cmd

    `.\make.cmd` from a local project is way better though.
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

.Example
    PS> vendor\diskuv-ocaml\installtime\windows\setup-userprofile.ps1
#>

# Cygwin Rough Edges
# ------------------
#
# ALWAYS ALWAYS use Cygwin to create directories if they are _ever_ read from Cygwin.
# That is because Cygwin uses Windows ACLs attached to files and directories that
# native Windows executables and MSYS2 do not use. (See the 'BEGIN Remove extended ACL' script block)
#
# ONLY USE CYGWIN WITHIN THIS SCRIPT. See the above point about file permissions. If we limit
# the blast radius of launching Cygwin to this Powershell script, then we make auditing where
# file permissions are going wrong to one place (here!). AND we remove any possibility
# of Cygwin invoking MSYS which simply does not work by stipulating that Cygwin must only be used here.
#
# Troubleshooting: In Cygwin we can do 'setfacl -b ...' to remove extended ACL entries. (See https://cygwin.com/cygwin-ug-net/ov-new.html#ov-new2.4s)
# So `find build/ -print0 | xargs -0 --no-run-if-empty setfacl --remove-all --remove-default` would just leave ordinary
# POSIX permissions in the build/ directory (typically what we want!)
#
# Launch Cygwin directly with an appropriate selection below:
# & $env:DiskuvOCamlHome\tools\cygwin\bin\mintty.exe -
# & $env:DiskuvOCamlHome\tools\ocaml-opam\msvc-amd64\cygwin64\bin\mintty.exe -

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification='Conditional block based on Windows 32 vs 64-bit',
    Target="CygwinPackagesArch")]
[CmdletBinding()]
param (
    [Parameter()]
    [int]
    $ParentProgressId = -1,
    [switch]
    $SkipAutoUpgradeGitWhenOld
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
Import-Module UnixInvokers

# ----------------------------------------------------------------
# Prerequisite Check

if (!$global:Skip64BitCheck -and ![Environment]::Is64BitOperatingSystem) {
    # This might work on 32-bit Windows, but that hasn't been tested.
    # One missing item is whether there are 32-bit Windows ocaml/opam Docker images
    throw "DiskuvOCaml is only supported on 64-bit Windows"
}


# ----------------------------------------------------------------
# Progress declarations

$global:ProgressStep = 0
$global:ProgressActivity = $null
$ProgressTotalSteps = 15
$ProgressId = $ParentProgressId + 1
$global:ProgressStatus = $null

function Write-ProgressStep {
    if (!$global:SkipProgress) {
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
    }
    $global:ProgressStep += 1
}

# ----------------------------------------------------------------
# BEGIN Git for Windows

# Git is _not_ part of the Diskuv OCaml distribution per se; it is
# is a prerequisite that gets auto-installed. Said another way,
# it does not get a versioned installation like the rest of Diskuv
# OCaml. So we explicitly do version checks during the installation of
# Git.

$global:ProgressActivity = "Install Git for Windows"
Write-ProgressStep

$GitWindowsSetupAbsPath = "$env:TEMP\gitwindows"

$GitOriginalVersion = @(0, 0, 0)
$SkipGitForWindowsInstallBecauseNonGitForWindowsDetected = $false
$GitExists = $false
$GitExe = & where.exe /Q git
if ($LastExitCode -eq 0) {
    $GitExists = $true
    $GitResponse = & $GitExe --version
    if ($LastExitCode -eq 0) {
        # git version 2.32.0.windows.2 -> 2.32.0.windows.2
        $GitResponseLast = $GitResponse.Split(" ")[-1]
        # 2.32.0.windows.2 -> 2 32 0
        $GitOriginalVersion = $GitResponseLast.Split(".")[0, 1, 2]
        # check for '.windows.'
        $SkipGitForWindowsInstallBecauseNonGitForWindowsDetected = $GitResponse -notlike "*.windows.*"
    }
}
if (-not $SkipGitForWindowsInstallBecauseNonGitForWindowsDetected) {
    # Less than 1.7.2?
    $GitTooOld = ($GitOriginalVersion[0] -lt 1 -or
        ($GitOriginalVersion[0] -eq 1 -and $GitOriginalVersion[1] -lt 7) -or
        ($GitOriginalVersion[0] -eq 1 -and $GitOriginalVersion[1] -eq 7 -and $GitOriginalVersion[2] -lt 2))
    if ((-not $GitExists) -or ($GitTooOld -and -not $SkipAutoUpgradeGitWhenOld)) {
        # Install Git for Windows 2.33.0

        if ([Environment]::Is64BitOperatingSystem) {
            $GitWindowsBits = "64"
        } else {
            $GitWindowsBits = "32"
        }
        if (!(Test-Path -Path $GitWindowsSetupAbsPath)) { New-Item -Path $GitWindowsSetupAbsPath -ItemType Directory | Out-Null }
        if (!(Test-Path -Path $GitWindowsSetupAbsPath\Git-2.33.0-$GitWindowsBits-bit.exe)) { Invoke-WebRequest -Uri https://github.com/git-for-windows/git/releases/download/v2.33.0.windows.1/Git-2.33.0-$GitWindowsBits-bit.exe -OutFile $GitWindowsSetupAbsPath\Git-2.33.0-$GitWindowsBits-bit.exe }

        # You can see the arguments if you run: Git-2.33.0-$GitWindowsArch-bit.exe /?
        # https://jrsoftware.org/ishelp/index.php?topic=setupcmdline has command line options.
        # https://github.com/git-for-windows/build-extra/tree/main/installer has installer source code.
        $proc = Start-Process -FilePath "$GitWindowsSetupAbsPath\Git-2.33.0-$GitWindowsBits-bit.exe" -NoNewWindow -Wait -PassThru `
            -ArgumentList @("/SP-", "/SILENT", "/SUPPRESSMSGBOXES", "/CURRENTUSER", "/NORESTART")
        $exitCode = $proc.ExitCode
        if ($exitCode -ne 0) {
            Write-Warning "Git installer failed"
            Start-Sleep 5
            Write-Host ''
            Write-Host 'Press any key to exit this script...';
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
            throw
        }

        # Get new PATH so we can locate the new Git
        $OldPath = $env:PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $GitExe = & where.exe git
        if ($LastExitCode -ne 0) {
            throw "DiskuvOCaml requires that Git is installed in the PATH. The Git installer failed to do so. Please install it manually from https://gitforwindows.org/"
        }
        $env:PATH = $OldPath
    }
}
if (Test-Path -Path $GitWindowsSetupAbsPath) {
    Remove-Item -Path $GitWindowsSetupAbsPath -Recurse -Force
}

$GitPath = (get-item "$GitExe").Directory.FullName

# END Git for Windows
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# QUICK EXIT if already current version already deployed

# Magic constants that will identify new and existing deployments:
# * Immutable git tags
$AvailableOpamVersion = "2.1.0.msys2.4" # needs to be a real Opam tag in https://github.com/diskuv/opam!
$NinjaVersion = "1.10.2"
$CMakeVersion = "3.21.1"
$CygwinPackages = @("curl",
    "diff",
    "diffutils",
    "git",
    "m4",
    "make",
    "patch",
    "unzip",
    "python",
    "python3",
    "cmake",
    "cmake-gui",
    "ninja",
    "wget",
    # needed by this script (install-world.ps1)
    "dos2unix",
    # needed by Moby scripted Docker downloads (download-frozen-image-v2.sh)
    "jq")
if ([Environment]::Is64BitOperatingSystem) {
    $CygwinPackagesArch = $CygwinPackages + @("mingw64-x86_64-gcc-core",
    "mingw64-x86_64-gcc-g++",
    "mingw64-x86_64-headers",
    "mingw64-x86_64-runtime",
    "mingw64-x86_64-winpthreads")
}
else {
    $CygwinPackagesArch = $CygwinPackages + @("mingw64-i686-gcc-core",
        "mingw64-i686-gcc-g++",
        "mingw64-i686-headers",
        "mingw64-i686-runtime",
        "mingw64-i686-winpthreads")
}
$MSYS2Packages = @(
    # Hints:
    #  1. Use `MSYS2\msys2_shell.cmd -here` to launch MSYS2 and then `pacman -Ss diff` to
    #     search for example for 'diff' packages.
    #     You can also browse https://packages.msys2.org
    #  2. Instead of `pacman -Ss [search term]` you can use something like `pacman -Fy && pacman -F x86_64-w64-mingw32-as.exe`
    #     to find which package installs for example the `x86_64-w64-mingw32-as.exe` file.

    # ----
    # Needed to create native Opam executable in `opam-bootstrap`
    # ----

    # "mingw-w64-i686-openssl", "mingw-w64-x86_64-openssl",
    "mingw-w64-i686-gcc", "mingw-w64-x86_64-gcc",
    # "mingw-w64-cross-binutils", "mingw-w64-cross-gcc"

    # ----
    # Needed by ProjectPath/Makefile
    # ----

    "make",
    "diffutils",
    "dos2unix",

    # ----
    # Needed by Opam
    # ----

    # "git", # use Git for Windows so can have filesystem cache. Without it Opam can be very slow.
    "patch",
    "rsync",
    # "tar", # use C:\WINDOWS\System32\tar.exe instead which does not have MSYS2 ambiguous file path resolution. Available in all Windows SKUs since build 17063 (https://docs.microsoft.com/en-us/virtualization/community/team-blog/2017/20171219-tar-and-curl-come-to-windows)
    "unzip",

    # ----
    # Needed by many OCaml packages during builds
    # ----

    "pkgconf",

    # ----
    # Needed for our own sanity!
    # ----

    "psmisc", # process management tools: `pstree`
    "rlwrap", # command line history for executables without builtin command line history support
    "tree" # directory structure viewer
)
if ([Environment]::Is64BitOperatingSystem) {
    $MSYS2PackagesArch = $MSYS2Packages + @(
        # ----
        # Needed for our own sanity!
        # ----

        "mingw-w64-x86_64-ag" # search tool called Silver Surfer
    )
} else {
    $MSYS2PackagesArch = $MSYS2Packages + @(
        # ----
        # Needed for our own sanity!
        # ----

        "mingw-w64-i686-ag" # search tool called Silver Surfer
    )
}
$DistributionPackages = @(
    "dune.2.9.0", # already present from dune-configurator pinning
    "ocaml-lsp-server.1.7.0",
    "ocamlfind.1.9.1",
    "ocamlformat.0.19.0",
    "ocamlformat-rpc.0.19.0",
    "utop.2.8.0"
)
$DistributionBinaries = @(
    "dune.exe",
    "flexlink.exe",
    "ocaml.exe",
    "ocamlc.byte.exe",
    "ocamlc.exe",
    "ocamlc.opt.exe",
    "ocamlcmt.exe",
    "ocamlcp.byte.exe",
    "ocamlcp.exe",
    "ocamlcp.opt.exe",
    "ocamldebug.exe",
    "ocamldep.byte.exe",
    "ocamldep.exe",
    "ocamldep.opt.exe",
    "ocamldoc.exe",
    "ocamldoc.opt.exe",
    "ocamlfind.exe",
    "ocamlformat.exe",
    "ocamllex.byte.exe",
    "ocamllex.exe",
    "ocamllex.opt.exe",
    "ocamllsp.exe",
    "ocamlmklib.byte.exe",
    "ocamlmklib.exe",
    "ocamlmklib.opt.exe",
    "ocamlmktop.byte.exe",
    "ocamlmktop.exe",
    "ocamlmktop.opt.exe",
    "ocamlobjinfo.byte.exe",
    "ocamlobjinfo.exe",
    "ocamlobjinfo.opt.exe",
    "ocamlopt.byte.exe",
    "ocamlopt.exe",
    "ocamlopt.opt.exe",
    "ocamloptp.byte.exe",
    "ocamloptp.exe",
    "ocamloptp.opt.exe",
    "ocamlprof.byte.exe",
    "ocamlprof.exe",
    "ocamlprof.opt.exe",
    "ocamlrun.exe",
    "ocamlrund.exe",
    "ocamlruni.exe",
    "ocamlyacc.exe",
    "ocp-indent.exe",
    "utop.exe",
    "utop-full.exe")

# Consolidate the magic constants into a single deployment id
$CygwinHash = Get-Sha256Hex16OfText -Text ($CygwinPackagesArch -join ',')
$MSYS2Hash = Get-Sha256Hex16OfText -Text ($MSYS2PackagesArch -join ',')
$PackagesHash = Get-Sha256Hex16OfText -Text ($DistributionPackages -join ',')
$BinariesHash = Get-Sha256Hex16OfText -Text ($DistributionBinaries -join ',')
$DeploymentId = "opam-$AvailableOpamVersion;ninja-$NinjaVersion;cmake-$CMakeVersion;cygwin-$CygwinHash;msys2-$MSYS2Hash;pkgs-$PackagesHash;bins-$BinariesHash"

# We will use the same standard established by C:\Users\<user>\AppData\Local\Programs\Microsoft VS Code
$ProgramParentPath = "$env:LOCALAPPDATA\Programs\DiskuvOCaml"

# Check if already deployed
$finished = Get-BlueGreenDeployIsFinished -ParentPath $ProgramParentPath -DeploymentId $DeploymentId
# Advanced. Skip check with ... $global:RedeployIfExists = $true ... remove it with ... Remove-Variable RedeployIfExists
if (!$global:RedeployIfExists -and $finished) {
    Write-Host "$DeploymentId already deployed."
    Write-Host "Enjoy Diskuv OCaml!"
    return
}

# ----------------------------------------------------------------
# BEGIN Start deployment

# We do support incremental deployments but for user safety we don't enable it by default;
# it is really here to help the maintainers of DiskuvOcaml rapidly develop new deployment ids.
# Use `$global:IncrementalDiskuvOcamlDeployment = $true` to enable incremental deployments.
# Use `Remove-Variable IncrementalDiskuvOcamlDeployment` to remove the override.
$EnableIncrementalDeployment = $global:IncrementalDiskuvOcamlDeployment -and $true

$ProgramPath = Start-BlueGreenDeploy -ParentPath $ProgramParentPath `
    -DeploymentId $DeploymentId `
    -KeepOldDeploymentWhenSameDeploymentId:$EnableIncrementalDeployment `
    -LogFunction ${function:\Write-ProgressCurrentOperation}
$DeploymentMark = "[$DeploymentId]"

# We also use "deployments" for any temporary directory we need since the
# deployment process handles an aborted setup and the necessary cleaning up of disk
# space (eventually).
$TempParentPath = "$Env:temp\diskuvocaml\setupuserprofile"
$TempPath = Start-BlueGreenDeploy -ParentPath $TempParentPath `
    -DeploymentId $DeploymentId `
    -KeepOldDeploymentWhenSameDeploymentId:$EnableIncrementalDeployment `
    -LogFunction ${function:\Write-ProgressCurrentOperation}

# END Start deployment
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# Enhanced Progress Reporting

filter timestamp {"$(Get-Date -Format FileDateTimeUniversal): $_"}
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
$AuditLog = Join-Path -Path $ProgramPath -ChildPath "setup-userprofile.full.log"
$AuditCurrentLog = Join-Path -Path $ProgramPath -ChildPath "setup-userprofile.current.log"
function Invoke-CygwinCommandWithProgress {
    param (
        [Parameter(Mandatory=$true)]
        $Command,
        [Parameter(Mandatory=$true)]
        $CygwinDir,
        $CygwinName = "cygwin"
    )
    # Append what we will do into $AuditLog
    $what = "[$CygwinName] $Command"
    Add-Content -Path $AuditLog -Value $what

    if (!$global:SkipProgress) {
        $global:ProgressStatus = $what
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -Status $what `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
        Invoke-CygwinCommand -Command $Command -CygwinDir $CygwinDir `
            -RedirectStandardOutput $AuditCurrentLog -TailFunction ${function:\Write-ProgressCurrentOperation}
    } else {
        Invoke-CygwinCommand -Command $Command -CygwinDir $CygwinDir `
            -RedirectStandardOutput $AuditCurrentLog
    }
    # Append $AuditCurrentLog onto $AuditLog
    Add-Content -Path $AuditLog -Value $what
    Add-Content -Path $AuditLog -Value (Get-Content -Path $AuditCurrentLog)
}
function Invoke-MSYS2CommandWithProgress {
    param (
        [Parameter(Mandatory=$true)]
        $Command,
        [Parameter(Mandatory=$true)]
        $MSYS2Dir
    )
    # Add Git to path
    $GitMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$GitPath"
    $Command = "export PATH='$($GitMSYS2AbsPath)':`"`$PATH`" && $Command"

    # Append what we will do into $AuditLog
    $what = "[MSYS2] $Command"
    Add-Content -Path $AuditLog -Value $what

    if (!$global:SkipProgress) {
        $global:ProgressStatus = $what
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -Status $global:ProgressStatus `
            -CurrentOperation $Command `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
        Invoke-MSYS2Command -Command $Command -MSYS2Dir $MSYS2Dir `
            -RedirectStandardOutput $AuditCurrentLog -TailFunction ${function:\Write-ProgressCurrentOperation}
    } else {
        Invoke-MSYS2Command -Command $Command -MSYS2Dir $MSYS2Dir `
            -RedirectStandardOutput $AuditCurrentLog
    }
    # Append $AuditCurrentLog onto $AuditLog
    Add-Content -Path $AuditLog -Value (Get-Content -Path $AuditCurrentLog)
}

# From here on we need to stuff $ProgramPath with all the binaries for the distribution
# VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV

# Notes:
# * Include lots of `TestPath` existence tests to speed up incremental deployments.

$AdditionalDiagnostics = "`n`n"
try {

    # ----------------------------------------------------------------
    # BEGIN Ninja

    $global:ProgressActivity = "Install Ninja"
    Write-ProgressStep

    $NinjaCachePath = "$TempPath\ninja"
    $NinjaZip = "$NinjaCachePath\ninja-win.zip"
    $NinjaExeBasename = "ninja.exe"
    $NinjaToolDir = "$ProgramPath\tools\ninja"
    $NinjaExe = "$NinjaToolDir\$NinjaExeBasename"
    if (!(Test-Path -Path $NinjaExe)) {
        if (!(Test-Path -Path $NinjaToolDir)) { New-Item -Path $NinjaToolDir -ItemType Directory | Out-Null }
        if (!(Test-Path -Path $NinjaCachePath)) { New-Item -Path $NinjaCachePath -ItemType Directory | Out-Null }
        Invoke-WebRequest -Uri "https://github.com/ninja-build/ninja/releases/download/v$NinjaVersion/ninja-win.zip" -OutFile "$NinjaZip"
        Expand-Archive -Path $NinjaZip -DestinationPath $NinjaCachePath
        Remove-Item -Path $NinjaZip
        Copy-Item -Path "$NinjaCachePath\$NinjaExeBasename" -Destination "$NinjaExe"
    }


    # END Ninja
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN CMake

    $global:ProgressActivity = "Install Ninja"
    Write-ProgressStep

    $CMakeCachePath = "$TempPath\cmake"
    $CMakeZip = "$CMakeCachePath\cmake.zip"
    $CMakeToolDir = "$ProgramPath\tools\cmake"
    if (!(Test-Path -Path "$CMakeToolDir\bin\cmake.exe")) {
        if (!(Test-Path -Path $CMakeToolDir)) { New-Item -Path $CMakeToolDir -ItemType Directory | Out-Null }
        if (!(Test-Path -Path $CMakeCachePath)) { New-Item -Path $CMakeCachePath -ItemType Directory | Out-Null }
        if ([Environment]::Is64BitOperatingSystem) {
            $CMakeDistType = "x86_64"
        } else {
            $CMakeDistType = "i386"
        }
        Invoke-WebRequest -Uri "https://github.com/Kitware/CMake/releases/download/v$CMakeVersion/cmake-$CMakeVersion-windows-$CMakeDistType.zip" -OutFile "$CMakeZip"
        Expand-Archive -Path $CMakeZip -DestinationPath $CMakeCachePath
        Remove-Item -Path $CMakeZip
        Copy-Item -Path "$CMakeCachePath\cmake-$CMakeVersion-windows-$CMakeDistType\*" `
            -Recurse `
            -Destination $CMakeToolDir
    }


    # END CMake
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Cygwin

    $CygwinRootPath = "$ProgramPath\tools\cygwin"

    $global:ProgressActivity = "Install Cygwin"
    Write-ProgressStep

    # Much of the remainder of the 'Cygwin' section is modified from
    # https://github.com/esy/esy-bash/blob/master/build-cygwin.js

    $CygwinCachePath = "$TempPath\cygwin"
    if ([Environment]::Is64BitOperatingSystem) {
        $CygwinSetupExeBasename = "setup-x86_64.exe"
        $CygwinDistType = "x86_64"
    } else {
        $CygwinSetupExeBasename = "setup-x86.exe"
        $CygwinDistType = "x86"
    }
    $CygwinSetupExe = "$CygwinCachePath\$CygwinSetupExeBasename"
    if (!(Test-Path -Path $CygwinCachePath)) { New-Item -Path $CygwinCachePath -ItemType Directory | Out-Null }
    if (!(Test-Path -Path $CygwinSetupExe)) {
        Invoke-WebRequest -Uri "https://cygwin.com/$CygwinSetupExeBasename" -OutFile "$CygwinSetupExe.tmp"
        Rename-Item -Path "$CygwinSetupExe.tmp" "$CygwinSetupExeBasename"
    }

    $CygwinSetupCachePath = "$CygwinRootPath\var\cache\setup"
    if (!(Test-Path -Path $CygwinSetupCachePath)) { New-Item -Path $CygwinSetupCachePath -ItemType Directory | Out-Null }

    $CygwinMirror = "http://cygwin.mirror.constant.com"

    # Skip with ... $global:SkipCygwinSetup = $true ... remove it with ... Remove-Variable SkipCygwinSetup
    if (!$global:SkipCygwinSetup) {
        # https://cygwin.com/faq/faq.html#faq.setup.cli
        $CommonCygwinMSYSOpts = "-qWnNdOfgoB"
        $proc = Start-Process -FilePath $CygwinSetupExe -Wait -PassThru `
            -RedirectStandardOutput $AuditCurrentLog `
            -ArgumentList $CommonCygwinMSYSOpts, "-a", $CygwinDistType, "-R", $CygwinRootPath, "-s", $CygwinMirror, "-l", $CygwinSetupCachePath, "-P", ($CygwinPackagesArch -join ",")
        # Append $AuditCurrentLog onto $AuditLog
        Add-Content -Path $AuditLog -Value (Get-Content -Path $AuditCurrentLog)
        # Check exit
        $exitCode = $proc.ExitCode
        if ($exitCode -ne 0) {
            Write-Error "Cygwin installation failed! Exited with $exitCode."
            throw
        }
    }

    $AdditionalDiagnostics += "[Advanced] DiskuvOCaml Cygwin commands can be run with: $CygwinRootPath\bin\mintty.exe -`n"

    # Create home directories
    Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "exit 0"

    function Invoke-CygwinSyncScript {
        param (
            $CygwinDir = $CygwinRootPath
        )

        # Create /opt/diskuv-ocaml/installtime/ which is specific to Cygwin with common pieces from UNIX.
        $cygwinAbsPath = & $CygwinDir\bin\cygpath.exe -au "$DkmlPath"
        Invoke-CygwinCommandWithProgress -CygwinDir $CygwinDir -Command "/usr/bin/install -d /opt/diskuv-ocaml/setup && /usr/bin/rsync -a --delete '$cygwinAbsPath'/installtime/cygwin/ '$cygwinAbsPath'/installtime/unix/ /opt/diskuv-ocaml/installtime/ && /usr/bin/find /opt/diskuv-ocaml/installtime/ -type f | /usr/bin/xargs /usr/bin/chmod +x"

        # Run through dos2unix which is only installed in $CygwinRootPath
        $dkmlSetupCygwinAbsMixedPath = & $CygwinDir\bin\cygpath.exe -am "/opt/diskuv-ocaml/installtime/"
        Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "/usr/bin/find '$dkmlSetupCygwinAbsMixedPath' -type f | /usr/bin/xargs /usr/bin/dos2unix --quiet"
    }

    # Create /opt/diskuv-ocaml/installtime/ which is specific to Cygwin with common pieces from UNIX
    Invoke-CygwinSyncScript

    # END Cygwin
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Moby scripted Docker downloads

    $global:ProgressActivity = "Download ocaml/opam Docker image"
    Write-ProgressStep

    $OcamlOpamRootPath = "$ProgramPath\tools\ocaml-opam"
    $MobyPath = "$TempPath\moby"
    $OcamlOpamRootCygwinAbsPath = & $CygwinRootPath\bin\cygpath.exe -au "$OcamlOpamRootPath"
    $MobyCygwinAbsPath = & $CygwinRootPath\bin\cygpath.exe -au "$MobyPath"
    Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "install -m 755 -d '$OcamlOpamRootCygwinAbsPath' '$MobyCygwinAbsPath'"

    # Download the downloader script
    Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "/opt/diskuv-ocaml/installtime/download-moby-downloader.sh '$MobyCygwinAbsPath'"

    # Download the latest windows-msvc-20H2 and windows-mingw-20H2.
    # Q: Why 20H2? Ans:
    #    1. because it is a single kernel image so it is much smaller than multikernel `windows-msvc`
    #    2. it is the latest as of 2021-08-05 so it will be a long time before that Windows kernel is no longer built;
    #       would be nice if we could query https://github.com/avsm/ocaml-dockerfile/blob/ac54d3550159b0450032f0f6a996c2e96d3cafd7/src-opam/dockerfile_distro.ml#L36-L47
    # Q: Why download with Cygwin rather than MSYS? Ans: The Moby script uses `jq` which has shell quoting failures when run with MSYS `jq`.
    # Q: Why both mingw and msvc? Ans: Mingw's opam.exe has no runtime dependency on Cygwin, so msvc's opam.exe is unusable in our MSYS2 scripting environment.
    #    But msvc is needed because dynamic linking of C + OCaml with the same compiler does not expose us to difficult-to-resolve cross-compiler interaction bugs.
    #
    # Skip with ... $global:SkipMobyDownload = $true ... remove it with ... Remove-Variable SkipMobyDownload
    if (!$global:SkipMobyDownload) {
        Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "/opt/diskuv-ocaml/installtime/moby-download-docker-image.sh '$MobyCygwinAbsPath' ocaml/opam:windows-msvc-20H2 amd64"
        Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "/opt/diskuv-ocaml/installtime/moby-download-docker-image.sh '$MobyCygwinAbsPath' ocaml/opam:windows-mingw-20H2 amd64"
    }

    # = Extract the tarballs =
    # Note: You may be tempted to use the bundled BuildTools/ rather than ask the user to install MSBuild (see BUILDING-Windows.md).
    #       But that is dangerous because Microsoft can and likely does but hardcoded paths and system information into that directory.
    #       Definitely not worth the insane troubleshooting that would ensue.
    Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "/opt/diskuv-ocaml/installtime/moby-extract-opam-root.sh '$MobyCygwinAbsPath' ocaml/opam:windows-msvc-20H2 amd64 msvc '$OcamlOpamRootCygwinAbsPath'"
    Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "/opt/diskuv-ocaml/installtime/moby-extract-opam-root.sh '$MobyCygwinAbsPath' ocaml/opam:windows-mingw-20H2 amd64 mingw '$OcamlOpamRootCygwinAbsPath'"

    foreach ($portAndArch in "msvc-amd64", "mingw-amd64") {
        $AdditionalDiagnostics += "[Advanced] Cygwin commands for Docker $portAndArch image 'ocaml/opam' can be run with: $OcamlOpamRootPath\$portAndArch\cygwin64\bin\mintty.exe -`n"

        # Create /opt/diskuv-ocaml/installtime/ which is specific to Cygwin with common pieces from UNIX
        Invoke-CygwinSyncScript -CygwinDir "$OcamlOpamRootPath\$portAndArch\cygwin64"

        # Skip with ... $global:SkipMobyFixup = $true ... remove it with ... Remove-Variable SkipMobyFixup
        if (!$global:SkipMobyFixup) {
            # Create home directories
            Invoke-CygwinCommandWithProgress -CygwinDir "$OcamlOpamRootPath\$portAndArch\cygwin64" -Command "exit 0"

            # Fix up symlinks pointing to C:\Opam . Not only does that not exist, but we want relative symlinks since we'll be cloning this Opam root!
            # Also fixes symlinks pointing to C:\Windows if your system drive / Windows installation is different.
            # Ex. Was:  build/_tools/common/ocaml-opam/msvc-amd64/opam/.opam/plugins/bin/opam-depext.exe -> /cygdrive/c/opam/.opam/4.12/bin/opam-depext.exe
            #     Want: build/_tools/common/ocaml-opam/msvc-amd64/opam/.opam/plugins/bin/opam-depext.exe -> ../../4.12/bin/opam-depext.exe
            Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command ("find $OcamlOpamRootCygwinAbsPath/$portAndArch -xtype l | while read linkpath; do /opt/diskuv-ocaml/installtime/idempotent-fix-symlink.sh " + '$linkpath' + " $OcamlOpamRootCygwinAbsPath $portAndArch /cygdrive/c/; done")
        }
    }

    # END Moby scripted Docker downloads
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Recompile and install opam.exe
    #
    # Note 1
    # ------
    #
    # We sandbox opam into its own `tools/opam` directory so we can minimize DLL hell problems if they
    # arise.
    #
    # Note 2
    # ------
    #
    # The ocaml-opam Docker images use a Cygwin dependent opam.exe. So their opam.exe is unusable in our MSYS2 scripting environment
    # because of cygwin1.dll conflicts when Cygwin opam.exe spawns curl.exe from the PATH of our MSYS2 environment, for example.
    #
    # Since Opam only provides instructions for MinGW based compilation, we use the MinGW ocaml-opam Docker image
    # for this task.

    $global:ProgressActivity = "Install Native Windows OPAM.EXE"
    Write-ProgressStep

    $ProgramRelToolDir = "tools\opam"
    $ProgramToolOpamDir = "$ProgramPath\$ProgramRelToolDir"
    $OpamBootstrapDir = "$TempPath\opam-bootstrap"

    # If the opam.exe already exists in the User Profile, we don't reinstall it.
    if (!(Test-Path -Path $ProgramToolOpamDir\opam.exe)) {
        # Compile native Windows OPAM.EXE with ocaml/opam's mingw-amd64 Cygwin.
        # * We do not do `make install` since only OPAM.EXE builds and we don't care about any other Opam artifacts (which we can copy from ocaml/opam)
        # * We configure OPAM.EXE during compilation to use $ProgramToolOpamDir as the hardcoded install location.
        $Dkml_OcamlOpamCygwinAbsPath = & "$OcamlOpamRootPath\mingw-amd64\cygwin64\bin\cygpath.exe" -au "$DkmlPath"
        $ProgramToolOpam_OcamlOpamCygwinAbsPath = & "$OcamlOpamRootPath\mingw-amd64\cygwin64\bin\cygpath.exe" -au "$ProgramToolOpamDir"
        $OpamBootstrap_OcamlOpamCygwinAbsPath = & "$OcamlOpamRootPath\mingw-amd64\cygwin64\bin\cygpath.exe" -au "$OpamBootstrapDir"
        Invoke-CygwinCommandWithProgress `
            -CygwinName "ocaml-opam/mingw-amd64" `
            -CygwinDir "$OcamlOpamRootPath\mingw-amd64\cygwin64" `
            -Command "/opt/diskuv-ocaml/installtime/compile-native-opam.sh '$Dkml_OcamlOpamCygwinAbsPath' $AvailableOpamVersion '$OpamBootstrap_OcamlOpamCygwinAbsPath' '$ProgramToolOpam_OcamlOpamCygwinAbsPath'"

        # Install it in the final location. Do a tiny safety check and only install from a whitelist of file extensions.
        Write-Progress -Activity "$DeploymentMark $ProgressActivity" -Status "Installing opam.exe"
        if (!(Test-Path -Path $ProgramToolOpamDir)) { New-Item -Path $ProgramToolOpamDir -ItemType Directory | Out-Null }
        Copy-Item -Path "$OpamBootstrapDir\bin\*" `
            -Include @("*.dll", "*.exe", "*.manifest") `
            -Destination $ProgramToolOpamDir
    }


    # END Recompile and install opam.exe
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN MSYS2

    $global:ProgressActivity = "Install MSYS2"
    Write-ProgressStep

    $MSYS2Dir = "$ProgramPath\tools\MSYS2"
    $MSYS2CachePath = "$TempPath\MSYS2"
    if ([Environment]::Is64BitOperatingSystem) {
        $MSYS2SetupExeBasename = "msys2-x86_64-20210725.exe"
        $MSYS2DistType = "x86_64"
    } else {
        $MSYS2SetupExeBasename = "msys2-i686-20200517.exe"
        $MSYS2DistType = "i686"
    }
    $MSYS2Setup64Exe = "$MSYS2CachePath\$MSYS2SetupExeBasename"
    if (!(Test-Path -Path $MSYS2CachePath)) { New-Item -Path $MSYS2CachePath -ItemType Directory | Out-Null }
    if (!(Test-Path -Path $MSYS2Setup64Exe)) {
        Invoke-WebRequest -Uri "http://repo.msys2.org/distrib/$MSYS2DistType/$MSYS2SetupExeBasename" -OutFile "$MSYS2Setup64Exe.tmp"
        Rename-Item -Path "$MSYS2Setup64Exe.tmp" "$MSYS2SetupExeBasename"
    }

    # Skip with ... $global:SkipMSYS2Setup = $true ... remove it with ... Remove-Variable SkipMSYS2Setup
    if (!$global:SkipMSYS2Setup) {
        # https://github.com/msys2/msys2-installer#cli-usage-examples
        if (!(Test-Path "$MSYS2Dir\msys2.exe")) {
            if (!(Test-Path -Path $MSYS2Dir)) { New-Item -Path $MSYS2Dir -ItemType Directory | Out-Null }

            $proc = Start-Process -NoNewWindow -FilePath $MSYS2Setup64Exe -Wait -PassThru -ArgumentList "in", "--confirm-command", "--accept-messages", "--root", $MSYS2Dir
            $exitCode = $proc.ExitCode
            if ($exitCode -ne 0) {
                Write-Error "MSYS2 installation failed! Exited with $exitCode."
                throw
            }
        }
    }

    $AdditionalDiagnostics += "[Advanced] MSYS2 commands can be run with: $MSYS2Dir\msys2_shell.cmd`n"

    # Create home directories and other files and settings. Use the native MSYS2 launcher for
    # future-proofing this iniitial set rather than Invoke-MSYS2Command
    & $MSYS2Dir\msys2_shell.cmd -l -c "exit 0"

    # Synchronize packages
    #
    # Skip with ... $global:SkipMSYS2Update = $true ... remove it with ... Remove-Variable SkipMSYS2Update
    if (!$global:SkipMSYS2Update) {
        # Pacman does not update individual packages but rather the full system is upgraded. We _must_
        # upgrade the system before installing packages. Confer:
        # https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command ("pacman -Syu --noconfirm")
        # Install new packages and/or full system if any were not installed ("--needed")
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command ("pacman -S --needed --noconfirm " + ($MSYS2PackagesArch -join " "))
    }

    # Create /opt/diskuv-ocaml/installtime/ which is specific to MSYS2 with common pieces from UNIX.
    # Run through dos2unix.
    $DkmlMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$DkmlPath"
    Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
        -Command ("/usr/bin/install -d /opt/diskuv-ocaml/setup && " +
        "/usr/bin/rsync -a --delete '$DkmlMSYS2AbsPath'/installtime/msys2/ '$DkmlMSYS2AbsPath'/installtime/unix/ /opt/diskuv-ocaml/installtime/ && " +
        "/usr/bin/find /opt/diskuv-ocaml/installtime/ -type f | /usr/bin/xargs /usr/bin/dos2unix --quiet && " +
        "/usr/bin/find /opt/diskuv-ocaml/installtime/ -type f | /usr/bin/xargs /usr/bin/chmod +x")


    # END MSYS2
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Define dkmlvars

    # dkmlvars.* (DiskuvOCaml variables) are scripts that set variables about the deployment.
    $ProgramParentMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$ProgramParentPath"
    $ProgramMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$ProgramPath"
    $UnixVarsArray = @(
        "DiskuvOCamlVarsVersion=1",
        "DiskuvOCamlHome='$ProgramMSYS2AbsPath'",
        "DiskuvOCamlBinaryPaths='$ProgramMSYS2AbsPath/bin:$ProgramMSYS2AbsPath/tools/opam'"
    )
    $UnixVarsContents = $UnixVarsArray -join [environment]::NewLine
    $UnixVarsContentsOnOneLine = $UnixVarsArray -join " "
    $PowershellVarsContents = @"
`$env:DiskuvOCamlVarsVersion = 1
`$env:DiskuvOCamlHome = '$ProgramPath'
`$env:DiskuvOCamlBinaryPaths = '$ProgramPath\bin;$ProgramPath\tools\opam'
"@

    # END Define dkmlvars
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN opam init

    $global:ProgressActivity = "Initialize Opam Package Manager"
    Write-ProgressStep

    # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
    if (!$global:SkipOpamSetup) {
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command "env $UnixVarsContentsOnOneLine bash -x '$DkmlPath\setup\unix\init-opam-root.sh' dev"
    }


    # END opam init
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN opam switch create diskuv-boot-DO-NOT-DELETE

    $global:ProgressActivity = "Create diskuv-boot-DO-NOT-DELETE Opam Switch"
    Write-ProgressStep

    # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
    if (!$global:SkipOpamSetup) {
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command "env $UnixVarsContentsOnOneLine '$DkmlPath\setup\unix\create-diskuv-boot-DO-NOT-DELETE-switch.sh'"
        }

    # END opam switch create diskuv-boot-DO-NOT-DELETE
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN opam switch create diskuv-system

    $global:ProgressActivity = "Create diskuv-system local Opam switch"
    Write-ProgressStep

    # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
    if (!$global:SkipOpamSetup) {
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command "env $UnixVarsContentsOnOneLine '$DkmlPath\setup\unix\create-opam-switch.sh' -s -b Release"
        }

    # END opam switch create diskuv-system
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN opam install required `diskuv-system` packages

    $global:ProgressActivity = "Install packages in diskuv-system local Opam Switch"
    Write-ProgressStep

    # Note: flexlink.exe is already installed because it is part of the OCaml system compiler (ocaml-variants).

    # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
    if (!$global:SkipOpamSetup) {
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command (
            "env $UnixVarsContentsOnOneLine '$DkmlPath\runtime\unix\platform-opam-exec' -s install --yes " +
            "$($DistributionPackages -join ' ')"
        )
    }


    # END opam install required `diskuv-system` packages
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN install `diskuv-system` to Programs

    $global:ProgressActivity = "Install diskuv-system binaries"
    Write-ProgressStep

    $ProgramRelBinDir = "bin"
    $ProgramBinDir = "$ProgramPath\$ProgramRelBinDir"
    $DiskuvSystemDir = "$ProgramPath\system\_opam"

    if (!(Test-Path -Path $ProgramBinDir)) { New-Item -Path $ProgramBinDir -ItemType Directory | Out-Null }
    foreach ($binary in $DistributionBinaries) {
        if (!(Test-Path -Path "$ProgramBinDir\$binary")) {
            Copy-Item -Path "$DiskuvSystemDir\bin\$binary" -Destination $ProgramBinDir
        }
    }


    # END opam install `diskuv-system` to Programs
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Remove extended ACL

    # Cygwin uses Windows ACLs attached to files and directories that
    # native Windows executables do not use. (See https://cygwin.com/cygwin-ug-net/using-filemodes.html)
    #
    # Typically MSYS2 does not use those Windows ACL either but it can be turned on with the MSYS environment variable.
    #
    # 1. We do **not** presume we are the only Cygwin / MSYS2 installation so we will **not** modify the
    # CYGWIN and MSYS environment variables. For example, the widely used Git for Windows uses MSYS underneath.
    # 2. You may think to use /etc/fstab but the reading of the 'noacl' option is done at the _first_
    # read of /etc/fstab by cygwin1.dll or msys-2.0.dll which may not be our Cygwin / MSYS2 installation.
    # So that approach is unreliable.
    #
    # We instead forcibly remove extended ACLs with `setfacl`.

    $global:ProgressActivity = "Remove extended ACLs"
    Write-ProgressStep

    $DiskuvBootCygwinAbsPath = & $CygwinRootPath\bin\cygpath.exe -au "$env:USERPROFILE\.opam\diskuv-boot-DO-NOT-DELETE"
    Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "find '$DiskuvBootCygwinAbsPath' -print0 | xargs -0 --no-run-if-empty setfacl --remove-all --remove-default"

    $ProgramCygwinAbsPath = & $CygwinRootPath\bin\cygpath.exe -au "$ProgramPath"
    # Note: We get a lot of `setfacl: Permission denied` and a few `setfacl: No such file or directory`.
    # Not sure how to remove them, so will just use `|| true` to ignore the failures.
    Invoke-CygwinCommandWithProgress -CygwinDir $CygwinRootPath -Command "find '$ProgramCygwinAbsPath' -print0 | xargs -0 --no-run-if-empty setfacl --remove-all --remove-default || true"


    # END Remove extended ACL
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Stop deployment. Write deployment vars.

    $global:ProgressActivity = "Finalize deployment"
    Write-ProgressStep

    Stop-BlueGreenDeploy -ParentPath $ProgramParentPath -DeploymentId $DeploymentId -Success
    Stop-BlueGreenDeploy -ParentPath $TempParentPath -DeploymentId $DeploymentId # no -Success so always delete the temp directory

    # dkmlvars.* (DiskuvOCaml variables)
    #
    # Since for Unix we should be writing BOM-less UTF-8 shell scripts, and PowerShell 5.1 (the default on Windows 10) writes
    # UTF-8 with BOM (cf. https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-content?view=powershell-5.1)
    # we write to standard Windows encoding `Unicode` (UTF-16 LE with BOM) and then use dos2unix to convert it to UTF-8 with no BOM.
    Set-Content -Path "$ProgramParentPath\dkmlvars.utf16le-bom.sh" -Value $UnixVarsContents -Encoding Unicode
    Set-Content -Path "$ProgramParentPath\dkmlvars.ps1" -Value $PowershellVarsContents -Encoding Unicode

    Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
        -Command (
            "dos2unix --newfile '$ProgramParentMSYS2AbsPath/dkmlvars.utf16le-bom.sh' '$ProgramParentMSYS2AbsPath/dkmlvars.tmp.sh' && " +
            "rm -f '$ProgramParentMSYS2AbsPath/dkmlvars.utf16le-bom.sh'" +
            "mv '$ProgramParentMSYS2AbsPath/dkmlvars.tmp.sh' '$ProgramParentMSYS2AbsPath/dkmlvars.sh'"
        )


    # END Stop deployment. Write deployment vars.
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Modify User's environment variables

    Write-Progress -Activity "$DeploymentMark $ProgressActivity" -Status "Modify environment variables"
    Write-ProgressStep

    $splitter = [System.IO.Path]::PathSeparator # should be ';' if we are running on Windows (yes, you can run Powershell on other operating systems)

    $userpath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $userpathentries = $userpath -split $splitter # all of the User's PATH in a collection
    $PathModified = $false

    # DiskuvOCamlHome
    [Environment]::SetEnvironmentVariable("DiskuvOCamlHome", "$ProgramPath", 'User')

    # Add bin\ to the User's PATH if it isn't already
    if (!($userpathentries -contains $ProgramBinDir)) {
        # remove any old entries, even from old deployments
        $PossibleDirs = Get-PossibleSlotPaths -ParentPath $ProgramParentPath -SubPath $ProgramRelBinDir
        foreach ($possibleDir in $PossibleDirs) {
            $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
        }
        # add new PATH entry
        $userpathentries = @( $ProgramBinDir ) + $userpathentries
        $PathModified = $true
    }

    # Add tools\opam\ to the User's PATH if it isn't already
    if (!($userpathentries -contains $ProgramToolOpamDir)) {
        # remove any old entries, even from old deployments
        $PossibleDirs = Get-PossibleSlotPaths -ParentPath $ProgramParentPath -SubPath $ProgramRelToolDir
        foreach ($possibleDir in $PossibleDirs) {
            $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
        }
        # add new PATH entry
        $userpathentries = @( $ProgramToolOpamDir ) + $userpathentries
        $PathModified = $true
    }

    if ($PathModified) {
        # modify PATH
        [Environment]::SetEnvironmentVariable("PATH", ($userpathentries -join $splitter), 'User')
    }

    # END Modify User's environment variables
    # ----------------------------------------------------------------
}
catch {
    $ErrorActionPreference = 'Continue'
    Write-Error (
        "Setup did not complete because an error occurred.`n$_`n`n$($_.ScriptStackTrace)`n`n" +
        "$AdditionalDiagnostics`n`nLogs files available at $AuditLog and $AuditCurrentLog")
    exit 1
}

Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $global:ProgressActivity -Completed

Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "Setup is complete. Congratulations!"
Write-Host "Enjoy Diskuv OCaml! Documentation can be found at https://diskuv.github.io/diskuv-ocaml/"
Write-Host ""
Write-Host ""
Write-Host ""
if ($PathModified) {
    Write-Warning "Your User PATH was modified."
    Write-Warning "You will need to log out and log back in"
    Write-Warning "-OR- (for advanced users) exit all of your Command Prompts, Windows Terminals,"
    Write-Warning "PowerShells and IDEs like Visual Studio Code"
}
