# How this project is worked on

Two of everything: one you play, one I break.

## Branches

| Branch | What it is |
|---|---|
| `main` | **Stable.** Only ever receives finished, tested work. Every release is tagged here (`v1.8.1`, ...). |
| `dev`  | **Development.** All work happens here, without exception. |

Nothing is committed to `main` directly. Work lands on `dev`, is proved
on the dev install, and only then is merged to `main` and tagged.

## Installs

| Folder | What it is |
|---|---|
| `D:\Battle of Britain II` | **Stable.** Patrick's game. Not touched by development work. |
| `D:\Battle of Britain II_Latest_test` | **Dev.** Every experiment, every unproven change, goes here first. |

An experiment goes on the dev install and is confirmed there - including
across a flight, where display changes tend to come undone - before it is
applied to the stable one.

## Why

On 8 September 2026 a day was lost testing unproven changes on the live
install. Two of them broke a working game: an explicit `DPIUNAWARE`
compatibility layer made the cockpit enormous, and dropping control-free
dialogs from the menu-scale patch crashed the game outright. Both were
reverted, but only after Patrick had launched the game a dozen times to
find out what I had done.

The rule that came out of it: **if it has not been proved on the dev
install, it does not go near the stable one.** A second install costs
2 GB of disk and settles in one launch what hours of reasoning could not.
