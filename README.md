# omakvn

Native [Omarchy 4](https://omarchy.org/) Quickshell bar plugin for
[kvn-tui](https://github.com/yarikov/kvn-tui).

The widget shows the live VPN state and traffic, lets you connect or switch
profiles, and exposes routing mode, geo region, kill switch, and auto-connect
controls directly from the bar.

![omakvn plugin preview](preview.png)

## Requirements

- Omarchy 4 with Shell plugin support
- `kvn-tui` installed and available on `PATH`
- A `kvn-tui` build that supports semantic IPC commands

## Install

```bash
omarchy plugin add https://github.com/yarikov/omakvn.git --enable
```

The plugin is placed in the right bar section by default. It can also be moved
after installation:

```bash
omarchy bar move kvn.tui --section right
```

Alternatively, `kvn-tui setup --omarchy` installs and enables the plugin along
with the optional launcher keybinding and window rule.

## Usage

- Left click opens the control panel.
- Right click connects the last-used profile or disconnects the active tunnel.
- Middle click opens the full TUI.
- The panel supports `j`/`k`, arrow keys, `g`/`G`, Enter, `h`/`l`, `s`, `r`,
  `a`, `K`, `t`, and Escape.

The plugin communicates with the `kvn-tui` daemon over its user-only Unix
socket. It does not implement VPN protocols or manage the tunnel itself.

## Update

```bash
omarchy plugin update kvn.tui
```

## Remove

```bash
omarchy plugin remove kvn.tui
```

## Development

Validate the repository before publishing changes:

```bash
omarchy plugin validate .
```

For local testing, install the working tree manually under
`~/.config/omarchy/plugins/kvn.tui/`, rescan plugins, and enable it:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable kvn.tui
```

## Credits

The original Omarchy 4 integration was contributed by
[Denis Chupritskiy](mailto:denischupritsky@gmail.com).

## License

[MIT](LICENSE)
