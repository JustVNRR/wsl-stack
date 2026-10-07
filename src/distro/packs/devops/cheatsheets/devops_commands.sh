# ==========================================
# THE PROJECT TARGETS (the devops pack)
# ==========================================
# What a project is built and pushed with, and the PRs it opens. All of them run
# from the root of a project under ~/projects.

# --- 1. DOCKER (LOCAL IMAGES) ---
gmake docker_build_local                     # Build Docker image for local development environment
gmake docker_run_local                       # Run Docker container locally

# --- 2. GITHUB CLI (PULL REQUESTS) ---
gmake gh_pr_create                           # Create a new Pull Request on GitHub
gmake gh_pr_toreview                         # Mark a Pull Request as ready for review
gmake gh_pr_wip                              # Convert a Pull Request back to draft status (WIP)
gmake gh_pr_ls                               # List all open Pull Requests in the repository
