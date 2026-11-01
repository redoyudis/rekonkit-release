param([string]$Version)

function Assert-RekonkitVersionTag {
    param([string]$Tag)
    $number = '(?:0|[1-9][0-9]*)'
    $identifier = '(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    if ($Tag -cnotmatch "\Av$number\.$number\.$number(?:-$identifier(?:\.$identifier)*)?\z") {
        throw "Invalid version '$Tag'; use vMAJOR.MINOR.PATCH with an optional SemVer prerelease."
    }
}

function Get-RekonkitUserPath {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if ($null -eq $key) { return $null }
    try { $key.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    finally { $key.Dispose() }
}

function Set-RekonkitUserPath {
    param([AllowNull()]$Value)
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        if ($null -eq $Value) { $key.DeleteValue('Path', $false) }
        else {
            $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
            if ($key.GetValueNames() -icontains 'Path') { $kind = $key.GetValueKind('Path') }
            $key.SetValue('Path', $Value, $kind)
        }
    } finally { $key.Dispose() }
    if (-not ('RekonkitInstallerEnvironment' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RekonkitInstallerEnvironment {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam,
        string lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
    }
    $result = [UIntPtr]::Zero
    $sent = [RekonkitInstallerEnvironment]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) { Write-Warning 'PATH saved, but environment notification timed out; sign out/in if new terminals do not see the change.' }
}

function Get-RekonkitUpdatedPath {
    param([AllowNull()][string]$Value, [string]$InstallDir)
    $seen = @{}
    $entries = @(
        foreach ($entry in @($Value -split ';') + @($InstallDir)) {
            $entry = $entry.Trim()
            $key = [Environment]::ExpandEnvironmentVariables($entry.Trim('"')).TrimEnd([char[]]'\/')
            # C: is drive-relative, whereas C:\ and \ denote roots.
            if ($key -match '\A[A-Za-z]:\z' -and $entry -match '[\\/]$') { $key += '\' }
            if ($entry -and -not $key) { $key = '\' }
            if ($key -and -not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $entry
            }
        }
    )
    $entries -join ';'
}

function Assert-RekonkitSafePath {
    param([string]$Path, [switch]$File)
    $item = [IO.FileInfo]::new([IO.Path]::GetFullPath($Path))
    $first = $true
    while ($null -ne $item) {
        # GetAttributes also catches dangling links, unlike Test-Path.
        try { $attributes = [IO.File]::GetAttributes($item.FullName) }
        catch [IO.FileNotFoundException] { $attributes = $null }
        catch [IO.DirectoryNotFoundException] { $attributes = $null }
        if ($null -ne $attributes) {
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing reparse point: $($item.FullName)"
            }
            $isDirectory = ($attributes -band [IO.FileAttributes]::Directory) -ne 0
            if (($first -and $File -and $isDirectory) -or ((-not $first -or -not $File) -and -not $isDirectory)) {
                throw "Unexpected file/directory at $($item.FullName)"
            }
        }
        $item = [IO.Directory]::GetParent($item.FullName)
        $first = $false
    }
}

function Test-RekonkitExecutable {
    param([string]$Path, [string]$ExpectedVersion)
    $output = @(& $Path --version 2>&1)
    $match = [regex]::Match(($output -join "`n"), '\Arekonkit\s+(\S+)')
    if ($LASTEXITCODE -ne 0 -or -not $match.Success -or ($ExpectedVersion -and $match.Groups[1].Value -cne $ExpectedVersion)) {
        throw "Version check failed for '$Path'; refusing to overwrite or install an unrelated executable."
    }
}

function Replace-RekonkitBinary {
    param([string]$Stage, [string]$Target, [string]$Backup)
    try { [IO.File]::Replace($Stage, $Target, $Backup) }
    catch { throw "Cannot replace '$Target' (close running rekonkit processes): $($_.Exception.Message)" }
}

function Invoke-RekonkitRequest {
    param([string]$Uri, [hashtable]$Headers, [string]$OutFile)
    # Windows PowerShell's automatic redirects can downgrade HTTPS to HTTP.
    # Follow redirects ourselves and accept only GitHub's HTTPS release/CDN hosts.
    for ($redirects = 0; $redirects -lt 10; $redirects++) {
        $url = [uri]$Uri
        if ($url.Scheme -cne 'https' -or $url.Port -ne 443 -or $url.UserInfo -or
            @('api.github.com', 'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com') -notcontains $url.Host) {
            throw "Refusing untrusted download URL: $Uri"
        }
        $request = @{ Uri = $Uri; Headers = $Headers; UseBasicParsing = $true; MaximumRedirection = 0; TimeoutSec = 300; ErrorAction = 'Stop' }
        if ($OutFile) { $request.OutFile = $OutFile; $request.PassThru = $true }
        try { $response = Invoke-WebRequest @request }
        catch {
            $response = $_.Exception.Response
            if ($null -eq $response -or [int]$response.StatusCode -lt 300 -or [int]$response.StatusCode -ge 400) { throw }
        }
        if ([int]$response.StatusCode -ge 300 -and [int]$response.StatusCode -lt 400) {
            $location = if ($response.Headers -is [Net.WebHeaderCollection]) { $response.Headers.Get('Location') }
                        else { [string]$response.Headers.Location }
            if (-not $location) { throw 'GitHub redirect has no Location header.' }
            $Uri = [uri]::new($url, $location).AbsoluteUri
        } else {
            if (-not $OutFile) { return $response }
            return
        }
    }
    throw 'Too many GitHub download redirects.'
}

function Install-Rekonkit {
    param([string]$Version)
    $ErrorActionPreference = 'Stop'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This installer requires Windows.' }
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -ine 'AMD64') { throw "Unsupported Windows architecture '$architecture'; only AMD64 is supported." }
    if ($PSBoundParameters.ContainsKey('Version')) { Assert-RekonkitVersionTag $Version }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA) -or $env:LOCALAPPDATA -notmatch '\A(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+\\)') {
        throw 'LOCALAPPDATA must be an absolute directory path.'
    }
    $installDir = Join-Path $env:LOCALAPPDATA 'rekonkit\bin'
    $target = Join-Path $installDir 'rekonkit.exe'
    Assert-RekonkitSafePath $installDir
    Assert-RekonkitSafePath $target -File

    $temp = $null
    $stage = $null
    $backup = $null
    $replaced = $false
    $completed = $false
    $pathAttempted = $false
    $oldUserPath = Get-RekonkitUserPath
    $oldSessionPath = $env:Path
    $oldTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        if ($PSVersionTable.PSVersion.Major -le 5) {
            [Net.ServicePointManager]::SecurityProtocol = $oldTls -bor [Net.SecurityProtocolType]::Tls12
        }
        $repo = 'redoyudis/rekonkit-release'
        $api = "https://api.github.com/repos/$repo"
        $headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'rekonkit-installer' }
        Write-Host 'Looking up the official RekonKit release...'
        $metadata = (Invoke-RekonkitRequest -Uri $api -Headers $headers).Content | ConvertFrom-Json
        if ($metadata.full_name -cne $repo -or $metadata.private -ne $false -or $metadata.default_branch -cne 'main') {
            throw 'Official release repository must be public redoyudis/rekonkit-release with default branch main.'
        }
        $endpoint = "$api/releases/latest"
        if ($Version) { $endpoint = "$api/releases/tags/$Version" }
        $release = (Invoke-RekonkitRequest -Uri $endpoint -Headers $headers).Content | ConvertFrom-Json
        $tag = [string]$release.tag_name
        Assert-RekonkitVersionTag $tag
        if (($Version -and $tag -cne $Version) -or $release.draft -ne $false -or
            (-not $Version -and ($release.prerelease -ne $false -or $tag.Contains('-')))) {
            throw 'Release tag mismatch or unpublished release.'
        }
        $assetName = 'rekonkit-windows-amd64.exe'
        foreach ($name in @($assetName, 'SHA256SUMS')) {
            if (@($release.assets | Where-Object { $_.name -ceq $name }).Count -ne 1) {
                throw "Release must contain exactly one '$name' asset."
            }
        }
        $temp = Join-Path ([IO.Path]::GetTempPath()) ('rekonkit-download-' + [guid]::NewGuid().ToString('N'))
        Assert-RekonkitSafePath $temp
        [IO.Directory]::CreateDirectory($temp) | Out-Null
        Assert-RekonkitSafePath $temp
        $binaryPath = Join-Path $temp $assetName
        $sumsPath = Join-Path $temp 'SHA256SUMS'
        $download = "https://github.com/$repo/releases/download/$tag"
        Write-Host "Downloading and verifying $assetName..."
        Invoke-RekonkitRequest -Uri "$download/SHA256SUMS" -Headers $headers -OutFile $sumsPath
        Invoke-RekonkitRequest -Uri "$download/$assetName" -Headers $headers -OutFile $binaryPath
        $checksums = @{}
        foreach ($line in [IO.File]::ReadAllLines($sumsPath)) {
            if ($line -ceq '') { continue }
            if ($line -cnotmatch '\A([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)\z') { throw 'Malformed SHA256SUMS.' }
            if ($checksums.ContainsKey($Matches[2])) { throw 'Duplicate SHA256SUMS entry.' }
            $checksums[$Matches[2]] = $Matches[1]
        }
        if (-not $checksums.ContainsKey($assetName) -or (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $checksums[$assetName]) {
            throw 'Binary checksum mismatch or missing checksum.'
        }
        Assert-RekonkitSafePath $installDir
        [IO.Directory]::CreateDirectory($installDir) | Out-Null
        Assert-RekonkitSafePath $target -File
        $stage = Join-Path $installDir ('.rekonkit-' + [guid]::NewGuid().ToString('N') + '.exe')
        [IO.File]::Copy($binaryPath, $stage, $false)
        Test-RekonkitExecutable $stage $tag
        Assert-RekonkitSafePath $target -File
        if ([IO.File]::Exists($target)) {
            Test-RekonkitExecutable $target
            $backup = Join-Path $installDir ('.rekonkit-' + [guid]::NewGuid().ToString('N') + '.backup')
            Replace-RekonkitBinary $stage $target $backup
        } else {
            [IO.File]::Move($stage, $target)
        }
        $replaced = $true
        Test-RekonkitExecutable $target $tag
        $pathAttempted = $true
        Set-RekonkitUserPath (Get-RekonkitUpdatedPath $oldUserPath $installDir)
        $env:Path = Get-RekonkitUpdatedPath $oldSessionPath $installDir
        Write-Host "Installed $target ($tag). User and current-session PATH updated."
        $completed = $true
    } catch {
        $failure = $_.Exception.Message
        if ($replaced -or ($backup -and [IO.File]::Exists($backup))) {
            try {
                Assert-RekonkitSafePath $target -File
                if ($backup) {
                    if ([IO.File]::Exists($target)) {
                        [IO.File]::Replace($backup, $target, [System.Management.Automation.Language.NullString]::Value)
                    } else { [IO.File]::Move($backup, $target) }
                } else { [IO.File]::Delete($target) }
            } catch { $failure += " Rollback failed; preserved old binary at '$backup': $($_.Exception.Message)" }
        }
        if ($pathAttempted) {
            $env:Path = $oldSessionPath
            try { Set-RekonkitUserPath $oldUserPath }
            catch { $failure += " User PATH restore failed: $($_.Exception.Message)" }
        }
        throw $failure
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $oldTls
        # A backup left after failed rollback is deliberately retained for recovery.
        foreach ($file in @($stage, $(if ($completed) { $backup }))) {
            if ($file) {
                try { [IO.File]::Delete($file) }
                catch { Write-Warning "Could not clean up '$file': $($_.Exception.Message)" }
            }
        }
        if ($temp) {
            try { [IO.Directory]::Delete($temp, $true) }
            catch { Write-Warning "Could not clean up '$temp': $($_.Exception.Message)" }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Install-Rekonkit @PSBoundParameters }
    catch { Write-Error $_; exit 1 }
}
