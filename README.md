# RekonKit

CLI for reconciliation project parameters, database definitions, migrations and debug SQL. Install a prebuilt release: **no Go, source checkout, sudo or Administrator privileges required**. Git is needed later for project initialization.

| System | CPUs | Installed command |
|---|---|---|
| Windows | AMD64 (x64) | `%LOCALAPPDATA%\Programs\Rekonkit\rekonkit.exe` |
| Linux | AMD64 (x86_64), ARM64 (aarch64) | `$HOME/.local/bin/rekonkit` |
| macOS | Intel (x86_64), Apple Silicon (arm64) | `$HOME/.local/bin/rekonkit` |

Windows requires Windows 10 or later (x64), matching the Go runtime. Windows ARM64/32-bit and other operating systems are not supported. Under macOS Rosetta, the detected x86_64 binary is used.

## Windows

1. Download [rekonkit-setup.exe (latest release)](https://github.com/redoyudis/rekonkit-release/releases/latest/download/rekonkit-setup.exe). For a specific version, choose its installer on the [Releases page](https://github.com/redoyudis/rekonkit-release/releases).
2. Verify its SHA-256 against the `rekonkit-setup.exe` entry in `SHA256SUMS` from the **same release**, before running it. In PowerShell, `Get-FileHash .\rekonkit-setup.exe -Algorithm SHA256` prints the hash; stop if the manifest entry is absent, duplicated or mismatched.
3. Run the installer normally, **not as Administrator**. It installs per user to `%LOCALAPPDATA%\Programs\Rekonkit`, registers **Rekonkit** in Windows Installed Apps, and adds the directory to your user PATH without duplicating an existing entry. No application is launched automatically.
4. Open a **new terminal** and run `rekonkit --version` (or `rekonkit version`). Existing terminals do not automatically acquire the new PATH.

To upgrade, close running RekonKit processes and run the newer installer. It replaces the binary under the same application identity; it does not create a second Installed Apps entry. Project files are not removed. Downloading the setup and running it needs no PowerShell download script or execution-policy changes.

**Unsigned software:** Windows SmartScreen may warn, and corporate AppLocker, WDAC or antivirus policies may block the installer or CLI. Ask IT to approve the exact release; **do not disable protection or bypass policy**. SHA-256 is an integrity check, not a trusted-publisher signature or a guarantee against a compromised publisher.

### Existing legacy installation

The previous script/local developer installer used `%LOCALAPPDATA%\rekonkit\bin`. Setup stops if that directory is still on user or system PATH, including an expanded `%LOCALAPPDATA%` entry. It never deletes legacy files or edits that PATH entry automatically because it has no ownership record.

Close RekonKit, then use Windows **Environment Variables** settings to remove **only** that old directory from PATH; preserve every unrelated entry. A system PATH entry requires administrator/IT assistance. Retry setup, reopen your terminal, and check `Get-Command rekonkit -All` if the wrong version runs. An old binary outside PATH can be kept, or you may remove only the known old `rekonkit.exe` after verifying the new installation; do not delete directories containing other files. Other manually installed copies can still shadow the new command: inspect them before editing PATH.

### Silent installation and uninstallation

From **Command Prompt** (wait for completion):

```bat
start /wait "" rekonkit-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
start /wait "" "%LOCALAPPDATA%\Programs\Rekonkit\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

Legacy PATH conflicts also fail silent installation; they are never silently removed. Add `/LOG="C:\path\setup.log"` for diagnostics. Use **Settings → Apps → Installed apps → Rekonkit → Uninstall** for interactive removal. Uninstall removes the application and only the PATH entry setup added. An equivalent PATH entry that already existed before installation belongs to you and is left unchanged. Unrelated PATH entries and project data remain intact. Reopen terminals afterward.

### Portable alternative

Download `rekonkit-windows-amd64.zip` and `SHA256SUMS` from the same release. Verify the ZIP's exact manifest entry with `Get-FileHash -Algorithm SHA256` before extracting. Extract `rekonkit.exe` into a directory you control, separate from a setup-managed installation, and run it by full path or add **only that directory** to your user PATH. To upgrade, close RekonKit and replace that file with a newly verified copy. To remove, delete your portable executable and only your own PATH entry. Portable installs have no Installed Apps registration or automatic PATH management. The standalone `rekonkit-windows-amd64.exe` remains available; rename a verified copy to `rekonkit.exe` if preferred.

## Linux and macOS

Requires Bash, curl, standard text/file utilities and either `sha256sum` (Linux) or `shasum` (macOS). No jq or Python required.

```bash
curl -fsSLO https://raw.githubusercontent.com/redoyudis/rekonkit-release/main/install.sh
bash install.sh
```

Specific version:

```bash
bash install.sh --version v0.3.0
```

When needed, the installer adds `$HOME/.local/bin` to Bash's `~/.bashrc` (Linux), the first existing Bash login profile (macOS), or Zsh's `${ZDOTDIR:-$HOME}/.zshrc`. It avoids duplicate installer lines. Reopen your terminal, or use this immediately:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Linked/nonregular profiles are left unchanged. For other shells, configure PATH using that shell's syntax (Fish: `fish_add_path $HOME/.local/bin`). Bash login-only Linux setups may also need the export in their login profile. Never replace your entire existing PATH.

### Optional Unix remote execution

Only if you understand and accept that this executes a script without prior inspection:

```bash
curl -fsSL https://raw.githubusercontent.com/redoyudis/rekonkit-release/main/install.sh | bash
```

Use only the official installer URL. The script itself is not authenticated by a release checksum. Rerun to update to the latest stable release, or use `--version vMAJOR.MINOR.PATCH` (optional SemVer prerelease suffix). New Unix downloads are verified before execution; failed upgrades retain the previous binary. An uncatchable termination/power loss may leave temporary files; review them before removing. The Bash installer refuses linked install paths and unrelated existing executables.

## Verify

```text
rekonkit --version
rekonkit --help
```

There is no in-app updater. On Windows, run the newer setup; on Unix, rerun the Bash installer.

## Integrity and troubleshooting

- All binaries, Windows packages and `SHA256SUMS` come only from [this repository's releases](https://github.com/redoyudis/rekonkit-release/releases). Verify a matching filename/hash before executing or extracting downloaded files. SHA-256 detects corruption; it **does not protect against a compromised publisher** or replace repository security, code signing or organizational approval. Windows releases are unsigned; macOS releases are not signed/notarized. Follow your organization's approval process if execution is blocked.
- **Setup link not available yet:** native setup and portable ZIP appear only after the first new release containing them. Older standalone releases are not changed. The Unix raw script URL needs a successful installer synchronization run.
- **Command not found/wrong version:** reopen the terminal; use `Get-Command rekonkit -All` (Windows) or `command -v rekonkit` (Unix). A different installation earlier in PATH can shadow this one. Use the full installed path to check it before changing PATH.
- **Network/proxy:** allow HTTPS access to `api.github.com`, `github.com`, `raw.githubusercontent.com` and GitHub's release asset/CDN hosts. curl honors `HTTPS_PROXY`/`NO_PROXY`; use your browser's configured proxy for setup downloads. Follow IT's proxy/certificate instructions; never disable TLS verification. GitHub's anonymous API is rate-limited; wait and retry after rate-limit errors. Setup itself installs its embedded binary without network access.
- **Permissions or file locks:** close RekonKit, check user-directory permissions and antivirus logs, and retry. Do not run the installer as Administrator or with sudo. Use a normal writable/executable user filesystem. On Unix, review a leftover `~/.local/bin/.rekonkit-install.lock` only after confirming no installer is running.
- **Manual/offline Unix installation:** download your standalone binary and `SHA256SUMS` from the same release: `rekonkit-linux-amd64`, `rekonkit-linux-arm64`, `rekonkit-darwin-amd64` or `rekonkit-darwin-arm64`. Verify before copying or executing with `sha256sum` (Linux), or `shasum -a 256` (macOS), comparing the exact manifest filename/hash; missing, duplicate or mismatched entries must stop installation. Copy the verified file to `$HOME/.local/bin/rekonkit`, `chmod 755`, then add that directory to your user PATH if needed. Close running RekonKit processes before replacing the binary. Manual copies lack the Bash installer's rollback protections. GitHub's automatic source-code downloads are not binary packages.

## Uninstall on Linux/macOS

`rm "$HOME/.local/bin/rekonkit"`. Remove the `# RekonKit user-local binaries` comment and its following export from the profile changed by the installer **only if other tools do not need that PATH entry**. Do not delete `~/.local/bin` or unrelated PATH entries. Project data/configuration is not removed.
