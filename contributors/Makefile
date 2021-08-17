ifdef DiskuvOCamlHome
CMAKE = '$(DiskuvOCamlHome)'/tools/cmake/bin/cmake.exe
else
CMAKE = cmake
endif
PUBLISHDOCS_WORKDIR  = _build/.publishdocs

.PHONY: clean
clean:
	$(CMAKE) -E remove_directory _build || $(CMAKE) -E rm -rf _build

.PHONY: install-github-cli
install-github-cli:
	@ PATH="$$PATH:/usr/bin:/bin"; \
	if which pacman >/dev/null 2>&1 && which cygpath >/dev/null 2>&1; then \
		pacman --sync --needed --noconfirm mingw64/mingw-w64-x86_64-github-cli; \
	fi
	@PATH="$$PATH:/usr/bin:/bin:/mingw64/bin"; if ! which gh >/dev/null 2>&1; then \
		echo "FATAL: GitHub CLI was not installed, and the Makefile does not know how to install it." >&2; exit 1; \
	fi

.PHONY: auth-github-cli
auth-github-cli: install-github-cli
	@PATH="$$PATH:/usr/bin:/bin:/mingw64/bin" ; if which gh.exe >/dev/null 2>&1; then GH=gh.exe; else GH=gh; fi; \
	$$GH auth status || $$GH auth login

.PHONY: release-start-major
release-start-major:
	@PATH="$$PATH:/usr/bin:/bin:/mingw64/bin" ; \
	if which pacman >/dev/null 2>&1 && which cygpath >/dev/null 2>&1; then HOME="$$USERPROFILE"; fi; \
	cd .. && bump2version major --no-tag --message 'Start v{new_version} release' --verbose && \
	NEW_VERSION=`awk '$$1=="current_version"{print $$NF; exit 0}' .bumpversion.cfg` && \
	printf '## %s (@@YYYYMMDD@@)\n\n' $$NEW_VERSION > contributors/changes/v$$NEW_VERSION.md

.PHONY: release-start-minor
release-start-minor:
	@PATH="$$PATH:/usr/bin:/bin:/mingw64/bin" ; \
	if which pacman >/dev/null 2>&1 && which cygpath >/dev/null 2>&1; then HOME="$$USERPROFILE"; fi; \
	cd .. && bump2version minor --no-tag --message 'Start v{new_version} release' --verbose && \
	NEW_VERSION=`awk '$$1=="current_version"{print $$NF; exit 0}' .bumpversion.cfg` && \
	printf '## %s (@@YYYYMMDD@@)\n\n' $$NEW_VERSION > contributors/changes/v$$NEW_VERSION.md

.PHONY: release-start-patch
release-start-patch:
	@PATH="$$PATH:/usr/bin:/bin:/mingw64/bin" ; \
	if which pacman >/dev/null 2>&1 && which cygpath >/dev/null 2>&1; then HOME="$$USERPROFILE"; fi; \
	cd .. && bump2version patch --no-tag --message 'Start v{new_version} release' --verbose && \
	NEW_VERSION=`awk '$$1=="current_version"{print $$NF; exit 0}' .bumpversion.cfg` && \
	printf '## %s (@@YYYYMMDD@@)\n\n' $$NEW_VERSION > contributors/changes/v$$NEW_VERSION.md

.PHONY: release-publish-prerelease
release-publish-prerelease: auth-github-cli
	@PATH="$$PATH:/usr/bin:/bin:/mingw64/bin" ; if which gh.exe >/dev/null 2>&1; then GH=gh.exe; else GH=gh; fi; \
	if which pacman >/dev/null 2>&1 && which cygpath >/dev/null 2>&1; then HOME="$$USERPROFILE"; fi; \
	cd .. && bump2version prerelease --message 'Prerelease v{new_version}' --verbose && \
	NEW_VERSION=`awk '$$1=="current_version"{print $$NF; exit 0}' .bumpversion.cfg` && \
	git push && git push --tags && \
	$$GH release create v$$NEW_VERSION --prerelease

.PHONY: release-complete
release-complete:
	@PATH="$$PATH:/usr/bin:/bin:/mingw64/bin" ; if which gh.exe >/dev/null 2>&1; then GH=gh.exe; else GH=gh; fi; \
	if which pacman >/dev/null 2>&1 && which cygpath >/dev/null 2>&1; then HOME="$$USERPROFILE"; fi; \
	cd .. && \
	OLD_VERSION=`awk '$$1=="current_version"{print $$NF; exit 0}' .bumpversion.cfg | sed 's/[-+].*//' ` && \
	sed -i s/@@YYYYMMDD@@/`date +%Y-%m-%d` contributors/changes/v$$OLD_VERSION.md && \
	echo >> CHANGES.md && cat contributors/changes/v$$OLD_VERSION.md >> CHANGES.md && \
	git commit -m "Release date for $$OLD_VERSION" CHANGES.md contributors/changes/v$$OLD_VERSION.md && \
	bump2version change --message 'Finish v{new_major}.{new_minor}.{new_patch} release' --tag-name 'v{new_major}.{new_minor}.{new_patch}' --verbose && \
	NEW_VERSION=`awk '$$1=="current_version"{print $$NF; exit 0}' .bumpversion.cfg` && \
	git push && git push --tags && \
	$$GH release create v$$NEW_VERSION --notes-file contributors/changes/v$$NEW_VERSION.md

.PHONY: publish-docs
publish-docs:
	@if test -n "$$(git status --porcelain)"; then echo "FATAL: The working directory must be clean! All changes have to be commited to git or removed."; exit 1; fi
	@$(MAKE) clean

	$(CMAKE) -E echo Building Sphinx html twice so that Sphinx cross-references work ...
	$(MAKE) html
	$(MAKE) html

	$(CMAKE) -E echo Cloning current git repository inside a work folder ...
	git rev-parse gh-pages >/dev/null 2>&1 || git branch gh-pages origin/gh-pages
	git clone --branch gh-pages "file://$$PWD/../.git" $(PUBLISHDOCS_WORKDIR)/
	$(CMAKE) -E copy_directory _build/html/ $(PUBLISHDOCS_WORKDIR)/docs
	$(CMAKE) -E touch $(PUBLISHDOCS_WORKDIR)/docs/.nojekyll
	git -C $(PUBLISHDOCS_WORKDIR) add -A
	GIT_AUTHOR_EMAIL=publish-docs.diskuv@example.net GIT_COMMITTER_EMAIL=publish-docs.diskuv@example.net git -C $(PUBLISHDOCS_WORKDIR) commit -m "Updated site"

	$(CMAKE) -E echo Trying to open a web browser so you can review the final result ...
	$(CMAKE) -E echo "Once you are finished the review, use 'git -C $$PWD/$(PUBLISHDOCS_WORKDIR) push && git push origin gh-pages' to publish the changes"
	wslview _build/.publishdocs/docs/index.html || open _build/.publishdocs/docs/index.html || explorer '_build\.publishdocs\docs\index.html' || \
		$(CMAKE) -E echo "Cannot find a browser. Please review the web site at _build/.publishdocs/docs/index.html"

# You can set these variables from the command line, and also
# from the environment for the first two.
SPHINXOPTS    ?=
SPHINXBUILD   ?= sphinx-build
SOURCEDIR     = .
BUILDDIR      = _build

sphinx-help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

.PHONY: sphinx-help Makefile html

# $(O) is meant as a shortcut for $(SPHINXOPTS).
html: Makefile
	@$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)
