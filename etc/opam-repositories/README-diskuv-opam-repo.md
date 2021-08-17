# diskuv-opam-repo

## Creating your own package patches

> This procedure **will not work** if the package already has a patch. For example
> you can't use this procedure if the package is present in
> `etc/opam-repositories/diskuv-opam-repo` and has `patches: [...]` in its
> `opam` file. You may be able to remove the `patches` clause
> and then do a `opam update diskuv && opam upgrade` before doing any of these
> instructions, but that procedure has not been tested.

FIRST, find which OCaml package is failing and check out that package with:

```bash
opam source PACKAGE_NAME
```

> The version of the package is important. Using the above command will
> check out the *version* of the package that Opam thinks should be
> installed, which is almost always what you should be patching.

SECOND, create a local git repository; we'll be using `git` to create our patch:

```bash
cd PACKAGE_NAME.PACKAGE_VERSION
git init
git config core.safecrlf false
git add -A
GIT_AUTHOR_EMAIL=somebody@aol.com GIT_COMMITTER_EMAIL=somebody@aol.com git commit -m "Baseline for patch"
git tag baseline-patch
```

*If `git init` fails because Git is already there, do `git tag baseline-patch` and then proceed to the THIRD step*

THIRD, verify you can recreate the error:

```bash
ls *.opam
basename $PWD
opam install ./PACKAGE_NAME.opam
```

*There may be many `.opam` files. Use the one that matches the `basename` without the version number*

FOURTH,

Fix the error in the source code with your favorite editor, do a `GIT_AUTHOR_EMAIL=somebody@aol.com GIT_COMMITTER_EMAIL=somebody@aol.com git commit` and test it with:

```bash
opam install ./PACKAGE_NAME.opam
```

> Doing a `git commit` is **required**. Do not get concerned if you end up with a long string of
> bad `git commit`s; they will be squashed in the SIXTH step.


Repeat until you get a successful install.

FIFTH, remove your edits so they do not hide the `diskuv-opam-repo` repository:

```bash
opam remove PACKAGE_NAME
opam pin remove PACKAGE_NAME
```

SIXTH, create a patch:

```bash
git diff baseline-patch > /tmp/custom.patch
```

SEVENTH, create a self-contained `opam` file:

```bash
opam show PACKAGE_NAME -f opam-file > /tmp/opam
echo 'patches: ["custom.patch"]' >> /tmp/opam

cat /tmp/opam
```

> There should be a `url { src: "..." checksum: "" }` in your file. If not,
> make sure you ran `opam pin remove PACKAGE_NAME`

EIGHTH, create/modify the `diskuv-opam-repo` directory:

```text
etc
└── opam-repositories
    └── diskuv-opam-repo
        ├── packages
        │   └── <PACKAGE_NAME>
        │       └── <PACKAGE_NAME.PACKAGE_VERSION>
        │           ├── files
        │           │   └── custom.patch           <==  Copy /tmp/custom.patch
        │           └── opam                       <==  Copy /tmp/opam
        ├── README-diskuv-opam-repo.md             <==> You are reading this!
        └── repo
```

> For more details visit <https://opam.ocaml.org/doc/Manual.html#Package-definitions>

NINTH, update your Opam switch with your new `diskuv-opam-repo` patch:

```bash
opam update diskuv
```

*See [Troubleshooting: opam update diskuv](#opam-update-diskuv) if this fails*

TENTH, add your new package to the "PINNED_PACKAGES" variable in `runtime/unix/build-sandbox-configure.sh`
if it is not there already.

Done! Go ahead and continue with your normal builds.

---

### Troubleshooting

#### opam update diskuv

If after `opam update diskuv` you get:

```text
[diskuv] synchronised from file://Z:/somewhere/etc/opam-repositories/diskuv-opam-repo
[ERROR] Could not update repository "diskuv": "Z:\\somewhere\\build\\_tools\\common\\MSYS2\\usr\\bin\\patch.exe -p1 -i C:\\Users\\user\\.opam\\log\\patch-28544-5495c0" exited with code 1
```

then rerun the command as `opam update diskuv -vv`. That will give you something like:

```text
- patching file packages/dune-configurator/dune-configurator.2.9.0/files/custom.patch
- patching file packages/dune-configurator/dune-configurator.2.9.0/files/v1.patch
- Reversed (or previously applied) patch detected!  Assume -R? [n]
- Apply anyway? [n]
- Skipping patch.
- 1 out of 1 hunk ignored -- saving rejects to file packages/dune-configurator/dune-configurator.2.9.0/files/v1.patch.rej
- patching file packages/dune-configurator/dune-configurator.2.9.0/opam
- Hunk #1 FAILED at 47 (different line endings).
- 1 out of 1 hunk FAILED -- saving rejects to file packages/dune-configurator/dune-configurator.2.9.0/opam.rej
```

Anything with a `saving rejects to file packages/SOME_PACKAGE_NAME/.../*.rej` is showing a broken package.
Just remove the broken package with `opam remove SOME_PACKAGE_NAME` and `opam pin remove SOME_PACKAGE_NAME`,
like:

```bash
opam remove dune-configurator
opam pin remove dune-configurator

opam update diskuv
```

in the example above.

If that still doesn't work just do:

```bash
opam repository remove diskuv --all

# On Windows do: .\make init-dev
make init-dev

opam repository priority diskuv 1 --all
opam update diskuv
```

which will rebuild your repository.

Then you can do `make prepare-dev` to rebuild your switch.
