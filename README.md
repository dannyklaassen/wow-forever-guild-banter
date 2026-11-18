<img src=".github/icon.png" alt="GuildBanter icon" width="128" align="right">

# GuildBanter

A World of Warcraft Classic addon that posts funny messages in guild chat when something happens in your guild: a new member joins, someone leaves, an old friend comes back, or someone reaches level 40 or 60.

```text
Welcome Zarnok! You chose demons voluntarily. So you chose us voluntarily too. Good taste!
Grats Elowen, level 40! 100 gold for riding lessons and the mount comes free. Like a phone contract. Enjoy!
Look who rose from the dead! Brakk is back after 47 days. Welcome back!
```

## What it does

| Event | Message |
|---|---|
| New member joins | A welcome that teases their class (25 lines per class) |
| Member leaves | A friendly goodbye (25 lines) |
| Member comes back after a long absence | A welcome back that mentions how many days they were gone (25 lines) |
| Member reaches level 40 | Congratulations on their first mount (75 lines, some class-specific) |
| Member reaches level 60 | Congratulations on max level (75 lines, some class-specific) |

- **Five languages:** English, Nederlands, Deutsch, Français and Español. You pick the language yourself, so it can differ from your game client.
- **No repeats:** every line comes by once before any line is used again.
- **No double messages:** if several guild members run GuildBanter, each waits a random 1 to 8 seconds. If someone already mentioned the name in guild chat, it stays quiet.
- **Settings per guild:** language and options are saved per guild, so an alt in another guild can have its own settings.

The messages are posted in guild chat **by your character**. Turn off anything you don't want to say yourself.

## Installation

**CurseForge app:** search for *GuildBanter* and click Install.

**Manual:**

1. Download the latest zip from CurseForge or the [GitHub releases](https://github.com/dannyklaassen/wow-forever-guild-banter/releases).
2. Unzip it into `World of Warcraft/<your Classic version>/Interface/AddOns/`, for example `_classic_era_`. You should end up with `Interface/AddOns/GuildBanter/GuildBanter.toc`.
3. Restart the game, or type `/reload` if it is already running.

## Settings

Open them with `/gb`, or via Esc > Options > AddOns > GuildBanter.

- **Message language:** English (default), Nederlands, Deutsch, Français or Español.
- **One checkbox per event:** welcome, goodbye, level 40, level 60 and welcome back. All are on by default.
- **Welcome back after an absence of at least:** 1 week, 2 weeks (default), 1 month, 2 months or 3 months.

## Commands

| Command | What it does |
|---|---|
| `/gb` | Opens the settings |
| `/gb test hi\|bye\|back\|40\|60 [class] [name]` | Shows a sample message, styled as guild chat, in your own chat window only. Nothing is sent to the guild. Example: `/gb test 40 warlock Zarnok` |

`/gw` still works as an alias for players coming from GuildWelcome.

## Good to know

- Level milestones are detected by refreshing the guild roster once a minute, so a congratulation can follow up to a minute after the ding.
- Levels gained while you are offline are not congratulated afterwards.
- Members who are removed from the guild get no message.

## Development

`check.lua` validates all five language files against the Dutch structure: the same tables and counts, `{name}` in every chat line, at most 255 characters per message and no em dashes. Run it from the addon folder:

```bash
lua check.lua
```

It is excluded from the release package through `.pkgmeta`.

## License

[MIT](LICENSE)
