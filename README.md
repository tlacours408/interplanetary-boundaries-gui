# Interplanetary Boundaries KML Converter

This project provides a Node.js command-line tool and a Windows GUI for
rescaling KML coordinates. The converted shapes keep their physical size
when you display them on a body with a different radius.

## The problem

KML stores plain latitude/longitude values. Those are angular coordinates,
not physical distances - one degree of longitude covers a very different
physical distance on Earth (radius ≈ 6,371 km) than it does on Mars
(radius ≈ 3,390 km). If you take a KML outline of, say, the continental
United States and display it "as-is" on a Mars basemap, the shape will
cover the same range of degrees but a much smaller physical distance,
making it look far smaller than it should relative to the size of Mars.

This tool rewrites every coordinate so the outline instead covers the same
great-circle distance (in meters) on the target body, growing (or
shrinking) the angular span as needed.

## How the scaling works

### Arc length and the centroid

For a sphere of radius `R`, the great-circle (arc) distance between two
points separated by a central angle `θ` (radians) is:

```
distance = R * θ
```

To keep `distance` (the actual physical size, in meters) constant while
`R` changes from `sourceRadius` to `targetRadius`, the central angle has to
change to match - `θ = distance / R`.

Because scaling changes angular spans, a reference point is needed. This
tool uses the polygon's centroid (geometric center, computed via
spherical geometry using n-vectors) as the reference.

### Scaling every vertex: distance and bearing from the centroid

This tool computes the centroid of the polygon and uses
it as the reference point for all scaling. For each vertex, the tool:

1. Measures the great-circle distance (in meters) and initial
   bearing (compass direction) from the centroid to that vertex, on the
   source body (radius `sourceRadius`).
2. Places a new vertex at that same physical distance and same bearing
   from the anchor point, but computed on the target body (radius
   `targetRadius`).

If no `--anchor` is supplied, the anchor defaults to the centroid itself,
and the polygon scales in place around its center. If an `--anchor`
is provided, the polygon is moved so that its centroid is the target anchor location.
This helps when moving to a smaller radius body causes the polygon to
go over a pole or wrap around the entire body (e.g., USA on the moon). Moving the anchor
closer to the equator provides greater distance for the polygon to fit within.

**Equator crossing and shape inversion**: If the anchor point is on the
opposite side of the equator from the centroid (e.g., centroid in the
northern hemisphere but anchor in the southern), the entire shape is
flipped by reversing all bearing directions (adding 180° to each bearing).
This ensures that shapes maintain sensible orientation when moved across
hemispheres. The reversal treats the opposite pole as north for the moved
shape and preserves its familiar orientation. A downstream system that can
rotate the converted shape could handle this cosmetic adjustment, but the
CLI applies it when the centroid and anchor sit on opposite sides of zero
latitude.

Altitude (a third `lon,lat,altitude` value), if present, is left
untouched - only the horizontal position is rescaled.

This is implemented with the
[`geodesy`](https://www.npmjs.com/package/geodesy) library's
`LatLonNvectorSpherical` class (using n-vectors for centroid computation and
great-circle distance/bearing/destination calculations). The centroid is
computed using `LatLon.centreOf()`, which calculates the true spherical
geometric center via 3D vector averaging.

## Requirements

- Git, Node.js, and npm for installation and conversion.
- Windows PowerShell 5.1 and Windows Forms for `kml_convert_gui.bat`.

The CLI can run anywhere Node.js and the dependencies run. The GUI targets
Windows.

## Installation

``` bash
git clone https://github.com/tlacours408/interplanetary-boundaries-gui.git
cd interplanetary-boundaries-gui
npm ci
```

Run the test suite after installation:

``` bash
npm test
```

## CLI usage

``` bash
node scale-kml.js --input <file.kml> --output <file.kml> --target-radius <meters> [options]
```

### Required arguments

| Argument | Description |
| --- | --- |
| `--input <path>` | Path to the source KML file to read. |
| `--output <path>` | Path to write the rescaled KML file. Must **not** be the same path as `--input` - the tool refuses to overwrite the input file. |
| `--target-radius <meters>` | Radius, in meters, of the body the shape should be scaled *to* (e.g. `3389500` for Mars). |

### Optional arguments

| Argument | Description |
| --- | --- |
| `--source-radius <meters>` | Radius, in meters, that the input coordinates were originally measured on. Defaults to Earth's mean radius, `6371000` m. |
| `--anchor "<lat>,<lon>"` | The location where the polygon's centroid should be placed after rescaling. If omitted, the centroid stays in place and the polygon scales uniformly around it. Example: `--anchor "5,-100"` moves the shape's center to that location. |
| `-h`, `--help` | Print usage information and exit. |

All radii are in meters. Latitude/longitude values are in decimal
degrees.

### Examples

Scale a KML outline of the continental United States from Earth to Mars,
using Mars's mean radius (3,389.5 km). The polygon scales around its own
centroid:

```
node scale-kml.js --input usa.kml --output usa-on-mars.kml --target-radius 3389500
```

Same, but move the shape's centroid to a specific location (e.g.
Washington, D.C.):

```
node scale-kml.js --input usa.kml --output usa-on-mars.kml --target-radius 3389500 --anchor "38.9,-77.0"
```

Scale from a body other than Earth (e.g. re-project a shape that was
originally measured on the Moon, radius ≈ 1,737,400 m, onto Earth):

```
node scale-kml.js --input moon-shape.kml --output shape-on-earth.kml --source-radius 1737400 --target-radius 6371000
```

## Windows GUI

Launch `kml_convert_gui.bat` from File Explorer or a terminal:

``` powershell
.\kml_convert_gui.bat
```

The launcher changes to the repository directory and starts
`kml_convert_gui.ps1`. Node.js must be available on `PATH`.

