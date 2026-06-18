# Copyright (c) Microsoft Corporation. All rights reserved.
# Scaffold ASP.NET Core project with YARP proxy for side-by-side migration.
# Copies template files from the skill's templates/ folder and applies variable substitution.

param(
    [Parameter(Mandatory)]
    [string]$OldProjectPath,

    [Parameter(Mandatory)]
    [string]$SolutionPath,

    [Parameter(Mandatory)]
    [string]$TargetFramework,

    [string]$NewProjectName,

    [ValidateSet('MVC', 'WebAPI')]
    [string]$ProjectType = 'MVC',

    [Parameter(Mandatory)]
    [string]$OldAppUrl,

    [string]$SystemWebAdaptersVersion = '2.3.0',

    [string]$YarpVersion = '2.3.0',

    [string]$TemplatesRoot
)

$ErrorActionPreference = 'Stop'

# Resolve paths
$OldProjectPath = Resolve-Path $OldProjectPath
$SolutionPath = Resolve-Path $SolutionPath
$OldProjectDir = Split-Path $OldProjectPath -Parent
$ParentDir = Split-Path $OldProjectDir -Parent

if (-not $NewProjectName) {
    $NewProjectName = [System.IO.Path]::GetFileNameWithoutExtension($OldProjectPath) + '.Core'
}

# Validate project name uniqueness
$NewProjectDir = Join-Path $ParentDir $NewProjectName
$NewProjectPath = Join-Path $NewProjectDir "$NewProjectName.csproj"

if (Test-Path $NewProjectDir) {
    Write-Error "Directory already exists: $NewProjectDir. Choose a different project name."
    return
}

# Check solution for name conflict
$slnCheck = Get-Content $SolutionPath -Raw
if ($slnCheck -match [regex]::Escape("`"$NewProjectName`"")) {
    Write-Error "A project named '$NewProjectName' already exists in the solution. Choose a different name."
    return
}

# Locate template folder
if (-not $TemplatesRoot) {
    $TemplatesRoot = Join-Path $PSScriptRoot 'templates'
}

$templateKey = if ($ProjectType -eq 'WebAPI') { 'webapi' } else { 'mvc' }
$templateDir = Join-Path $TemplatesRoot $templateKey

if (-not (Test-Path $templateDir)) {
    Write-Error "Template directory not found: $templateDir"
    return
}

$HttpsPort = Get-Random -Minimum 7100 -Maximum 7999
$HttpPort = Get-Random -Minimum 5100 -Maximum 5999
$NewPort = Get-Random -Minimum 60000 -Maximum 65000
$NewSslPort = Get-Random -Minimum 44300 -Maximum 44399

Write-Host "Creating side-by-side project: $NewProjectName" -ForegroundColor Cyan
Write-Host "  Old project : $OldProjectPath"
Write-Host "  New project : $NewProjectPath"
Write-Host "  Template    : $templateDir"
Write-Host "  TFM         : $TargetFramework"
Write-Host "  Type        : $ProjectType"
Write-Host "  Proxy target: $OldAppUrl"
Write-Host "  Ports       : HTTPS=$HttpsPort, HTTP=$HttpPort, IIS=$NewPort, IIS-SSL=$NewSslPort"

# Variable map: template placeholder -> value
$substitutions = @{
    '$TargetFramework$'          = $TargetFramework
    '$SystemWebAdaptersVersion$' = $SystemWebAdaptersVersion
    '$YarpVersion$'              = $YarpVersion
    '$ProjectName$'              = $NewProjectName
    '$HttpsPort$'                = $HttpsPort.ToString()
    '$HttpPort$'                 = $HttpPort.ToString()
    '$NewPort$'                  = $NewPort.ToString()
    '$NewSslPort$'               = $NewSslPort.ToString()
    '$OldAppUrl$'                = $OldAppUrl
}

function Copy-TemplateWithSubstitutions {
    param([string]$Source, [string]$Destination, [hashtable]$Vars)

    # Pure .NET — no PowerShell path cmdlets at all
    $sourceDir = [System.IO.DirectoryInfo]::new($Source)
    if (-not $sourceDir.Exists) { Write-Error "Source not found: $Source"; return }

    [System.IO.Directory]::CreateDirectory($Destination) | Out-Null

    foreach ($file in $sourceDir.GetFiles('*', [System.IO.SearchOption]::AllDirectories)) {
        # Get path relative to source
        $relativePath = $file.FullName.Substring($sourceDir.FullName.TrimEnd('\').Length + 1)

        # Rename ProjectName.csproj
        if ($relativePath -like '*ProjectName.csproj') {
            $relativePath = $relativePath.Replace('ProjectName.csproj', "$NewProjectName.csproj")
        }

        # Flatten appsettings\<env>.json → appsettings.<env>.json
        $relativePath = $relativePath -replace '^appsettings\\(.+)', 'appsettings.$1'

        $destFile = [System.IO.Path]::Combine($Destination, $relativePath)
        $destDir = [System.IO.Path]::GetDirectoryName($destFile)

        # Create parent directory if needed
        if (-not [System.IO.Directory]::Exists($destDir)) {
            [System.IO.Directory]::CreateDirectory($destDir) | Out-Null
        }

        # Read, substitute, write
        $content = [System.IO.File]::ReadAllText($file.FullName)
        foreach ($key in $Vars.Keys) {
            $content = $content.Replace($key, $Vars[$key])
        }
        [System.IO.File]::WriteAllText($destFile, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "    -> $relativePath"
    }
}

Copy-TemplateWithSubstitutions -Source $templateDir -Destination $NewProjectDir -Vars $substitutions
Write-Host "  Files created from template." -ForegroundColor Green

Write-Host "  Adding to solution..." -ForegroundColor Cyan
dotnet sln $SolutionPath add $NewProjectPath
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to add project to solution"; return }
Write-Host "  Added to solution." -ForegroundColor Green

# Find new project GUID and link old project
$slnContent = Get-Content $SolutionPath -Raw
$escapedName = [regex]::Escape($NewProjectName)
$slnMatch = [regex]::Match($slnContent, "Project\([^)]+\)\s*=\s*`"$escapedName`"\s*,\s*`"[^`"]+`"\s*,\s*`"\{([0-9A-Fa-f-]+)\}`"")
$newProjectGuid = if ($slnMatch.Success) { $slnMatch.Groups[1].Value } else { $null }

if ($newProjectGuid) {
    Write-Host "  New project GUID: $newProjectGuid" -ForegroundColor Cyan
    $oldCsproj = Get-Content $OldProjectPath -Raw
    if ($oldCsproj -notmatch '_MigrateToProjectGuid') {
        $oldCsproj = $oldCsproj -replace '(</PropertyGroup>)', "    <_MigrateToProjectGuid>$newProjectGuid</_MigrateToProjectGuid>`n  `$1"
        Set-Content -Path $OldProjectPath -Value $oldCsproj -NoNewline -Encoding utf8NoBOM
        Write-Host "  Linked old project via _MigrateToProjectGuid." -ForegroundColor Green
    }
} else {
    Write-Warning "Could not find new project GUID in solution. Add _MigrateToProjectGuid manually."
}

Write-Host "  Building new project..." -ForegroundColor Cyan
dotnet build $NewProjectPath --nologo -v:q
if ($LASTEXITCODE -eq 0) { Write-Host "  Build succeeded." -ForegroundColor Green }
else { Write-Warning "Build failed. Check the project configuration." }

Write-Host "`nScaffolding complete: $NewProjectPath" -ForegroundColor Green
Write-Host "ProxyTo: $OldAppUrl (in launchSettings.json)" -ForegroundColor Cyan