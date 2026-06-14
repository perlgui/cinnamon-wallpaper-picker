# Wallpaper Picker

A lightweight, keyboard-friendly wallpaper browser for Linux Mint Cinnamon desktop. It presents all images from your Pictures folder as a full-width thumbnail strip that slides in over the centre of the screen, letting you browse and apply wallpapers without opening a file manager or diving into system settings.



<img width="3840" height="2160" alt="1" src="https://github.com/user-attachments/assets/e1939883-f112-4e5c-9cad-06b597111d6e" />


---

## Features

- Full width thumbnail strip floats over the middle of the screen, stays on top of all windows
- Smooth scrolling with trackpad inertia, mouse wheel coasting, and animated settle-to-centre snap
- Keyboard navigation enables arrow keys to move, Enter to apply, Escape to close
- Click to select, double click to apply. Click an unselected thumbnail to move to it; click the already-selected one to set it as wallpaper
- Thumbnails are generated once and stored on disk; subsequent launches are instant
- Reads the GDK scale factor and renders at the correct physical resolution

---

## Requirements

- Linux Mint with the Cinnamon desktop (uses `gsettings org.cinnamon.desktop.background`)
- Perl 5.10 or later
- GTK3 Perl bindings
- The following Perl modules (installed automatically by `install.sh`):
  - `Moo` (via CPAN)
  - `Gtk3`
  - `Glib`
  - `Digest::SHA`
  - `File::Path`, `File::Glob` (Perl core - no separate install needed)

---

## Installation

Clone or download the repository, then run the installer from the project directory:

```bash
git clone https://github.com/perlgui/perl-wallpaper-picker.git
cd perl-wallpaper-picker
chmod +x install.sh
./install.sh
```

The installer will:

1. Install system packages via `apt` (`perl`, `cpanminus`, `libgtk3-perl`, etc.)
2. Install `Moo` from CPAN via `cpanm`
3. Copy `wallpaper-picker.svg` to `~/.local/share/perl-wallpaper-picker/application-icon/`
4. Copy the script to `~/.local/bin/wallpaper-picker` and make it executable
5. Add `~/.local/bin` to your `PATH` in your shell's rc file (`.bashrc`, `.zshrc`, or `config.fish`)
6. Create a `.desktop` entry so the app appears in the Mint application menu under Preferences category
7. Run `update-desktop-database` so the menu picks up the entry immediately


---

## Usage

Create a custom shortcut in Cinnamon System Settings --> Keyboard --> Shortcuts --> Custom Shortcuts --> Add custom shortcut

<img width="1600" height="1288" alt="custom shortcut1" src="https://github.com/user-attachments/assets/c5dafa43-257e-43f0-8b45-827d45656928" />


Or launch it from the terminal:

```bash
wallpaper-picker
```

Or find Wallpaper Picker in the application menu under Preferences


### Controls

| Action | Result |
|---|---|
| `←` / `→` or `↑` / `↓` | Move selection left / right |
| `Enter` or `Numpad Enter` | Apply selected wallpaper |
| `Escape` | Close |
| Mouse wheel / trackpad scroll | Scroll the strip |
| Click a thumbnail | Select it (centres the strip on it) |
| Click the selected thumbnail | Apply it as wallpaper |

---

## Configuration

There are no configuration files. To change defaults, adapt the constructor arguments near the bottom of `wallpaper-picker.pl`:

```perl
my $picker = WallpaperPicker->new(
    pictures_dir     => "$ENV{HOME}/Pictures",  # directory to scan for images
    thumb_height     => 300,                    # thumbnail height in px
    thumb_width      => 480,                    # thumbnail width in px
    fade_steps       => 20,                     # frames in the fade transition
    fade_interval_ms => 30,                     # ms between fade frames (~33 fps)
);
```

Adjust any line you want to change, then save the file. No reinstall is needed, the script runs directly from `~/.local/bin`.

The thumbnail cache lives at:

```
~/.local/share/perl-wallpaper-picker/thumbnails/
```

Delete this directory to force all thumbnails to regenerate (useful after changing `thumb_width` or `thumb_height`).

---

## Uninstall

```bash
rm ~/.local/bin/wallpaper-picker
rm ~/.local/share/applications/wallpaper-picker.desktop
rm -rf ~/.local/share/perl-wallpaper-picker/
update-desktop-database ~/.local/share/applications
```

Remove the `PATH` line added to your shell rc file if you no longer need `~/.local/bin` on your path.

---

## License

MIT
