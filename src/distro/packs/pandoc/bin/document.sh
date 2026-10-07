#!/usr/bin/env bash
# ==============================================================================
# THE PANDOC PACK - THE SCRIPTS BEHIND `pdf_from_md`, `pdf_open` AND `docx_from_md`
# ==============================================================================
# The targets call this, one line each: the questions and the work live here.
#
# Three modes:
#   document.sh          builds the PDF (pdf_from_md)
#   document.sh open     opens a built PDF (pdf_open)
#   document.sh docx     writes the same document in Word format (docx_from_md -
#                        pandoc writes .docx itself: no Word, no Office)
#
# Which markdown: PDF_SRC when the .env or the command line names one (the only
# path that needs no terminal); else the folder's only .md; several: fzf asks,
# and Escape is a decision; none: one line, and out. `pdf_open` asks which PDF
# for the same reason - it opens results, not sources.
#
# This output stays inside the instance: the ASCII rule of install.sh and
# remove.sh is about wsl.exe, not about a target.

set -euo pipefail

# PDF_SRC, PDF_OUT, PDF_TEMPLATE, PDF_VIEWER, DOCX_OUT and DOCX_REFERENCE
# arrive from the environment: the Makefile exports everything it loaded -
# nothing is parsed a second time.
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

# One menu, one shape: fzf, the choice in CHOICE. A menu needs a terminal -
# Escape (130) is a decision, not a failure: one line and exit 0, so make must
# not write "Error" over it.
CHOICE=""
choose_one() {
    local prompt=$1 status
    shift
    if CHOICE=$(printf '%s\n' "$@" | fzf --exact --prompt="$prompt > " --info=inline --layout=reverse); then
        [ -n "$CHOICE" ] || die "Nothing chosen."
    else
        status=$?
        if [ "$status" -eq 130 ]; then
            printf 'Nothing chosen.\n'
            exit 0
        fi
        die "No choice made - a menu needs a terminal."
    fi
}

# --- the one question a build asks: replacing a file that already exists ------
#
# An existing output is not replaced in silence - it can be annotated, or a
# name chosen once and forgotten. The answer is a menu: overwrite, cancel,
# save as... (the name asked plainly, nothing pre-filled).
#
# Escape and cancel are decisions: one line and exit 0. A menu that cannot be
# drawn (no terminal) lets the build go on, replacing - a caller that wants
# another name says so in PDF_OUT or DOCX_OUT.
settle_overwrite() {
    local file=$1 answer choice status
    while [ -e "$file" ]; do
        printf '%s already exists (%s, %s).\n' \
            "$file" "$(du -h "$file" | cut -f1)" "$(date -r "$file" '+%Y-%m-%d %H:%M')"
        if choice=$(printf '%s\n' overwrite cancel 'save as...' |
            fzf --exact --prompt="action > " --info=inline --layout=reverse); then
            case "$choice" in
            overwrite)
                OUT=$file
                return 0
                ;;
            cancel)
                printf 'Nothing written.\n'
                exit 0
                ;;
            'save as...')
                printf 'New name: '
                if read -r answer && [ -n "$answer" ]; then
                    # A name of its own; the loop asks again if THAT one
                    # exists too - nothing is replaced in silence, twice over.
                    file=$answer
                    continue
                fi
                printf 'Nothing written.\n'
                exit 0
                ;;
            esac
        else
            status=$?
            # fzf exits 130 on Escape or Ctrl-C: a decision. Any other failure
            # is the menu that could not be drawn, and the build goes on.
            if [ "$status" -eq 130 ]; then
                printf 'Nothing written.\n'
                exit 0
            fi
            OUT=$file
            return 0
        fi
    done
    OUT=$file
}

MODE=${1:-build}
SRC=""
OUT=""

# --- the builds: which markdown ------------------------------------------------

if [ "$MODE" != open ]; then
    if [ -n "${PDF_SRC:-}" ]; then
        SRC=$PDF_SRC
        [ -f "$SRC" ] || die "PDF_SRC=$SRC: no such file in $(pwd)."
    else
        # nullglob, so a folder with no .md at all hands the array nothing
        # rather than the pattern itself.
        shopt -s nullglob
        files=(*.md)
        shopt -u nullglob
        case ${#files[@]} in
        0)
            die "No markdown files found in the current folder."
            ;;
        1)
            SRC=${files[0]}
            ;;
        *)
            choose_one "document" "${files[@]}"
            SRC=$CHOICE
            ;;
        esac
    fi

    # --- built where -----------------------------------------------------------
    # PDF_OUT, or the source's name with .pdf.
    OUT=${PDF_OUT:-}
    [ -n "$OUT" ] || OUT=${SRC%.md}.pdf
