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
omarchy-profile remove work           # its windows move to the master first
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

## Why a switch restarts the shell

Because a reload is not enough, and "it usually works, restart if it looks
wrong" is not a thing to ship. Plugins hold their own config and state files
open, so a swapped Spotify session or dock file goes unnoticed; enabling a
plugin that was off needs it instantiated; and Qt keeps compiled QML cached.
Each of those produced a switch that looked half-applied.

The order is what makes it safe: **files first, restart second, IPC third.**
Restarting before the writes would have the new shell read the old files, and
setting do-not-disturb over IPC before a restart wastes the call on a process
about to exit. Do-not-disturb and the idle flag are persisted under
`XDG_STATE_HOME`, so they survive the restart either way.

The cost is a visible blip and about five seconds, most of it the theme retint.
A profile switch is already a visual event, so the blip reads as part of it.

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

No caveat about reloading: a switch restarts the shell, so every plugin reads
its new copy. See *Why a switch restarts the shell*.

## Password-protected profiles

```bash
omarchy-profile lock work      # entering it now asks
omarchy-profile unlock work    # stops asking — and asks first, to prove you could
```

Authentication goes through **PAM**, not a passphrase of this plugin's own,
because PAM is already where your identity is decided. Whatever you have set up
works with nothing added here — a face (`pam_exec` with a verifier, as
`omarchy-face` installs), a fingerprint (`pam_fprintd`), or your password as the
fallback. Adding a method later needs no change to this plugin.

The default `unlock.method` is `polkit`. `pkcheck` asks for an authorisation
decision on the action `no.graveklar.profiles.unlock` without running anything
as root, because that is what this is — a decision, not a privileged action, and
it should not have to become one to be asked. The agent runs the `polkit-1` PAM
stack, so a face is tried first where one is configured, then the password.

The policy is `auth_self` deliberately **without** `_keep`. A cached
authorisation is precisely the hole this gate exists to close: the threat is a
person at an unattended machine, and "you authorised something five minutes ago"
is no evidence that you are the one standing here now.

Because polkit draws its own dialog through the session agent, a locked switch
started from the panel no longer relaunches itself in a floating terminal.
Authentication still happens **before** anything is captured or written, so a
failed unlock leaves the machine exactly where it was.

`unlock.method` may also be `sudo` (the previous behaviour: `sudo -k` then
`sudo -v`, which works but clobbers your real sudo timestamp as a side effect)
or `none`.

### A face other than yours

A profile can also answer to a named face that is not the account owner's:

```bash
omarchy-profile identity work partner   # bind
omarchy-profile identity work           # read
omarchy-profile identity work none      # clear
```

The face is enrolled by `omarchy-face` and verified through
`omarchy-face-identity`, which needs no authorisation prompt — the point is that
the other person cannot authorise as you. Binding one is gated exactly like
unlocking, because choosing who else may enter a profile is at least as
consequential as entering it.

The check is **additive**. If the named face is not recognised, the owner check
still runs, so a camera that cannot see is never the reason somebody is locked
out of their own machine.

### What this is, and what it is not

It gates **entering** a profile. It stops a person at the keyboard.

It is **not** a security boundary. Every profile runs as the same Unix user, so
a process running as you can read any profile's files whether or not this
prompt exists. Real isolation would need a separate Unix user and a separate
login session, which is not a profile switch.

**The same is true of a bound identity.** A profile can name whose face opens
it — a partner's, say — but the binding lives in `~/.config`, writable by the
same user who is being gated. It decides who the machine greets, not who can
reach the files. A profile bound to somebody else's face is not private from
you, and yours is not private from anyone who can edit your config.
