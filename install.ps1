#Requires -Version 5.1
<#
.SYNOPSIS
    oh-my-cursor installer for Windows.

.DESCRIPTION
    Install Team Avatar as a Cursor plugin (rules, agents, commands, hooks, skills).
    PowerShell equivalent of install.sh.

.PARAMETER Scope
    Install scope: 'user' (default, ~/.cursor/plugins/local/oh-my-cursor) or 'project' (./.cursor/).

.PARAMETER Force
    Overwrite existing files.

.PARAMETER DryRun
    Show what would be done without making changes.

.PARAMETER Verbose
    Enable verbose output.

.PARAMETER Uninstall
    Remove the plugin and leftover v0.4 injection files.

.PARAMETER Disable
    Disable orchestration (rename rule so Cursor stops applying it).

.PARAMETER Enable
    Re-enable orchestration (rename rule back).

.PARAMETER AlsoClaude
    Also install to .claude/ for Claude Code compatibility.

.PARAMETER AlsoCodex
    Also install to .codex/ for Codex compatibility.

.PARAMETER NoSkills
    Skip installing bundled agent skills (skills are installed by default).

.EXAMPLE
    .\install.ps1
    # Install the Cursor plugin to user scope (default)

.EXAMPLE
    .\install.ps1 -Scope project
    # Install to project scope

.EXAMPLE
    .\install.ps1 -Force
    # Overwrite existing files

.EXAMPLE
    .\install.ps1 -DryRun
    # Preview changes

.EXAMPLE
    .\install.ps1 -Uninstall
    # Remove the plugin and leftover injection files

.EXAMPLE
    irm https://raw.githubusercontent.com/tmcfarlane/oh-my-cursor/main/install.ps1 | iex
    # One-liner install from GitHub (default options only; clone the repo to pass flags)
#>

[CmdletBinding()]
param(
    [ValidateSet('user', 'project')]
    [string]$Scope = 'user',

    [switch]$Force,
    [switch]$DryRun,
    [switch]$Uninstall,
    [switch]$Disable,
    [switch]$Enable,
    [switch]$AlsoClaude,
    [switch]$AlsoCodex,
    [switch]$NoSkills
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$VERSION = '0.5.2'
$CURSOR_MODE_LABEL = 'Team Avatar (Cursor Plugin)'
$PLUGIN_NAME = 'oh-my-cursor'

$AGENT_FILES = @('aang.md', 'sokka.md', 'katara.md', 'zuko.md', 'toph.md', 'appa.md', 'momo.md', 'iroh.md')
$PROTOCOL_FILES = @('protocols/team-avatar.md')
$COMMAND_FILES = @('plan.md', 'build.md', 'search.md', 'fix.md', 'tasks.md', 'scout.md', 'cactus-juice.md', 'doc.md', 'image.md')
$HOOK_FILES = @('post-edit-lint.js', 'pre-commit-check.js', 'guard-shell.js', 'hooks.json')
$HOOK_SCRIPT_FILES = @('post-edit-lint.js', 'pre-commit-check.js', 'guard-shell.js')
$LEGACY_HOOK_FILES = @('post-edit-lint.sh', 'pre-commit-check.sh', 'guard-shell.sh')
$PLUGIN_MANIFEST_FILES = @('plugin.json', 'marketplace.json')
$RULE_FILE = 'orchestrator.mdc'
$RULE_FILE_DISABLED = 'orchestrator.mdc.disabled'
$SKILL_DIRS = @(
    'architect'
    'codebase-search'
    'create-an-asset'
    'cursor-image-generation'
    'debugging'
    'design-patterns-implementation'
    'docs-write'
    'documentation-engineer'
    'documentation-writing'
    'exploring-codebases'
    'frontend-builder'
    'implementing-figma-designs'
    'mgrep-code-search'
    'planning'
    'refactoring'
    'refactoring-patterns'
    'technical-roadmap-planning'
    'vercel-composition-patterns'
    'vercel-react-best-practices'
    'web-design-guidelines'
)

$LEGACY_AGENT_FILES = @('atlas.md', 'explore.md', 'generalPurpose.md', 'hephaestus.md', 'librarian.md', 'metis.md', 'momus.md', 'multimodal-looker.md', 'oracle.md', 'prometheus.md', 'sisyphus.md')
$LEGACY_PROTOCOL_FILES = @('protocols/swarm-coordinator.md')

$SOURCE_BASE_URL_DEFAULT = 'https://raw.githubusercontent.com/tmcfarlane/oh-my-cursor/main'
$SourceBaseUrl = if ($env:OH_MY_CURSOR_SOURCE_BASE_URL) { $env:OH_MY_CURSOR_SOURCE_BASE_URL } else { $SOURCE_BASE_URL_DEFAULT }

$script:RemovedCount = 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    Write-Host $Message
}

function Write-LogVerbose {
    param([string]$Message)
    if ($VerbosePreference -ne 'SilentlyContinue') {
        Write-Host $Message -ForegroundColor DarkGray
    }
}

function Get-ScriptDir {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }
    return $null
}

function Remove-PathIfPresent {
    param(
        [string]$Target,
        [string]$Label,
        [bool]$IsDryRun
    )
    if (Test-Path $Target) {
        if ($IsDryRun) {
            Write-Host "  [remove] ${Label}" -ForegroundColor Red
        }
        else {
            Remove-Item $Target -Recurse -Force
            Write-Host "  [removed] ${Label}" -ForegroundColor Red
        }
        return $true
    }
    return $false
}

# ---------------------------------------------------------------------------
# Directory resolution
# ---------------------------------------------------------------------------

