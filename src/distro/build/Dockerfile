FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Remove default 'ubuntu' user created in Noble 24.04 base images
RUN userdel -r ubuntu 2>/dev/null || true

# Remove all dpkg drop-in filters so documentation and examples (like fzf bindings) are installed
RUN rm -f /etc/dpkg/dpkg.cfg.d/*

# 1. Install prerequisites for third-party repositories and core networking tools
#
# apt-utils is here for the line it silences: without it, debconf announces
# "delaying package configuration, since apt-utils is not installed" on every
# apt run that configures a package - which is every pack's install, in front
# of the user.
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    apt-utils \
    ca-certificates \
    curl \
    gnupg \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. Configure third-party APT repositories (GitHub CLI, eza)
#
# Only the tools this image installs register a repository here. A tool
# installed on demand registers its own at that moment: the image carries no
# key for a machine that may never use it, and uninstalling has something to
# undo.
RUN mkdir -p -m 755 /etc/apt/keyrings \
    # GitHub CLI
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list \
    # eza (modern ls replacement)
    && curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list

# 3. Install system packages, developer CLI tools, build dependencies, and DS/ML libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    # System & Shell utilities
    locales \
    adduser \
    sudo \
    tzdata \
    # The dialog frontend debconf draws its lists with, one entry per line:
    # first_boot.sh's timezone question asks for it by name, and without it
    # debconf quietly falls back to the columned readline list.
    whiptail \
    zsh \
    nano \
    git \
    openssh-client \
    strace \
    lsof \
    # make is the whole command surface of this image, and it used to arrive as
    # a dependency of build-essential - the python pack's now. Named here in
    # plain sight: without this line the image would carry no make at all, and
    # every gmake target would be gone with it.
    make \
    # No systemd: nothing this image starts is a service, and the systemd
    # package alone never boots anything - WSL runs /sbin/init, which comes
    # from systemd-sysv. `gmake systemd_up` installs both on the instance that
    # asks.
    # git pages through `less` - a Recommends that --no-install-recommends
    # drops - and the bash cheatsheet documents it and ping
    less \
    iputils-ping \
    tree \
    tar \
    unzip \
    bzip2 \
    unrar \
    p7zip-full \
    gzip \
    xz-utils \
    zstd \
    # Modern shell UX & CLI tools
    bat \
    direnv \
    eza \
    fd-find \
    fzf \
    gh \
    jq \
    ripgrep \
    # The line editor cruft's and ccds' questions lack: cookiecutter reads a
    # plain line, so the bytes an arrow key sends land in the answer.
    # src/distro/packs/scaffold/make/project-setup.mk runs it in front of the three tools,
    # and it has to be there before the first project.
    rlwrap \
    shellcheck \
    zoxide \
    # Database CLI
    sqlite3 \
    # No Python and no compiler for it: uv, python3-dev, libffi-dev, libssl-dev
    # and build-essential are the `python` pack's, and ffmpeg, ImageMagick and
    # Tesseract the `vision` pack's - they arrive on the instance that asks,
    # with `.\wsl.ps1 add_pack`.
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure UTF-8 locale
RUN locale-gen en_US.UTF-8 fr_FR.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create symlinks for binary compatibility (fdfind -> fd, batcat -> bat)
RUN ln -s $(which fdfind) /usr/local/bin/fd \
    && ln -s $(which batcat) /usr/local/bin/bat

# Guarantee fzf bindings are uncompressed if dpkg shipped them compressed
RUN if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh.gz ]; then \
        gunzip -f /usr/share/doc/fzf/examples/key-bindings.zsh.gz; \
    fi

# 4. Install prompt (Starship) and tealdeer
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "amd64" ]; then STARSHIP_ARCH="x86_64"; else STARSHIP_ARCH="aarch64"; fi \
    && curl -fsSL "https://github.com/starship/starship/releases/latest/download/starship-${STARSHIP_ARCH}-unknown-linux-gnu.tar.gz" -o starship.tar.gz \
    && tar -xzf starship.tar.gz -C /usr/local/bin \
    && rm starship.tar.gz \
    && curl -fsSL "https://github.com/tealdeer-rs/tealdeer/releases/latest/download/tealdeer-linux-${STARSHIP_ARCH}-musl" -o /usr/local/bin/tldr \
    && chmod +x /usr/local/bin/tldr

# 5. Clone Oh-My-Zsh and its custom plugins into the user skeleton
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /etc/skel/.local/share/oh-my-zsh \
    && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
       /etc/skel/.local/share/oh-my-zsh/custom/plugins/zsh-autosuggestions \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
       /etc/skel/.local/share/oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# Nothing of the packs, and none of the zsh configuration either: the image
# carries the tools - the shell, Oh-My-Zsh, the modern CLI set - and the zsh
# pack carries the settings. The pack installs like every other one, with
# `.\wsl.ps1 add_pack` or by being chosen while an instance is built, and
# fills ~/.config/zsh and the skeleton from its own config/ folder. Without
# it, an instance has zsh and no settings.

# The skeleton's directories. The base image leaves a bash dotfile set
# (.bashrc, .bash_logout, .profile) in /etc/skel, inherited by accounts for a
# shell this image never runs - they go. The ZDOTDIR bootstrap and the shell's
# state/cache directories are not here: they come with the configuration, so
# they are the zsh pack's to write, into the home and into this skeleton.
RUN rm -f /etc/skel/.bashrc /etc/skel/.bash_logout /etc/skel/.profile \
    && mkdir -p /etc/skel/.ssh \
    && mkdir -p /etc/skel/projects \
    && chmod 700 /etc/skel/.ssh

# 6. Deploy first-boot onboarding script and trigger it via root bashrc
COPY src/distro/build/first_boot.sh /root/first_boot.sh
RUN chmod +x /root/first_boot.sh \
    && echo '/root/first_boot.sh' >> /root/.bashrc \
    && chown -R root:root /etc/skel

CMD ["/bin/bash"]