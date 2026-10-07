# Instance Administration

`wsl.ps1`, at the root of the repository, is the only thing to type. The
commands themselves live in `src\windows\`.

```powershell
.\wsl.ps1               # which command? - the menu below
```

```text

WSL Stack
  > gui          open graphical fleet manager
    list         list our instances and the archives
    build        build an instance from the image
    start        start a stopped instance
    stop         stop a running instance
    restart      restart an instance
    shell        open a shell inside an instance
    add_pack     install a pack into an instance
    remove_pack  uninstall a pack from an instance
    manage_packs choose the packs an instance should carry
    theme        choose the icon, font and colours
    unregister   remove an instance
    archive      write an instance to a named archive
    restore      rebuild an instance from an archive
    duplicate    copy an instance under another name
    shrink       reclaim the space an instance has freed
    wslconfig    open the Windows-wide WSL settings
  up/down to move, Enter to choose, Escape to cancel
```

The same menu every command shows when it asks something — the instances, the
packs, the archives — answered the same way. Where there is no console to read
a key from (a script, a pipe), it becomes the numbered prompt, and the answer is
typed.

Going down a level, or coming back up, clears the screen: a visit is one menu at
a time, and the output above goes with it. A run whose answers are piped in
keeps every line — a log is read, not looked at.

Every line says what it **is** rather than what colour to write it in, and takes
that kind's colour from the colour scheme of the window it is written in — so
the output stays readable on a dark scheme and on a light one. With no scheme to
read, the colours a console has always had are used.

## All commands

| Command | What it does |
| :--- | :--- |
| [`.\wsl.ps1 gui`](#gui) | open graphical fleet manager |
| [`.\wsl.ps1 list`](#list) | list our instances and the archives |
| [`.\wsl.ps1 build`](#build) | build an instance from the image |
| [`.\wsl.ps1 start`](#start) | start a stopped instance |
| [`.\wsl.ps1 stop`](#stop) | stop a running instance |
| [`.\wsl.ps1 restart`](#restart) | restart an instance |
| [`.\wsl.ps1 shell`](#shell) | open a shell inside an instance |
| [`.\wsl.ps1 add_pack`](#add_pack) | install a pack into an instance |
| [`.\wsl.ps1 remove_pack`](#remove_pack) | uninstall a pack from an instance |
| [`.\wsl.ps1 manage_packs`](#manage_packs) | choose the packs an instance should carry |
| [`.\wsl.ps1 theme`](#theme) | choose the icon, font and colours |
| [`.\wsl.ps1 unregister`](#unregister) | remove an instance |
| [`.\wsl.ps1 archive`](#archive) | write an instance to a named archive |
| [`.\wsl.ps1 restore`](#restore) | rebuild an instance from an archive |
| [`.\wsl.ps1 duplicate`](#duplicate) | copy an instance under another name |
| [`.\wsl.ps1 shrink`](#shrink) | reclaim the space an instance has freed |
| [`.\wsl.ps1 wslconfig`](#wslconfig) | open the Windows-wide WSL settings |

## Which WSL instances are ours

Every instance created by `build`, `restore` or `duplicate` carries a
**marker**, named `.wsl-stack`, in its own folder next to its
virtual disk:

```text
D:\WSL\ubuntu-template\
├── ext4.vhdx
├── terminal-icon.png        drawn from the name, and kept here
├── instance.json            its look: the font, the colours, the icon's recipe
└── .wsl-stack
```

## Where things live

One working folder, and nothing to decide: `D:\WSL` when the D: drive exists,
`%USERPROFILE%\WSL` otherwise.

```text
D:\WSL\
├── ubuntu-template\          an instance is a folder: its disk, its marker
├── template-bac\
└── archives\                 an archive is a folder too
    └── ubuntu-template\
        ├── ubuntu-template.tar.gz   the instance's file system
        ├── instance.json            its look, the same file the instance keeps
        └── terminal-icon.png        its icon
