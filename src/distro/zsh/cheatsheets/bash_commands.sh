# ============================================================
# BASH & LINUX CHEATSHEET
# ============================================================

# --- 1. NAVIGATION & DIRECTORY EXPLORATION ---
pwd                                                           # Print absolute path of current working directory
cd <PATH>                                                     # Navigate to a specific directory path
cd ..                                                         # Move up to parent directory
cd -                                                          # Switch back to previously visited directory
ls -1                                                         # List files and directories one per line
ls -lh                                                        # List with human-readable file sizes (KB, MB)
ls -la                                                        # List all files including hidden files with details

# --- 2. FILE & DIRECTORY MANIPULATION ---
touch <FILE_NAME>                                             # Create empty file or update timestamp of existing file
mkdir <DIR_NAME>                                              # Create a new directory
mkdir -p <PATH/TO/DIR>                                        # Create full nested directory tree recursively
cp <SOURCE> <DESTINATION>                                     # Copy a file to target path
cp -r <SOURCE_DIR> <DEST_DIR>                                 # Copy directory and its contents recursively
mv <SOURCE> <DESTINATION>                                     # Move or rename a file or directory
rm <FILE_NAME>                                                # Remove a single file
rm -rf <DIR_NAME>                                             # Forcefully remove directory and contents recursively
ln -s <TARGET_PATH> <LINK_NAME>                               # Create a symbolic link pointing to target path

# --- 3. FILE READING & INSPECTION ---
cat <FILE_NAME>                                               # Output entire file contents to stdout
less <FILE_NAME>                                              # Paginate through file (arrow keys to move, 'q' to quit)
head -n <N> <FILE_NAME>                                       # Display first N lines of a file (e.g. -n 10)
tail -n <N> <FILE_NAME>                                       # Display last N lines of a file (e.g. -n 10)
tail -f <FILE_NAME>                                           # Follow appended lines in real time (log inspection)

# --- 4. TEXT PROCESSING & EXTRACTION (GREP / CUT / SED / AWK) ---
grep "<TEXT>" <FILE_NAME>                                     # Search for pattern inside a specific file
grep -c "<TEXT>" <FILE_NAME>                                  # Count number of lines matching pattern
grep -l "<TEXT>" *                                            # List only names of matching files in directory
grep -ri "<TEXT>" <DIR_PATH>                                  # Case-insensitive recursive search in a directory
cut -d'<DELIM>' -f<COL> <FILE_NAME>                           # Extract specific column using delimiter (e.g. -d':' -f1)
sort <FILE_NAME>                                              # Sort and display file lines alphabetically
sort <FILE_NAME> | uniq -c | sort -nr                         # Count duplicate line occurrences (descending order)
tr '<DELIM>' '\n' < <FILE_NAME>                               # Split text on delimiter into separate lines
seq -s ' ' <MAX>                                              # Output sequence from 1 to MAX separated by spaces
awk '{s+=$1} END {print s}' <FILE_NAME>                       # Sum numeric values in the first column of a file

# --- 5. SEARCH & ADVANCED OPS (FIND) ---
find <DIR_PATH> -name "<PATTERN>"                             # Find file by exact name or glob pattern
find <DIR_PATH> -type d -name "<DIR_NAME>"                    # Find directory specifically matching name pattern
find . -maxdepth 1 -type f | wc -l                            # Count total regular files in current directory
find . -type f -printf "%f\n"                                 # List all files recursively without relative path prefix
find . -type f -mtime -<DAYS>                                 # Find files modified within last N days (e.g. -1)
find . -name "<PATTERN>*" -exec grep -h "<TEXT>" {} +         # Extract matching lines from matching files
find . -name "<PATTERN>*" -exec grep -hoE "([0-9]{1,3}\.){3}[0-9]{1,3}" {} + # Extract IP addresses from matching files
find . -name "*.<EXT>" -exec sed -i 's/<PATTERN>//g' {} +     # Recursively delete pattern occurrences within matching files
find . -empty -delete                                         # Find and delete all empty files and directories
find . -name "*.<EXT>" -delete                                # Recursively delete files matching specific extension
find . -mindepth 1 -delete                                    # Empty current directory contents preserving root folder

