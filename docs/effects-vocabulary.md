# Effects vocabulary

Blendolo describes makeup in its own words. A look's steps become a list of **effects**, and only the appearance provider adapter turns them into a provider's request. The rest of the app never sees a provider's field names.

- `Looks::EffectsBuilder` builds effects from look steps (`config/blendolo/steps.yml` holds each step's effect, `config/blendolo/looks.yml` the colours of each look).
- `Looks::Vocabulary.errors(effect)` lists what is wrong with an effect, or nothing when it is valid.

## Shape of an effect

A Hash with symbol keys. These six keys are always present, in this order, with `nil` when a category doesn't use them:

| Key | Value |
|---|---|
| `category` | One of the categories below. |
| `colour` | `"#RRGGBB"` in capitals. A list of them for multi-colour patterns, one per colour the pattern has, main shade first. |
| `intensity` | Integer 0 to 100: how strong the colour is. |
| `texture` | Finish, from the category's list below, or `nil`. |
| `pattern` | Id of a pattern from the provider's pattern catalogue, or the lip shape for `lip_color`. `nil` when the category has none. |
| `mode` | `eyebrows`: `"shape"` draws a new brow, `"color"` tints your own brows. `lip_color`: `"full"` covers the whole lip. Otherwise `nil`. |

Then, only when the effect uses them:

| Key | Value | Used by |
|---|---|---|
| `coverage` | 0 to 100, how much skin it hides | `foundation`, `concealer` |
| `glow` | 0 to 100, how much light it reflects | `foundation`, `highlighter`, `blush` (required for `satin`) |
| `shimmer` | 0 to 100, sparkle; 0 for none | `highlighter` |
| `gloss` | 0 to 100, shine | `lip_color` (required for `sheer` and `gloss`) |
| `transparency` | 0 to 100, how much of the lip shows through | `lip_color` (required for `sheer` and `gloss`) |
| `shape` | `eyebrows` in `shape` mode: `{ curvature: -100..100, thickness: -100..100, definition: 0..100 }`. `lip_liner`: `{ thickness: 0..100, smoothness: 0..100 }` | `eyebrows`, `lip_liner` |

## Categories

| Category | Pattern | Textures | Mode | Settings |
|---|---|---|---|---|
| `foundation` | none | none | none | `coverage`, `glow` |
| `concealer` | none | none | none | `coverage` |
| `blush` | yes | `matte`, `satin` | none | `glow` |
| `bronzer` | yes | none | none | |
| `contour` | yes | none | none | |
| `highlighter` | yes | none | none | `glow`, `shimmer` |
| `eyebrows` | in `shape` mode only | `matte` | `shape`, `color` | `shape` |
| `eye_shadow` | yes | `matte` | none | |
| `eye_liner` | yes | `matte` | none | |
| `eyelashes` | yes | none | none | |
| `lip_color` | lip shape, such as `original` | `matte`, `satin`, `sheer`, `gloss` | `full` | `gloss`, `transparency` |
| `lip_liner` | yes | `matte`, `satin` | none | `shape` |

## Rules

- **One effect per category.** When two steps render the same category, the first one wins.
- **Skin colour is never guessed.** Foundation and concealer take the colour of the person's skin (`build(steps, skin: "#RRGGBB")`). Without it they are left out of the preview.
- **Steps that don't show in a photo** (powder, setting spray, a curl, tidying up) have no effect.
- **Colours fit the pattern.** A look's colour replaces the step's default. If a pattern takes fewer colours than given, the first ones are kept; if it takes more, the last one repeats. That is how a three-colour crease, swapped for a one-colour lid wash, keeps its main shade.
- **Swaps change parameters, not just steps.** The easy version of a step keeps the look's colour and takes the easier step's own settings. For example:

| Classic step | Easier step | Effect change |
|---|---|---|
| Winged liquid liner | Smudged pencil | `eye_liner` pattern `OpenWings2` to `Smoke4`, near-black brown at 88 |
| Liquid matte lipstick and lip liner | Tinted balm | `lip_color` `matte` to `sheer`, intensity 45, gloss 35, transparency 60; no `lip_liner` |
| Strip lashes | Mascara | `eyelashes` `UpperDense1` to `Natural2` at 75 |
| Brow pencil or powder | Tinted brow gel | `eyebrows` mode `shape` to `color` |
| Two or three colour eyeshadow | One colour | `eye_shadow` to a one-colour pattern |
| Contour line | Bronzer stick | `contour` to `bronzer` |
| Liquid foundation | Tinted moisturiser | `foundation` coverage 60 to 25 |
| Powder blush | Cream blush | `blush` `matte` to `satin`, glow 30 |

## Example: the red lip, classic and easy

Classic (without a skin colour, so no foundation):

```ruby
[
  { category: "eyebrows", colour: "#3B2A20", intensity: 60, texture: "matte", pattern: "SoftArch3", mode: "shape",
    shape: { curvature: 0, thickness: 10, definition: 55 } },
  { category: "eye_liner", colour: "#111111", intensity: 90, texture: "matte", pattern: "OpenWings2", mode: nil },
  { category: "eyelashes", colour: "#000000", intensity: 85, texture: nil, pattern: "Natural2", mode: nil },
  { category: "lip_liner", colour: "#8E1424", intensity: 70, texture: "matte", pattern: "Natural1", mode: nil,
    shape: { thickness: 50, smoothness: 50 } },
  { category: "lip_color", colour: "#B0182A", intensity: 85, texture: "matte", pattern: "original", mode: "full" }
]
```

Easy version for the default hand profile:

```ruby
[
  { category: "eyebrows", colour: "#3B2A20", intensity: 45, texture: "matte", pattern: nil, mode: "color" },
  { category: "eye_liner", colour: "#2B1D16", intensity: 88, texture: "matte", pattern: "Smoke4", mode: nil },
  { category: "eyelashes", colour: "#000000", intensity: 85, texture: nil, pattern: "Natural2", mode: nil },
  { category: "lip_color", colour: "#B0182A", intensity: 45, texture: "sheer", pattern: "original", mode: "full",
    gloss: 35, transparency: 60 }
]
```

## Example: a seven effect look

Useful as a check for a provider adapter, since every category setting appears once:

```ruby
[
  { category: "foundation", colour: "#7E4A30", intensity: 35, texture: nil, pattern: nil, mode: nil,
    coverage: 35, glow: 30 },
  { category: "blush", colour: "#B5524A", intensity: 45, texture: "matte", pattern: "Oblique1", mode: nil },
  { category: "eye_shadow", colour: "#7A4E3A", intensity: 55, texture: "matte", pattern: "1color6", mode: nil },
  { category: "eye_liner", colour: "#111111", intensity: 90, texture: "matte", pattern: "OpenWings2", mode: nil },
  { category: "eyelashes", colour: "#000000", intensity: 85, texture: nil, pattern: "Natural2", mode: nil },
  { category: "eyebrows", colour: "#2B1B14", intensity: 60, texture: "matte", pattern: "SoftArch3", mode: "shape",
    shape: { curvature: 0, thickness: 10, definition: 55 } },
  { category: "lip_color", colour: "#8E1F2F", intensity: 85, texture: "matte", pattern: "original", mode: "full" }
]
```