```

---

## `gui`

The fleet manager, in a window: the mouse-first way in, over the same engine
everything else asks.

```powershell
.\wsl.ps1 gui
```

It lists our instances - state and size, the same list `list` prints - with,
on each row, its verbs: **open** (a new terminal window on the instance's
own profile - its icon, colours and font ride along - where `shell` would
borrow the console), **start** or **stop** (whichever the state allows),
**edit** (the packs: tickboxes with the same rules as `manage_packs` -
requirements and removals shown live underneath, with their reasons, and its
APPLY greys while there is nothing to do - the run opens in a console window
of its own, where the déroulé, the same
lines `manage_packs` prints, can be watched), **appearance** (the look:
icon letters and colours, font and colour scheme - the same lists the
`theme` menu shows, note included - or an image of your own through the
file picker, everything shown live in a small terminal preview),
**duplicate** (a copy under a name of its own: the engine's own guard
refuses a taken name, the room for twice the disk is checked, and a running
source is stopped for the read and started again after), **archive** (the same backup
`archive` writes: it asks the name, the instance's own prefilled, and stops
a running instance for the export, starting it again once the tar is done),
**Compact** (the same compact `shrink` runs, behind a gate - the instance
must be idle, and the removal's archive-first box is offered - and the row
shows a small scrolling band while it works), and the trash, which opens the same gate
`unregister` puts up - what is lost, spelled out, and the exact
name typed back - then removes it through the same engine. The archives sit
in the same list, one alphabetical walk with the instances - a same-named
archive shows right beside its instance - status **Archived** and the tar's
size, with **restore** and the trash alone on their row: restore asks the
name the new instance takes (the archive's own, prefilled - an empty name
cancels), then imports through the same engine `restore` uses, the row
scrolling its band while it works - the archive is kept; the trash opens a
gate of the same manners as the instance's - what is lost, spelled out, and
the exact name typed back - and the folder goes for good, tar and look
together. The header carries its icons beside the title: **+**, a new
instance - name, user and packs in one form, a name that already exists
refused right there, and a Docker that is not running offered its start
right over the form - whose run then opens a console window of its own
(Docker's questions and the first shell included, since only it can ask
them); the refresh, which rereads the fleet; and the gear, the window's own
face - the font, its size and its colour theme, dark and light versions
shipped (assets\colours) - with the sun and the moon beside it, switching
the current theme's version on the spot.
Nothing here exists only in the window: it is a keystroke-free way in, not a
second engine.

---

## `list`

Lists all WSL instances carrying the `.wsl-stack` marker.

```powershell
.\wsl.ps1 list
```

```text
Instances of this template:
   1.  template-bac       running       1.1 GB  D:\WSL\template-bac
   2.  ubuntu-template    stopped       2.4 GB  D:\WSL\ubuntu-template

Archives in D:\WSL\archives (most recent first):
      ubuntu-template            29 MB    2026-09-23 16:50
```

### Folders left behind by an unregistered instance

Removing an instance happens in two steps — Windows forgets the distribution,
then the folder and its disk are erased — and the second sometimes fails. The
folder stays, marker included, taking up room; no instance claims it and no
command removes it. `list` says it exists, what it weighs, and that it is to be
deleted by hand:

```text
Folders left behind by an instance that is gone:
      vieux-test                        1.2 GB  D:\WSL\vieux-test
      No instance claims them, and no command removes them: delete them by hand.
