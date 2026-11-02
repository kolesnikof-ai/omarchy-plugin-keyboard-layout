# Keyboard layout

[Русский](README.ru.md)

Bar widget for the Omarchy shell. It shows the active XKB layout as a flag or a short language code. A click switches to the next layout.

![Keyboard layout shown as a circular flag on the Omarchy bar](preview.png)

This is a replacement for the built-in `omarchy.keyboard-layout` widget. Sergey Kolesnikov, based on Omarchy.

## Install

From a git repository:

```bash
omarchy plugin add <git-url> --enable
```

The plugin id is `kolesnikof.keyboard-layout`. While `omarchy.clonedFrom` is `omarchy.keyboard-layout`, this copy takes the place of the built-in widget.

## Remove

```bash
omarchy plugin remove kolesnikof.keyboard-layout
```

Removing this clone restores the built-in keyboard layout widget.

## Use

The widget appears when Hyprland has two or more layouts. A single-layout setup stays hidden. If Hyprland does not report the layout list, the label stays visible.

A click advances the keyboard the label is describing. The tooltip is the full layout name, such as `English (US)`.

Flag mode uses the XKB layout id (`us`, `ru`, `gb`). A layout with no flag file, a failed image, or a vertical bar falls back to the short language code. Those codes come from `xkbcli list` (`EN`, `RU`). A code is at most three characters.

## Settings

Put the values on this widget's entry in `~/.config/omarchy/shell.json`, inside the bar layout:

```json
{
  "id": "kolesnikof.keyboard-layout",
  "layoutDisplay": "flag",
  "flagShape": "circle",
  "horizontalMargin": [6, 6],
  "fontSize": "title"
}
```

| Key | Default | Values |
|-----|---------|--------|
| `layoutDisplay` | `flag` | `flag` draws the flag. `text` keeps the language code. |
| `flagShape` | `circle` | `circle`, `rounded`, or `rect`. Any other value is a plain rectangle. |
| `fontSize` | `title` | `caption`, `body-small`, `body`, `subtitle`, `title`, `heading`, `display`, `display-large`. The size follows the shell font scale. The flag matches that size. |
| `horizontalMargin` | `[6, 6]` | One number pads both sides. Two numbers set the left and right insets. The numbers are pixels, scaled with the shell spacing scale. |

## Dependencies

Omarchy already provides both:

- Hyprland, for `hyprctl`
- libxkbcommon, for `xkbcli`

The widget does not download anything.

## Flag artwork

- Rectangular flags in `flags/rect` are from [flag-icons](https://github.com/lipis/flag-icons), MIT, Copyright (c) 2013 Panayiotis Lipiridis.
- Circular flags in `flags/circle` are from [circle-flags](https://github.com/HatScripts/circle-flags), MIT, Copyright (c) 2026 HatScripts.

The full notices are in `flags/LICENSE`.
