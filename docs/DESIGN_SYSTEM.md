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
| Secondary text | `#475569` | `#94A3B8` |
| Muted text | `#94A3B8` | `#64748B` |
| Primary accent, text/icons | `#0284C7` | `#38BDF8` |
| Primary accent, fills | `#0EA5E9` | `#38BDF8` |
| Primary accent, hover/text | `#0284C7` | `#7DD3FC` |
| Primary accent tint | `#0EA5E9` at 10% | `#38BDF8` at 12% |
| CTA fill | `#F43F5E` | `#F43F5E` |
| CTA hover / accent text | `#E11D48` | `#FB7185` |
| CTA tint | `#F43F5E` at 10% | `#FB7185` at 12% |
| Subtle border | `#E2E8F0` | `#94A3B8` at 12% |
| Focus border | `#0EA5E9` | `#38BDF8` |
| Accent border | `#0EA5E9` at 18% | `#38BDF8` at 18% |
| Text on CTA | `#FFFFFF` | `#FFFFFF` |

Keep the vast majority of each screen neutral. Use blue/cyan for navigation,
links, selections, progress, secondary buttons, and data visualization. Rose is
reserved for primary intent (import/play), favorites, the active spoken word,
and attention states. Status labels retain an icon or text alongside color.

Use `themeCard` for cards: a surface, a 1-point subtle border, and a diffuse
12-point shadow at y=4. The shadow token is slate at 5% in light mode and fully
transparent in dark mode. Inputs and hover surfaces use the elevated token.

Use `ThemeButtonStyle` for primary and secondary buttons, and
`ThemePlayButtonStyle` for round playback actions. Both preserve disabled and
pressed states. Rose primary actions use white labels; hover adds a 16-point
rose glow at 30% only in dark mode. Reduced Motion disables state animation.

`ThemeSegmentedPicker` uses blue/cyan selection tints and borders, with a native
Picker accessibility representation. Larger accessibility text sizes use the
menu picker on the iPhone Add screen.

The app follows the system appearance and has no separate theme preference.
Named asset colors also honor SwiftUI appearance overrides. Modal surfaces use
the same palette. Web articles retain the publisher's layout and appearance;
Pagehum's playback highlight is resolved from the native tint and updates when
the app appearance changes, without reloading the article.

`AppThemeTests` verifies the resolved native colors and alpha values in both
appearances, including the web highlight and the absence of dark card shadows.
