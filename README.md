# fastfetch-config

A terminal tool that manages your [fastfetch](https://github.com/fastfetch-cli/fastfetch) config, so you don't have to hand-edit JSON for the 500th time. It installs an `ff` command you can run from anywhere.

Point it at a logo (built-in or your own image), set the OS name, mess with colors and modules, and it keeps backups so you can undo the damage. There's also a TUI if typing is too much work.

## What it can do

- Set the logo to a built-in ASCII art, a custom text file, or an image.
- Render images with chafa, or with the Kitty graphics protocol if you're in Kitty. In auto mode it picks whichever one fits.
- Resize the logo to your terminal on every run, so nothing wraps.
- Rename the OS field to whatever you want ("Windows 95", "TempleOS", your own name).
- Add, remove, reorder, and tweak modules.
- Recolor the logo by slot, with 150+ named colors (plus hex and ANSI codes).
- Back up, diff, export, import, and reset the config.
- Browse fastfetch's built-in logos in a gallery and apply one.
- A TUI menu for all of the above.

## Support (or lack of it)

Works best on Arch Linux and Arch-based distros (CachyOS, EndeavourOS, and friends), but should work anywhere bash, jq, and fastfetch do. On NixOS you need to install the dependencies yourself. (Can confirm, I, aaronYTDev, use NixOS.) There's experimental macOS support that might be rough around the edges.

## Requirements

- bash
- fastfetch
- jq
- for image logos: chafa and, if you want the installer to convert images, ImageMagick

The installer tries to grab whatever's missing with your package manager. If it can't tell what distro you're on, it tells you what to install by hand.

## Install

Stable:
```
curl -fsSL https://raw.githubusercontent.com/AaronYTDev/fastfetch-config/main/install-ff.sh | bash
```

Testing (newest code, might be broken):
```
curl -fsSL https://raw.githubusercontent.com/AaronYTDev/fastfetch-config/main/install-ff-testing.sh | bash
```

The installer drops two things in `~/.local/bin`: `fastfetch-config` and a tiny `ff` wrapper. It writes a default config to `~/.config/fastfetch/config.jsonc`, puts some ASCII logos in `~/.config/fastfetch/logos`, and adds `~/.local/bin` to your PATH in your shell rc.

One warning: if you already have a config, the installer overwrites it. To keep the one you have, pass `-nodelete`:
```
curl -fsSL https://raw.githubusercontent.com/AaronYTDev/fastfetch-config/main/install-ff.sh | bash -s -- -nodelete
```

Open a new shell (or `source ~/.bashrc`) and you're good.

## Usage

Run `ff` on its own and you just get fastfetch. Any arguments you hand it go straight to fastfetch, so `ff --logo none` does what you'd expect.

```
ff tui                 # open the menu and press keys
ff logo arch           # use a built-in logo
ff logo ~/pic.png      # use your own image
ff logo fit            # re-fit the logo to this terminal
ff osname "MyOS 1.0"   # change what the OS line says
ff color 1 cyan        # recolor a logo slot
ff module add memory   # add a module
ff backup              # save the current config
ff restore <name>      # go back to a backup
ff gallery             # browse built-in logos
```

`ff help` prints the whole list. A few handy ones:

- `ff status` / `ff stats`: what's going on right now.
- `ff doctor`: check for missing pieces.
- `ff diff [backup]`: see what changed since a backup.
- `ff update`: get the latest stable. `ff update testing` switches to testing, and `ff update check` just looks without installing.

## Where things live

- Config: `~/.config/fastfetch/config.jsonc` (honors `$XDG_CONFIG_HOME`)
- Your logos: `~/.config/fastfetch/logos`
- Backups: `~/.config/fastfetch/backups`
- Commands: `~/.local/bin/fastfetch-config` and `~/.local/bin/ff`

## Uninstall

```
rm -f ~/.local/bin/fastfetch-config ~/.local/bin/ff
rm -rf ~/.config/fastfetch
```

Then delete the `# Added by fastfetch-config installer` line (and the PATH export under it) from your shell rc.

## Notes

We are kids. We are just kids coding this for fun. Don't expect things to work 100%, and don't expect a schedule for releases.

## Credits

This tool was made by 2 people. aaronYTDev & Madrinth. Without one of us we wouldn't have a stable release today.

## License

GPL-3.0. See [LICENSE](LICENSE).

## Everything else

Wiki [here](https://ff-iwiki.netlify.app)