```

---

## `build`

Builds a new instance from the rootfs image, asks for the user the instance
will open as, walks you through the first-boot onboarding (password or
passwordless sudo, timezone), applies the Windows Terminal profile, and opens
a shell in it.

```powershell
.\wsl.ps1 build
```

It takes no options: it asks for the name, for the folder, for the user the
instance will open as, and — when this checkout carries packs — which of them
the instance should start with.

```text
==> Creating a new instance
Name of the instance (CTRL+C to abort): ubuntu-ml-dev
Create [D:\WSL\ubuntu-ml-dev]? [Y/n]
```

The name is checked as it is typed (letters, digits, `.`, `_`, `-`), then the
location is shown and confirmed — Enter accepts it, and it is the folder every
other command writes to. Answer `n` to put the disk somewhere else: the folder
question follows.

An answer that cannot be used comes back with the reason, and the question is
asked again:

- the folder is, or holds, the folder of another instance — erasing it would
  take that instance with it;
- the folder already exists — choose another location.

Docker Desktop must be running: the script checks before asking anything.

One build at a time: started while another build is still working, it stops
before asking anything and says so.

If an instance already carries the name, it shows the red warning and asks you
to **type the exact name**: a rebuild erases that instance and everything in it.

The packs are asked before anything is created:

```text
Packs for 'ubuntu-ml-dev'
  > [ ] gcp          The Google Cloud CLI (about 409 MB installed)
    [ ] vision       ffmpeg, ImageMagick and Tesseract OCR (about 500 MB)
  up/down to move, space to check, Enter to apply, Escape to cancel
```

Escape, or an empty checklist, is a real answer: no pack, and the build goes on.
A rebuild arrives with the boxes ticked for what the instance being replaced
carries, so its packs come back without being chosen again. What is ticked is
summarised and confirmed as in `manage_packs` — one question for the whole list.

They are installed **once the instance exists** — after the deployment, and the
`* Packs` line of the screen that announces it carries the outcome. A pack that
fails to install does not fail the build: the instance is built, the pack's
files are taken back out, and the build names the pack and points at
`.\wsl.ps1 manage_packs`. The shell that opens repeats the same news.

The last question is the user the instance will open as — a lowercase letter
first, then lowercase letters, digits, `_` and `-`. The Windows account's
name is offered in brackets (`[jean-dupont]`) when it cleans into a usable
one, and Enter takes it. It is asked with the rest, so the instance is born with it
and the first-boot onboarding does not ask again. The name is checked against
the image's own accounts just before the import; a name the image already
carries is asked again there, before anything is created.

---

## `start`

Starts a stopped instance, without opening a shell in it.

```powershell
.\wsl.ps1 start
```

Only stopped instances are listed — an instance already running has nothing to
do here:

```text
Stopped instances - the ones that can be started:
   1.  template-bac                  1.1 GB
   2.  ubuntu-template               2.4 GB
   0.  Cancel
```

To work inside it, open its Windows Terminal profile — it is the profile the
build wrote, icon, font and colours included.

---

## `stop`

Stops a running instance.

```powershell
.\wsl.ps1 stop
```

Only running instances are listed:

```text
Running instances - the ones that can be stopped:
   1.  template-bac                  1.1 GB
   0.  Cancel
```

**Whatever is open in there and not saved is lost.** What is written on the
disk stays: stopping ends the running processes, it does not touch the disk.
Asked once, and the default is to go ahead.

---

## `restart`

Stops an instance and starts it again, in one command.

```powershell
.\wsl.ps1 restart
```

Only running instances are listed — a stopped one has `start`:

```text
Running instances - the ones that can be restarted:
   1.  template-bac                  1.1 GB
   0.  Cancel
```

**Whatever is open in there and not saved is lost**, exactly as with `stop`.
The disk is not touched: the instance comes back with everything it had
written.

It is what applies a change to the files WSL reads when it starts —
`/etc/wsl.conf` and `/etc/resolv.conf`, which `gmake wsl_config` and
`gmake dns_resolve` open. When it is back up, open it again from its Windows
Terminal profile.

---

## `shell`

Opens a shell in one of our instances — the quickest way in when you are
already in a terminal.

```powershell
.\wsl.ps1 shell
```

The instance comes from the list, like everywhere else:

```text
Our Instances
   1.  template-bac                   running      1.1 GB
   2.  ubuntu-template                stopped      2.4 GB
   0.  Cancel
```

An instance that was stopped is started on the way in: `start` first is not
needed. The shell opens **in your home**, not in the Windows folder you ran the
command from — the same thing the build does when a new instance is ready.

`exit` in there brings you back to PowerShell.

---

## `add_pack`

Installs a pack into an instance: the tool itself (its packages and its APT
repository) and the pack's files — its gmake targets, its cheatsheets, its
environment samples.

```powershell
.\wsl.ps1 add_pack
```

Two lists, then it installs:

```text
Our Instances
   1.  template-bac                   running      1.1 GB
   2.  ubuntu-template                stopped      2.4 GB
   0.  Cancel
