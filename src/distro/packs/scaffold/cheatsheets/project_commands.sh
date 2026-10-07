# ==========================================
# PROJECT SCAFFOLDING CHEATSHEET
# ==========================================
# `fnew` is this pack's own shell function (zsh/scaffold.zsh), and the three
# targets below come from its module (make/project-setup.mk): the sheet travels
# with what it documents. No `# requires:` header - the pack's folder is the
# switch, and the tools these commands drive are taken by the pack's own uvx the
# first time one of them runs.

fnew                                        # Scaffold a new project: interactively pick a template from the catalog
fnew gh:owner/repo [cruft] [version]        # Scaffold straight from a URL the catalog does not list (reads and writes nothing)
gmake copier_project PROJECT_NAME=<name> PROJECT_TEMPLATE_REPO=<url>  # Scaffold with Copier (skip the picker; from ~/projects only)
gmake cruft_project PROJECT_TEMPLATE_REPO=<url>                       # Scaffold with Cruft/Cookiecutter (skip the picker; from ~/projects only)
gmake ccds_project PROJECT_TEMPLATE_REPO=<url>                        # Scaffold with the ccds CLI, CCDS v2 (skip the picker; from ~/projects only)
