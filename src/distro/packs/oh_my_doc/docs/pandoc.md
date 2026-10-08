# Pandoc & PDF

[← Back to the README](../../../../../README.md#bundled-software--stack)

Pandoc and a LaTeX engine, installed by the `oh_my_doc` pack and removed with it,
plus seven targets: `gmake pdf_from_md` and `gmake docx_from_md` turn the
project's markdown into a PDF or a Word file, `gmake pdf_open` displays the
result, `gmake csl_from_catalog` fetches a citation style, and the three
`font_from_*` bring a font family — from Windows, Google Fonts or Ubuntu.

## What it brings

| Piece | For | Commands |
| :--- | :--- | :--- |
| Pandoc | converting markdown; `--citeproc` handles the bibliography | `oh_my_doc` |
| XeLaTeX | the PDF engine a template with its own fonts asks for | `xelatex` |
| PDF tools | checking and assembling the results | `pdftotext`, `pdfinfo`, `pdftoppm`, `pdfunite` |

## Installing and removing it

```powershell
.\wsl.ps1 add_pack      # pick the instance, then pandoc
.\wsl.ps1 remove_pack   # the reverse
```

## The targets

From the root of a project under `~/projects`:

```bash
gmake pdf_from_md                            # the folder's markdown -> the PDF beside it
gmake pdf_from_md PDF_SRC=rapport.md         # a document of several, named
gmake pdf_from_md PDF_SRC=rapport.md PDF_OUT=rapport-rv.pdf
gmake pdf_open                               # open the PDF that pdf_from_md built
gmake docx_from_md                           # the same markdown, in Word
gmake csl_from_catalog                       # fetch a citation style from the catalog (menu, or STYLE=name)
```

| Variable | Default | What it is |
| :--- | :--- | :--- |
| `PDF_SRC` | the folder decides | the markdown to build: the only `.md` of the project, or the one the menu offers when there are several. Named — in the command or in the `.env` — it skips the menu, and that is the form a script calls |
| `PDF_OUT` | `PDF_SRC` with `.pdf` | what to write — and, when it is set, the PDF `pdf_open` opens |
| `PDF_TEMPLATE` | `template.tex` when it is there, pandoc's own template otherwise | the template that gives the PDF its look |
| `PDF_VIEWER` | the first viewer installed | what `pdf_open` runs — `evince`, `zathura`, `xpdf`… `sudo apt install evince` is one command away |
| `DOCX_OUT` | `PDF_OUT` with `.docx` | where the Word file lands |
| `DOCX_REFERENCE` | pandoc's own styles | the `.docx` whose styles the Word file inherits |
| `STYLE` | a menu over the catalog | what `csl_from_catalog` fetches — the name zotero.org/styles shows (`ieee`, `vancouver`…) |
| `FONT` | a menu over the catalogue of the target that runs | the family a `font_from_*` takes; a part of the name is enough |

## Bringing a style or a font

A `.csl` is the file that tells pandoc how citations are written and how the
bibliography is ordered — numbers or author-year, superscript or not. A style
belongs to the document, which is why the pack ships none: `gmake
csl_from_catalog` fetches one from the official catalog and drops it in the
project's `csl/` folder, and the YAML header names it with that path
(`csl: csl/<name>.csl`).

A font cannot be aliased into place (XeLaTeX ignores fontconfig
substitutions), so the files themselves are what arrive, and a template only
asks for the family's name. Four ways to one:

| Source | Target | What it brings |
| :--- | :--- | :--- |
| The Windows side | `font_from_windows` | the fonts this machine already owns — Arial is one of them |
| Google Fonts | `font_from_google` | ~1 800 free families, into `~/.local/share/fonts/google/<family>/` |
| The Ubuntu archive | `font_from_ubuntu` | ~200 `fonts-` packages, installed by apt |
| Anywhere | — | a `.ttf` dropped into `~/.local/share/fonts/` is one `fc-cache -f` away |

The first two copy into `~/.local/share/fonts/`, the third installs a package
(`/usr/share/fonts/`) — none of them is the pack's, and removing the pack
leaves them where they are.

A font that must travel **with the project** goes in it, and the template
names the file: `\setmainfont{arial.ttf}[Path=fonts/]`. The `font_from_*`
targets put a family on the machine once, and leave the templates that name it
as they are (`\setmainfont{Arial}`).

Any of pandoc's other outputs is one flag away, with no LaTeX involved:
`-o rapport.html`, `-o rapport.epub`.

## When the build stops

| Message | What it means |
| :--- | :--- |
| `No markdown files found in the current folder.` | there is nothing to build here |
| `No PDF in this folder - gmake pdf_from_md builds one.` | `pdf_open` found no `.pdf` here |
| `File <name>.csl not found in resource path` | the CSL style named in the YAML is not beside the document |
| `Unable to load picture or PDF file '<name>'` | an image the document calls is missing |
| `The font Arial cannot be found` | the family is not on this machine — `gmake font_from_windows FONT=Arial` |
| `Something's wrong--perhaps a missing \item`, at `\end{CSLReferences}` | the template's `$if(csl-refs)$` block is from an older pandoc: `pandoc -D latex` prints the block of the installed one |
