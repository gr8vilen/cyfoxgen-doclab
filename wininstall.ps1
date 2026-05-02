# ============================================================
#  HACKLAB Ultimate One-Shot Installer (Fast Edition)
# ============================================================

try {
    $SCRIPT_URL = "https://raw.githubusercontent.com/gr8vilen/uneo-HACKLAB/main/install.sh"
    $UNAME = "hacklab"
    $UPASS = "hacklab"
    $DISTRO = "Debian"

    Write-Host "" -ForegroundColor Cyan
    Write-Host "  _     _      _____ ____ " -ForegroundColor Green
    Write-Host " / \ /\/ \  /|/  __//  _ \ " -ForegroundColor Green
    Write-Host " | | ||| |\ |||  \  | / \| " -ForegroundColor Green
    Write-Host " | \_/|| | \|||  /_ | \_/| " -ForegroundColor Green
    Write-Host " \____/\_/  \|\____\\____/ " -ForegroundColor Green
    Write-Host "    ULTIMATE HACKLAB ONE-SHOT (FAST) " -ForegroundColor Cyan
    Write-Host " --------------------------------------------------------" -ForegroundColor DarkGray

    # 1. Admin Check
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "  X ERROR: YOU MUST RUN THIS AS ADMINISTRATOR." -ForegroundColor Red
        Read-Host "  Press Enter to exit"
        exit
    }

    # 2. WSL Enable
    Write-Host "[1/3] Checking Windows Features..." -ForegroundColor White
    $wslReady = $false
    try { $null = wsl --status 2>$null; $wslReady = $true } catch { }

    if (-not $wslReady) {
        Write-Host "  ! WSL is not enabled. Enabling now..." -ForegroundColor Yellow
        wsl --install --no-distribution
        Write-Host "  V Done. PC WILL REBOOT IN 10 SECONDS TO FINISH SETUP." -ForegroundColor Green
        for ($i=10; $i -gt 0; $i--) { Write-Host "  Rebooting in $i... " -NoNewline; Start-Sleep 1 }
        Restart-Computer -Force
        exit
    }

    # 3. Linux Auto-Install (Debian is ~100MB)
    Write-Host "[2/3] Checking Linux Environment..." -ForegroundColor White
    $distros = (wsl.exe -l -v | Out-String)
    
    if ($distros -notlike "*$DISTRO*") {
        Write-Host "  ! $DISTRO missing. Installing (Fast ~100MB)..." -ForegroundColor Yellow
        
        $installOutput = (wsl --install -d $DISTRO --no-launch 2>&1 | Out-String)
        Write-Host $installOutput
        
        if ($installOutput -match "Virtual Machine Platform" -or $installOutput -match "HCS_E_HYPERV_NOT_INSTALLED") {
            Write-Host "  X CRITICAL ERROR: Virtualization is not enabled on your PC." -ForegroundColor Red
            Write-Host "  To fix this, you must:" -ForegroundColor Yellow
            Write-Host "  1. Restart your computer and enter your BIOS/UEFI settings." -ForegroundColor White
            Write-Host "  2. Find the setting for 'Virtualization', 'VT-x', 'AMD-V', or 'SVM'." -ForegroundColor White
            Write-Host "  3. Enable it, save, and restart Windows." -ForegroundColor White
            Write-Host "  4. Run this script again." -ForegroundColor White
            Read-Host "  Press Enter to exit"
            exit
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ! $DISTRO failed, trying Ubuntu-22.04 as fallback..." -ForegroundColor DarkYellow
            $DISTRO = "Ubuntu-22.04"
            wsl --install -d $DISTRO --no-launch
        }
        
        Start-Sleep 5
        Write-Host "  . Configuring user '$UNAME'..." -ForegroundColor Gray
        
        # We try useradd syntax for Debian/Ubuntu
        wsl -d $DISTRO -u root bash -c "useradd -m -s /bin/bash $UNAME && echo '${UNAME}:${UPASS}' | chpasswd && usermod -aG sudo $UNAME"
        
        # Set this user as default
        wsl -d $DISTRO -u root bash -c "echo -e '[user]\ndefault=$UNAME' > /etc/wsl.conf"
        wsl --terminate $DISTRO
        Write-Host "  V $DISTRO ready." -ForegroundColor Green
    }

    # 4. Launch HACKLAB
    Write-Host "[3/3] Launching HACKLAB..." -ForegroundColor White
    wsl -d $DISTRO -u $UNAME bash -c "curl -fsSL $SCRIPT_URL | bash"

} catch {
    Write-Host ""
    Write-Host "  X CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "  Press Enter to close"
}
