# NVIDIA Driver Installer TUI

A beautiful terminal user interface for installing NVIDIA proprietary drivers on Linux systems.

## Features

### Core Functionality
- Automatic GPU detection (including legacy Kepler GPUs for 470xx drivers)
- Secure Boot detection with detailed MOK enrollment guidance
- LUKS encryption detection with automatic initramfs/dracut configuration
- Idempotent - detects existing installations and skips unless forced
- Non-interactive auto mode for scripting and automation
- Support for both RPM and DEB-based distributions

### User Interface
- Beautiful TUI with Unicode box-drawing characters (╭╮╰╯│─)
- Color-coded status messages:
  - Green (✓) for success
  - Yellow (⚠) for warnings
  - Red (✗) for errors
  - Cyan (●) for in-progress operations
- Green highlighted selection in Yes/No dialogs for clear visual feedback
- Centered dialog text and navigation hints
- Context-aware prompts ("Press any key to exit..." when exiting, "Press any key..." otherwise)
- Vim-style keyboard navigation (h/j/k/l) in addition to arrow keys
- Dynamic box sizing based on content (adjusts for Secure Boot/LUKS information)

## Supported Systems

### RPM-based (DNF)
- Fedora
- RHEL / CentOS / Rocky Linux / AlmaLinux

### DEB-based (APT)
- Ubuntu
- Kubuntu / Xubuntu / Lubuntu
- Linux Mint
- Pop!_OS

## Requirements

- Root privileges (sudo)
- NVIDIA GPU
- Internet connection (for package downloads)

## System Detection

The installer automatically detects and handles:

| Detection | Method | Action |
|-----------|--------|--------|
| **Distribution** | `/etc/os-release` | Selects DNF or APT package manager |
| **NVIDIA GPU** | `lspci` | Identifies GPU model, detects legacy Kepler GPUs |
| **Existing drivers** | `nvidia-smi`, `modinfo`, package manager | Offers reinstall option or skips |
| **Secure Boot** | `mokutil --sb-state` | Shows detailed MOK enrollment instructions |
| **LUKS encryption** | `lsblk -f` | Configures initramfs with NVIDIA modules |

## Installation

```bash
git clone <repository-url>
cd nvidiaInstaller
chmod +x nvidia-installer.sh
```

## Usage

### Interactive Mode (TUI)

Run the installer with the full terminal user interface:

```bash
sudo ./nvidia-installer.sh
```

This will guide you through:
1. System detection (distro, GPU, Secure Boot, LUKS)
2. Driver already installed check (if applicable)
3. Secure Boot warning (if enabled)
4. Installation confirmation
5. Package installation
6. Reboot prompt

### Automatic Mode

Run the installer non-interactively, accepting all defaults:

```bash
sudo ./nvidia-installer.sh -y
```

In auto mode:
- Clean console output instead of TUI (suitable for scripts and logs)
- If drivers are already installed, installation is **skipped** (displays message with current version)
- Use `--force` to reinstall even when drivers exist
- If Secure Boot is enabled, a warning is displayed but installation proceeds
- After installation, system reboots automatically after 5 seconds (use `--no-reboot` to skip)

**Auto mode output example:**
```
NVIDIA Driver Installer - Automatic Mode

● Checking system...
✓ Running as root
✓ Distribution: Fedora 41
✓ GPU: NVIDIA GeForce RTX 3080
✓ Secure Boot: Disabled
✓ No LUKS encryption

Installing:
  ● RPM Fusion repositories (if needed)
  ● akmod-nvidia (latest driver)
  ● xorg-x11-drv-nvidia-cuda

● Starting installation...
✓ RPM Fusion Free already enabled
✓ RPM Fusion Non-Free already enabled
✓ NVIDIA drivers installed

✓ Installation completed successfully!
```

### Command-Line Options

| Option | Description |
|--------|-------------|
| `-y`, `--auto`, `--yes` | Run in automatic mode, accepting all defaults |
| `-f`, `--force` | Force reinstall even if drivers are already installed |
| `--no-reboot` | Do not reboot after installation |
| `-h`, `--help` | Show help message and exit |

### Examples

```bash
# Interactive TUI mode
sudo ./nvidia-installer.sh

# Automatic installation (skips if already installed)
sudo ./nvidia-installer.sh -y

# Force reinstall automatically
sudo ./nvidia-installer.sh -y -f

# Auto install without rebooting
sudo ./nvidia-installer.sh -y --no-reboot

# Force reinstall without reboot (useful for scripting)
sudo ./nvidia-installer.sh -y -f --no-reboot

# Show help
./nvidia-installer.sh --help
```

## What Gets Installed

### Fedora / RPM-based Systems

1. **RPM Fusion repositories** (Free and Non-Free) - if not already enabled
2. **Driver packages:**
   - Modern GPUs (Maxwell 2014+ / GTX 900+): `akmod-nvidia`, `xorg-x11-drv-nvidia-cuda`
   - Legacy GPUs (Kepler / GTX 600-700): `akmod-nvidia-470xx`, `xorg-x11-drv-nvidia-470xx-cuda`
3. **Dracut configuration** - if LUKS encryption is detected

### Ubuntu / DEB-based Systems

1. `ubuntu-drivers-common`
2. Recommended NVIDIA driver (auto-detected, fallback to `nvidia-driver-535`)
3. **initramfs update** - if LUKS encryption is detected

## Post-Installation