fi

# --- docx: the same document, in Word ------------------------------------------
#
# A .docx is Office XML and pandoc writes it itself - no Word, no Office. Its
# LOOK comes from a reference document whose styles pandoc copies
# (DOCX_REFERENCE); without one, pandoc's default styles.
if [ "$MODE" = docx ]; then
    docx_out=${DOCX_OUT:-}
    [ -n "$docx_out" ] || docx_out=${OUT%.pdf}.docx
    REF_ARGS=()
    if [ -n "${DOCX_REFERENCE:-}" ]; then
        [ -f "$DOCX_REFERENCE" ] || die "DOCX_REFERENCE=$DOCX_REFERENCE: no such file in $(pwd)."
        REF_ARGS=(--reference-doc="$DOCX_REFERENCE")
    fi
    settle_overwrite "$docx_out"
    docx_out=$OUT
    echo "📄 Building $SRC -> $docx_out (Word)..."
    pandoc "$SRC" --citeproc "${REF_ARGS[@]}" -o "$docx_out"
    echo "✅ $docx_out ($(du -h "$docx_out" | cut -f1))"
    exit 0
fi

# --- pdf_open: which PDF, and hand it to something that displays it ------------
#
# The pack installs no viewer - each is a matter of taste, and none is needed
# to build. This asks the instance, in this order:
#   - PDF_VIEWER, when the project's .env or the command line names one;
#   - the viewers people install by hand, the convivial one first;
#   - Windows, through explorer.exe, when the instance can reach it (wslpath
#     for the path). Interop off shuts this door, and the line below says what
#     to do instead.
if [ "$MODE" = open ]; then
    if [ -n "${PDF_OUT:-}" ]; then
        # Named outright: the PDF the project writes, wherever the build put it.
        OUT=$PDF_OUT
    elif [ -n "${PDF_SRC:-}" ]; then
        # The source is named, so the PDF is the one the build derives from it
        # - and PDF_SRC named a file that is not built yet is said, not built
        # in silence: naming a source is a choice, and this target opens.
        OUT=${PDF_SRC%.md}.pdf
    else
        shopt -s nullglob
        pdfs=(*.pdf)
        shopt -u nullglob
        case ${#pdfs[@]} in
        0)
            die "No PDF in this folder - gmake pdf_from_md builds one."
            ;;
        1)
            OUT=${pdfs[0]}
            ;;
        *)
            choose_one "pdf" "${pdfs[@]}"
            OUT=$CHOICE
            ;;
        esac
    fi

    [ -f "$OUT" ] || die "$OUT is not built yet - gmake pdf_from_md builds it."
    if [ -n "${PDF_VIEWER:-}" ]; then
        command -v "$PDF_VIEWER" >/dev/null 2>&1 ||
            die "PDF_VIEWER=$PDF_VIEWER: not installed in this instance. Install it, or drop the setting - the viewers are tried in turn without it."
        exec "$PDF_VIEWER" "$OUT"
    fi
    for viewer in evince zathura xpdf okular mupdf; do
        if command -v "$viewer" >/dev/null 2>&1; then
            exec "$viewer" "$OUT"
        fi
    done
    if command -v explorer.exe >/dev/null 2>&1; then
        exec explorer.exe "$(wslpath -w "$OUT")"
    fi
    die "No PDF viewer in this instance, and no way through to Windows.
One command installs one: sudo apt install evince
Or copy it out and open it there: cp $OUT /mnt/d/"
fi

# --- pdf_from_md: build it -----------------------------------------------------

# PDF_TEMPLATE, or template.tex when the project has one - pandoc's own
# otherwise. An array, not a string: an empty variable between two arguments
# would vanish into the word split.
tpl=${PDF_TEMPLATE:-template.tex}
if [ -f "$tpl" ]; then
    TEMPLATE_ARGS=(--template="$tpl")
else
    TEMPLATE_ARGS=()
    printf '   no %s in this project: pandoc own template will be used.\n' "$tpl"
fi

# --citeproc: the bibliography and the CSL style come from the document's own
# YAML header. set -e is on: a failed build stops here, before the tick line -
# a success line over a failed build would be the one lie this script could
# tell.
settle_overwrite "$OUT"
echo "📄 Building $SRC -> $OUT (pandoc + xelatex)..."
pandoc "$SRC" --citeproc "${TEMPLATE_ARGS[@]}" -o "$OUT" --pdf-engine=xelatex
echo "✅ $OUT ($(du -h "$OUT" | cut -f1))"
