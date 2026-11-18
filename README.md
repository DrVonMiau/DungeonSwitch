<p align="center"><img src="media/logo.jpg" alt="DungeonSwitch" width="180"></p>

# DungeonSwitch

**Turn off the addons you don't need in dungeons and raids, with one click.**

Plenty of addons are useful in town and while questing but only get in the way inside an
instance: auction tools, tooltip extras, quest guides, bag scanners. They still react to every
loot, tooltip and buff while you're in a dungeon. DungeonSwitch gives each character two modes:

- **Normal**: your usual addons.
- **Dungeon**: the addons on your list are turned off.

WoW only loads or unloads addons on a UI reload, so switching reloads your UI once on the way in
and once on the way out.

Made for **WoW: Forever**.

## How it works

- **First start:** a welcome screen lists your installed addons. Tick the ones to turn off in
  dungeons. It only appears once.
- **Entering a dungeon or raid:** a popup asks *Switch to Dungeon mode?* Click **Switch** and
  your UI reloads without those addons.
- **Leaving:** it offers to switch back.
- **Only restores what it turned off:** addons you had disabled yourself stay disabled.
- **Never reloads in combat:** it waits until the fight is over.
- **No nagging:** no popup on corpse runs or when you re-enter after saying *Not now*.
- **Shared list:** one list for all your characters; the mode is remembered per character.
- **Cost:** it only does work when you change zones. No timers, nothing running in the background.

## Commands

| Command | What it does |
|---|---|
| `/ds` | Switch between Normal and Dungeon mode (asks first) |
| `/ds config` | Open the settings (also: right-click the minimap key) |
| `/ds status` | Show the current mode and your dungeon list |
| `/ds minimap` | Show or hide the minimap button |

**Minimap key:** grey in Normal mode, coloured in Dungeon mode. Left-click to switch, right-click
for settings, drag to move.

## Settings

Options → AddOns → DungeonSwitch:

- **Your list:** tick the addons to turn off in Dungeon mode.
- **Popup:** turn the automatic popup on entering or leaving dungeons on or off.
- **Minimap button:** show or hide it.

## Issues and source

Bug reports and ideas: [GitHub issues](https://github.com/DrVonMiau/DungeonSwitch/issues).
MIT licensed.
