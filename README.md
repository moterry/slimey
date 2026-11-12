# Slimey

**A tiny pixel slime that lives on your Mac desktop and keeps an eye on your Claude usage.**

[中文说明](README.zh-CN.md)

<p align="center"><img src="media/slimey-demo.gif" width="480" alt="Slimey demo: a pixel slime showing Claude usage and a task light"></p>

- **Usage at a glance.** The label above its head shows how much of your current Claude session you've used and when it resets (`53% · 03:40`).
- **It has moods.** Green and bouncy under 50%, yellow past 50%, red and sweating past 80%, and at 100% it melts into a sleepy puddle.
- **Click for details.** Session and weekly limits with reset times, plus any free reset you have.
- **Claude Code task light.** An antenna lamp glows **blue** while Claude Code is working, blinks **yellow** when it's waiting on you, and turns **green** when it's done. In the Claude desktop app, the green light only goes out once you actually open the finished session.

Slimey is a small native macOS app (Swift + AppKit, no dependencies, ~1 MB).

## Install

1. Download `Slimey-x.y.z.zip` from [Releases](https://github.com/moterry/slimey/releases), unzip it, and move `Slimey.app` to Applications.
2. Slimey isn't notarized by Apple, so macOS blocks the first launch. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Slimey.app
   ```
3. A claude.ai sign-in window opens. Sign in the way you normally do. Slimey keeps that session in its own web view; it never sees your password.

Requires macOS 13 or later (Apple silicon or Intel).

### Turn on the Claude Code task light (optional)

Right-click Slimey → **Claude Code task light (installs hooks)**. This copies a tiny script to `~/.slimey/hook.sh` and adds hooks to `~/.claude/settings.json`. Your existing settings and hooks are kept, and the original file is backed up to `settings.json.slimey-backup`. Click the same item again to remove them.

From a terminal: `/Applications/Slimey.app/Contents/MacOS/Slimey --install-hooks` (or `--uninstall-hooks`).

Sessions that were already open when you installed the hooks start reporting after they're restarted.

### Launch at login (optional)

Right-click Slimey → **Launch at login**.

## How it works

- **Usage** comes from the same endpoint the claude.ai usage page uses, called once a minute from a hidden web view that is signed in with your own session.
- **Task status** comes from [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks). Each session writes one word (`running`, `waiting` or `done`) to `~/.slimey/sessions/<session-id>`, and Slimey reads those files.
- **"Have I seen it?"** comes from the Claude desktop app's local session metadata (the time you last focused each session). Sessions started in a terminal don't have that, so for those, clicking Slimey clears the green light.

## Privacy

Slimey itself only contacts **claude.ai**, using your own signed-in session, to read your usage. (The sign-in window is claude.ai's own page, so it loads whatever claude.ai and the sign-in provider you pick load.) Slimey has no server, no analytics and no telemetry. Everything else stays in local files on your Mac.

To report a security problem, see [SECURITY.md](SECURITY.md).

## Disclaimer

Slimey is an unofficial fan project. It is **not affiliated with or endorsed by Anthropic**. "Claude" is a trademark of Anthropic.

It relies on **undocumented** claude.ai endpoints and on internal files of the Claude desktop app. Either can change at any time and break Slimey. Polling claude.ai from an app may also fall outside what Anthropic's terms allow, so read [Anthropic's Consumer Terms](https://www.anthropic.com/legal/consumer-terms) and decide for yourself. Use it at your own risk.

## Build from source

You only need Xcode or the Command Line Tools (no Xcode project, no package manager):

```sh
./test.sh                 # run the tests
./build.sh                # builds Slimey.app (universal)
open Slimey.app
SLIMEY_LANG=en open Slimey.app   # force English (or zh)
./Slimey.app/Contents/MacOS/Slimey --demo 85   # fake data, no sign-in
```

`tools/make-video.sh` renders the demo video and GIF in `media/` from the app's own drawing code.

## Uninstall

1. Right-click Slimey and uncheck the task light (this removes the hooks), then **Quit Slimey**.
2. Delete `Slimey.app` and `~/.slimey`.

## License

[MIT](LICENSE)
