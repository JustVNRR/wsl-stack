# Project Scaffolding

[← Back to the README](../../../README.md#optional-tooling)

## Targets

| Target | Action |
|---|---|
| `copier_project` | Scaffold a project with Copier, from `~/projects` only (the `fnew` picker delegates here) |
| `cruft_project` | Scaffold a project with Cruft / Cookiecutter, from `~/projects` only (the `fnew` picker delegates here) |
| `ccds_project` | Scaffold a project with the `ccds` CLI (Cookiecutter Data Science v2), from `~/projects` only (the `fnew` picker delegates here) |

All three only run from `~/projects` itself. 

## Variables

| Variable | Required | Notes |
|---|---|---|
| `PROJECT_NAME` | copier only | Destination directory, created relative to the current directory — cruft and ccds ask for the name themselves |
| `PROJECT_TEMPLATE_REPO` | yes | Anything Copier/Cruft accepts (`gh:` shorthand or full git URL) |
| `PROJECT_TEMPLATE_VERSION` | no | Pin a template ref/tag — passed as `--vcs-ref` (Copier) or `--checkout` (Cruft and ccds) |
| `TEMPLATE_PACK` | no | Pack whose step runs once the template is copied (`fnew` passes the row's pack; a direct call reads it from `.env.global`) |

## The `fnew` picker

Type `fnew` from `~/projects`:

```console
$ fnew
# → fuzzy-pick a template (the pack it came from, the tool, the pinned version)
Project folder: my-analysis
📁 Creating project in: /home/you/projects/my-analysis
🏗️  Scaffolding project with Copier...
🎤 ...then answer the template's own questions (repo name, description...)...
📝 Creating ./.env from the project's .env.sample...
🐍 uv project detected (uv.lock or [project] table) — running uv sync...
🪄 Configuring direnv...
✅ Project ready in my-analysis/
```

## Trying a template without adding it

A template does not have to be in a catalog to be used:

```bash
cd ~/projects
fnew gh:owner/repo            # Copier by default
fnew gh:owner/repo cruft      # ...or Cruft, for a cookiecutter template
fnew gh:owner/repo ccds       # ...or the ccds CLI (cookiecutter-data-science v2)
fnew gh:owner/repo cruft v1   # ...pinned to a ref
```

## The catalogs

`fnew` reads the catalog of **every installed pack** —
`packs/<name>/cheatsheets/templates.tsv` — and shows each row with the pack it
was read from:

```text
python · copier @9.18.2  |  astral-sh/uv-fastapi  |  FastAPI service
java   · copier          |  spring-guides/gs-boot |  Spring Boot minimal
```

The optional `version` column pins a template ref — useful when a template's
default branch targets a different tool.

### The three tools

They are not interchangeable, and one repository can appear once per tool:

| Tool | What it runs | Worth knowing |
| :--- | :--- | :--- |
| `copier` | `copier copy` | stores your answers in `.copier-answers.yml`, so `copier update` can replay them |
| `cruft` | `cruft create` | cookiecutter-based; `cruft update` keeps a generated project in step with its template |
| `ccds` | the `ccds` command | the current Cookiecutter Data Science scaffold, on a branch that is no longer a plain cookiecutter template |

### Adding a line

`fnew` ignores any line that is not four tab-separated columns, and says so on
stderr, naming the catalog it found the row in — a row typed with spaces would
otherwise simply never appear in the picker, which looks exactly like an empty
catalog. The safe way to append one is a `printf` with an explicit `\t`, which
cannot turn into spaces:

```bash
printf '%s\t%s\t%s\t%s\n' \
  'gh:owner/repo' 'copier' '' 'What it is (and the fact that justifies it)' \
  >> ~/.config/packs/python/cheatsheets/templates.tsv
```

## Skipping the picker

```bash
gmake copier_project PROJECT_NAME=my-analysis PROJECT_TEMPLATE_REPO=gh:owner/python-copier-template-ds
gmake cruft_project PROJECT_TEMPLATE_REPO=gh:owner/cookiecutter-data-science PROJECT_TEMPLATE_VERSION=v1
```
