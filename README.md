# kvn-tui VPN for Omarchy

**VPN in your Omarchy bar. Full control in your terminal.**

`omakvn` is the native [Omarchy 4](https://omarchy.org/) bar integration for
[`kvn-tui`](https://github.com/yarikov/kvn-tui), a keyboard-driven VPN client
for Arch Linux built on top of [sing-box](https://sing-box.sagernet.org/).

Use the bar for everyday VPN controls, and open the full TUI when you need
advanced configuration.

![omakvn plugin preview](preview.png)

## What you can do from the Omarchy bar

- Connect, disconnect, and reconnect the VPN
- Switch VPN profiles
- Change routing mode
- Switch geo region
- Monitor connection state, live traffic rates, totals, and active connections
- Toggle the kill switch
- Control auto-connect
- Open the full `kvn-tui` interface

## What is kvn-tui?

`kvn-tui` is the main VPN application behind this plugin. It runs a background
daemon that manages the VPN connection and exposes its state to both the
terminal UI and the Omarchy bar integration. That means you can close the TUI
and keep the VPN running.

Use the full `kvn-tui` interface for tasks such as:

- Adding and managing VPN profiles
- Importing share links and subscriptions
- Advanced routing configuration
- DNS configuration
- Latency testing
- Connection monitoring
- Logs and diagnostics

## How it works

```text
                kvn-tui daemon
                      │
              manages sing-box
                      │
          ┌───────────┴───────────┐
          │                       │
      kvn-tui TUI             omakvn
    full configuration      Omarchy bar controls
```

Both interfaces talk to the same `kvn-tui` daemon over its user-only Unix
socket. `omakvn` does not implement VPN protocols or manage the tunnel
independently—it provides native Omarchy controls for the existing `kvn-tui`
service.

## Installation

Install [`kvn-tui`](https://github.com/yarikov/kvn-tui#installation-arch-linux)
first. The recommended setup for Omarchy is:

```bash
kvn-tui setup --omarchy
```

On supported Omarchy versions, this installs and enables the native bar widget
and configures the optional launcher keybinding and floating-window rule. Run
the command as your regular user, without `sudo`.

Alternatively, install and enable `omakvn` directly from its repository:

```bash
omarchy plugin add https://github.com/yarikov/omakvn.git --enable
```

This installs only the bar widget; `kvn-tui` must already be installed and
available on `PATH`.

## First connection

If you do not have any VPN profiles yet:

1. Open `kvn-tui`.
2. Press `p` to open profile management.
3. Add a VPN share link or subscription.
4. Connect to the profile.
5. Use the Omarchy bar for quick controls afterward.

## Usage

- Left click opens the control panel.
- Right click connects the last-used profile or disconnects the active tunnel.
- Middle click opens the full TUI.

| Key | Action |
|---|---|
| `j` / `k`, up/down | Move between controls |
| `gg` / `G` | Jump to the first or last control |
| `Enter` / `Space` | Activate the selected control |
| `h` / `l`, left/right | Change the selected routing mode or region |
| `s` | Disconnect |
| `r` | Reconnect |
| `a` | Toggle auto-connect |
| `K` | Toggle the kill switch |
| `t` | Open the full TUI |
| `Tab` / `Shift+Tab` | Switch between bar panels |
| `Escape` | Close the panel |

## Why omakvn?

The goal is not to replicate the entire terminal interface inside a bar widget.

Use the **Omarchy bar** for fast, frequent actions. Use **kvn-tui** for full VPN
configuration and management.

One VPN daemon, two native interfaces.

## Requirements

- Omarchy 4 with Shell plugin support
- [`kvn-tui`](https://github.com/yarikov/kvn-tui#installation-arch-linux)
  0.27.0 or newer, installed and available on `PATH`

`kvn-tui` uses sing-box as its VPN backend and installs it automatically through
the supported installation flow. Quickshell is provided by Omarchy Shell.

## Troubleshooting

Run the built-in read-only diagnostics:

```bash
kvn-tui doctor
```

## Update

```bash
omarchy plugin update yarikov.omakvn
```

## Remove

```bash
omarchy plugin remove yarikov.omakvn
```

## Projects

- Main application: [`yarikov/kvn-tui`](https://github.com/yarikov/kvn-tui)
- Omarchy integration: [`yarikov/omakvn`](https://github.com/yarikov/omakvn)

## Development

Validate the repository before publishing changes:

```bash
omarchy plugin validate .
```

For local testing, install the working tree manually under
`~/.config/omarchy/plugins/yarikov.omakvn/`, rescan plugins, and enable it:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable yarikov.omakvn
```

## Credits

The original Omarchy 4 integration was contributed by
[Denis Chupritskiy](https://github.com/chupre).

## License

[MIT](LICENSE)
