#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { DOMParser } from "@xmldom/xmldom";
import { kml as kmlToGeoJSON } from "@tmcw/togeojson";

import { walkFeatureCollection } from "./lib/geojson-walk.js";
import { featureCollectionToKml } from "./lib/write-kml.js";
import { EARTH_MEAN_RADIUS_METERS, scaleCoordinate, computeCentroid } from "./lib/scale.js";

const USAGE = `
Usage: node scale-kml.js --input <file.kml> --output <file.kml> --target-radius <meters> [options]

Rescales every coordinate in a KML file so that great-circle distances (and
therefore the physical size of the shapes) are preserved when the same
lat/lon values are displayed on a body with a different radius.

Required:
  --input <path>            Path to the source KML file.
  --output <path>            Path to write the rescaled KML file. Must not
                              be the same file as --input.
  --target-radius <meters>   Radius of the destination body, in meters.

Optional:
  --source-radius <meters>   Radius the input coordinates were measured on.
                              Defaults to Earth's mean radius (${EARTH_MEAN_RADIUS_METERS} m).
  --anchor "<lat>,<lon>"     Point that stays fixed while every other
                              coordinate is rescaled around it. Defaults to
                              the centroid (geometric center) of all coordinates.
  -h, --help                 Show this help message.
`;

function fail(message) {
  console.error(`Error: ${message}`);
  console.error(USAGE);
  process.exit(1);
}

function parseArgs(argv) {
  const args = { sourceRadius: EARTH_MEAN_RADIUS_METERS };

  for (let i = 0; i < argv.length; i++) {
    const token = argv[i];
    switch (token) {
      case "--input":
        args.input = argv[++i];
        break;
      case "--output":
        args.output = argv[++i];
        break;
      case "--source-radius":
        args.sourceRadius = Number(argv[++i]);
        break;
      case "--target-radius":
        args.targetRadius = Number(argv[++i]);
        break;
      case "--anchor":
        args.anchorRaw = argv[++i];
        break;
      case "-h":
      case "--help":
        args.help = true;
        break;
      default:
        fail(`Unknown argument "${token}"`);
    }
  }

  return args;
}

function parseAnchor(anchorRaw) {
  const parts = anchorRaw.split(",").map((part) => Number(part.trim()));
  if (parts.length !== 2 || parts.some((value) => !Number.isFinite(value))) {
    fail(`--anchor must be "lat,lon" with two numbers, got "${anchorRaw}"`);
  }
  const [lat, lon] = parts;
  if (lat < -90 || lat > 90) fail(`--anchor latitude ${lat} is out of range [-90, 90]`);
  if (lon < -180 || lon > 180) fail(`--anchor longitude ${lon} is out of range [-180, 180]`);
  return { lat, lon };
}

function validateArgs(args) {
  if (args.help) {
    console.log(USAGE);
    process.exit(0);
  }
  if (!args.input) fail("--input is required");
  if (!args.output) fail("--output is required");
  if (!fs.existsSync(args.input)) fail(`Input file not found: ${args.input}`);
  if (path.resolve(args.input) === path.resolve(args.output)) {
    fail("--output must not be the same file as --input (overwriting the input is not allowed)");
  }
  if (!Number.isFinite(args.sourceRadius) || args.sourceRadius <= 0) {
    fail(`--source-radius must be a positive number, got "${args.sourceRadius}"`);
  }
  if (!args.targetRadius) fail("--target-radius is required");
  if (!Number.isFinite(args.targetRadius) || args.targetRadius <= 0) {
    fail(`--target-radius must be a positive number, got "${args.targetRadius}"`);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  validateArgs(args);

  const anchorOverride = args.anchorRaw ? parseAnchor(args.anchorRaw) : null;

  // ---- Read + parse the input KML into GeoJSON ----
  const kmlText = fs.readFileSync(args.input, "utf8");
  const kmlDom = new DOMParser().parseFromString(kmlText, "text/xml");
  const geojson = kmlToGeoJSON(kmlDom);

  if (!geojson.features || geojson.features.length === 0) {
    fail("No features with coordinates were found in the input KML.");
  }

  // ---- Compute the centroid of the polygon (always used as reference) ----
  const centroid = computeCentroid(geojson);

  // ---- Determine where the centroid should move to (default: stay in place) ----
  let anchor = anchorOverride || centroid;

  // ---- Check if anchor crosses the equator (flip shape if it does) ----
  const flipShape = (centroid.lat >= 0 && anchor.lat < 0) || (centroid.lat < 0 && anchor.lat >= 0);

  // Scale factor, shown for informational purposes only - the actual
  // scaling is done per-vertex in scaleCoordinate() using sourceRadius and
  // targetRadius directly (see lib/scale.js).
  const k = args.sourceRadius / args.targetRadius;

  // ---- Rescale every coordinate in place, relative to the centroid ----
  walkFeatureCollection(geojson, (coord) => {
    const [newLon, newLat] = scaleCoordinate(coord[0], coord[1], centroid, anchor, args.sourceRadius, args.targetRadius, flipShape);
    coord[0] = newLon;
    coord[1] = newLat;
    // coord[2] (altitude), if present, is left untouched.
  });

  // ---- Write the result back out as KML ----
  const outputKml = featureCollectionToKml(geojson);
  fs.writeFileSync(args.output, outputKml, "utf8");

  console.log(`Scaled KML written to ${args.output}`);
  console.log(`Centroid: lat=${centroid.lat}, lon=${centroid.lon}`);
  console.log(`Anchor: lat=${anchor.lat}, lon=${anchor.lon}`);
  if (flipShape) {
    console.log(`Shape flipped (crosses equator)`);
  }
  console.log(`Scale factor (sourceRadius / targetRadius): ${k}`);
}

main();
