# Prism-Engine project instructions

## Mandatory design standard

Use the installed Anti-Slop Taste Skill at `.agents/skills/design-taste-frontend/SKILL.md` as
an ongoing design constraint for every Flutter screen, widget, layout, interaction, typography
choice, spacing decision, color palette, and animation.

Before implementing or redesigning UI:

1. Read the relevant Taste Skill guidance and decide the screen's visual direction and primary user goal.
2. Inspect the existing theme, navigation, assets, fonts, and reusable widgets.
3. Prefer a distinctive product-specific composition over generic dashboard, card-grid, gradient,
   glow, floating-container, or decorative-icon patterns.
4. Use intentional typography, consistent spacing, accessible contrast, clear hierarchy, and
   purposeful interaction states.
5. Preserve functionality, maintainability, performance, responsive behavior, and accessibility.

After UI changes, review the result critically at narrow and wide layouts. Check empty, loading,
error, disabled, pressed, and success states, text scaling, overflow, contrast, touch targets,
and reduced-motion behavior where applicable. Fix anything that looks generic, amateurish,
inconsistent, cluttered, or AI-generated.

The Taste Skill's browser-only commands and HTML-specific metadata do not apply directly to this
Flutter app. For Flutter validation, use the project's normal checks:

```powershell
dart format .
flutter analyze
flutter test
```

Do not run untrusted skill scripts or modify the Taste Skill's installed files.