Which one? (0 to cancel) 2

       Already in 'ubuntu-template': python
Packs available for 'ubuntu-template':
   1.  gcp          The Google Cloud CLI (about 409 MB installed)
   0.  Cancel
Which one? (0 to cancel) 1

==> Installing 'gcp' in 'ubuntu-template'...
```

Only the packs the instance does not have yet are offered. The packs are the
folders under `packs\`: a folder carrying a `pack.conf` is a pack.

The pack's files travel from the Windows checkout into the instance — through
the mounted drives when they are there, and through Windows' own
`\\wsl.localhost` share when the instance has them unmounted (`gmake
automount_down`) — so a pack arrives either way, and its scripts are made
executable on arrival.

The list is the packs a **user** chooses. A pack that says `PACK_VISIBLE := no`
in its `pack.conf` is never in it: it is a shared dependency — `devops` is the
project targets several packs need — and it arrives with the pack that requires
it, before it, in the same run:

```text
==> Installing 'devops' in 'ubuntu-template'...
    It comes with 'gcp', which requires it.

==> Installing 'gcp' in 'ubuntu-template'...
```

**It asks nothing.** The packages and the APT address belong to root, and the
pack's `install.sh` takes `sudo` where it needs to - but the engine opens
WSL's own passwordless root door to `sudo` for the length of the installs, and
closes it after: the run never stops to ask. (Run `install.sh` by hand inside
the instance and `sudo` asks as usual.)

Nothing has to be reopened afterwards: `gmake` reads the pack's files at every
run, and `fcheat` re-reads its cheatsheets at every opening.

One step is left for you, and the command names it at the end: `gmake
env_global_enable`, inside the instance, merges the pack's environment samples
into your `.env.global`. Nothing writes into that file on your behalf — it is
yours, and so is the project's `.env`.

If the installation fails, the pack's files are removed and the script says so.
What the install had already put in place stays; running `add_pack` again picks
up where it stopped.

---

## `remove_pack`

The reverse: the pack's own `remove.sh` runs first — the tool and its APT
repository leave the system — then its folder leaves the instance.

```powershell
.\wsl.ps1 remove_pack
```

```text
Packs installed in 'ubuntu-template':
   1.  gcp
   0.  Cancel
Which one? (0 to cancel) 1

==> Removing from 'ubuntu-template': gcp
Remove 'gcp'? [Y/n] y
```

The list comes from the instance, not from this repository: a pack installed by
an older copy is still removable, because its `remove.sh` travelled with it.
What is *not* in it is a pack marked invisible: it is nobody's to remove by
hand, since removing it would pull the base out from under a pack still
installed. It leaves with the last pack that requires it:

```text
==> Removing from 'ubuntu-template': python, devops
    'devops' goes with 'python': nothing installed requires it any more.
Remove python, devops? [Y/n]
```

The chosen pack goes first, and the packs it held up follow: that order is what
lets a `remove.sh` ask whether a neighbour still claims its packages and get
the right answer.

No password is asked: the removal runs behind WSL's own root door. What the
pack left in your files is not touched: your `gcloud` logins, the variables it
copied into `.env.global`.

A pack installed before packs carried a `remove.sh` is a special case: the
command says so, and deleting its files undoes nothing on the system side.

### What it takes back after the pack is gone

A `remove.sh` names what it installed — `ffmpeg`, the Google CLI — and takes
those away. What arrived with them as *dependencies* is nobody's to name, and it
is the bulk of the weight. So the command asks one more question, and removes
only if both answers come back empty:

| Question | Who answers |
| :--- | :--- |
| Does any installed package depend on it? | apt — the automatic packages no installed package needs any more |
| Does anything **outside apt** link its libraries? | `ldd` over `~/.local`, `~/projects`, `/usr/local` and `/opt`, each library traced to its package with `dpkg -S` |

A program apt knows nothing about — a venv, a binary you built — stops the
cleanup, and the command names it:

```text
    Kept in place: something outside apt still links what would go.

    /usr/local/bin/mytool links libtesseract5, liblept5, libtiff6
    Remove the package by hand if that program is gone.