After installation completes:

1. **Reboot** your system
2. **Verify** the installation:
   ```bash
   nvidia-smi
   ```

## Secure Boot Handling

If Secure Boot is enabled, the NVIDIA kernel module must be signed and enrolled in your system's MOK (Machine Owner Key) database.

### What the installer does:
- Detects Secure Boot status via `mokutil --sb-state`
- Displays a detailed warning explaining the MOK enrollment process
- Proceeds with installation (the driver packages handle key generation)

### What you must do manually after reboot:

1. **A blue "MOK Management" screen will appear** - this is normal
2. Select **"Enroll MOK"**
3. Select **"Continue"**
4. Select **"Yes"** to enroll the key
5. **Enter the password** you created during installation
6. Select **"Reboot"**

> **⚠️ WARNING:** If you skip this step, select "Continue boot", or enter the wrong password, the NVIDIA driver will **NOT** load. Your system will fall back to the nouveau driver and you won't have GPU acceleration.

### If you missed MOK enrollment:

```bash
# Re-import the MOK key
sudo mokutil --import /var/lib/dkms/mok.pub

# You'll be prompted to create a password
# Then reboot and complete enrollment
sudo reboot
```

### Verifying MOK enrollment:

```bash
# Check if NVIDIA module is loaded
lsmod | grep nvidia

# If empty, check Secure Boot status
mokutil --sb-state

# List enrolled keys
mokutil --list-enrolled
```

## LUKS Encryption Handling

If your system uses LUKS disk encryption, the NVIDIA driver modules need to be included in the initramfs for proper early-boot graphics support.

### What the installer does automatically:

**On Fedora/RPM systems:**
- Creates `/etc/dracut.conf.d/nvidia.conf` with:
  ```
  add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
  ```
- Regenerates initramfs with `dracut --force`

**On Ubuntu/DEB systems:**
- Updates initramfs with `update-initramfs -u`

### Why this matters:

Without NVIDIA modules in the initramfs, you may experience:
- Black screen or low resolution during LUKS password prompt
- Graphics issues during early boot
- Plymouth (boot splash) problems

### Manual verification:

```bash
# Fedora - check dracut config
cat /etc/dracut.conf.d/nvidia.conf

# Fedora - list modules in initramfs
lsinitrd | grep nvidia

# Ubuntu - check initramfs
lsinitramfs /boot/initrd.img-$(uname -r) | grep nvidia
```

## Idempotent Behavior

The installer checks for existing NVIDIA driver installations before proceeding:

- **Interactive mode**: Displays current installation details and asks if you want to reinstall (default: No)
- **Auto mode (`-y`)**: Skips installation and exits cleanly with a message
- **Force mode (`-y -f`)**: Proceeds with reinstallation regardless of existing installation

Example output when drivers are already installed (auto mode):
```
✓ NVIDIA drivers already installed (Package: akmod-nvidia, Version: 560.35.03)
ℹ Use --force to reinstall
ℹ [No Changes] Existing installation kept
```

## Keyboard Navigation (Interactive Mode)

The TUI supports both arrow keys and Vim-style navigation:

| Key | Action |
|-----|--------|
| `↑` / `k` | Move selection up |
| `↓` / `j` | Move selection down |
| `←` / `h` | Toggle Yes/No selection left |
| `→` / `l` | Toggle Yes/No selection right |
| `Enter` | Confirm selection |
| `q` | Quit (in menus) |
| Any key | Continue (on info screens) |

### Dialog Highlights

- **Selected option** is shown in **green and bold**
- **Unselected option** is shown in dim/gray
- Navigation hints are centered below the options

## Troubleshooting

### Driver not loading after reboot

**Check if the module exists but isn't loaded:**
```bash
modinfo nvidia          # Should show module info
lsmod | grep nvidia     # Should show nvidia modules
```

**If Secure Boot is the issue:**
```bash
# Check Secure Boot status
mokutil --sb-state

# If enabled and driver not loading, re-enroll MOK:
sudo mokutil --import /var/lib/dkms/mok.pub
sudo reboot
# Complete MOK enrollment at boot
```

### Black screen after installation

1. Boot into recovery mode or TTY (Ctrl+Alt+F2)
2. Check if nouveau is conflicting:
   ```bash
   lsmod | grep nouveau
   ```
3. If nouveau is loaded, blacklist it:
   ```bash
   echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
   sudo dracut --force  # Fedora
   sudo update-initramfs -u  # Ubuntu
   sudo reboot
   ```

### LUKS password prompt has no graphics

Regenerate initramfs with NVIDIA modules:
```bash
# Fedora
echo 'add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee /etc/dracut.conf.d/nvidia.conf
sudo dracut --force

# Ubuntu
sudo update-initramfs -u
```

### Check installation status

```bash
# Fedora - check installed packages
rpm -qa | grep nvidia

# Ubuntu - check installed packages
dpkg -l | grep nvidia

# Check driver version
nvidia-smi

# Check module version
modinfo -F version nvidia
```

### Reinstall drivers

```bash
sudo ./nvidia-installer.sh -y -f
```

### Complete removal (if needed)

```bash
# Fedora
sudo dnf remove '*nvidia*'
sudo rm -f /etc/dracut.conf.d/nvidia.conf
sudo dracut --force

# Ubuntu
sudo apt purge '*nvidia*'
sudo update-initramfs -u
```

## License

GNU General Public License v3.0
