# ==============================================================================
# THE PACKS THIS CHECKOUT CARRIES
# ==============================================================================
# The packs folder, read once, and the two resolutions the pack commands need:
# what goes in (requirements included) and what leaves with it.
class WslPackCatalog {
    [string]$PacksRoot
    [WslPack[]]$AvailablePacks = @()

    WslPackCatalog([string]$packsRoot) {
        $this.PacksRoot = $packsRoot
        $this.Refresh()
    }

    # Every folder carrying a pack.conf - a folder without one is not a pack.
    # Sorted by name: the menus number these, so the order must not move.
    [void] Refresh() {
        $this.AvailablePacks = @()
        if (-not (Test-Path $this.PacksRoot)) { return }

        foreach ($dir in (Get-ChildItem -Path $this.PacksRoot -Directory | Sort-Object Name)) {
            $conf = Join-Path $dir.FullName "pack.conf"
            if (-not (Test-Path $conf)) { continue }
            $this.AvailablePacks += [WslPack]::new($dir.Name, $dir.FullName)
        }
    }

    [WslPack] GetPack([string]$name) {
        return ($this.AvailablePacks | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
    }

    # The list to install, in order: a pack is installed on top of what it
    # requires, so requirements come first - and one already installed is not
    # placed twice. A requirement this checkout does not carry is skipped here;
    # the pack that asked is the one that will fail.
    #
    # $installed is never optional: a class method takes no default, so the
    # caller says what the instance has - an empty array included.
    [string[]] ResolveSelection([string[]]$names, [string[]]$installed) {
        $seen = @{}
        $ordered = New-Object System.Collections.ArrayList
        foreach ($name in $names) {
            $this.AddRequires($name, $installed, $seen, $ordered)
        }
        return @($ordered)
    }

    # The helper behind ResolveSelection - public, since PowerShell classes
    # have no private: a requirement two levels down travels before both.
    [void] AddRequires([string]$name, [string[]]$installed, [hashtable]$seen, [System.Collections.ArrayList]$ordered) {
        if ($seen.ContainsKey($name)) { return }
        $seen[$name] = $true

        $pack = @($this.AvailablePacks | Where-Object { $_.Name -eq $name })[0]
        if ($null -eq $pack) { return }

        # Through it even when it is already there: what IT requires may be
        # missing.
        foreach ($need in $pack.Requires) {
            $this.AddRequires($need, $installed, $seen, $ordered)
        }

        if ($installed -notcontains $name) { [void]$ordered.Add($name) }
    }

    # What leaves, with what has to leave with it: an invisible pack is never
    # in the checklist - it leaves when the last pack that requires it does.
    # Repeated until nothing moves: an invisible pack may itself require
    # another, and the second loses its claimant the moment the first does.
    # $arriving holds the packs on their way in: one of them is a claimant too
    # (explicit, like $installed above - @() when nothing is arriving).
    [string[]] ResolveRemoval([string[]]$installed, [string[]]$leaving, [string[]]$arriving) {
        $gone = New-Object System.Collections.ArrayList
        foreach ($name in $leaving) { [void]$gone.Add($name) }

        do {
            $added = 0
            $remaining = @($installed | Where-Object { $gone -notcontains $_ }) + @($arriving)

            foreach ($name in $installed) {
                if ($gone -contains $name) { continue }

                # Not carried by this checkout: not in the checklist either,
                # and left alone for the same reason. An offered one only ever
                # leaves because the user unticked it.
                $pack = @($this.AvailablePacks | Where-Object { $_.Name -eq $name })[0]
                if ($null -eq $pack) { continue }
                if ($pack.Offered) { continue }

                $claimed = $false
                foreach ($other in $remaining) {
                    $otherPack = @($this.AvailablePacks | Where-Object { $_.Name -eq $other })[0]
                    if ($null -ne $otherPack -and $otherPack.Requires -contains $name) { $claimed = $true; break }
                }
                if (-not $claimed) {
                    [void]$gone.Add($name)
                    $added++
                }
            }
        } while ($added -gt 0)

        return @($gone)
    }
}
