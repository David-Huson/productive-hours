# ADR 0003: Glanceable menu bar and detailed dashboard

Status: accepted interface direction from user feedback, October 31, 2026. Not yet implemented.

## Decision

The menu bar answers whether the user is on track and what needs attention. Detailed accounting belongs in a native dashboard. This refines PRD section 7.1's dense popover; it does not remove required metrics.

- Menu-bar label: compact pace/status indicator with accessible text. Show On track, Behind pace, Above target pace, or Calibrating when evidence is insufficient. Paused or a collection failure takes priority over a reassuring pace indicator.
- Popover: pace direction, a short explanation and one useful next step when supported by data. Include Open dashboard and Pause/resume. Show limited coverage or data gaps clearly. No detailed breakdown tables.
- Dashboard: actual weekly productive total and 35–40h target band, time to minimum, headroom/overage, today's total, Active/Passive split, forecast and assumptions, scheduled capacity, confidence and coverage, daily/weekly history, classification review and settings. Keep manual meeting/offline time distinct.

Trend means projected weekly pace relative to the configured target and remaining schedule, not whether cumulative time increased. A brief fluctuation should not flip the status repeatedly. Do not make behavioral recommendations from low-confidence or missing observations. Before three usable days exist, show Calibrating with a clearly labeled simple schedule-based pace where available. Never hide tracking failure behind a trend arrow or imply a forecast is an actual total.

## Validation

Test below/on/above-target pace, target reached, insufficient history, no remaining scheduled time, paused collection and degraded coverage. Confirm the compact UI links directly to detailed totals; accessible text must convey the same meaning as icons/color. The diagnostic prototype remains diagnostic until the reducer, persistence and forecast supply real values.
