# Profiles

Separate desktops on one Omarchy machine. Each profile has its own theme,
wallpaper, bar layout, plugins, visible applications and block of workspaces —
same files, same user, different desk.

Switching is not "apply a template". The profile you are leaving is **captured
on the way out**, so anything you changed while inside it is still there when
you come back. Change the theme in `work`, switch to `dev`, switch back: `work`
is how you left it.

One profile is the **master**. It sees every application, new profiles are
copied from it, and an application installed anywhere is registered to it.
Other profiles start without it and opt in — the way a second user on a phone
does not automatically get everything the owner installs.

## Why workspaces

Hyprland has no app grouping, so workspaces are the only layer available: five
fullscreen apps means five workspaces. Each profile therefore owns a block of
ten real workspaces — master 1–10, the next profile 11–20, and so on — while
`SUPER+1..0` keeps meaning "this profile's first through tenth". The bar shows
1–10 in every profile; only the workspace ids underneath move.

## Install

```bash
omarchy plugin add https://github.com/Kalinewb/omarchy-profiles.git --enable
```

Then adopt the machine as it stands as your master profile:

```bash
~/.config/omarchy/plugins/graveklar.profiles/bin/omarchy-profile init
```

`init` only reads state — it never imposes any — so it is safe to run on a
desktop you have already set up.

## Use

The bar widget shows the active profile; click it to switch or to open the
manager. Everything it does is also a command:

```bash
omarchy-profile list                  # * is active, (master) is the master
omarchy-profile set work              # captures the outgoing profile first
omarchy-profile create work --clean   # or --from-master
omarchy-profile remove work           # refuses while it still has windows
omarchy-profile capture               # save live state into the active profile now

omarchy-profile apps work allow hey            # which applications it can see
omarchy-profile plugin work disable quickshell.spotify
omarchy-profile ws 3                  # focus this profile's third workspace
```

## Workspace keys

To make `SUPER+1..0` follow the active profile, point them at the engine in
`~/.config/hypr/bindings.lua`:

```lua
local profile = os.getenv("HOME") .. "/.config/omarchy/plugins/graveklar.profiles/bin/omarchy-profile"

for w = 1, 10 do
  local key = "code:" .. tostring(w + 9)
  hl.unbind("SUPER + " .. key)
  o.bind("SUPER + " .. key, "Workspace " .. w, profile .. " ws " .. w)
  hl.unbind("SUPER + SHIFT + " .. key)
  o.bind("SUPER + SHIFT + " .. key, "Move to workspace " .. w, profile .. " move " .. w)
end
```

Without this the keys still work; they just always address workspaces 1–10
rather than the active profile's block.

## Files

| Path | What |
|---|---|
| `~/.config/omarchy/profiles/config.json` | master name, pinned plugins, workspace span |
| `~/.config/omarchy/profiles/<name>.json` | one profile |
| `~/.local/state/omarchy-profiles/current.json` | which profile is active |

## Pinned plugins

A profile may not disable anything listed in `pinned_plugins`. This plugin is
pinned by default: a profile that could switch off its own picker would leave
no way back except a terminal. Add your background, lock or bar plugins there
too if losing them mid-session would look like a broken desktop.

## Notes

- Every state change is an **absolute** setter, never a toggle, so applying a
  profile twice does nothing the second time and an interrupted switch is fixed
  by running it again.
- Theme changes are skipped when the theme is already current — retinting every
  terminal takes seconds and there is no reason to pay it to stay put.
- `omarchy.idle`'s IPC target does not exist while that plugin is disabled (the
  normal state when a third-party lock/idle plugin has replaced it), so idling
  is set through `omarchy toggle idle allow-idle|stay-awake` instead. Note the
  sense: stay-awake *inhibits* idling.

## License

MIT

## Per-profile plugin data

A plugin's settings are already per-profile when it keeps them inline in
`shell.json`, because a profile captures that whole object. Plugins with their
own files outside it are global — the Spotify plugin's session lives in
`~/.local/state/omarchy-spotify`, so every profile is signed in as the same
person, and the dock keeps one `arc-dock.json`, so every profile gets the same
dock.

Isolate those paths and each profile gets its own copy:

```bash
omarchy-profile isolate add ~/.local/state/omarchy-spotify
omarchy-profile isolate add ~/.config/omarchy/arc-dock.json
omarchy-profile isolate list          # * marks the one in use now
omarchy-profile isolate remove <path> # puts the active copy back as a real file
```

It works the way browsers do for their own profiles: one copy per profile, with
the path the plugin knows pointed at the active profile's copy. The plugin is
unchanged and unaware.

Swapping is lossless and self-healing. Leaving profile F for T, for each
isolated path: a symlink is removed, a real file is moved into F's store since
the live data is F's, and T is linked to its own store — or, if T has none, the
path is left absent so the plugin makes a fresh one, which the next switch away
adopts into T's store. Nothing is deleted and no symlink is left dangling.

New profiles follow the same choice as everything else: **copy of master**
inherits the stores (already signed in, same dock), **clean** inherits none
(signed out, default dock). Removing a profile deletes its store with it.

One caveat: a plugin already running may not notice the swap until it reloads.
A profile switch that also changes the theme restarts enough of the shell to
cover it; otherwise `omarchy restart shell`.
