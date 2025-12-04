# Modern CSS Best Practices Guide

A comprehensive analysis of modern CSS architecture, demonstrating how to work without preprocessors.

---

## 1. Architecture Overview

### No Preprocessors - Pure Modern CSS

Use **zero CSS preprocessors** (no SCSS, LESS, or PostCSS). Instead, it leverage cutting-edge CSS features:
- CSS Custom Properties (variables)
- CSS Nesting (`&` syntax)
- `@layer` for cascade control
- Modern selectors (`:has()`, `:is()`, `:where()`)

### File Organization

```
app/assets/stylesheets/
├── _global.css          # Entry point: layers + all variables
├── reset.css            # Browser reset
├── base.css             # Base element styles
├── utilities.css        # Utility classes
├── animation.css        # Keyframe animations
├── buttons.css          # Button component
├── cards.css            # Card component
├── inputs.css           # Form inputs
├── icons.css            # Icon system
└── [component].css      # One file per component
```

**Key principle**: Flat directory structure with one file per component/concern.

---

## 2. CSS Layers (Cascade Control)

All files wrap styles in `@layer` directives, declared at the top of `_global.css`:

```css
@layer reset, base, components, modules, utilities;
```

**Layer hierarchy** (lowest to highest specificity):
1. **reset** - Browser normalization
2. **base** - Global element styles
3. **components** - Reusable UI components
4. **modules** - Feature-specific styles (rarely used)
5. **utilities** - Helper classes (highest priority)

**Usage pattern**:
```css
/* In buttons.css */
@layer components {
  .btn { ... }
}

/* In utilities.css */
@layer utilities {
  .txt-small { ... }
}
```

---

## 3. CSS Custom Properties System

### Spacing Scale

```css
:root {
  /* Base units */
  --inline-space: 1ch;        /* Horizontal (character-based) */
  --block-space: 1rem;        /* Vertical (rem-based) */

  /* Derived values */
  --inline-space-half: calc(var(--inline-space) / 2);
  --inline-space-double: calc(var(--inline-space) * 2);
  --block-space-half: calc(var(--block-space) / 2);
  --block-space-double: calc(var(--block-space) * 2);
}
```

### Typography Scale

```css
:root {
  --font-sans: system-ui;
  --font-serif: ui-serif, serif;
  --font-mono: ui-monospace, monospace;

  --text-xx-small: 0.55rem;
  --text-x-small: 0.75rem;
  --text-small: 0.85rem;
  --text-normal: 1rem;
  --text-medium: 1.1rem;
  --text-large: 1.5rem;
  --text-x-large: 1.8rem;
  --text-xx-large: 2.5rem;

  /* Responsive override */
  @media (max-width: 639px) {
    --text-xx-small: 0.65rem;
    --text-x-small: 0.85rem;
    /* ... larger on mobile for readability */
  }
}
```

### OKLCH Color System

Colors use OKLCH (perceptually uniform color space) with a two-tier system:

```css
:root {
  /* Raw OKLCH values (lightness% chroma hue) */
  --lch-blue-dark: 57.02% 0.1895 260.46;
  --lch-blue-medium: 66% 0.196 257.82;
  --lch-blue-light: 84.04% 0.0719 255.29;

  /* Named color abstractions */
  --color-link: oklch(var(--lch-blue-dark));
  --color-negative: oklch(var(--lch-red-dark));
  --color-positive: oklch(var(--lch-green-dark));
  --color-canvas: oklch(var(--lch-canvas));
  --color-ink: oklch(var(--lch-ink-darkest));
}
```

**Benefits**:
- Consistent lightness across hues
- Easy dark mode (swap OKLCH values)
- `color-mix()` for dynamic tints

### Component Variables

```css
:root {
  /* Buttons */
  --btn-size: 2.65em;

  /* Focus rings */
  --focus-ring-color: var(--color-link);
  --focus-ring-offset: 1px;
  --focus-ring-size: 2px;

  /* Shadows (multi-layer for depth) */
  --shadow: 0 0 0 1px oklch(var(--lch-black) / 5%),
            0 0.2em 0.2em oklch(var(--lch-black) / 5%),
            0 0.4em 0.4em oklch(var(--lch-black) / 5%),
            0 0.8em 0.8em oklch(var(--lch-black) / 5%);

  /* Easing */
  --ease-out-expo: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-out-overshoot: cubic-bezier(0.25, 1.75, 0.5, 1);

  /* Z-index scale */
  --z-popup: 10;
  --z-nav: 30;
  --z-flash: 40;
  --z-tooltip: 50;
}
```

