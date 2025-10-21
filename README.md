# Multi-OS Dotfiles with Chezmoi

A comprehensive dotfiles management solution using [chezmoi](https://www.chezmoi.io/) that supports multiple operating systems including Ubuntu, Arch Linux, NixOS, and macOS.

## 🌟 Features

- **Multi-OS Support**: Automatically detects and configures for Ubuntu, Arch Linux, NixOS, and macOS
- **OS-Aware Templates**: Different configurations and package installations based on the target OS
- **Automated Package Installation**: Installs essential packages using the appropriate package manager
- **Modern Configurations**: Includes configurations for:
  - Shell environments (Bash, Zsh with Oh My Zsh support)
  - Git with OS-specific settings
  - Tmux with modern keybindings and themes
  - Neovim with sensible defaults
- **Work Environment Support**: Optional work-specific configurations
- **Template-Based**: Uses Go templates for dynamic configuration generation

## 📋 Supported Operating Systems

| OS | Detection ID | Package Manager | Status |
|----|--------------|-----------------|--------|
| Ubuntu | `linux-ubuntu` | `apt` | ✅ Fully Supported |
| Arch Linux | `linux-arch` | `pacman` | ✅ Fully Supported |
| NixOS | `linux-nixos` | `nix` | ✅ Supported (declarative) |
| macOS | `darwin` | `brew` | ✅ Fully Supported |

## 🚀 Quick Start

### Prerequisites

1. Install chezmoi:
   ```bash
   # On Ubuntu/Debian
   sudo apt install chezmoi
   
   # On Arch Linux
   sudo pacman -S chezmoi
   
   # On macOS
   brew install chezmoi
   
   # On NixOS, add to configuration.nix:
   environment.systemPackages = with pkgs; [ chezmoi ];
   ```

### Installation

1. Initialize chezmoi with this repository:
   ```bash
   chezmoi init --apply https://github.com/yourusername/dotfiles.git
   ```

2. Or clone and initialize manually:
   ```bash
   git clone https://github.com/yourusername/dotfiles.git ~/.local/share/chezmoi
   chezmoi init
   chezmoi apply
   ```

### First-Time Setup

1. Configure your personal information:
   ```bash
   chezmoi data
   ```
   
   You'll be prompted for:
   - `name`: Your full name for git configuration
   - `email`: Your email address for git configuration
   - `work`: Whether this is a work environment (true/false)

2. Apply the configuration:
   ```bash
   chezmoi apply
   ```

## 📁 Repository Structure

```
chezmoi-dotfiles/
├── home/
│   ├── .config/
│   │   ├── chezmoi/
│   │   │   └── chezmoi.toml.tmpl      # OS detection and user data
│   │   ├── git/
│   │   │   └── config.tmpl            # Git configuration
│   │   ├── tmux/
│   │   │   └── tmux.conf.tmpl         # Tmux configuration
│   │   └── nvim/
│   │       └── init.lua               # Neovim configuration
│   ├── dot_bashrc.tmpl                # Bash configuration
│   ├── dot_zshrc.tmpl                 # Zsh configuration
│   ├── run_onchange_install-packages.sh.tmpl  # Package installation
│   └── .chezmoiignore                 # Files to ignore per OS
└── README.md                          # This file
```

## 🔧 Configuration

### OS Detection

The system automatically detects your operating system and creates an `osid` variable:
- `linux-ubuntu` for Ubuntu
- `linux-arch` for Arch Linux  
- `linux-nixos` for NixOS
- `darwin` for macOS

### Package Installation

The `run_onchange_install-packages.sh.tmpl` script automatically installs essential packages:

**Ubuntu/Debian:**
```bash
sudo apt-get install -y neovim tmux zsh git curl wget build-essential
```

**Arch Linux:**
```bash
sudo pacman -Syu --noconfirm --needed neovim tmux zsh git curl wget base-devel
```

**macOS:**
```bash
brew install neovim tmux zsh git curl wget
```

**NixOS:**
Packages should be managed through your NixOS configuration or home-manager.

### Customization

#### Personal Information
Edit `~/.config/chezmoi/chezmoi.toml` to set:
```toml
[data]
    name = "Your Name"
    email = "your.email@example.com"
    work = false
```

#### Work Environment
Set `work = true` in your chezmoi configuration to enable work-specific settings:
- Separate git configuration for work repositories
- Work-specific shell configurations
- Additional work-related aliases and functions

#### Local Overrides
Create local configuration files that won't be managed by chezmoi:
- `~/.bashrc.local` - Local bash configuration
- `~/.zshrc.local` - Local zsh configuration
- `~/.zshrc.work` - Work-specific zsh configuration (if work = true)

## 🛠️ Usage

### Daily Operations

```bash
# Update dotfiles from repository
chezmoi update

# See what changes would be applied
chezmoi diff

# Apply changes
chezmoi apply

# Edit a template
chezmoi edit ~/.bashrc

# Add a new file to be managed
chezmoi add ~/.newconfig
```

### Managing Changes

```bash
# Check status
chezmoi status

# See what files are managed
chezmoi managed

# Verify all managed files
chezmoi verify
```

## 🎨 Included Configurations

### Shell (Bash/Zsh)
- Comprehensive aliases for common operations
- Git aliases and shortcuts
- Development-focused environment variables
- OS-specific PATH modifications
- Safety aliases (rm -i, cp -i, mv -i)

### Git
- User configuration from chezmoi data
- OS-specific editor settings
- Useful aliases and shortcuts
- Work-specific configuration support

### Tmux
- Modern key bindings (Ctrl-a prefix)
- Vim-style pane navigation
- Mouse support enabled
- Custom status bar with system information
- OS-specific clipboard integration

### Neovim
- Modern Lua configuration
- Sensible defaults for editing
- Useful key mappings
- Automatic directory creation
- Filetype-specific settings

## 🔍 Troubleshooting

### Common Issues

1. **Package installation fails**:
   - Ensure you have sudo privileges
   - Check if package manager is available
   - For NixOS, manage packages through configuration.nix

2. **Templates not rendering correctly**:
   - Check chezmoi data: `chezmoi data`
   - Verify OS detection: `chezmoi execute-template '{{ .data.osid }}'`

3. **Files not being applied**:
   - Check .chezmoiignore for exclusions
   - Verify file permissions
   - Use `chezmoi apply -v` for verbose output

### Getting Help

```bash
# Show chezmoi help
chezmoi help

# Show template data
chezmoi data

# Execute a template to test
chezmoi execute-template '{{ .data.osid }}'

# Show what would be applied
chezmoi diff
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on multiple operating systems if possible
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [chezmoi](https://www.chezmoi.io/) for the excellent dotfiles management tool
- The open-source community for inspiration and best practices
- Contributors to the various configuration tools and applications