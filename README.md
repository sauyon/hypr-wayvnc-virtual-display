# hypr-wayvnc-virtual-display

A persistent headless output for [Hyprland](https://hypr.land) plus a small
sidecar that keeps [wayvnc](https://github.com/any1/wayvnc) attached to it
across monitor hotplug events.

## Problem

Running wayvnc against a Hyprland session has two failure modes that compound:

1. **wayvnc dies when its physical output disappears.** If wayvnc is capturing
   the only connected output and that output is unplugged (laptop closed, KVM
   switched away, HDMI yanked), wayvnc has nothing to fall back to and exits.

2. **Hyprland destroys and recreates a monitor's `wl_output` global on every
   mirror-mode transition.** wayvnc tracks outputs by Wayland registry id, so
   any monitor hotplug that flips a mirror state silently moves wayvnc to a
   "fallback" output — usually the wrong one — or detaches it entirely.

The first issue is normally worked around by creating a persistent headless
output via `hyprctl output create headless` and capturing that. The second
issue is the one nobody else has addressed: even with the headless output
present, Hyprland's mirror lifecycle keeps yanking wayvnc off it.

## Solution

Two small pieces:

- **`wayvnc-headless`** — a oneshot that creates a Hyprland headless output
  (defaulting to `HEADLESS-1`), sets its mode, and optionally configures it as
  a mirror of a physical output so an attached display drives the framebuffer.

- **`wayvnc-output-pin`** — a long-running sidecar that subscribes to
  Hyprland's `socket2` IPC, and on every `monitoraddedv2` / `monitorremovedv2`
  event re-issues `wayvncctl attach $WAYLAND_DISPLAY` followed by
  `wayvncctl output-set $HEADLESS_NAME`. This forces wayvnc back onto the
  intended output after every mirror-mode transition.

You bring your own `wayvnc.service`. The only requirement is that wayvnc is
started with `--detached` so it survives transient output loss instead of
exiting.

## Requirements

- Hyprland (any version supporting `hyprctl output create headless`, mirror
  rules, and the `monitoraddedv2` / `monitorremovedv2` events on `socket2` —
  v0.36+)
- wayvnc 0.9+
- `bash`, `jq`, `socat`
- systemd user instance

## Install

### Nix flake (home-manager)

```nix
{
  inputs.hypr-wayvnc-virtual-display.url = "github:sauyon/hypr-wayvnc-virtual-display";

  outputs = { self, nixpkgs, home-manager, hypr-wayvnc-virtual-display, ... }: {
    homeConfigurations.you = home-manager.lib.homeManagerConfiguration {
      modules = [
        hypr-wayvnc-virtual-display.homeManagerModules.default
        {
          services.hypr-wayvnc-virtual-display = {
            enable = true;
            headless.mirrorOutput = "DP-5";  # or "HDMI-A-1", or omit entirely
          };
        }
      ];
    };
  };
}
```

### Plain make

```sh
make install PREFIX=$HOME/.local
mkdir -p $HOME/.config/hypr-wayvnc-virtual-display
cp examples/config $HOME/.config/hypr-wayvnc-virtual-display/config
# edit the config to taste, then:
systemctl --user daemon-reload
systemctl --user enable --now wayvnc-headless.service wayvnc-output-pin.service
```

Or with `PREFIX=/usr/local` and `sudo make install` for a system-wide install.

## Configure

For the Makefile install, configuration lives at
`$XDG_CONFIG_HOME/hypr-wayvnc-virtual-display/config` and is sourced by the
systemd units via `EnvironmentFile=`.

| Variable        | Default          | Description                                            |
|-----------------|------------------|--------------------------------------------------------|
| `HEADLESS_NAME` | `HEADLESS-1`     | Hyprland output name to create and pin wayvnc to.      |
| `HEADLESS_MODE` | `1920x1080@60`   | Mode for the headless output.                          |
| `MIRROR_OUTPUT` | (unset)          | Physical output to mirror, e.g. `DP-5`, `HDMI-A-1`.    |

For the home-manager module, the same surface is exposed as:

```nix
services.hypr-wayvnc-virtual-display = {
  enable = true;
  headless = {
    name = "HEADLESS-1";
    mode = "1920x1080@60";
    mirrorOutput = "DP-5";   # null to leave standalone
  };
};
```

## Your wayvnc.service

The flake does not own `wayvnc.service` because the binding address, LAN
forwarding, and authentication are personal choices. A minimal example:

```ini
[Unit]
Description=WayVNC server
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/bin/wayvnc --detached 127.0.0.1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
```

Key points:

- `--detached` is required. Without it, wayvnc exits the moment its target
  output disappears and `wayvnc-output-pin` has nothing to talk to.
- Order `wayvnc-output-pin.service` *after* `wayvnc.service` (the shipped unit
  does this already).

## How it survives a mirror transition

When a physical output (say `HDMI-A-1`) connects while `HEADLESS-1` is set to
mirror it:

1. Hyprland removes `HEADLESS-1`'s `wl_output` global, then adds a fresh one.
2. wayvnc sees its tracked output disappear, tries `switch_to_prev_output`,
   and lands on whichever output it sees first — typically not the one you
   want.
3. Hyprland emits `monitoraddedv2>>...,HDMI-A-1,...` on `socket2`.
4. `wayvnc-output-pin` reads the event, sleeps 300ms to let Hyprland settle,
   and runs `wayvncctl output-set HEADLESS-1`.
5. wayvnc snaps back to `HEADLESS-1`, which is now the mirror view of the
   newly-connected physical output, so VNC clients keep seeing whatever the
   physical display shows.

Disconnect events follow the same path in reverse.

## License

MIT. See [LICENSE](./LICENSE).
