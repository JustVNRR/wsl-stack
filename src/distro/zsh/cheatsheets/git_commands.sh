# ===================
# 🐙 GIT CHEATSHEET
# ===================

# --- 1. INSPECTION & HISTORY ---
git status                                   # Check working tree status and modified files
git log --oneline                            # Compact commit history view
git diff                                     # Inspect unstaged changes in detail

# --- 2. STAGING AREA ---
git add <FILE_PATH>                          # Stage a specific file
git add .                                    # Stage all modified and untracked files
git rm <FILE_PATH>                           # Remove a file from working tree and index
git rm --cached <FILE_PATH>                  # Untrack a file while keeping it on local disk

# --- 3. COMMITTING ---
git commit -m "<COMMIT_MESSAGE>"             # Record changes with a commit message
git commit -a -m "<COMMIT_MESSAGE>"          # Stage tracked modified files and commit
git commit --amend -m "<NEW_MESSAGE>"        # Update the latest commit message
git commit --amend --no-edit                 # Add staged changes to latest commit without changing message

# --- 4. BRANCH MANAGEMENT ---
git branch                                   # List local branches
git branch -a                                # List all local and remote branches
git switch <BRANCH_NAME>                     # Switch to an existing branch
git switch -c <BRANCH_NAME>                  # Create and switch to a new branch
git switch -                                 # Switch back to the previous branch
git branch -m <NEW_BRANCH_NAME>              # Rename current branch
git branch -d <BRANCH_NAME>                  # Delete branch safely (prevent deleting unmerged work)
git branch -D <BRANCH_NAME>                  # Force delete branch regardless of merge status

# --- 5. SYNCHRONIZATION ---
git fetch                                    # Download objects and refs from remote repository
git pull                                     # Fetch from and integrate with remote branch (fetch + merge)
git push -u origin <BRANCH_NAME>             # Push branch and set upstream tracking reference
git push --force-with-lease origin <BRANCH_NAME> # Force push safely without overwriting unknown remote work

# --- 6. STASHING ---
git stash                                    # Stash uncommitted changes in working directory
git stash pop                                # Restore and drop most recent stashed state
git stash list                               # List all stashed changesets

# --- 7. UNDOING CHANGES & REBASE ---
git restore --staged <FILE_PATH>             # Unstage file changes (reverse git add)
git reset --hard HEAD                        # ⚠️ Discard all working tree changes and reset to HEAD
git reset --soft HEAD~1                      # Undo last commit while keeping changes staged
git rebase <BASE_BRANCH>                     # Reapply commits on top of another base branch
git rebase -i HEAD~<NUMBER>                  # Interactive rebase over the last N commits
git rebase --continue                        # Resume rebase after resolving merge conflicts
git rebase --abort                           # Abort in-progress rebase and restore original state


# ========== Oh My Zsh aliases ==========

# --- 1. INSPECTION & HISTORY ---
gst                                          # [git status] Check working tree status and modified files
glo                                          # [git log --oneline] Compact commit history view
gd                                           # [git diff] Inspect unstaged changes in detail

# --- 2. STAGING AREA ---
ga <FILE_PATH>                               # [git add] Stage a specific file
gaa                                          # [git add --all] Stage all modified and untracked files
grm <FILE_PATH>                              # [git rm] Remove a file from working tree and index
grmc <FILE_PATH>                             # [git rm --cached] Untrack a file while keeping it on local disk

# --- 3. COMMITTING ---
gcmsg "<COMMIT_MESSAGE>"                     # [git commit -m] Record changes with a commit message
gcam "<COMMIT_MESSAGE>"                      # [git commit -a -m] Stage tracked modified files and commit
gc! -m "<NEW_MESSAGE>"                       # [git commit --amend -m] Update the latest commit message
gcan!                                        # [git commit -a --amend --no-edit] Add staged changes to latest commit without changing message

# --- 4. BRANCH MANAGEMENT ---
gb                                           # [git branch] List local branches
gba                                          # [git branch -a] List all local and remote branches
gsw <BRANCH_NAME>                            # [git switch] Switch to an existing branch
gswc <BRANCH_NAME>                           # [git switch -c] Create and switch to a new branch
gsw -                                        # [git switch -] Switch back to the previous branch
gb -m <NEW_BRANCH_NAME>                      # [git branch -m] Rename current branch
gbd <BRANCH_NAME>                            # [git branch -d] Delete branch safely (prevent deleting unmerged work)
gbD <BRANCH_NAME>                            # [git branch -D] Force delete branch regardless of merge status

# --- 5. SYNCHRONIZATION ---
gf                                           # [git fetch] Download objects and refs from remote repository
gl                                           # [git pull] Fetch from and integrate with remote branch (fetch + merge)
gpsup                                        # [git push --set-upstream...] Push current branch and configure upstream tracking
gpf                                          # [git push --force-with-lease] Force push current branch safely without overwriting unknown remote work

# --- 6. STASHING ---
gsta                                         # [git stash] Stash uncommitted changes in working directory
gstp                                         # [git stash pop] Restore and drop most recent stashed state
gstl                                         # [git stash list] List all stashed changesets

# --- 7. UNDOING CHANGES & REBASE ---
grst <FILE_PATH>                             # [git restore --staged] Unstage file changes (reverse git add)
grhh                                         # [git reset --hard HEAD] ⚠️ Discard all working tree changes and reset to HEAD
grh --soft HEAD~1                            # [git reset --soft HEAD~1] Undo last commit while keeping changes staged
grb <BASE_BRANCH>                            # [git rebase] Reapply commits on top of another base branch
grbi HEAD~<NUMBER>                           # [git rebase -i] Interactive rebase over the last N commits
grbc                                         # [git rebase --continue] Resume rebase after resolving merge conflicts
grba                                         # [git rebase --abort] Abort in-progress rebase and restore original state