function Resolve-InstallDirs {
    param([string]$InstallScope)

    if ($InstallScope -eq 'user') {
        $cursorDir = Join-Path $HOME '.cursor'
        $pluginDir = Join-Path (Join-Path (Join-Path $cursorDir 'plugins') 'local') $PLUGIN_NAME
        return @{
            CursorDir   = $cursorDir
            PluginDir   = $pluginDir
            AgentsDir   = Join-Path $pluginDir 'agents'
            RulesDir    = Join-Path $pluginDir 'rules'
            CommandsDir = Join-Path $pluginDir 'commands'
            HooksDir    = Join-Path $pluginDir 'hooks'
            SkillsDir   = Join-Path $pluginDir 'skills'
        }
    }

    $cursorDir = Join-Path '.' '.cursor'
    return @{
        CursorDir   = $cursorDir
        PluginDir   = $null
        AgentsDir   = Join-Path $cursorDir 'agents'
        RulesDir    = Join-Path $cursorDir 'rules'
        CommandsDir = Join-Path $cursorDir 'commands'
        HooksDir    = Join-Path $cursorDir 'hooks'
        SkillsDir   = Join-Path $cursorDir 'skills'
    }
}

function Get-OrchestratorRuleDirs {
    param([hashtable]$Dirs)

    if ($Scope -eq 'user') {
        return @(
            (Join-Path $Dirs.PluginDir 'rules')
            (Join-Path (Join-Path $HOME '.cursor') 'rules')
        )
    }
    return @($Dirs.RulesDir)
}

# ---------------------------------------------------------------------------
# Toggle orchestration rule
# ---------------------------------------------------------------------------

function Set-OrchestratorRule {
    param(
        [hashtable]$Dirs,
        [bool]$DisableRule,
        [bool]$IsDryRun
    )

    Write-Host "oh-my-cursor v${VERSION}" -ForegroundColor White
    Write-Host $CURSOR_MODE_LABEL -ForegroundColor DarkGray
    Write-Host ''

    $found = $false
    foreach ($rulesDir in (Get-OrchestratorRuleDirs -Dirs $Dirs)) {
        $rulePath = Join-Path $rulesDir $RULE_FILE
        $disabledPath = Join-Path $rulesDir $RULE_FILE_DISABLED
        if (-not (Test-Path $rulePath) -and -not (Test-Path $disabledPath)) {
            continue
        }
        $found = $true

        if ($DisableRule) {
            if (Test-Path $rulePath) {
                if ($IsDryRun) {
                    Write-Host "  [would disable] ${RULE_FILE} in ${rulesDir}" -ForegroundColor Yellow
                }
                else {
                    Move-Item -Path $rulePath -Destination $disabledPath -Force
                    Write-Host "  [disabled] ${rulePath} - orchestration off. Agents and commands still available." -ForegroundColor Green
                }
            }
            else {
                Write-Host "  Already disabled (${disabledPath})" -ForegroundColor DarkGray
            }
        }
        else {
            if (Test-Path $disabledPath) {
                if ($IsDryRun) {
                    Write-Host "  [would enable] ${RULE_FILE} in ${rulesDir}" -ForegroundColor Yellow
                }
                else {
                    Move-Item -Path $disabledPath -Destination $rulePath -Force
                    Write-Host "  [enabled] ${rulePath} - Team Avatar orchestration on." -ForegroundColor Green
                }
            }
            else {
                Write-Host "  Already enabled (${rulePath})" -ForegroundColor DarkGray
            }
        }
    }

    if (-not $found) {
        Write-Host '  No orchestrator rule found. Install first, then retry -Disable/-Enable.' -ForegroundColor Yellow
    }

    Write-Host ''
}

# ---------------------------------------------------------------------------
# Source file acquisition
# ---------------------------------------------------------------------------

function Copy-SourcesFromLocalRepo {
    param([string]$OutDir)

    $scriptDir = Get-ScriptDir
    if (-not $scriptDir) { return $false }
    if (-not (Test-Path (Join-Path $scriptDir 'agents'))) { return $false }
    if (-not (Test-Path (Join-Path $scriptDir 'rules'))) { return $false }

    try {
        foreach ($name in @('agents', 'rules', 'commands', 'hooks', '.cursor-plugin')) {
            $path = Join-Path $OutDir $name
            if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
        }

        foreach ($file in $AGENT_FILES) {
            Copy-Item (Join-Path $scriptDir 'agents' $file) (Join-Path $OutDir 'agents' $file) -Force
        }

        foreach ($file in $PROTOCOL_FILES) {
            $destSubDir = Join-Path (Join-Path $OutDir 'agents') (Split-Path $file -Parent)
            if (-not (Test-Path $destSubDir)) { New-Item -ItemType Directory -Path $destSubDir -Force | Out-Null }
            Copy-Item (Join-Path $scriptDir 'agents' $file) (Join-Path (Join-Path $OutDir 'agents') $file) -Force
        }

        Copy-Item (Join-Path $scriptDir 'rules' $RULE_FILE) (Join-Path $OutDir 'rules' $RULE_FILE) -Force

        $cmdSrcDir = Join-Path $scriptDir 'commands'
        if (Test-Path $cmdSrcDir) {
            foreach ($file in $COMMAND_FILES) {
                Copy-Item (Join-Path $cmdSrcDir $file) (Join-Path $OutDir 'commands' $file) -Force
            }
        }

        $hooksSrcDir = Join-Path $scriptDir 'hooks'
        if (Test-Path $hooksSrcDir) {
            foreach ($file in $HOOK_FILES) {
                Copy-Item (Join-Path $hooksSrcDir $file) (Join-Path $OutDir 'hooks' $file) -Force
            }
        }

        $manifestSrcDir = Join-Path $scriptDir '.cursor-plugin'
        if (Test-Path $manifestSrcDir) {
            foreach ($file in $PLUGIN_MANIFEST_FILES) {
                $src = Join-Path $manifestSrcDir $file
                if (Test-Path $src) {
                    Copy-Item $src (Join-Path $OutDir '.cursor-plugin' $file) -Force
                }
            }
        }

        $permSrc = Join-Path $scriptDir 'permissions.json'
        if (Test-Path $permSrc) {
            Copy-Item $permSrc (Join-Path $OutDir 'permissions.json') -Force
        }

        $skillsSrcDir = Join-Path $scriptDir 'skills'
        if (Test-Path $skillsSrcDir) {
            Copy-Item $skillsSrcDir (Join-Path $OutDir 'skills') -Recurse -Force
        }

        return $true
    }
    catch {
        return $false
    }
}

