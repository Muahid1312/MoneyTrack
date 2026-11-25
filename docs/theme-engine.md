# MoneyTrack theme engine

Open **Settings → Appearance** or search for **Appearance** in More. Light, Dark and System are independent of the accent. The palette starts with Emerald (`#09694F`) and includes Ocean Blue, Midnight Navy, Royal Purple, Crimson Red, Sunset Orange, Teal, Graphite, Rose, Indigo, Forest Green and Obsidian.

Presets and recent colors apply immediately. The custom editor previews its draft with a saturation and brightness spectrum, three sliders and a six-digit HEX field. Apply saves the draft throughout the app. Reset returns the accent to Emerald. The preview uses sample amounts.

`AppAccent` stores the selected opaque seed and up to six recent colors. `AccentPalette` derives the accessible primary, primary foreground, surface and surface foreground, and the deep balance-card background. `AppPalette` supplies neutral surfaces and the income, expense, warning and success roles. Applied color schemes keep those financial roles stable. Balance cards, buttons, navigation, filters, keypad actions, budget and savings progress, and fund accents draw from the shared tokens.

Riverpod supplies the theme to both brightness modes. Accent preferences use one SharedPreferences value so the selection and recent list are persisted together. Mode and language have their own settings. The encrypted portable snapshot includes these preferences and validates their values on restore. Older backups fall back to the normal defaults for absent keys. Appearance requires no SQLite migration.
