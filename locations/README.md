# Anchor map assets

`map_images.json` is the authoritative registry for anchor-map filenames and provenance. The GUI does not keep a second map list.

Registered images are local equirectangular maps. Each must be approximately 2:1, with longitude `-180` to `180` from left to right and latitude `90` to `-90` from top to bottom. The GUI uses its generated black-and-white latitude/longitude grid when an entry or image is unavailable.

## Catalog schema

The catalog contains `schemaVersion: 1` and a `maps` object keyed by an existing target-body key such as `mars`.

Each map entry requires:

- `fileName`: a safe path relative to this directory. URLs, absolute paths, and `..` traversal are rejected.
- `sourceDescription`: a concise description of the image's origin.
- `sourceUrl`: an optional `http` or `https` provenance URL, or `null`.
- `attribution`: the credit that applies to the image.
- `redistributionAllowed`: a JSON boolean.
- `redistributionLicense`: the license or redistribution status.

## Add or replace an image

1. Copy the image into `locations/`. Use a `.png` or another format supported by Windows `System.Drawing`.
2. Confirm the image is approximately 2:1 and uses the coordinate orientation described above.
3. Open `map_images.json`.
4. Add or update the property whose name exactly matches an existing target-body key.
5. Set `fileName` to the image's relative filename and complete every provenance field.
6. Launch the GUI, select that target, and open `Choose on map...`.

Do not add map filenames or source details to the PowerShell GUI. Add them only to `map_images.json`.
