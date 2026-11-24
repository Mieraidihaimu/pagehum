# Adaptive color system

`Pagehum/Assets.xcassets` owns the sRGB values and the light/dark variants.
`Pagehum/Extensions/AppTheme.swift` exposes semantic roles shared by iPhone and Mac.
`DesktopStyle` delegates its existing color API to those same tokens.

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | `#FFFFFF` | `#0B0F17` |
| Surface | `#F8FAFC` | `#161F30` |
| Elevated / input | `#F1F5F9` | `#1E293B` |
| Primary text | `#0F172A` | `#F8FAFC` |
| Secondary text | `#475569` | `#A3B3C6` |
| Muted text | `#94A3B8` | `#64748B` |
| Primary accent, text/icons | `#0284C7` | `#38BDF8` |
| High-contrast accent text | `#0369A1` | `#38BDF8` |
| Primary accent, fills | `#0EA5E9` | `#38BDF8` |
| Primary accent, hover/text | `#0284C7` | `#7DD3FC` |
| Primary accent tint | `#0EA5E9` at 10% | `#38BDF8` at 12% |
| CTA fill (Playback / Primary) | `#E11D48` | `#F43F5E` |
| CTA hover | `#BE123C` | `#FB7185` |
| CTA accent text | `#E11D48` | `#FB7185` |
| CTA tint | `#F43F5E` at 10% | `#FB7185` at 12% |
| Favorite / Warning | `#D97706` | `#FBBF24` |
| Favorite tint / text | `#F59E0B` at 12% / `#92400E` | `#F59E0B` at 16% / `#FDE68A` |
| Destructive / Error | `#DC2626` | `#F87171` |
| Destructive tint / text | `#EF4444` at 10% / `#B91C1C` | `#EF4444` at 15% / `#FCA5A5` |
| Active sentence highlight | `#0EA5E9` at 9% | `#38BDF8` at 10% |
| Active spoken word bg / text | `#0EA5E9` at 22% / `#0C4A6E` | `#38BDF8` at 26% / `#F8FAFC` |
| Player surface / border | `#FFFFFF` at 94% / `#E2E8F0` | `#121A29` / `#94A3B8` at 18% |
| Subtle border | `#E2E8F0` | `#94A3B8` at 12% |
| Focus border | `#0EA5E9` | `#38BDF8` |
| Accent border | `#0EA5E9` at 18% | `#38BDF8` at 18% |
| Text on CTA | `#FFFFFF` | `#FFFFFF` |

Keep the vast majority of each screen neutral. Use blue/cyan for navigation,
links, selections, progress, secondary buttons, reader sentence/word highlights,
and data visualization. Rose is reserved strictly for primary playback & action
CTAs (Play/Pause, "Play N articles", primary submit). Amber is reserved for
favorites/starred items and non-fatal cautions, while crimson/red (`destructive`)
is used for failures and destructive actions. Status labels retain an icon or
text alongside color.

Use `themeCard` for cards: a surface, a 1-point subtle border, a subtle top-edge
highlight in dark mode (`DarkTopHighlight`), and a diffuse 12-point shadow at
y=4 (`CardShadow` in light mode, or `FloatingShadow` for floating bars/docks).
Inputs and hover surfaces use the elevated token.

Use `ThemeButtonStyle` for primary and secondary buttons, and
`ThemePlayButtonStyle` for round playback actions. Both preserve disabled and
pressed states. Rose primary actions use white labels; hover adds a 16-point
rose glow at 30% only in dark mode. Reduced Motion disables state animation.

`ThemeSegmentedPicker` uses blue/cyan selection tints and borders, with a native
Picker accessibility representation. Larger accessibility text sizes use the
menu picker on the iPhone Add screen.

The app follows the system appearance and has no separate theme preference.
Named asset colors also honor SwiftUI appearance overrides. Modal surfaces use
the same palette. Tech blog previews default to a reader view styled with the
app palette. The original page is available from the preview and opens
automatically when extraction fails. The live playback view shows the
publisher's page and updates its highlight tint when the app appearance changes.

`AppThemeTests` verifies the resolved native colors and alpha values in both
appearances, including the web highlight, dark card shadows, and WCAG AA (>= 4.5:1)
text contrast for all browse, reader, badge, and CTA combinations.
