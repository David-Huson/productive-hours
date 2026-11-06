# Daily timeline rendering

Status: accepted, November 5, 2026.

The earlier experimental timeline was removed after severe interaction slowness. The replacement follows the requested daily-row layout, with productive/unproductive/undefined active and passive states, ignored time, inactive time, and explicitly untracked intervals.

Use a finite native AppKit renderer inside SwiftUI instead of a scrollable Charts domain. Prepare at most 31 calendar days when stored intervals, rules, settings, or date selection change. Split intervals at reporting-timezone midnight and merge only adjacent observations with identical source, state, and reason. Never fill missing intervals or reclassify history for presentation. Manual meetings and expired detail are excluded and labeled as such.

The renderer caches its bitmap. Hover draws that bitmap plus an opaque tooltip and binary-searches exact intervals, without publishing changes through the tracking service. Zoom and pan use a bounded fractional viewport. Each row uses its actual calendar-day duration and labels its own time ticks, including 23/25-hour days. Schedule markers use local clock time. Subpixel observations collapse only for overview drawing; totals and hit tests retain exact intervals. Zoom in to inspect dense events.

Automated coverage includes clipping, missing-time behavior, DST, classification, merging, viewport bounds, native rendering, and performance with 200,000 intervals. Offscreen tests also exercise the pointer tooltip and repeated zoom redraws. Physical trackpad behavior still needs normal use on the target Mac; passing offscreen tests is not proof of that interaction.