---

## 4. Naming Conventions

### Component Pattern (BEM-inspired)

```
.component
.component__element
.component--modifier
```

**Examples**:
```css
.card { }
.card__header { }
.card__body { }
.card--notification { }

.btn { }
.btn--link { }
.btn--negative { }
.btn__group { }
```

### Utility Class Prefixes

| Prefix | Purpose |
|--------|---------|
| `.txt-*` | Typography |
| `.pad-*` | Padding |
| `.margin-*` | Margins |
| `.flex-*` | Flexbox |
| `.fill-*` | Background colors |
| `.border-*` | Borders |
| `.align-*` | Alignment |

**Directional suffixes** (logical properties):
- `-start`, `-end` (inline direction)
- `-block`, `-inline` (block/inline axes)
- `-half`, `-double` (scale modifiers)

---

## 5. Component Architecture

### Base Component Pattern

```css
@layer components {
  .btn {
    /* Internal variables (overridable) */
    --icon-size: var(--btn-icon-size, 1.3em);
    --btn-border-radius: 99rem;
    --btn-hover-brightness: 0.9;

    /* Base styles */
    align-items: center;
    background-color: var(--btn-background, var(--color-canvas));
    border-radius: var(--btn-border-radius);
    border: var(--btn-border-size, 1px) solid var(--btn-border-color, var(--color-ink-light));
    color: var(--btn-color, var(--color-ink));
    /* ... */

    /* Interactive states using nesting */
    @media (any-hover: hover) {
      &:hover {
        filter: brightness(var(--btn-hover-brightness));
      }
    }

    /* Dark mode adjustment */
    @media (prefers-color-scheme: dark) {
      --btn-hover-brightness: 1.25;
    }

    /* Disabled states */
    &[disabled],
    &:has([disabled]) {
      cursor: not-allowed;
      opacity: 0.3;
      pointer-events: none;
    }
  }

  /* Variants override internal variables */
  .btn--link {
    --btn-background: var(--color-link);
    --btn-border-color: var(--color-canvas);
    --btn-color: var(--color-ink-inverted);
  }

  .btn--negative {
    --btn-background: var(--color-negative);
    --btn-border-color: var(--color-negative);
    --btn-color: var(--color-ink-inverted);
  }
}
```

### Dynamic Color Mixing

```css
.card {
  /* Generate tinted backgrounds from a single color */
  --card-bg-color: color-mix(in srgb, var(--card-color) 4%, var(--color-canvas));
  --card-content-color: color-mix(in srgb, var(--card-color) 30%, var(--color-ink));
  --card-border: 1px solid color-mix(in srgb, var(--card-color) 33%, var(--color-ink-inverted));
}
```

---

## 6. Icon System

Icons use CSS masks with `currentColor` for automatic color inheritance:

```css
.icon {
  background-color: currentColor;       /* Inherits text color */
  block-size: var(--icon-size, 1em);
  inline-size: var(--icon-size, 1em);
  mask-image: var(--svg);
  mask-position: center;
  mask-repeat: no-repeat;
  mask-size: var(--icon-size, 1em);
}

/* Icon definitions */
.icon--check { --svg: url("check.svg"); }
.icon--close { --svg: url("close.svg"); }
.icon--menu { --svg: url("menu.svg"); }
```

**Benefits**:
- Icons automatically match text color
- Easy to resize with `--icon-size`
- No need for icon fonts or complex SVG embedding

---

## 7. Responsive Design

### Breakpoints

```css
/* Mobile-first, then override for larger screens */
@media (max-width: 639px) { /* Mobile */ }
@media (max-width: 799px) { /* Tablet */ }
@media (min-width: 640px) { /* Desktop */ }
@media (min-width: 100ch) { /* Wide text */ }
```

### Input Detection

```css
/* Hover-capable devices only */
@media (any-hover: hover) {
  .btn:hover { ... }
}

/* Touch devices */
@media (any-hover: none) { ... }
@media (pointer: coarse) { ... }

/* PWA mode */
@media (display-mode: standalone) { ... }
@media (display-mode: browser) { ... }
```

### Responsive Units

