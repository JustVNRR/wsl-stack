# ==============================================================================
# WHAT AN INSTANCE IS DOING
# ==============================================================================
# Running or Stopped for a registered one; Archived when only the archive
# folder is left of it; Unknown when there is no way to tell.
enum WslState {
    Stopped
    Running
    Archived
    Unknown
}
