# Discord Rich Presence

Worktempo can mirror your menu-bar activity indicator on Discord while tracking is running.

## Setup

1. Open the [Discord Developer Portal](https://discord.com/developers/applications) and create an application (any name is fine).
2. Set the application **name** to **Worktempo** (this is the title on your profile activity card).
3. Copy the **Application ID** from the General Information page.
4. In Worktempo **Settings → Discord Rich Presence**, enable **Show activity on Discord**, paste the ID, choose which totals to show, and **Save settings**.
5. (Optional) In **Rich Presence → Art Assets**, upload:
   - `worktempo` — large artwork (512×512)
   - `status_active`, `status_passive`, `status_inactive`, `status_unproductive` — small status dots (optional; emoji still appear in text)

Worktempo asks Discord to use the **details** line in the **member list** (instead of the portal application name), so friends see `Worktempo: Active 🟢` rather than a test app name. Requires a recent Discord desktop client.

## What Discord shows

| Field | Content |
| ----- | ------- |
| **Member list** | `Worktempo: Active 🟢` (via `status_display_type`) |
| **Profile — line 1** | Same status line (`details`) |
| **Profile — line 2** | `3h 28m today · 5h 32m this week` when toggles are on (`state`) |
| **Artwork tooltip** | `This week — Mon 4h · Tue 5h …` when weekly breakdown is enabled |

Discord limits each text field to 128 characters, so the per-day list is compressed on the artwork tooltip.

## Privacy

- No content, keystrokes, or outbound telemetry beyond Discord’s own Rich Presence IPC to the Discord desktop client.
- Presence clears when you pause tracking, hit a data gap, or disable the feature.