```

When nothing answers yes, it goes: `46 dependencies nothing needs any more:
78 MB`.

It is the one place the repository runs `autoremove`, and it never runs it
blind.

---

## `manage_packs`

Several packs at once. The list shows every pack this repository carries, the
ones the instance already has arrive checked, and what comes back is applied:
the missing ones installed, the unchecked ones taken out.

```powershell
.\wsl.ps1 manage_packs
```

```text
Packs for 'new_distro2'
  > [x] gcp          The Google Cloud CLI (about 409 MB installed)
    [ ] vision       ffmpeg, ImageMagick and Tesseract OCR (about 500 MB)
  up/down to move, space to check, Enter to apply, Escape to cancel
```

Space checks and unchecks, Enter applies, Escape cancels. Each list gets a line
when it has something in it, and one question covers them both:

```text
Will install : python, devops
               (devops: required by python)
Will remove  : gcp
               Their tools leave, and the dependencies nothing needs any more.

Proceed? [Y/n]
```

A pack nobody ticked gets its reason on the line under the list — it arrives
because something requires it, or leaves because nothing does any more.

If the boxes have not moved, it says so and stops there.

### The order

The folders of the packs to add are copied **before** anything is removed: a
pack's `remove.sh` asks which installed pack still claims a package, and a
folder that has just arrived counts — so a package two packs share is left in
place. There is no list of packages compared anywhere: the packs say what they
claim, and the question is asked of the instance.

`add_pack` and `remove_pack` stay what they were, for one pack at a time. A
failure here stops the run where it stands: the pack that failed and the packs
that had not run yet lose their folder, and the command says what was installed,
what failed, what was skipped.

---

## `theme`

What an instance wears: its icon, its font and its colours. The instance is asked
first, once; the menu behind it holds the things that can be changed, and it is
drawn again after each of them — changing the icon and then the font is one
visit.

Escape walks back up the way it came: from the theme menu to the list of
instances, so another one can be picked, and from that list to the prompt.

```powershell
.\wsl.ps1 theme
```

```text
Our Instances
  > ubuntu-ml-dev                running    2,1 GB
    ...

Theme of 'ubuntu-ml-dev'
  > icon    the tile in the tab
    font    what the whole terminal is written in
    color   the background, the text, and sixteen colours
  up/down to move, Enter to choose, Escape to cancel
```

### `icon`

Draws the icon of an instance, or puts an image of yours in its place. The
script the build calls does the drawing, so the letters and the colours follow
the same rule in both places.

It keeps asking — change the colours, then the text, and both are kept; Escape
brings the theme menu back, and nothing moves but the icon.

```text
Icon of 'ubuntu-ml-dev'
  > By Default
    text
    colors
    local file
  up/down to move, Enter to choose, Escape to cancel
```

| Choice | What it does |
| :--- | :--- |
| `By Default` | the letters and the colour pair the name gives |
| `text` | one to three characters, typed — the current ones are the default answer |
| `colors` | one of eight pairs, each shown with your letters on it |
| `local file` | a PNG, JPG, ICO or BMP, copied in place |

The icon is a **file**, not a setting: `terminal-icon.png` in the instance's own
folder, the one its Terminal profile points at. Nothing else is written, and
nothing has to be stopped.

The visit over, Windows Terminal is asked to look again: **nothing appears
while you are still in the menu** — a reload cannot land on a pane that is
running one — and the change shows the moment you leave. The colours change at
once then; the font and the icon belong to a tab as it is opened, so those want
a new one.

Changing one part keeps the other: the recipe of the last drawing — its letters,
its three colours — is noted in the instance's own `instance.json`, the same
file an archive carries, so picking other colours keeps the letters you typed,
and the other way round. An image of your own replaces the picture and leaves
the recipe alone.

The icon travels with the instance: `archive` takes the file and the picture,
`restore` and `duplicate` put both back.

### `font`

Sets what the whole terminal is written in, for one instance.

```text
Font of 'ubuntu-ml-dev'
  > JetBrainsMono NF                 (current)
    JetBrainsMonoNL NF
    MesloLGS NF
    Cascadia Mono NF
    ...
  up/down to move, Enter to choose, Escape to cancel
  Get more Nerd Fonts at https://www.nerdfonts.com
