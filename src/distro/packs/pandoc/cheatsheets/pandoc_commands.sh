# ==========================================
# PANDOC / PDF CHEATSHEET
# requires: pandoc
# ==========================================
# Pandoc, the LaTeX engine and the PDF tools the `pandoc` pack installs
# (`.\wsl.ps1 add_pack`), and the seven targets it adds.
# The pack is removed the same way; its page is packs/pandoc/docs/pandoc.md.
# Offered only while pandoc is installed - the header above is what hides the
# sheet when it was removed by hand.

# --- 1. THE PROJECT TARGETS (from the root of a project) ---
gmake pdf_from_md                             # The folder's markdown: the only .md, or the one the menu offers
gmake pdf_from_md PDF_SRC=rapport.md          # Name it directly - no menu, the form scripts use
gmake pdf_from_md PDF_SRC=rapport.md PDF_OUT=rapport-rv.pdf   # Write it under another name
gmake pdf_open                                # Open a built PDF (PDF_OUT's, PDF_SRC's, or the folder's - menu)
gmake docx_from_md                            # The same markdown in Word - Word is not needed
# An existing PDF or Word is never replaced in silence: a menu asks - overwrite, cancel, save as...

# --- 2. BRINGING WHAT A DOCUMENT NEEDS ---
gmake csl_from_catalog                        # A citation style: menu over the official catalog (~10 000 styles)
gmake csl_from_catalog STYLE=ieee             # ... or named, no menu - the name zotero.org/styles shows
gmake font_from_windows                       # A font family: menu over the Windows side
gmake font_from_windows FONT=times            # ... or named; Times New Roman's template asks for it by that name
gmake font_from_google                        # ... or from Google Fonts (~1 800 free families)
gmake font_from_google FONT=roboto            # ... named, no menu
gmake font_from_ubuntu                        # ... or from the Ubuntu archive (~200 fonts- packages)
gmake font_from_ubuntu FONT=noto              # ... named

# --- 3. WHAT THE DOCUMENT CARRIES (its YAML header) ---
# ---
# bibliography: bibliographie.bib             # the .bib beside the document
# csl: csl/vancouver-superscript.csl          # the style, in the project's csl/ folder
# citeproc: true                              # render the citations
# ---

# --- 4. THE COMMAND BEHIND THE TARGET ---
pandoc rapport.md --citeproc --template=template.tex -o rapport.pdf --pdf-engine=xelatex
pandoc rapport.md --citeproc -o rapport.docx  # Word output, no LaTeX involved
pandoc --version                              # Which version is installed

# --- 5. THE PDF TOOLS (poppler) ---
pdfinfo rapport.pdf                           # Pages, size, engine - the facts
pdftotext -layout rapport.pdf - | less        # The text, to check or to grep
pdftotext -layout rapport.pdf - | grep -n "rétention"   # Find a passage and its page context
pdftoppm -png -f 1 -l 1 rapport.pdf page      # Page 1 as page-1.png
pdfunite rapport.pdf annexes.pdf envoi.pdf    # Merge PDFs: the document and its annexes, one file

# --- 6. WHEN THE BUILD STOPS ---
ls *.md *.bib *.csl                           # What the command needs, beside the document
pandoc -D latex | less                        # The template pandoc ships (for the CSLReferences block)
fc-list Arial                                 # The family on this machine: one line per face, or nothing
