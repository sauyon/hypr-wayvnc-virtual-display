# hypr-wayvnc-virtual-display

> [!WARNING]
> The code in this repository was written by Claude (an LLM) and has not been
> reviewed line-by-line by the author. It works for the author's setup but
> should be treated as unreviewed code: read it before running, and don't
> expect production-grade guarantees.

An on-demand headless output for [Hyprland](https://hypr.land), lifecycled by
[wayvnc](https://github.com/any1/wayvnc) client connect/disconnect events. The
output exists only while at least one VNC client is connected; the rest of the
time Hyprland is exactly as it was, with no virtual monitor and no ghost
workspace.

## Problem

Running wayvnc against a Hyprland session has two compounding failure modes:

1. **wayvnc dies when its physical output disappears.** If wayvnc is capturing
   the only connected output and that output is unplugged (laptop closed, KVM
   switched away, HDMI yanked), wayvnc has nothing to fall back to and exits.

2. **A persistent headless output creates an unreachable ghost workspace.**
   The usual workaround for (1) is to create a permanent headless output via
   `hyprctl output create headless` and capture that. But Hyprland treats it
   as a real monitor: it gets its own workspace, and that workspace is
   unreachable unless you mirror a physical output onto it — and *that*
   doesn't work either with wayvnc 0.11+, which filters mirrored outputs out
   of its capture list.

## Solution

One small daemon — **`wayvnc-on-demand`** — subscribes to wayvnc's IPC
(`wayvncctl event-receive`) and:

- On first `client-connected` (`connection_count == 1`): runs
  `hyprctl output create headless`, sets its mode, then
  `wayvncctl attach $WAYLAND_DISPLAY` + `wayvncctl output-set <name>` to
  pin wayvnc's capture target.
- On last `client-disconnected` (`connection_count == 0`): disables the
  output via `hyprctl keyword monitor "<name>, disable"`.
- On `output-added` for the headless name during an active session: re-pins
  wayvnc (covers monitor hotplug, mirror toggles).
- On `detached` during an active session: re-attaches and re-pins.
- On service stop or process death: tears the output down via an
  `EXIT`/`INT`/`TERM` trap.

You bring your own `wayvnc.service`. Two requirements:

- wayvnc started with `--detached` — the daemon attaches/detaches around
  client lifecycle, so wayvnc must be willing to run unattached.
- wayvnc ≥ 0.11 (master, ahead of v0.10.0 by 2026-06). The earlier 0.9.x
  series has a use-after-destroy on the `ext_image_copy_capture_frame_v1`
  path that triggers a SIGABRT every time the captured `wl_output` is
  destroyed; v0.10.0 fixes the worst of it, but the explicit
  deferred-detach + cancel-on-readd that makes this design *clean*
  (commits `dba849620`, `86688dc17`, `3bcf77d10`) is master-only.

## Implementation notes

- **Fresh output every cycle.** wayvnc caches `wl_output` proxies by
  registry id, and Hyprland reuses HEADLESS-N names when you disable then
  re-enable an output. The combination gives wayvnc a stale proxy with the
  old capabilities, so `output-set` fails with "No such output". The daemon
  always creates a new HEADLESS-N rather than reusing a disabled one.
  Hyprland's name counter increments forever, but disabled entries don't
  consume workspaces or framebuffers.
- **No mirror.** wayvnc 0.11 filters mirrored outputs out of its capture
  list, so a mirrored HEADLESS is permanently invisible to wayvnc. The
  on-demand lifecycle already solves the ghost-workspace problem that
  mirroring was meant to address.
- **Short attach retry budget.** The attach + output-set loop in this
  script is intentionally bounded to ~2.5 seconds. The retry runs from the
  event loop, and a long blocking retry buries the next event (especially
  `client-disconnected`, which the tear_down depends on).

## Requirements

- wayvnc master (≥ v0.10.0 minimum, but the on-demand lifecycle assumes the
  master-only deferred-detach commits).
- Hyprland v0.36+ (`hyprctl output create headless`, `hyprctl keyword monitor
  "<name>, disable"`, `monitor=NAME,...,mirror,SRC` rules). `hyprctl output
  remove` is broken in Hyprland through 0.55.2 — always reports "output not
  found" — so the daemon uses `monitor=<name>, disable` instead, which is why
  disabled HEADLESS entries accumulate in the monitor list across cycles.
- `bash`, `jq`
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
            # Optional: change the headless mode (default 1920x1080@60)
            # headless.mode = "2560x1440@60";
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
systemctl --user enable --now wayvnc-on-demand.service
```

Or with `PREFIX=/usr/local` and `sudo make install` for a system-wide install.

## Configure

For the Makefile install, configuration lives at
`$XDG_CONFIG_HOME/hypr-wayvnc-virtual-display/config` and is sourced by the
systemd unit via `EnvironmentFile=`.

| Variable        | Default          | Description                                            |
|-----------------|------------------|--------------------------------------------------------|
| `HEADLESS_MODE` | `1920x1080@60`   | Mode for the headless output.                          |

For the home-manager module:

```nix
services.hypr-wayvnc-virtual-display = {
  enable = true;
  headless.mode = "1920x1080@60";
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

- `--detached` is required. The daemon attaches wayvnc to Wayland only while
  a client is connected, so wayvnc must be willing to run unattached.
- Order `wayvnc-on-demand.service` *after* `wayvnc.service` (the shipped unit
  already does this).

## License

MIT. See [LICENSE](./LICENSE).
