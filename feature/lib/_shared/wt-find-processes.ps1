# Finds processes belonging to ONE worktree, so cleanup can stop them
# before deleting the directory. ASCII-only, PS 5.1 compatible.
#
# Targeting is deliberately narrow - a dozen dev servers from sibling worktrees run
# on this machine and killing a foreign one is real damage. A process qualifies only if:
#   (a) its command line contains this worktree's path (either slash flavour), or
#   (b) it LISTENS on this worktree's dev PORT and is node.exe.
# From those seeds the parent chain is walked upwards while the parent is node.exe or
# cmd.exe (the `npm run dev` wrapper keeps its CWD in the worktree and would keep the
# directory locked). Ancestors of THIS process are always excluded so the cleanup run
# cannot kill its own shell.
#
# Output: one line per process, "<pid>\t<name>\t<reason>". No other noise.
param(
  [Parameter(Mandatory = $true)][string]$Root,
  [int]$Port = 0
)

$ErrorActionPreference = 'Stop'

$rootFull = $Root
try { $rootFull = (Resolve-Path -LiteralPath $Root).ProviderPath } catch { }
$rootBack = $rootFull.TrimEnd('\')
$rootFwd = $rootBack.Replace('\', '/')

$procs = @{}
foreach ($p in Get-CimInstance Win32_Process) { $procs[[int]$p.ProcessId] = $p }

# Ancestors of the current process - never touch them.
$selfChain = @{}
$cur = $PID
$guard = 0
while ($cur -and $procs.ContainsKey($cur) -and $guard -lt 64) {
  $selfChain[$cur] = $true
  $cur = [int]$procs[$cur].ParentProcessId
  $guard++
}

$hits = @{}

function Add-Hit([int]$processId, [string]$reason) {
  if ($processId -le 4) { return }
  if ($selfChain.ContainsKey($processId)) { return }
  if (-not $procs.ContainsKey($processId)) { return }
  if (-not $hits.ContainsKey($processId)) { $hits[$processId] = $reason }
}

# (a) command line points into this worktree
foreach ($p in $procs.Values) {
  $cl = $p.CommandLine
  if (-not $cl) { continue }
  if ($cl.IndexOf($rootBack, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
      $cl.IndexOf($rootFwd, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
    Add-Hit ([int]$p.ProcessId) 'cmdline'
  }
}

# (b) node process listening on this worktree's dev PORT
if ($Port -gt 0) {
  $owners = @()
  try {
    $owners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
      Select-Object -ExpandProperty OwningProcess)
  } catch {
    foreach ($line in (netstat -ano -p tcp)) {
      if ($line -match "LISTENING" -and $line -match "[:\.]$Port\s") {
        $parts = ($line -split '\s+') | Where-Object { $_ }
        if ($parts.Count -ge 1) { $owners += [int]$parts[-1] }
      }
    }
  }
  foreach ($owner in ($owners | Select-Object -Unique)) {
    $pid2 = [int]$owner
    if ($procs.ContainsKey($pid2) -and $procs[$pid2].Name -eq 'node.exe') {
      Add-Hit $pid2 "port:$Port"
    }
  }
}

# Walk parents of every seed while they are node.exe / cmd.exe wrappers.
foreach ($seed in @($hits.Keys)) {
  $parent = [int]$procs[$seed].ParentProcessId
  $guard = 0
  while ($parent -gt 4 -and $procs.ContainsKey($parent) -and $guard -lt 16) {
    if ($selfChain.ContainsKey($parent)) { break }
    $name = $procs[$parent].Name
    if ($name -ne 'node.exe' -and $name -ne 'cmd.exe') { break }
    if ($hits.ContainsKey($parent)) { break }
    Add-Hit $parent 'wrapper'
    $parent = [int]$procs[$parent].ParentProcessId
    $guard++
  }
}

foreach ($processId in ($hits.Keys | Sort-Object)) {
  $name = $procs[$processId].Name
  Write-Output ("{0}`t{1}`t{2}" -f $processId, $name, $hits[$processId])
}

exit 0