# --- 6. SYSTEM, STORAGE, PROCESSES & PERMISSIONS ---
df -h                                                         # Show available disk space across all mounted filesystems
du -sh *                                                      # Show human-readable disk usage per directory/file
top                                                           # Monitor active processes, memory, and CPU usage live
pgrep -fl "<PROCESS_NAME>"                                    # Search running process by name pattern with command details
pkill -f "<PROCESS_NAME>"                                     # Terminate all processes matching search pattern
chmod +x <FILE_NAME>                                          # Make script or binary executable
find . -type f -exec chmod <PERM_FILES> {} +                  # Recursively set permissions on regular files only (e.g. 644)
find . -type d -exec chmod <PERM_DIRS> {} +                   # Recursively set permissions on directories only (e.g. 755)
chown <USER>:<GROUP> <FILE_NAME>                              # Change owner and group assignment of a file

# --- 7. ARCHIVES, NETWORKING & PARALLEL EXECUTION ---
tar -czf <ARCHIVE_NAME>.tar.gz <DIR_PATH>                     # Create gzip-compressed tar archive from directory
tar -xzf <ARCHIVE_NAME>.tar.gz                                # Extract gzip-compressed tar archive into current directory
curl <URL>                                                    # Send GET request and dump response payload to stdout
curl -O <URL>                                                 # Download file from URL preserving remote filename
curl -L <URL>                                                 # Query or download URL following redirect headers
curl -X POST -d "<DATA>" <URL>                                # Send POST payload data to target endpoint
wget <URL>                                                    # Download file directly from URL
cat <URLS_FILE> | xargs -P <JOBS> -n 1 curl -O                # Download URLs in parallel using N concurrent jobs
ping <DOMAIN_OR_IP>                                           # Test host ICMP network reachability (Ctrl+C to stop)

# --- 8. SHELL ENVIRONMENT & EDITOR HOOKS (ZSH) ---
code "$ZDOTDIR"                                               # Open Zsh configuration directory in VS Code
reload                                                        # Apply config changes: restarts the shell (exec zsh under the hood)
exec zsh                                                      # The same thing spelled out, when the alias is not loaded
code "$HISTFILE"                                              # Open persistent history file in VS Code for manual edits
> "$HISTFILE"                                                 # Truncate persistent history file completely
nano <FILE_NAME>                                              # Open file inside Nano terminal editor

# --- 9. PACKAGE MANAGEMENT (APT - DEBIAN / UBUNTU) ---
sudo apt update                                               # Refresh package repository indices
sudo apt upgrade                                              # Upgrade installed packages to newest available versions
sudo apt install <PACKAGE_NAME>                               # Install specified package from repositories
sudo apt remove <PACKAGE_NAME>                                # Remove package while preserving configuration files
sudo apt purge <PACKAGE_NAME>                                 # Remove package and purge all associated configurations
apt search <KEYWORD>                                          # Search available package catalog by keyword
apt show <PACKAGE_NAME>                                       # Display detailed package metadata and dependencies
sudo apt autoremove                                           # Remove unused orphaned dependency packages

# --- 10. REDIRECTIONS, FILTERS & PIPELINES ---
<COMMAND> > <FILE_NAME>                                       # Redirect stdout to file (overwrites existing content)
<COMMAND> >> <FILE_NAME>                                      # Append stdout to end of file
history | grep "<TEXT>"                                       # Search matching commands in shell session history
docker ps | grep "<CONTAINER_NAME>"                           # Filter running containers by container name pattern
ls -la | grep "\.sh$"                                         # Filter directory list to show only .sh files
