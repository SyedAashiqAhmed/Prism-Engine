---
name: product-ui-design
description: Design distinctive, polished Flutter interfaces with intentional visual hierarchy and interaction details.
---

Create interfaces that feel designed for this product, not generated from a generic template.

Before changing UI:

1. Inspect the existing theme, navigation, assets, fonts, and reusable widgets.
2. Identify the screen's primary user goal and make it visually dominant.
3. Preserve established product patterns unless there is a clear usability reason to change them.

Design principles:

1. Use a restrained, deliberate color palette with accessible contrast.
2. Establish a clear typography hierarchy; avoid excessive font sizes, weights, and text styles.
3. Use consistent spacing and alignment based on a small spacing scale.
4. Prefer meaningful composition and whitespace over decorative cards, gradients, shadows, or unnecessary borders.
5. Avoid repetitive card grids, oversized hero sections, arbitrary pills, and default-looking layouts.
6. Use icons and illustrations only when they clarify meaning or support the product identity.
7. Make loading, empty, error, disabled, pressed, and success states intentional.
8. Support small screens, large screens, text scaling, touch targets, and dark mode where the project supports them.
9. Keep animations subtle, purposeful, and respectful of reduced-motion preferences when applicable.
10. Build reusable widgets and theme tokens instead of scattering visual constants through screens.

Validation:

1. Run `dart format .`.
2. Run `flutter analyze`.
3. Run relevant widget tests.
4. Check the changed screen on narrow and wide layouts.
5. Check contrast, overflow, text scaling, and interactive states.

When presenting a UI change, explain the visual direction and the user problem it solves.
