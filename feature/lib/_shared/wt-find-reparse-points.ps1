# Lists directory reparse points (junctions / directory symlinks) under -Root.
# ASCII-only, PS 5.1 compatible (this file is read as ANSI - do not add non-ASCII).
#
# WHY: node_modules inside a worktree is a junction into the MAIN repo, and Next.js
# copies further junctions into .next/node_modules + .next/dev/node_modules.
# A recursive delete that walks INTO such a link wipes files in the main repo.
# Cleanup must therefore unlink every reparse point as a LINK first, and only
# then delete the remaining plain directories.
#
# The walk itself never descends into a reparse point either - it enumerates the
# link and stops there. Output: one absolute Windows path per line, no other noise.
param(
  [Parameter(Mandatory = $true)][string]$Root
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Root)) { exit 0 }

$reparse = [System.IO.FileAttributes]::ReparsePoint
$rootFull = (Resolve-Path -LiteralPath $Root).ProviderPath

# If the root itself is a link, report it and stop - never look inside.
try {
  $rootAttr = [System.IO.File]::GetAttributes($rootFull)
  if (($rootAttr -band $reparse) -eq $reparse) {
    Write-Output $rootFull
    exit 0
  }
} catch { exit 0 }

$stack = New-Object 'System.Collections.Generic.Stack[string]'
$stack.Push($rootFull)

while ($stack.Count -gt 0) {
  $dir = $stack.Pop()
  try { $children = [System.IO.Directory]::GetDirectories($dir) } catch { continue }
  foreach ($child in $children) {
    try { $attr = [System.IO.File]::GetAttributes($child) } catch { continue }
    if (($attr -band $reparse) -eq $reparse) {
      Write-Output $child
    } else {
      $stack.Push($child)
    }
  }
}

exit 0