function Get-SourcesFromGitHub {
    param([string]$OutDir)

    try {
        foreach ($file in $AGENT_FILES) {
            $dest = Join-Path $OutDir 'agents' $file
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Invoke-WebRequest -Uri "${SourceBaseUrl}/agents/${file}" -OutFile $dest -UseBasicParsing
        }

        foreach ($file in $PROTOCOL_FILES) {
            $dest = Join-Path (Join-Path $OutDir 'agents') $file
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Invoke-WebRequest -Uri "${SourceBaseUrl}/agents/${file}" -OutFile $dest -UseBasicParsing
        }

        $rulesOut = Join-Path $OutDir 'rules'
        if (-not (Test-Path $rulesOut)) { New-Item -ItemType Directory -Path $rulesOut -Force | Out-Null }
        Invoke-WebRequest -Uri "${SourceBaseUrl}/rules/${RULE_FILE}" -OutFile (Join-Path $rulesOut $RULE_FILE) -UseBasicParsing

        $cmdOutDir = Join-Path $OutDir 'commands'
        if (-not (Test-Path $cmdOutDir)) { New-Item -ItemType Directory -Path $cmdOutDir -Force | Out-Null }
        foreach ($file in $COMMAND_FILES) {
            Invoke-WebRequest -Uri "${SourceBaseUrl}/commands/${file}" -OutFile (Join-Path $cmdOutDir $file) -UseBasicParsing
        }

        $hooksOutDir = Join-Path $OutDir 'hooks'
        if (-not (Test-Path $hooksOutDir)) { New-Item -ItemType Directory -Path $hooksOutDir -Force | Out-Null }
        foreach ($file in $HOOK_FILES) {
            Invoke-WebRequest -Uri "${SourceBaseUrl}/hooks/${file}" -OutFile (Join-Path $hooksOutDir $file) -UseBasicParsing
        }

        $manifestOut = Join-Path $OutDir '.cursor-plugin'
        if (-not (Test-Path $manifestOut)) { New-Item -ItemType Directory -Path $manifestOut -Force | Out-Null }
        foreach ($file in $PLUGIN_MANIFEST_FILES) {
            Invoke-WebRequest -Uri "${SourceBaseUrl}/.cursor-plugin/${file}" -OutFile (Join-Path $manifestOut $file) -UseBasicParsing
        }

        Invoke-WebRequest -Uri "${SourceBaseUrl}/permissions.json" -OutFile (Join-Path $OutDir 'permissions.json') -UseBasicParsing

        $manifestUrl = "${SourceBaseUrl}/skills/MANIFEST"
        $manifestTmp = Join-Path ([System.IO.Path]::GetTempPath()) "oh-my-cursor-manifest-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        try {
            Invoke-WebRequest -Uri $manifestUrl -OutFile $manifestTmp -UseBasicParsing
            $skillsOutDir = Join-Path $OutDir 'skills'
            if (-not (Test-Path $skillsOutDir)) { New-Item -ItemType Directory -Path $skillsOutDir -Force | Out-Null }
            $manifestLines = Get-Content $manifestTmp
            foreach ($skillFile in $manifestLines) {
                if ([string]::IsNullOrWhiteSpace($skillFile)) { continue }
                $skillFileDir = Join-Path $skillsOutDir (Split-Path $skillFile -Parent)
                if (-not (Test-Path $skillFileDir)) { New-Item -ItemType Directory -Path $skillFileDir -Force | Out-Null }
                try {
                    Invoke-WebRequest -Uri "${SourceBaseUrl}/skills/${skillFile}" -OutFile (Join-Path $skillsOutDir $skillFile) -UseBasicParsing
                }
                catch {
                    # Non-fatal: individual skill file download failure
                }
            }
            Copy-Item $manifestTmp (Join-Path $skillsOutDir 'MANIFEST') -Force
        }
        catch {
            # MANIFEST not available, skip skills
        }
        finally {
            if (Test-Path $manifestTmp) { Remove-Item $manifestTmp -Force -ErrorAction SilentlyContinue }
        }

        return $true
    }
    catch {
        return $false
    }
}

function New-SourceFiles {
    param([string]$Dir)

    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }

    if (Copy-SourcesFromLocalRepo -OutDir $Dir) {
        Write-LogVerbose 'Using local repo sources'
        return
    }

    if (Get-SourcesFromGitHub -OutDir $Dir) {
        Write-LogVerbose "Downloaded sources from ${SourceBaseUrl}"
        return
    }

    Write-Host 'Failed to acquire source files.' -ForegroundColor Red
    Write-Host 'Tried local repo checkout and GitHub raw download.' -ForegroundColor DarkGray
    Write-Host 'Override the download base with $env:OH_MY_CURSOR_SOURCE_BASE_URL=...' -ForegroundColor DarkGray
    throw 'Source acquisition failed'
}

