# RepairReminder

RepairReminder is a lightweight World of Warcraft addon that reminds you to repair your gear before durability becomes a problem.

It is designed to be:
- minimal
- event-driven (no polling or timers)
- secure (no protected actions)
- respectful of player context (no combat spam)

---

## Features

- One-time reminder when **overall durability is at or below 50%**
- Automatically resets after repairing to **95% or higher**
- Suppresses reminders while in combat
- Optional re-nudge after a configurable time
- Shows the lowest-durability item (optional)
- Quiet reset mode (no chat spam)

---

## Commands
/rr
/rr status
Show current settings and durability status.

/rr 50
/rr 50%
Set reminder threshold (default: 50%).

/rr reset
Manually reset the session reminder (useful for testing).

/rr quiet on|off
Enable or disable chat messages when the reminder resets after repair.

/rr worst on|off
Show or hide the lowest-durability item in the reminder message.

/rr renudge <minutes>
Allow the reminder to trigger again after X minutes (checked only when opening a repair vendor).
Set to `0` to disable.

---

## Installation

1. Download the addon.
2. Extract the `RepairReminder` folder into:
3. Launch the game and enable the addon from the AddOns menu.

---

## Supported Version

- World of Warcraft Retail
- Tested on 12.0.1

---

## Philosophy

RepairReminder intentionally avoids:
- automatic repairs
- UI clutter
- continuous background processing

The goal is a polite, predictable reminder that stays out of your way.

---

## License

MIT License. See `LICENSE` file for details.