```css
/* Dynamic viewport (accounts for mobile address bar) */
min-height: 100dvh;

/* Fluid sizing with clamp() */
--tray-size: clamp(12rem, 25dvw, 24rem);
--main-padding: clamp(var(--inline-space), 3vw, calc(var(--inline-space) * 3));
```

### Container Queries

```css
.card-columns {
  container-type: inline-size;
}

/* Style based on container width, not viewport */
@container (min-width: 600px) {
  .card { ... }
}
```

---

## 8. Logical Properties

All directional properties use logical equivalents for RTL support:

| Physical | Logical |
|----------|---------|
| `width` | `inline-size` |
| `height` | `block-size` |
| `margin-left` | `margin-inline-start` |
| `margin-right` | `margin-inline-end` |
| `padding-top` | `padding-block-start` |
| `padding-bottom` | `padding-block-end` |

```css
.card {
  inline-size: 100%;                    /* Instead of width */
  padding: var(--block-space) var(--inline-space);
  margin-inline-start: auto;            /* Instead of margin-left */
}
```

---

## 9. Utility Classes

### Text Utilities

```css
.txt-small { font-size: var(--text-small); }
.txt-large { font-size: var(--text-large); }
.txt-align-center { text-align: center; }
.txt-subtle { color: var(--color-ink-dark); }
.txt-nowrap { white-space: nowrap; }
.txt-uppercase { text-transform: uppercase; }
```

### Layout Utilities

```css
.flex { display: flex; }
.flex-column { flex-direction: column; }
.gap {
  column-gap: var(--column-gap, var(--inline-space));
  row-gap: var(--row-gap, var(--block-space));
}
.justify-center { justify-content: center; }
.align-center { align-items: center; }
```

### Spacing Utilities

```css
.pad { padding: var(--block-space) var(--inline-space); }
.pad-block { padding-block: var(--block-space); }
.pad-inline-half { padding-inline: var(--inline-space-half); }
.margin-block-end { margin-block-end: var(--block-space); }
.center { margin-inline: auto; }
```

### Accessibility Utilities

```css
.visually-hidden,
.for-screen-reader {
  block-size: 1px;
  clip-path: inset(50%);
  inline-size: 1px;
  overflow: hidden;
  position: absolute;
  white-space: nowrap;
}

[hidden] { display: none !important; }
```

---

## 10. Accessibility & Motion

### Keyboard Focus

```css
:is(a, button, input, textarea, .btn) {
  &:where(:focus-visible) {
    outline: var(--focus-ring-size) solid var(--focus-ring-color);
    outline-offset: var(--focus-ring-offset);
  }
}
```

### Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

---

## 11. Dark Mode

Dark mode uses separate OKLCH values, not filters or inversions:

```css
:root {
  /* Light mode (default) */
  --lch-canvas: var(--lch-white);
  --lch-ink-darkest: 26% 0.05 264;

  @media (prefers-color-scheme: dark) {
    /* Complete color replacement */
    --lch-canvas: 15% 0.02 264;
    --lch-ink-darkest: 96% 0.01 264;
  }
}
```

---

## 12. Animation Patterns

### Keyframe Library

```css
@keyframes shake {
  0%  { transform: translateX(-2rem); }
  25% { transform: translateX(2rem); }
  50% { transform: translateX(-1rem); }
  75% { transform: translateX(1rem); }
}

@keyframes pulse {
  0%   { opacity: 1; }
  50%  { opacity: 0.4; }
  100% { opacity: 1; }
}

@keyframes slide-up {
  from { transform: translateY(2rem); }
  to   { transform: translateY(0); }
}
```

### Usage with utility class

```css
.shake {
  animation: shake 400ms both;
}
```

---

## Key Takeaways

1. **No preprocessors** - Modern CSS features eliminate the need for SCSS/LESS
2. **`@layer` for cascade** - Predictable specificity without `!important`
3. **Variables everywhere** - Consistent spacing, colors, and component customization
4. **OKLCH colors** - Perceptually uniform palette with easy `color-mix()`
5. **Logical properties** - RTL-ready from the start
6. **Component variants via variables** - Override internal custom properties, not selectors
7. **Icon system with masks** - `currentColor` inheritance for automatic theming
8. **Flat file structure** - One component per file, easy to find and maintain
9. **Accessibility built-in** - Focus rings, reduced motion, screen reader utilities
10. **Container queries** - Components adapt to their container, not viewport

---

*Source: Analysis of Fizzy codebase at `/home/elio/work/open-source/fizzy/app/assets/stylesheets/`*