# ---------------------------------------------------------------------------
# Install a set of files from src_dir to dest_dir
# ---------------------------------------------------------------------------

function Install-FileSet {
    param(
        [string]$SrcDir,
        [string]$DestDir,
        [string]$Label,
        [string[]]$Files,
        [bool]$IsForce,
        [bool]$IsDryRun
    )

    if ($Files.Count -eq 0) { return }

    if (-not $IsDryRun) {
        if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir -Force | Out-Null }
    }

    Write-Host "Installing ${Label} to ${DestDir}" -ForegroundColor White
    Write-Host ''

    foreach ($file in $Files) {
        $src = Join-Path $SrcDir $file
        $dest = Join-Path $DestDir $file

        if (-not (Test-Path $src)) {
            Write-LogVerbose "  [skip] ${file} (source not found)"
            continue
        }

        $destSubDir = Split-Path $dest -Parent
        if (-not $IsDryRun -and -not (Test-Path $destSubDir)) {
            New-Item -ItemType Directory -Path $destSubDir -Force | Out-Null
        }

        if (-not (Test-Path $dest)) {
            if ($IsDryRun) {
                Write-Host "  [new] ${file}" -ForegroundColor Green
            }
            else {
                try {
                    Copy-Item $src $dest -Force
                    Write-Host "  [installed] ${file}" -ForegroundColor Green
                }
                catch {
                    Write-Host "  [failed] ${file}" -ForegroundColor Red
                    continue
                }
            }
        }
        elseif ((Get-FileHash $src).Hash -eq (Get-FileHash $dest).Hash) {
            Write-Host "  [unchanged] ${file}" -ForegroundColor DarkGray
        }
        elseif ($IsForce) {
            if ($IsDryRun) {
                Write-Host "  [update] ${file}" -ForegroundColor Yellow
            }
            else {
                try {
                    Copy-Item $src $dest -Force
                    Write-Host "  [updated] ${file}" -ForegroundColor Yellow
                }
                catch {
                    Write-Host "  [failed] ${file}" -ForegroundColor Red
                    continue
                }
            }
        }
        else {
            Write-Host "  [skipped] ${file} (use -Force to overwrite)" -ForegroundColor Yellow
        }
    }

    Write-Host ''
}

function Write-ProjectHooksJson {
    param(
        [string]$Dest,
        [bool]$IsDryRun
    )
    if ($IsDryRun) {
        if (Test-Path $Dest) {
            Write-Host '  [update] hooks.json (project paths)' -ForegroundColor Yellow
        }
        else {
            Write-Host '  [new] hooks.json (project paths)' -ForegroundColor Green
        }
        return
    }
    $destDir = Split-Path $Dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    $body = @'
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      { "command": "node .cursor/hooks/guard-shell.js", "failClosed": true }
    ],
    "afterFileEdit": [
      { "command": "node .cursor/hooks/post-edit-lint.js" }
    ]
  }
}
'@
    [IO.File]::WriteAllText($Dest, ($body -replace "`r`n", "`n"))
    Write-Host '  [installed] hooks.json (project paths)' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Migrate leftover v0.4 user-scope injection
# ---------------------------------------------------------------------------

