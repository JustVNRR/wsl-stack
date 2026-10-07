# ==============================================================================
# A PACK, AS THE REPOSITORY DECLARES IT
# ==============================================================================
# Its folder, and what its pack.conf says: description, requirements, whether
# it is ever offered, welcome line.
class WslPack {
    [string]$Name
    [string]$Path
    [string]$Description

    # What it requires: a pack is installed on top of these - a requirement
    # arrives before it, and leaves with the last pack that requires it.
    [string[]]$Requires = @()

    # Whether the pack is ever offered to the user. `PACK_VISIBLE := no`
    # withholds it: in no menu, travelling with the pack that requires it, and
    # gone when nothing requires it any more.
    [bool]$Offered = $true

    # The line shown once it is installed.
    [string]$Welcome

    WslPack([string]$name, [string]$path) {
        $this.Name = $name
        $this.Path = $path
        $this.LoadConfig()
    }

    # The keys pack.conf may carry. Absent means the ordinary case, and only an
    # explicit `PACK_VISIBLE := no` withholds a pack - a value that is neither
    # yes nor no leaves it offered, where a typo should land.
    [void] LoadConfig() {
        $confFile = Join-Path $this.Path "pack.conf"
        if (-not (Test-Path $confFile)) { return }
        foreach ($line in (Get-Content -Path $confFile -Encoding UTF8)) {
            if ($line -match '^\s*PACK_DESCRIPTION\s*:=\s*(.+?)\s*$') { $this.Description = $Matches[1] }
            elseif ($line -match '^\s*PACK_REQUIRES\s*:=\s*(.*)$') { $this.Requires = @($Matches[1] -split '\s+' | Where-Object { $_ }) }
            elseif ($line -match '^\s*PACK_VISIBLE\s*:=\s*(\S+)') { $this.Offered = ($Matches[1] -notmatch '^(?i)no$') }
            elseif ($line -match '^\s*PACK_WELCOME\s*:=\s*(.+?)\s*$') { $this.Welcome = $Matches[1] }
        }
    }

    # A sample is a file; a pack shipping none has nothing to merge into the
    # user's .env files.
    [bool] ShipsSamples() {
        return (Test-Path (Join-Path $this.Path "env.global.sample")) -or
               (Test-Path (Join-Path $this.Path "env.project.sample"))
    }
}
