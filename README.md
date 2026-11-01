# RekonKit

CLI for reconciliation project parameters, database definitions, migrations and debug SQL. Install a prebuilt release: **no Go, source checkout, sudo or Administrator privileges required**. Git is needed later for project initialization.

| System | CPUs | Installed command |
|---|---|---|
| Windows | AMD64 (x64) | `%LOCALAPPDATA%\rekonkit\bin\rekonkit.exe` |
| Linux | AMD64 (x86_64), ARM64 (aarch64) | `$HOME/.local/bin/rekonkit` |
| macOS | Intel (x86_64), Apple Silicon (arm64) | `$HOME/.local/bin/rekonkit` |

Windows ARM64/32-bit and other operating systems are not supported. Under macOS Rosetta, the detected x86_64 binary is used.

## Windows

In Windows PowerShell 5.1 or PowerShell 7, download, **inspect**, then run:

```powershell
Invoke-WebRequest -UseBasicParsing `
  https://raw.githubusercontent.com/redoyudis/rekonkit-release/main/install.ps1 `
  -OutFile install.ps1
Get-Content .\install.ps1
.\install.ps1
```

Install a specific version instead:

```powershell
.\install.ps1 -Version v0.3.0
```

The installer adds the directory to your user PATH and current PowerShell session. Other terminals need reopening. Close running RekonKit processes before upgrading. If execution policy, AppLocker, WDAC, antivirus or organizational policy blocks installation, ask your administrator to approve the script/binary; **do not disable protection or bypass policy**. These releases are not code-signed.

## Linux and macOS

Requires Bash, curl, standard text/file utilities and either `sha256sum` (Linux) or `shasum` (macOS). No jq or Python required.

```bash
curl -fsSLO https://raw.githubusercontent.com/redoyudis/rekonkit-release/main/install.sh
less install.sh
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

## Optional remote execution

Only if you understand and accept that these commands execute a script without prior inspection:

```powershell
(Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/redoyudis/rekonkit-release/main/install.ps1).Content | Invoke-Expression
```

```bash
curl -fsSL https://raw.githubusercontent.com/redoyudis/rekonkit-release/main/install.sh | bash
```

Downloading and inspecting first is recommended. Installers themselves are not authenticated by a release checksum.

## Verify and update

```text
rekonkit --version
rekonkit --help
```

Rerun the installer to update to the latest stable GitHub release, or supply an explicit `vMAJOR.MINOR.PATCH` (optional SemVer prerelease suffix). New downloads are verified before execution; failed upgrades retain the previous binary. An uncatchable termination/power loss may leave temporary files; review them before removing. Installers refuse linked install paths and unrelated existing executables. They do not add an in-app update command.

## Integrity and troubleshooting

- Standalone binaries and `SHA256SUMS` come only from [this repository's releases](https://github.com/redoyudis/rekonkit-release/releases). The installers download the matching binary directly; no ZIP/tar tools or extraction are needed. A missing/invalid checksum aborts installation before execution. SHA-256 detects corruption; it **does not protect against a compromised publisher** or replace repository security, code signing or organizational approval. macOS releases are not signed/notarized; follow your organization's approval process if Gatekeeper blocks execution.
- No installer scripts published yet? A maintainer must enable the source repository's installer synchronization workflow; the raw URLs will work after its first successful run.
- **Command not found/wrong version:** reopen the terminal; use `Get-Command rekonkit -All` (Windows) or `command -v rekonkit` (Unix). A different installation earlier in PATH can shadow this one. Use the full installed path to check it before changing PATH.
- **Network/proxy:** allow HTTPS access to `api.github.com`, `github.com`, `raw.githubusercontent.com` and GitHub's release asset/CDN hosts. curl honors `HTTPS_PROXY`/`NO_PROXY`; PowerShell uses its configured system/.NET proxy. Follow IT's proxy/certificate instructions; never disable TLS verification. GitHub's anonymous API is rate-limited; wait and retry after rate-limit errors. Repeatedly failing downloads do not replace the old binary.
- **Permissions or file locks:** close RekonKit, check user-directory permissions and antivirus logs, and retry. Do not run the installer as Administrator or with sudo. Use a normal writable/executable user filesystem. On Unix, review a leftover `~/.local/bin/.rekonkit-install.lock` only after confirming no installer is running.
- **Manual/offline installation:** download your standalone binary and `SHA256SUMS` from the same release: `rekonkit-windows-amd64.exe`, `rekonkit-linux-amd64`, `rekonkit-linux-arm64`, `rekonkit-darwin-amd64` or `rekonkit-darwin-arm64`. Verify **before copying or executing** with `Get-FileHash -Algorithm SHA256` (Windows), `sha256sum` (Linux), or `shasum -a 256` (macOS), comparing the exact manifest filename/hash; missing, duplicate or mismatched entries must stop installation. Copy/rename the verified file to the installation path in the table above (Unix: `chmod 755`), then add that directory to your user PATH if needed. Close running RekonKit processes before replacing the binary. Manual copies lack the online installers' rollback protections. New releases have no installer archives; older published archives remain available. GitHub's automatic source-code downloads are not binary packages.

## Uninstall

Windows: remove `%LOCALAPPDATA%\rekonkit\bin\rekonkit.exe`; remove **only** `%LOCALAPPDATA%\rekonkit\bin` from your user PATH using Environment Variables settings, then reopen terminals. Remove the empty RekonKit directories if desired.

Linux/macOS: `rm "$HOME/.local/bin/rekonkit"`. Remove the `# RekonKit user-local binaries` comment and its following export from the profile changed by the installer **only if other tools do not need that PATH entry**. Do not delete `~/.local/bin` or unrelated PATH entries. Project data/configuration is not removed.