The `File` menu contains `Input File...` and `Quit`. The `Help` menu opens
the local `docs` folder through `Documentation`.

### Single-file mode

1. Keep `Single file` selected.
2. Choose an input `.kml` file and an output location.
3. Select a target object. Mars is the default.
4. Set optional radius and anchor values.
5. Choose filename and Digistar options, then select `Convert File`.

The GUI shows the generated filename before conversion. It logs the CLI
arguments, process output, and a `PASS` or `FAIL` result.

### Folder batch mode

Select `Folder batch`, then choose separate input and output folders. The
GUI processes `.kml` files in sorted order. `Include subfolders and preserve
the input folder tree` scans subfolders and recreates their relative
directories under the output folder.

The GUI validates the full batch before conversion, reports output
collisions, and asks once about output paths that existed during preflight.
It reports each file as `PASS`, `FAIL`, or `SKIP`, then prints summary counts.
One failed item does not stop later items.

### Radius controls

The GUI radius fields use kilometers. `scale-kml.js` accepts meters, so the
GUI multiplies each supplied radius by 1,000 before it starts Node.js.

`Target object` selects a built-in body from Sun through Pluto. The selected
body supplies its stored radius. A positive value in `Custom target radius
km` overrides that preset but keeps the selected body name for maps,
filenames, and Digistar generation.

Leave `Custom source radius km` blank to use the CLI Earth mean-radius
default. A positive value overrides the source radius.

### Anchor controls and maps

Enter anchor latitude and longitude together, or select `Choose on map...`.
The map picker updates both text boxes as soon as you click inside the map.
Manual changes to those text boxes also move the marker when the picker is
open. `Clear anchor` clears both fields and omits `--anchor` from the CLI
arguments.

The map picker expects a local equirectangular image with an approximate
2:1 aspect ratio. It maps longitude from `-180` to `180` left to right and
latitude from `90` to `-90` top to bottom. If the selected target has no
usable map, the picker creates a clickable black-and-white latitude and
longitude grid.

[`locations/map_images.json`](locations/map_images.json) owns map filenames
and provenance. See [locations/README.md](locations/README.md) before adding
or replacing an image. The GUI does not download map images.

### Generated filenames

The GUI rewrites output filenames with this required base:

``` text
<chosenStem>_<targetKey>_greatCircle.kml
```

It replaces runs of non-alphanumeric filename characters with underscores
and removes leading or trailing underscores. `None` omits the optional
anchor and radius components. `All` selects both `Anchor point` and
`Target radius (trKm...)`:

``` text
<chosenStem>_anchor_<latitude>_<longitude>_<targetKey>_greatCircle_trKm<radius>.kml
```

The anchor option requires both coordinates. Its token uses `negative` for a
minus sign and `point` for a decimal point. The radius token replaces the
decimal point with `p`. Folder mode uses each source filename as
`<chosenStem>`.

### Digistar script generation

`Create Digistar scripts` is off by default. To enable it, create the local
`digistar_templates` directory and add both template files:

``` text
digistar_templates/addKmlObjectToCustomPlanet.ds
digistar_templates/removeKmlObjectToCustomPlanet.ds
```

Templates can use these placeholders:

``` text
{{convertedKmlPath}}
{{targetObject}}
{{planetCopyObjectName}}
{{kmlObjectName}}
{{radiusExpression}}
```

After a successful KML conversion, the GUI writes paired `_on.ds` and
`_off.ds` files beside the converted KML. Preset radii use the Digistar
radius name `r<targetKey>`. Custom radii use a `<kilometers> km` expression.
The generator makes Digistar-safe object names and adds stable hashes when
batch items would collide.

The repository ignores the template directory and all `.ds`, `.dscp`, and
`.lis` files. Keep proprietary Digistar files local.

See [docs/gui_cli_contract.md](docs/gui_cli_contract.md) for the control,
validation, and argument contract.

## Project layout

| File | Purpose |
| --- | --- |
| `scale-kml.js` | CLI entry point: argument parsing/validation, orchestrates read → transform → write. |
| `kml_convert_gui.bat` | Windows launcher for the PowerShell GUI. |
| `kml_convert_gui.ps1` | Windows Forms UI, validation, CLI orchestration, map picker, batch processing, filenames, and Digistar generation. |
| `locations/map_images.json` | Map-image and provenance registry used by the picker. |
| `docs/gui_cli_contract.md` | GUI control-to-CLI behavior contract. |
| `lib/scale.js` | Core math: `scaleCoordinate` (per-vertex distance/bearing scaling from the polygon's centroid to each vertex, with optional bearing reversal for equator-crossing shape inversion), and `computeCentroid` (true spherical geometric center). |
| `lib/geojson-walk.js` | Recursive helper that visits every `[lon, lat]`/`[lon, lat, alt]` coordinate in a GeoJSON `FeatureCollection`, across all geometry types. |
| `lib/write-kml.js` | Minimal, dependency-free GeoJSON → KML serializer. |

## Notes and limitations

- Only latitude and longitude are rescaled; altitude values pass through
  unchanged.
- KML is read and written via a GeoJSON round-trip. Basic
  shapes (`Point`, `LineString`, `Polygon` with holes, and their `Multi*`
  variants) and each placemark's `name`/`description` are preserved;
  other KML-specific extras (styles, extended data, folders, etc.) are
  not carried through.
- Distances and bearings are computed on a spherical earth model (not an
  ellipsoidal one) using n-vectors.
- The centroid is computed using `LatLon.centreOf()`, which
  produces the true spherical geometric center rather than an arithmetic mean
  of angular coordinates.
- When an anchor point crosses the equator relative to the polygon's
  centroid (i.e., they are on opposite sides of 0° latitude), the CLI
  flips the shape by reversing all bearing directions.
