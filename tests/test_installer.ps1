# Installer checks on a scratch COPY of a game (never your real install or Documents): rollback, byte-for-byte removal, an update with another layer build,
# the player's own Game.ini settings, a foreign d3d8.dll, and (with -HdPack) the HD path. The real Documents\Shrek 2 must not change.
# Usage: test_installer.ps1 -GameCopy <game folder copy> -DocsCopy <copy of Documents\Shrek 2> -Package <folder with the built setup exe and "files"> [-HdPack <unpacked ShrekHD folder>]
param([Parameter(Mandatory = $true)][string]$GameCopy, [Parameter(Mandatory = $true)][string]$DocsCopy, [Parameter(Mandatory = $true)][string]$Package, [string]$HdPack = '')
$ErrorActionPreference = 'Stop'
$w    = Join-Path $env:TEMP ('shrek2-p1-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $w | Out-Null
Copy-Item $GameCopy "$w\game" -Recurse
Copy-Item $DocsCopy "$w\docs" -Recurse
Copy-Item $Package "$w\pkg" -Recurse
$game = "$w\game"; $docs = "$w\docs"; $sys = "$game\System"; $exe = "$w\pkg\Shrek2-Enhanced-Setup.exe"
$layerPath = "$w\pkg\files\layer\d3d8.dll"
$ownerDocs = Join-Path $env:USERPROFILE 'Documents\Shrek 2'
$ownerBefore = Get-ChildItem $ownerDocs -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTime.Ticks)" }
$env:SHREK2_SETUP_DOCS = $docs
$script:n = 0
function Assert($c, $m) { if (-not $c) { throw "FAILED: $m" } else { "ok: $m" } }
function Run([string[]]$a) {
    $script:n++
    $log = "$w\run$($script:n).log"
    $p = Start-Process -FilePath $exe -ArgumentList (@($a) + @('/log', $log)) -Wait -PassThru -WindowStyle Hidden
    $script:code = $p.ExitCode
    $script:text = Get-Content $log -Raw -Encoding UTF8
}
function Snap {
    $m = @{}
    foreach ($r in @($game, $docs)) { Get-ChildItem $r -Recurse -File -Force | ForEach-Object { $m[$_.FullName.Substring($w.Length)] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash } }
    return $m
}
function TreeDiff($a, $b) {
    $o = @()
    foreach ($k in $a.Keys) { if (-not $b.ContainsKey($k)) { $o += "REMOVED $k" } elseif ($a[$k] -ne $b[$k]) { $o += "CHANGED $k" } }
    foreach ($k in $b.Keys) { if (-not $a.ContainsKey($k)) { $o += "ADDED $k" } }
    return @($o | Where-Object { $_ })
}
function SameAsBase($why) { $d = TreeDiff $base (Snap); Assert ($d.Count -eq 0) ("${why}: tree identical to the stock state" + $(if ($d.Count) { ' -- ' + ($d -join '; ') } else { '' })) }
try {
    Run @('/silent', '/dir', $game, '/uninstall')     # the test copy may be left installed by an earlier test
    Assert ($code -eq 0) 'leftover state removed'
    # a Cyrillic name in a UTF-16 User.ini (the game writes it that way) must survive the install and come back byte for byte
    $ui = "$docs\Shrek 2\User.ini"
    $nameRu = -join ([char[]](0x41F, 0x440, 0x438, 0x432, 0x435, 0x442))
    [IO.File]::WriteAllText($ui, [IO.File]::ReadAllText($ui) + "`r`n[EncTest]`r`nName=$nameRu`r`n", [Text.Encoding]::Unicode)
    $base = Snap
    "baseline: $($base.Count) files"

    # blocked last step -> everything is put back
    New-Item -ItemType Directory "$sys\d3d8.dll" | Out-Null
    Run @('/silent', '/dir', $game, '/textures', 'ru')
    Assert ($code -eq 1) 'install fails when the layer cannot be written'
    Remove-Item "$sys\d3d8.dll" -Force
    SameAsBase 'after the failed install'
    Assert (-not (Get-ChildItem $game -Force -Directory | Where-Object Name -like '.enhanced-txn*')) 'no transaction folder left'

    # install, install again, remove
    Run @('/silent', '/dir', $game, '/textures', 'ru'); Assert ($code -eq 0) 'install'
    $ub = [IO.File]::ReadAllBytes($ui)
    Assert (($ub[0] -eq 0xFF) -and ($ub[1] -eq 0xFE)) 'User.ini is still UTF-16 after the install'
    Assert ([IO.File]::ReadAllText($ui).Contains($nameRu)) 'the Cyrillic name is still in User.ini'
    $inst = Snap
    Run @('/silent', '/dir', $game, '/textures', 'ru'); Assert ($code -eq 0) 'second install'
    Assert ((TreeDiff $inst (Snap)).Count -eq 0) 'second install changes nothing'
    Run @('/silent', '/dir', $game, '/uninstall'); Assert ($code -eq 0) 'removal'
    SameAsBase 'after install, install, removal'

    # the player changes his own settings after the install: they survive the removal, the two lines of the mod go
    $gi = "$docs\Shrek 2\Game.ini"
    $origGi = [IO.File]::ReadAllText($gi)
    Run @('/silent', '/dir', $game, '/textures', 'ru')
    $t = [IO.File]::ReadAllText($gi)
    [IO.File]::WriteAllText($gi, ($t -replace '(?m)^(FullscreenViewportX=)\d+', '${1}1234'))
    Run @('/silent', '/dir', $game, '/uninstall')
    $g = [IO.File]::ReadAllText($gi)
    Assert ($g -match '(?m)^FullscreenViewportX=1234') 'a setting changed after the install survives the removal'
    Assert (($g -match '(?m)^Map=HP-Test\.unr') -and ($g -match '(?m)^DefaultGame=ShGame\.ShGame') -and ($g -notmatch '(?m)^Map=Book_FrontEnd') -and ($g -notmatch 'EnhancedGame')) 'the two lines of the mod are put back'
    Assert ($g -match '(?m)^;LocalMap=Book_FrontEnd\.unr') 'a commented line that looks alike is untouched'
    Assert (-not (Test-Path "$gi.enhanced-backup")) 'Game.ini backup dropped'
    [IO.File]::WriteAllText($gi, $origGi)   # the test's own edit goes back
    SameAsBase 'after the player-settings check'

    # Game.ini made by the game after the install (no backup of it): the mod lines still go
    Run @('/silent', '/dir', $game, '/textures', 'ru')
    Remove-Item "$gi.enhanced-backup" -Force
    Run @('/silent', '/dir', $game, '/uninstall')
    $g = [IO.File]::ReadAllText($gi)
    Assert (($g -notmatch 'EnhancedGame') -and ($g -match '(?m)^Map=HP-Test\.unr')) 'Game.ini without a backup is cleaned too'

    # update of the mod: the new package has another layer build
    $L1 = [IO.File]::ReadAllBytes($layerPath)
    Run @('/silent', '/dir', $game, '/textures', 'ru')
    [IO.File]::WriteAllBytes($layerPath, $L1 + [byte[]](1, 2, 3, 4))
    Run @('/silent', '/dir', $game, '/textures', 'ru'); Assert ($code -eq 0) 'update with another layer build'
    Assert (-not (Test-Path "$sys\d3d8.dll.enhanced-backup")) 'our old layer is not kept as a "backup"'
    Run @('/silent', '/dir', $game, '/uninstall'); Assert ($code -eq 0) 'removal after the update'
    Assert (-not (Test-Path "$sys\d3d8.dll")) 'no layer left after the update + removal'
    Assert (-not (Test-Path "$sys\d3d8_real.dll")) 'no d3d8_real.dll left after the update + removal'
    SameAsBase 'after update + removal'

    # a setup of another build removes what an older build installed
    [IO.File]::WriteAllBytes($layerPath, $L1)
    Run @('/silent', '/dir', $game, '/textures', 'ru')
    [IO.File]::WriteAllBytes($layerPath, $L1 + [byte[]](9, 9, 9))
    Run @('/silent', '/dir', $game, '/uninstall')
    Assert (-not (Test-Path "$sys\d3d8.dll")) 'removal by a setup of another build takes the layer away'
    SameAsBase 'after removal by a setup of another build'

    # a foreign d3d8.dll that was there before the mod comes back; one that replaced ours stays
    [IO.File]::WriteAllBytes($layerPath, $L1)
    $foreign = [Text.Encoding]::ASCII.GetBytes('foreign-wrapper-before-the-mod')
    [IO.File]::WriteAllBytes("$sys\d3d8.dll", $foreign)
    Run @('/silent', '/dir', $game, '/textures', 'ru')
    Run @('/silent', '/dir', $game, '/uninstall')
    Assert ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes("$sys\d3d8.dll")) -eq 'foreign-wrapper-before-the-mod') 'a foreign d3d8.dll that preceded the mod is restored'
    Remove-Item "$sys\d3d8.dll", "$sys\d3d8_real.dll", "$sys\d3d8_real.dll.enhanced-made" -Force -ErrorAction SilentlyContinue
    Run @('/silent', '/dir', $game, '/textures', 'ru')
    [IO.File]::WriteAllBytes("$sys\d3d8.dll", [Text.Encoding]::ASCII.GetBytes('foreign-wrapper-after'))
    Run @('/silent', '/dir', $game, '/uninstall')
    Assert ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes("$sys\d3d8.dll")) -eq 'foreign-wrapper-after') 'a foreign d3d8.dll that replaced ours is left alone'
    Remove-Item "$sys\d3d8.dll", "$sys\d3d8_real.dll", "$sys\d3d8_real.dll.enhanced-made" -Force -ErrorAction SilentlyContinue
    SameAsBase 'after the foreign-wrapper checks'

    Run @('/silent', '/dir', $game, '/nolayer'); Assert ($code -eq 1) '/nolayer is refused'
    SameAsBase 'after the refused /nolayer'

    # read-only marks: on files already in the game (left by an earlier install or a copy) and on the packaged files themselves
    Run @('/silent', '/dir', $game, '/textures', 'ru'); Assert ($code -eq 0) 'install before the read-only checks'
    $roNames = 'Enhanced.Rus', 'Enhanced.u', 'Enhanced.int', 'IpDrv.u', 'Packages.md5'
    foreach ($nm in $roNames) { (Get-Item "$sys\$nm").Attributes = 'ReadOnly' }
    foreach ($nm in 'Enhanced.Rus', 'Enhanced.int') { (Get-Item "$w\pkg\files\$nm").Attributes = 'ReadOnly' }
    Run @('/silent', '/dir', $game, '/textures', 'ru'); Assert ($code -eq 0) 'install over read-only files (the error of the player: access denied on Enhanced.Rus)'
    Assert (-not ((Get-Item "$sys\Enhanced.Rus").Attributes -band [IO.FileAttributes]::ReadOnly)) 'the installed file is not read-only'
    # a failed install over read-only files puts the files and their marks back
    foreach ($nm in $roNames) { (Get-Item "$sys\$nm").Attributes = 'ReadOnly' }
    $roHash = (Get-FileHash "$sys\Enhanced.Rus").Hash
    Remove-Item "$sys\d3d8.dll" -Force
    New-Item -ItemType Directory "$sys\d3d8.dll" | Out-Null
    Run @('/silent', '/dir', $game, '/textures', 'ru'); Assert ($code -eq 1) 'a failed install over read-only files fails cleanly'
    Remove-Item "$sys\d3d8.dll" -Force
    Assert ($text -notmatch 'ROLLBACK FAILED') 'the rollback of read-only files works'
    Assert (((Get-Item "$sys\Enhanced.Rus").Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) 'the read-only mark is put back by the rollback'
    Assert ((Get-FileHash "$sys\Enhanced.Rus").Hash -eq $roHash) 'the content is put back by the rollback'
    Assert (-not (Get-ChildItem $sys -Force | Where-Object Name -like '*.enhanced-tmp-*')) 'no temporary files left'
    Run @('/silent', '/dir', $game, '/uninstall'); Assert ($code -eq 0) 'removal of read-only files'
    Remove-Item "$sys\d3d8_real.dll", "$sys\d3d8_real.dll.enhanced-made" -Force -ErrorAction SilentlyContinue
    SameAsBase 'after the read-only checks'

    if ($HdPack) {
        $pack = $HdPack
        New-Item -ItemType Directory "$sys\d3d8.dll" | Out-Null
        Run @('/silent', '/dir', $game, '/textures', 'enhd', '/hdpack', $pack)
        Assert ($code -eq 1) 'HD install fails when the layer cannot be written'
        Remove-Item "$sys\d3d8.dll" -Force
        SameAsBase 'after the failed HD install (English + HD textures rolled back)'
        Run @('/silent', '/dir', $game, '/textures', 'enhd', '/hdpack', $pack); Assert ($code -eq 0) 'HD install'
        Run @('/silent', '/dir', $game, '/uninstall'); Assert ($code -eq 0) 'removal of the HD install'
        SameAsBase 'after HD install + removal'
    }

    # a running game is refused before anything changes
    Copy-Item "$env:WINDIR\System32\ping.exe" "$sys\Game.exe" -Force
    $gp = Start-Process "$sys\Game.exe" -ArgumentList '-t', '127.0.0.1' -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 800
    try {
        Run @('/silent', '/dir', $game, '/textures', 'ru')
        Assert ($code -eq 1) 'install is refused while the game runs'
        Assert ($text -match 'game is running|\(Game\.exe') ('the message says the game is running -- got: ' + $text)
        Assert (-not (Test-Path "$sys\Enhanced.u")) 'nothing was installed while the game ran'
    }
    finally { Stop-Process -Id $gp.Id -Force -ErrorAction SilentlyContinue }

    $ownerAfter = Get-ChildItem $ownerDocs -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTime.Ticks)" }
    Assert ((Compare-Object $ownerBefore $ownerAfter | Measure-Object).Count -eq 0) 'owner Documents untouched'
    'P1 INSTALLER TESTS PASSED'
}
finally {
    Remove-Item Env:SHREK2_SETUP_DOCS -ErrorAction SilentlyContinue
    Remove-Item $w -Recurse -Force -ErrorAction SilentlyContinue
}
