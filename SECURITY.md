# Security

Please report security problems privately through GitHub: open the **Security** tab of this repository and choose **Report a vulnerability**. Don't open a public issue for them.

What Slimey touches, so you know what to look at:

- **claude.ai**: a hidden web view, signed in with your own session, requests your usage once a minute. Slimey never sees or stores your password; the session cookie stays inside WebKit's own storage.
- **`~/.claude/settings.json`**: only when you turn on the task light. Slimey adds its own hook entries, keeps everything else, and backs up the original to `settings.json.slimey-backup`.
- **`~/.slimey/`**: the hook script and one small state file per Claude Code session.
- **Claude desktop app metadata** (`~/Library/Application Support/Claude/claude-code-sessions`): read-only, to see when you last opened a session.
