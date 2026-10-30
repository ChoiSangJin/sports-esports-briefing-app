# Launcher icon

The launcher uses one cyan ball on a dark background. The approved generated
foreground is `assets/branding/ball-foreground.png`; the opaque preview is
`assets/branding/sports-at-a-glance.png`.

Run `scripts/generate_launcher_icons.sh` with ImageMagick 7 to package the artwork
for all five Android densities. Alpha bounds ignore faint stray pixels when
centering. Legacy icons use a two-thirds-size ball. Adaptive foregrounds use a
56dp ball on a 108dp transparent canvas, inside Android's central 66dp safe zone.
Do not add another inset to the foreground drawable.

Android 26+ uses the adaptive foreground/background pair. Android 33+ additionally
supplies a monochrome vector for themed launchers. The manifest's normal and round
icon attributes both reference the density-aware launcher resource. The app's
name, package ID, and release signing key stay the same for upgrade installs.