```

The list is the monospaced families Windows has — a profile takes the family,
not a weight — that carry the glyphs a prompt is drawn with, measured by asking
each font file: a font without them draws a box where your prompt has a folder.
The line under the list says where more of them come from.

The font in use is in the list whatever it carries, and marked `(current)`: it
is what you came to look at, and on a machine with no Nerd Font at all it is the
only row there is. The build installs one, so an instance of this template
starts on a font that carries them.

A console writes every row in the font *it* is set to, so no list can show a font
in itself. The preview is the choice: the profile changes, and the next tab is
written in it.

### `color`

Sets the colours of the whole terminal, for one instance.

```text
Colours of 'ubuntu-ml-dev'
  > Campbell
    Campbell Powershell
    CGA
    ...
    One Half Dark                          (current)
    ...
    Vintage Custom
  up/down to move, Enter to choose, Escape to cancel
```

The list is every scheme this machine can be told to use: the ones Windows
Terminal ships — read from the file inside its own package — and the ones you
added or wrote over, your version of a name winning over the shipped one. Each
row is drawn in the colours of its own scheme — its background and its text — and
the one in use is marked `(current)`.

That file is JSON with comments in it, and the command reads it without
touching it — nothing here writes to it: it is Terminal's file.

---

## `unregister`

Removes an instance and everything it left on Windows.

```powershell
.\wsl.ps1 unregister
```

This is the only command that deletes without rebuilding, and it asks twice:

1. It lists the instances and you pick one.
2. It shows the red warning and asks you to **type the exact name**. An empty
   answer aborts, and picking from the list does not replace the typing.
3. It then offers `Archive it before deleting? [y/N]` — default no. Answering
   yes calls `archive` first, and **if the archive fails, nothing is deleted**.
4. It unregisters the distribution, then cleans up what it left behind: the
   installation folder, orphaned Windows Terminal profiles, this repository's
   appearance fragment, and its entry in Docker Desktop's list of integrated
   distros.

### What is lost with the instance

The virtual disk is deleted, so **nothing inside the instance survives**. A
rebuild destroys it the same way. Before either:

| Kept inside the instance | Before you unregister or rebuild |
| :--- | :--- |
| `~/projects/` | Nothing backs it up — push your work to a remote first |
| `~/.ssh/` | A key generated inside cannot be recovered: copy it out, or plan to revoke and regenerate it |
| `~/.config/gcloud/` | Both logins are redoable in minutes ([GCP onboarding](../../packs/gcp/docs/onboarding.md)) |
| `~/.config/zsh/gmake/.env.global` | A handful of lines; `gmake env_global_enable` recreates them from the samples the instance carries |
| `~/.config/packs/python/cheatsheets/templates.tsv` | Only for rows you added inside the instance: `add_pack` copied the file there — move the line into the pack to keep it |

`archive` is the way out: it writes the whole file system to a folder you can
restore from later.

---

## `archive`

Writes an instance to an archive: the file system, **plus what a tar cannot
carry** — the icon and what it is made of, the font and the colour scheme the
instance was using, and whether Docker Desktop knew it.

```powershell
.\wsl.ps1 archive
.\wsl.ps1 archive -Format tar.xz
```

| Option | Default | What it does |
| :--- | :--- | :--- |
| `-Format` | `tar.gz` | `tar`, `tar.gz` or `tar.xz` (`xz` compresses harder, and takes longer) |
| `-AfterExport` | `Ask` | what to do with the instance once the archive is written: `Ask`, `Start`, `Delete`, `Leave` |

If the instance is running, it has to be stopped for the export to read a
consistent disk — the script warns you first, because whatever is open and
unsaved goes with it.

It then shows the archives already taken and proposes the instance's own name:

```text
Archives already in D:\WSL\archives:
  ubuntu-template                    29 MB    2026-09-22 09:12

