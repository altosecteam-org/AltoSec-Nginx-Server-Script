<#
.SYNOPSIS
  Provision a GitHub Actions self-hosted runner on a remote Linux node from Windows.

.DESCRIPTION
  Runs the canonical bootstrap-node.sh one-liner on the target over SSH (it curls
  the script from the AltoSec-Nginx-Server-Script repo and runs it with sudo), so a
  blank Debian/Ubuntu box gets Docker + the runner + a systemd service in one shot.
  Requires the Windows OpenSSH client and SSH access (key or password) to the host.

.PARAMETER RunnerHost
  Target Linux host (IP or DNS name).

.PARAMETER RunnerName
  Runner name to register (e.g. proxy-node-01).

.PARAMETER Token
  GitHub registration token (repo Settings -> Actions -> Runners -> New self-hosted
  runner). Valid ~1 hour.

.PARAMETER SshUser
  SSH user with sudo on the target (default: root).

.PARAMETER Url
  Repository the runner registers against (default: the Altosec LoadBalancer repo).

.PARAMETER ScriptUrl
  Raw URL of bootstrap-node.sh (default: AltoSec-Nginx-Server-Script main branch).

.PARAMETER IdentityFile
  Optional SSH private key path.

.EXAMPLE
  ./Install-Runner.ps1 -RunnerHost 203.0.113.10 -RunnerName proxy-node-01 -Token AABBCCDD
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RunnerHost,
  [Parameter(Mandatory)][string]$RunnerName,
  [Parameter(Mandatory)][string]$Token,
  [string]$SshUser = "root",
  [string]$Url = "https://github.com/altosecteam-org/Altosec-nginx-manager",
  [string]$ScriptUrl = "https://raw.githubusercontent.com/altosecteam-org/AltoSec-Nginx-Server-Script/main/linux/bootstrap-node.sh",
  [string]$IdentityFile
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  throw "The OpenSSH client (ssh) was not found. Install 'OpenSSH Client' under Optional Features."
}

$sshArgs = @()
if ($IdentityFile) { $sshArgs += @("-i", $IdentityFile) }
$sshArgs += "$SshUser@$RunnerHost"

$remote = "curl -fsSL '$ScriptUrl' | sudo bash -s -- --token '$Token' --runner-name '$RunnerName' --url '$Url'"

Write-Host ">>> Provisioning runner '$RunnerName' on $RunnerHost ..."
& ssh @sshArgs $remote
if ($LASTEXITCODE -ne 0) { throw "Remote bootstrap failed (exit $LASTEXITCODE)." }

Write-Host ">>> Runner '$RunnerName' provisioned. Check $Url/settings/actions/runners"