function Remove-LegacyUserInjection {
    param(
        [string]$CursorDir,
        [bool]$IsDryRun
    )

    Write-Host "Checking for leftover user-scope injection in ${CursorDir}" -ForegroundColor White
    Write-Host ''

    $migrated = 0
    foreach ($file in ($AGENT_FILES + $LEGACY_AGENT_FILES + $PROTOCOL_FILES + $LEGACY_PROTOCOL_FILES)) {
        if (Remove-PathIfPresent -Target (Join-Path $CursorDir "agents/$file") -Label "agents/${file}" -IsDryRun $IsDryRun) {
            $migrated++
        }
    }
    foreach ($file in $COMMAND_FILES) {
        if (Remove-PathIfPresent -Target (Join-Path $CursorDir "commands/$file") -Label "commands/${file}" -IsDryRun $IsDryRun) {
            $migrated++
        }
    }
    foreach ($file in $LEGACY_HOOK_FILES) {
        if (Remove-PathIfPresent -Target (Join-Path $CursorDir "hooks/$file") -Label "hooks/${file}" -IsDryRun $IsDryRun) {
            $migrated++
        }
    }
    if (Remove-PathIfPresent -Target (Join-Path $CursorDir "rules/$RULE_FILE") -Label "rules/${RULE_FILE}" -IsDryRun $IsDryRun) {
        $migrated++
    }
    if (Remove-PathIfPresent -Target (Join-Path $CursorDir "rules/$RULE_FILE_DISABLED") -Label "rules/${RULE_FILE_DISABLED}" -IsDryRun $IsDryRun) {
        $migrated++
    }
    foreach ($skill in $SKILL_DIRS) {
        if (Remove-PathIfPresent -Target (Join-Path $CursorDir "skills/$skill") -Label "skills/${skill}/" -IsDryRun $IsDryRun) {
            $migrated++
        }
    }

    if ($migrated -gt 0) {
        Write-Host ''
        Write-Host "  Removed ${migrated} leftover file(s) from the old ~/.cursor injection layout." -ForegroundColor Yellow
        if (-not $IsDryRun) {
            foreach ($empty in @(
                    (Join-Path $CursorDir 'agents/protocols'),
                    (Join-Path $CursorDir 'agents'),
                    (Join-Path $CursorDir 'commands'),
                    (Join-Path $CursorDir 'hooks'),
                    (Join-Path $CursorDir 'rules'),
                    (Join-Path $CursorDir 'skills')
                )) {
                if ((Test-Path $empty) -and -not (Get-ChildItem $empty -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item $empty -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    else {
        Write-Host '  None found' -ForegroundColor DarkGray
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Migrate legacy agent files (Greek mythology -> ATLA)
# ---------------------------------------------------------------------------

function Remove-LegacyAgents {
    param(
        [string]$AgentsDir,
        [bool]$IsDryRun
    )

    $migrated = 0

    foreach ($file in $LEGACY_AGENT_FILES) {
        $target = Join-Path $AgentsDir $file
        if (Test-Path $target) {
            if ($IsDryRun) {
                Write-Host "  [migrate] removing legacy ${file}" -ForegroundColor Yellow
            }
            else {
                Remove-Item $target -Force
                Write-Host "  [migrated] removed legacy ${file}" -ForegroundColor Yellow
            }
            $migrated++
        }
    }

    foreach ($file in $LEGACY_PROTOCOL_FILES) {
        $target = Join-Path $AgentsDir $file
        if (Test-Path $target) {
            if ($IsDryRun) {
                Write-Host "  [migrate] removing legacy ${file}" -ForegroundColor Yellow
            }
            else {
                Remove-Item $target -Force
                Write-Host "  [migrated] removed legacy ${file}" -ForegroundColor Yellow
            }
            $migrated++
        }
    }

    if ($migrated -gt 0) {
        Write-Host ''
        Write-Host '  Migrated from v0.1 (Greek mythology) to v0.2 (Team Avatar)' -ForegroundColor Yellow
        Write-Host ''
    }
}

# ---------------------------------------------------------------------------
# Git pre-commit + install targets
# ---------------------------------------------------------------------------

function Install-GitPreCommitHook {
    param([bool]$IsDryRun)
    $gitDir = (& git rev-parse --absolute-git-dir 2>$null)
    if (-not $gitDir) { Write-Host '  [skip] git pre-commit hook (not a git repo)'; return }
    $hook = Join-Path (Join-Path $gitDir 'hooks') 'pre-commit'
    if ((Test-Path $hook) -and -not (Select-String -Path $hook -Pattern 'oh-my-cursor' -Quiet)) {
        Write-Host '  [skip] git pre-commit hook (existing non-OMC hook)'; return
    }
    if ($IsDryRun) { Write-Host "  [new] git pre-commit hook ($hook)" -ForegroundColor Green; return }
    New-Item -ItemType Directory -Path (Split-Path $hook -Parent) -Force | Out-Null
    $body = @'
#!/usr/bin/env bash
# oh-my-cursor defense-in-depth: catch anti-pattern commits regardless of HOW the commit is made
# (shell, git CLI, or Cursor's native git path). The beforeShellExecution guard only sees shell
# `git commit`; this git-native hook covers commits that bypass the shell.
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
exec node "$root/.cursor/hooks/pre-commit-check.js"
'@
    [IO.File]::WriteAllText($hook, ($body -replace "`r`n", "`n"))
    Write-Host "  [installed] git pre-commit hook ($hook)" -ForegroundColor Green
}

function Install-CursorPlugin {
    param(
        [string]$Dest,
        [string]$WorkDir,
        [bool]$IsForce,
        [bool]$IsDryRun
    )

    Remove-LegacyUserInjection -CursorDir (Join-Path $HOME '.cursor') -IsDryRun $IsDryRun
    Remove-LegacyAgents -AgentsDir (Join-Path $Dest 'agents') -IsDryRun $IsDryRun

    if (-not $IsDryRun -and -not (Test-Path $Dest)) {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }

    Install-FileSet -SrcDir (Join-Path $WorkDir '.cursor-plugin') -DestDir (Join-Path $Dest '.cursor-plugin') -Label 'plugin manifest' -Files $PLUGIN_MANIFEST_FILES -IsForce $IsForce -IsDryRun $IsDryRun
    Install-FileSet -SrcDir (Join-Path $WorkDir 'agents') -DestDir (Join-Path $Dest 'agents') -Label 'agents' -Files $AGENT_FILES -IsForce $IsForce -IsDryRun $IsDryRun
    Install-FileSet -SrcDir (Join-Path $WorkDir 'agents') -DestDir (Join-Path $Dest 'agents') -Label 'protocols' -Files $PROTOCOL_FILES -IsForce $IsForce -IsDryRun $IsDryRun
    Install-FileSet -SrcDir (Join-Path $WorkDir 'commands') -DestDir (Join-Path $Dest 'commands') -Label 'commands' -Files $COMMAND_FILES -IsForce $IsForce -IsDryRun $IsDryRun
    Install-FileSet -SrcDir (Join-Path $WorkDir 'hooks') -DestDir (Join-Path $Dest 'hooks') -Label 'hook scripts' -Files $HOOK_SCRIPT_FILES -IsForce $IsForce -IsDryRun $IsDryRun
    # Always refresh hooks.json so leftover bash commands cannot outlive deleted .sh files.
    Install-FileSet -SrcDir (Join-Path $WorkDir 'hooks') -DestDir (Join-Path $Dest 'hooks') -Label 'hooks.json' -Files @('hooks.json') -IsForce $true -IsDryRun $IsDryRun
    foreach ($file in $LEGACY_HOOK_FILES) {
        Remove-PathIfPresent -Target (Join-Path (Join-Path $Dest 'hooks') $file) -Label "hooks/${file}" -IsDryRun $IsDryRun | Out-Null
    }
    Install-FileSet -SrcDir (Join-Path $WorkDir 'rules') -DestDir (Join-Path $Dest 'rules') -Label 'rules' -Files @($RULE_FILE) -IsForce $IsForce -IsDryRun $IsDryRun
}

function Install-ToDir {
    param(
        [string]$TargetDir,
        [string]$WorkDir,
        [bool]$IsForce,
        [bool]$IsDryRun
    )

    $agentsDir = Join-Path $TargetDir 'agents'
    $rulesDir = Join-Path $TargetDir 'rules'
    $commandsDir = Join-Path $TargetDir 'commands'
    $hooksDir = Join-Path $TargetDir 'hooks'
    $isProjectCursor = ($Scope -eq 'project' -and (Split-Path $TargetDir -Leaf) -eq '.cursor')

    Remove-LegacyAgents -AgentsDir $agentsDir -IsDryRun $IsDryRun

    Install-FileSet -SrcDir (Join-Path $WorkDir 'agents') -DestDir $agentsDir -Label 'agents' -Files $AGENT_FILES -IsForce $IsForce -IsDryRun $IsDryRun
    Install-FileSet -SrcDir (Join-Path $WorkDir 'agents') -DestDir $agentsDir -Label 'protocols' -Files $PROTOCOL_FILES -IsForce $IsForce -IsDryRun $IsDryRun
    Install-FileSet -SrcDir (Join-Path $WorkDir 'commands') -DestDir $commandsDir -Label 'commands' -Files $COMMAND_FILES -IsForce $IsForce -IsDryRun $IsDryRun
    Install-FileSet -SrcDir (Join-Path $WorkDir 'hooks') -DestDir $hooksDir -Label 'hook scripts' -Files $HOOK_SCRIPT_FILES -IsForce $IsForce -IsDryRun $IsDryRun
    foreach ($file in $LEGACY_HOOK_FILES) {
        Remove-PathIfPresent -Target (Join-Path $hooksDir $file) -Label "hooks/${file}" -IsDryRun $IsDryRun | Out-Null
    }
    Install-FileSet -SrcDir (Join-Path $WorkDir 'rules') -DestDir $rulesDir -Label 'rules' -Files @($RULE_FILE) -IsForce $IsForce -IsDryRun $IsDryRun

    if ($isProjectCursor) {
        Write-Host "Installing project hook config to ${TargetDir}" -ForegroundColor White
        Write-Host ''
        Write-ProjectHooksJson -Dest (Join-Path $TargetDir 'hooks.json') -IsDryRun $IsDryRun
        if (Test-Path (Join-Path $WorkDir 'permissions.json')) {
            Install-FileSet -SrcDir $WorkDir -DestDir $TargetDir -Label 'auto-review policy' -Files @('permissions.json') -IsForce $IsForce -IsDryRun $IsDryRun
        }
        else {
            Write-Host ''
        }
        Install-GitPreCommitHook -IsDryRun $IsDryRun
        Write-Host ''
    }
}

# ---------------------------------------------------------------------------
# Skills installation
# ---------------------------------------------------------------------------

function Install-Skills {
    param(
        [string]$WorkDir,
        [string]$SkillsDir,
        [bool]$IsForce,
        [bool]$IsDryRun
    )

    $srcSkillsDir = Join-Path $WorkDir 'skills'

    if (-not (Test-Path $srcSkillsDir)) {
        Write-Host 'Warning: bundled skills not found in work directory. Skipping.' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    Write-Host "Installing skills to ${SkillsDir}" -ForegroundColor White
    Write-Host ''

    if (-not $IsDryRun -and -not (Test-Path $SkillsDir)) {
        New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
    }

    foreach ($skill in $SKILL_DIRS) {
        $skillSrc = Join-Path $srcSkillsDir $skill
        $skillDest = Join-Path $SkillsDir $skill

        if (-not (Test-Path $skillSrc)) {
            Write-LogVerbose "  [skip] ${skill} (source not found)"
            continue
        }

        if (-not (Test-Path $skillDest)) {
            if ($IsDryRun) {
                Write-Host "  [new] ${skill}/" -ForegroundColor Green
            }
            else {
                Copy-Item $skillSrc $skillDest -Recurse -Force
                Write-Host "  [installed] ${skill}/" -ForegroundColor Green
            }
        }
        elseif (Compare-SkillDirs -SrcDir $skillSrc -DestDir $skillDest) {
            Write-Host "  [unchanged] ${skill}/" -ForegroundColor DarkGray
        }
        elseif ($IsForce) {
            if ($IsDryRun) {
                Write-Host "  [update] ${skill}/" -ForegroundColor Yellow
            }
            else {
                Remove-Item $skillDest -Recurse -Force
                Copy-Item $skillSrc $skillDest -Recurse -Force
                Write-Host "  [updated] ${skill}/" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  [skipped] ${skill}/ (use -Force to overwrite)" -ForegroundColor Yellow
        }
    }

    Write-Host ''
}

function Compare-SkillDirs {
    param(
        [string]$SrcDir,
        [string]$DestDir
    )

    $srcFiles = @(Get-ChildItem $SrcDir -Recurse -File | Where-Object { $_.Name -ne '.DS_Store' })
    $destFiles = @(Get-ChildItem $DestDir -Recurse -File | Where-Object { $_.Name -ne '.DS_Store' })

    if ($srcFiles.Count -ne $destFiles.Count) { return $false }

    foreach ($srcFile in $srcFiles) {
        $relativePath = $srcFile.FullName.Substring($SrcDir.Length)
        $destFile = Join-Path $DestDir $relativePath
        if (-not (Test-Path $destFile)) { return $false }
        if ((Get-FileHash $srcFile.FullName).Hash -ne (Get-FileHash $destFile).Hash) { return $false }
    }

    return $true
}

# ---------------------------------------------------------------------------
# Uninstall logic
# ---------------------------------------------------------------------------

function Uninstall-Scattered {
    param(
        [string]$CursorDir,
        [bool]$IsDryRun
    )

    $removed = 0
    $agentsDir = Join-Path $CursorDir 'agents'
    $rulesDir = Join-Path $CursorDir 'rules'
    $commandsDir = Join-Path $CursorDir 'commands'
    $hooksDir = Join-Path $CursorDir 'hooks'
    $skillsDir = Join-Path $CursorDir 'skills'

    Write-Host "Removing agents from ${agentsDir}" -ForegroundColor White
    Write-Host ''
    foreach ($file in ($AGENT_FILES + $LEGACY_AGENT_FILES + $PROTOCOL_FILES + $LEGACY_PROTOCOL_FILES)) {
        $target = Join-Path $agentsDir $file
        if (Test-Path $target) {
            if ($IsDryRun) {
                Write-Host "  [remove] ${file}" -ForegroundColor Red
            }
            else {
                Remove-Item $target -Force
                Write-Host "  [removed] ${file}" -ForegroundColor Red
            }
            $removed++
        }
    }
    $protocolsDir = Join-Path $agentsDir 'protocols'
    if (-not $IsDryRun -and (Test-Path $protocolsDir) -and -not (Get-ChildItem $protocolsDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item $protocolsDir -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host "Removing commands from ${commandsDir}" -ForegroundColor White
    Write-Host ''
    foreach ($file in $COMMAND_FILES) {
        $target = Join-Path $commandsDir $file
        if (Test-Path $target) {
            if ($IsDryRun) {
                Write-Host "  [remove] ${file}" -ForegroundColor Red
            }
            else {
                Remove-Item $target -Force
                Write-Host "  [removed] ${file}" -ForegroundColor Red
            }
            $removed++
        }
    }

    Write-Host ''
    Write-Host "Removing hooks from ${hooksDir}" -ForegroundColor White
    Write-Host ''
    foreach ($file in ($HOOK_SCRIPT_FILES + $LEGACY_HOOK_FILES + @('hooks.json'))) {
        $target = Join-Path $hooksDir $file
        if (Test-Path $target) {
            if ($IsDryRun) {
                Write-Host "  [remove] ${file}" -ForegroundColor Red
            }
            else {
                Remove-Item $target -Force
                Write-Host "  [removed] ${file}" -ForegroundColor Red
            }
            $removed++
        }
    }

    foreach ($file in @('hooks.json', 'permissions.json')) {
        $target = Join-Path $CursorDir $file
        if (Test-Path $target) {
            if ($IsDryRun) {
                Write-Host "  [remove] ${file}" -ForegroundColor Red
            }
            else {
                Remove-Item $target -Force
                Write-Host "  [removed] ${file}" -ForegroundColor Red
            }
            $removed++
        }
    }

    Write-Host ''
    Write-Host "Removing rules from ${rulesDir}" -ForegroundColor White
    Write-Host ''
    foreach ($file in @($RULE_FILE, $RULE_FILE_DISABLED)) {
        $target = Join-Path $rulesDir $file
        if (Test-Path $target) {
            if ($IsDryRun) {
                Write-Host "  [remove] ${file}" -ForegroundColor Red
            }
            else {
                Remove-Item $target -Force
                Write-Host "  [removed] ${file}" -ForegroundColor Red
            }
            $removed++
        }
    }

    Write-Host ''
    Write-Host "Removing skills from ${skillsDir}" -ForegroundColor White
    Write-Host ''
    foreach ($skill in $SKILL_DIRS) {
        $skillDir = Join-Path $skillsDir $skill
        if (Test-Path $skillDir) {
            if ($IsDryRun) {
                Write-Host "  [remove] ${skill}/" -ForegroundColor Red
            }
            else {
                Remove-Item $skillDir -Recurse -Force
                Write-Host "  [removed] ${skill}/" -ForegroundColor Red
            }
            $removed++
        }
    }

    $script:RemovedCount = $removed
}

function Uninstall-Agents {
    param(
        [hashtable]$Dirs,
        [bool]$IsDryRun
    )

    Write-Host "oh-my-cursor v${VERSION}" -ForegroundColor White
    Write-Host $CURSOR_MODE_LABEL -ForegroundColor DarkGray
    Write-Host ''

    if ($IsDryRun) {
        Write-Host 'Dry run mode -- no changes will be made' -ForegroundColor Yellow
        Write-Host ''
    }

    $removed = 0

    if ($Scope -eq 'user') {
        if ($Dirs.PluginDir -and (Test-Path $Dirs.PluginDir)) {
            Write-Host "Removing Cursor plugin from $($Dirs.PluginDir)" -ForegroundColor White
            Write-Host ''
            if ($IsDryRun) {
                Write-Host "  [remove] $($Dirs.PluginDir)" -ForegroundColor Red
            }
            else {
                Remove-Item $Dirs.PluginDir -Recurse -Force
                Write-Host "  [removed] $($Dirs.PluginDir)" -ForegroundColor Red
                $localDir = Split-Path $Dirs.PluginDir -Parent
                if ((Test-Path $localDir) -and -not (Get-ChildItem $localDir -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item $localDir -Force -ErrorAction SilentlyContinue
                }
            }
            $removed++
            Write-Host ''
        }
        Write-Host "Removing leftover v0.4 injection from $(Join-Path $HOME '.cursor')" -ForegroundColor White
        Write-Host ''
        Uninstall-Scattered -CursorDir (Join-Path $HOME '.cursor') -IsDryRun $IsDryRun
        $removed += $script:RemovedCount
    }
    else {
        Uninstall-Scattered -CursorDir $Dirs.CursorDir -IsDryRun $IsDryRun
        $removed += $script:RemovedCount
    }

    $gitDir = (& git rev-parse --absolute-git-dir 2>$null)
    if ($gitDir) {
        $gitPc = Join-Path (Join-Path $gitDir 'hooks') 'pre-commit'
        if ((Test-Path $gitPc) -and (Select-String -Path $gitPc -Pattern 'oh-my-cursor' -Quiet)) {
            if ($IsDryRun) {
                Write-Host '  [remove] git pre-commit hook' -ForegroundColor Red
            }
            else {
                Remove-Item $gitPc -Force
                Write-Host '  [removed] git pre-commit hook' -ForegroundColor Red
            }
            $removed++
        }
    }

    Write-Host ''
    Write-Host 'Summary' -ForegroundColor White
    Write-Host "  Mode: ${CURSOR_MODE_LABEL}" -ForegroundColor DarkGray
    if ($removed -gt 0) {
        Write-Host "  Removed: ${removed}" -ForegroundColor Red
    }
    else {
        Write-Host '  Nothing to remove' -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Main {
    if ($Disable -and $Enable) {
        Write-Host 'Cannot use -Disable and -Enable together.' -ForegroundColor Red
        exit 1
    }

    $dirs = Resolve-InstallDirs -InstallScope $Scope

    if ($Disable -or $Enable) {
        Set-OrchestratorRule -Dirs $dirs -DisableRule $Disable.IsPresent -IsDryRun $DryRun.IsPresent
        return
    }

    if ($Uninstall) {
        Uninstall-Agents -Dirs $dirs -IsDryRun $DryRun.IsPresent
        return
    }

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "oh-my-cursor-$([guid]::NewGuid().ToString('N').Substring(0, 8))"

    try {
        Write-Host "oh-my-cursor v${VERSION}" -ForegroundColor White
        Write-Host $CURSOR_MODE_LABEL -ForegroundColor DarkGray
        Write-Host ''

        if ($DryRun) {
            Write-Host 'Dry run mode -- no changes will be made' -ForegroundColor Yellow
            Write-Host ''
        }

        Write-LogVerbose "Scope: ${Scope}"
        Write-LogVerbose "Target: $($dirs.CursorDir)"
        Write-LogVerbose "Force: ${Force}"

        New-SourceFiles -Dir $workDir

        if ($Scope -eq 'user') {
            Write-Host "Installing Cursor plugin to $($dirs.PluginDir)" -ForegroundColor White
            Write-Host ''
            Install-CursorPlugin -Dest $dirs.PluginDir -WorkDir $workDir -IsForce $Force.IsPresent -IsDryRun $DryRun.IsPresent
        }
        else {
            Write-Host "Installing to $($dirs.CursorDir)" -ForegroundColor White
            Write-Host ''
            Install-ToDir -TargetDir $dirs.CursorDir -WorkDir $workDir -IsForce $Force.IsPresent -IsDryRun $DryRun.IsPresent
        }

        if ($AlsoClaude) {
            $claudeDir = if ($Scope -eq 'user') { Join-Path $HOME '.claude' } else { Join-Path '.' '.claude' }
            Write-Host "Also installing to ${claudeDir} (Claude Code compatibility)" -ForegroundColor DarkGray
            Write-Host ''
            Install-ToDir -TargetDir $claudeDir -WorkDir $workDir -IsForce $Force.IsPresent -IsDryRun $DryRun.IsPresent
        }

        if ($AlsoCodex) {
            $codexDir = if ($Scope -eq 'user') { Join-Path $HOME '.codex' } else { Join-Path '.' '.codex' }
            Write-Host "Also installing to ${codexDir} (Codex compatibility)" -ForegroundColor DarkGray
            Write-Host ''
            Install-ToDir -TargetDir $codexDir -WorkDir $workDir -IsForce $Force.IsPresent -IsDryRun $DryRun.IsPresent
        }

        if (-not $NoSkills) {
            Install-Skills -WorkDir $workDir -SkillsDir $dirs.SkillsDir -IsForce $Force.IsPresent -IsDryRun $DryRun.IsPresent
        }

        Write-Host 'Summary' -ForegroundColor White
        Write-Host "  Mode: ${CURSOR_MODE_LABEL}" -ForegroundColor DarkGray
        if (-not $NoSkills) {
            Write-Host "  Agents: $($AGENT_FILES.Count) | Commands: $($COMMAND_FILES.Count) | Hooks: 3 | Skills: $($SKILL_DIRS.Count)" -ForegroundColor Green
        }
        else {
            Write-Host "  Agents: $($AGENT_FILES.Count) | Commands: $($COMMAND_FILES.Count) | Hooks: 3 | Skills: skipped" -ForegroundColor Green
        }
        Write-Host ''

        if ($Scope -eq 'user') {
            Write-Host 'Reload Cursor (Developer: Reload Window) or restart the app.' -ForegroundColor Yellow
            Write-Host 'Open Customize and confirm the oh-my-cursor plugin components are listed.' -ForegroundColor Yellow
            Write-Host ''
        }
        elseif ($Scope -eq 'project') {
            Write-Host 'Fully restart Cursor (Alt+F4) so project hooks register.' -ForegroundColor Yellow
            Write-Host ''
        }
    }
    finally {
        if (Test-Path $workDir) {
            Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Main
