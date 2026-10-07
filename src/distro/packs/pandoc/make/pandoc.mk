# ==============================================================================
# PDF, WORD, STYLE AND FONT TARGETS (PANDOC)
# ==============================================================================
# What this pack adds, seven targets. `pdf_from_md` and `docx_from_md` build
# the project's markdown and `pdf_open` displays the result - one resolution
# for the three, in bin/document.sh. `csl_from_catalog` brings a citation
# style; the three `font_from_*` bring a font family, each from its own
# catalogue: the Windows side, Google Fonts, the Ubuntu archive.
#
# The names say where they start: these targets are good at markdown, the
# document's own YAML carrying the bibliography and the citation style.
#
# The document targets are ordinary project targets - the gate holds them to a
# project root. The three font_from_* are exempt, and declared so below: a
# font is the machine's, and "which family do I have?" is asked from wherever
# one stands.
#
# The variables - PDF_SRC, PDF_OUT, PDF_TEMPLATE, PDF_VIEWER, DOCX_OUT,
# DOCX_REFERENCE, STYLE, FONT - each default to the ordinary case; the pack's
# page has the table. A project fixes its own in its .env, and the command
# line still wins.

GATE_EXEMPT_GOALS += font_from_windows font_from_google font_from_ubuntu

PDF_TEMPLATE ?= template.tex

# The scripts, resolved from this module's own path: make/ and bin/ are
# neighbours inside the pack folder, and the pack moves as one folder.
#
# A script variable must never carry the name of something a person sets: a
# variable called FONT once held this path, and the shell's bare `export`
# handed it to the script as the family name to copy.
DOCUMENT := $(dir $(lastword $(MAKEFILE_LIST)))../bin/document.sh
CSL_FROM_CATALOG := $(dir $(lastword $(MAKEFILE_LIST)))../bin/csl.sh
FONT_FROM_WINDOWS := $(dir $(lastword $(MAKEFILE_LIST)))../bin/font.sh
FONT_FROM_GOOGLE := $(dir $(lastword $(MAKEFILE_LIST)))../bin/font_google.sh
FONT_FROM_UBUNTU := $(dir $(lastword $(MAKEFILE_LIST)))../bin/font_ubuntu.sh

pdf_from_md: ## Build the project's markdown into a PDF (pandoc + XeLaTeX)
	@$(DOCUMENT)

pdf_open: ## Open a built PDF (PDF_OUT's, PDF_SRC's, or the folder's own - the menu lists those)
	@$(DOCUMENT) open

docx_from_md: ## Build the project's markdown in Word format (.docx) - Word is not needed
	@$(DOCUMENT) docx

csl_from_catalog: ## Fetch a citation style from the official CSL catalog, into this project
	@$(CSL_FROM_CATALOG)

font_from_windows: ## Copy a font family from the Windows side
	@$(FONT_FROM_WINDOWS)

font_from_google: ## Copy a font family from Google Fonts (~1 800 free families - menu, or FONT=)
	@$(FONT_FROM_GOOGLE)

font_from_ubuntu: ## Install a font package from the archive (menu, or FONT=)
	@$(FONT_FROM_UBUNTU)