Name of the archive? [ubuntu-template]
```

Enter accepts it. If the name is taken the proposal moves to
`ubuntu-template-1`, then `-2`, until one is free; typing the name of an
existing archive replaces it, and the script says so first.

Once the archive is written, it asks what should happen to the instance:

```text
What should happen to 'ubuntu-template' now?
  > Start it  (default)
    Delete it (the archive stays)
    Leave it stopped
  up/down to move, Enter to choose, Escape to cancel
```

The default is the state it was found in — the row says `(default)`, and
Escape takes it too. Answering **Delete it** goes through `unregister`, so the
exact name has to be typed again — the archive is what remains.

---

## `restore`

Rebuilds an instance from an archive.

```powershell
.\wsl.ps1 restore
```

It lists the archives, most recent first, and you pick one:

```text
Archives in D:\WSL\archives (most recent first):
   1.  ubuntu-template  -  29 MB, 2026-09-23 16:50
   2.  template-bac     -  31 MB, 2026-09-22 09:12
   0.  Cancel
```

It then asks for the name of the new instance and imports it into
`D:\WSL\<name>`. If an instance already carries that name, it stops and tells
you the command to run first — **it deletes nothing on its own**.

The icon, the font, the colour scheme and Docker Desktop's knowledge of the
instance come back with it, from the values stored next to the tar. If the font
is no longer installed on Windows, the script says so rather than failing.

**The archive is kept**: restoring copies it into a new instance, it does not
consume it.

---

## `duplicate`

Copies an instance under another name, leaving the original alone.

```powershell
.\wsl.ps1 duplicate
```

The source comes from the list, and the copy's name is typed — it is the one
name that cannot be picked, because nothing exists under it yet. A name already
taken is refused: this command never unregisters anything, so a busy name is a
dead end rather than a problem to solve.

If the source is running, it has to be stopped for the copy — the script asks
first, and starts it again afterwards when it was the one that stopped it.

The copy lands in `D:\WSL\<name>` and comes out dressed like its source, icon,
font and colours included. It needs **twice the disk's size** free at peak: the
temporary archive and the copy exist at the same time. The script checks and
shows the numbers before starting.

> A copy is made by reading the instance into an archive and unpacking it, not
> by copying the virtual disk — a raw disk copy is refused while WSL is up.

---

## `shrink`

Gives back to Windows the space the instance has freed inside itself.

```powershell
.\wsl.ps1 shrink
```

Space is only added to a virtual disk, never returned on its own: a 60 GB file
deleted inside the instance stays occupied on the Windows side. Compacting the
disk is what returns it. Nothing inside the instance is touched, and the disk's
virtual size does not change — only what it occupies on Windows.

It first asks `Archive it first? [Y/n]`, default yes. Answering no compacts
directly; answering yes takes an archive named after the instance (replacing an
older one of the same name, so archives do not pile up), and **if the archive
fails, nothing is compacted**.

It works on a running instance as well as a stopped one, and leaves it in the
state it was found in.

---

## `wslconfig`

Opens the Windows-wide WSL settings, `%USERPROFILE%\.wslconfig`, with the
application Windows gives that file.

```powershell
.\wsl.ps1 wslconfig
```

This is the machine's own file — the memory cap, the processors, the DNS
tunnel, the networking mode — not an instance's `/etc/wsl.conf`, which is per
distro and opened from inside with `gmake wsl_config`. When the file is not
there, it is created commented, so it documents itself; Windows asks which
application to use the first time if none is set for `.wslconfig`.

A change here is read when the WSL machine starts. `.\wsl.ps1 restart` does not
do that — it restarts one instance. Stop the machine with `wsl --shutdown`,
then open an instance again.

