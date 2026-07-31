// LatLonNvectorSpherical provides distance, bearing, and destination-point
// calculations using n-vectors (3D unit vectors normal to the Earth's surface).
// This approach avoids singularities at poles and computes true spherical
// centroids via vector averaging instead of naive arithmetic mean of angles.
import LatLon from "geodesy/latlon-nvector-spherical.js";
import { walkFeatureCollection } from "./geojson-walk.js";

// Mean radius of Earth in meters - used as the default --source-radius.
const EARTH_MEAN_RADIUS_METERS = 6371000;

/**
 * Computes the centroid (true spherical geometric center) of all coordinates
 * in a FeatureCollection using n-vectors. This is more accurate than arithmetic
 * mean of angular coordinates, especially for large polygons or those far from
 * the equator. N-vectors avoid singularities at poles.
 *
 * @param {Object} featureCollection - GeoJSON FeatureCollection
 * @returns {{lat: number, lon: number}} centroid coordinates
 */
function computeCentroid(featureCollection) {
  const points = [];

  function visitCoord(coord) {
    // GeoJSON uses [lon, lat]; LatLon constructor expects (lat, lon)
    points.push(new LatLon(coord[1], coord[0]));
  }

  walkFeatureCollection(featureCollection, visitCoord);

  if (points.length === 0) {
    return { lat: 0, lon: 0 };
  }

  const centre = LatLon.centreOf(points);
  return { lat: centre.lat, lon: centre.lon };
}

/**
 * Scales a single [lon, lat] coordinate so that its great-circle distance
 * and direction *from the centroid* are preserved when moving from a body of
 * `sourceRadius` to a body of `targetRadius`.
 *
 * The centroid of the polygon is computed separately and passed in. For each
 * vertex, we measure the great-circle distance and bearing from the centroid
 * to that vertex on the source body. We then place a new vertex at that same
 * scaled distance and bearing from the anchor point on the target body.
 *
 * If no explicit anchor is provided, the anchor will be the centroid itself,
 * and the polygon scales in place. If an anchor is provided, the polygon is
 * effectively translated so that its centroid moves to the anchor location.
 *
 * If the anchor crosses the equator relative to the centroid (i.e., they are
 * on opposite sides of 0° latitude), the shape is flipped by reversing all
 * bearings (adding 180° to each bearing direction).
 *
 * @param {number} lon - input longitude, degrees
 * @param {number} lat - input latitude, degrees
 * @param {{lat: number, lon: number}} centroid - centroid of the polygon
 * @param {{lat: number, lon: number}} anchor - point to treat as the new centroid location
 * @param {number} sourceRadius - radius of the body the input was measured on, meters
 * @param {number} targetRadius - radius of the destination body, meters
 * @param {boolean} flipShape - if true, reverse bearing direction by 180°
 * @returns {[number, number]} [newLon, newLat] in degrees
 */
function scaleCoordinate(lon, lat, centroid, anchor, sourceRadius, targetRadius, flipShape = false) {
  const centroidPoint = new LatLon(centroid.lat, centroid.lon);
  const vertexPoint = new LatLon(lat, lon);

  // If vertex is at the centroid, it doesn't move (relative to the new centroid).
  if (centroidPoint.equals(vertexPoint)) {
    return [anchor.lon, anchor.lat];
  }

  // Measure distance and bearing from centroid to vertex on source body.
  const distanceMeters = centroidPoint.distanceTo(vertexPoint, sourceRadius);
  let bearingDeg = centroidPoint.initialBearingTo(vertexPoint);

  // If flipping, reverse the bearing direction.
  if (flipShape) {
    bearingDeg = (bearingDeg + 180) % 360;
  }

  // Place the vertex at the same distance and bearing from the anchor on target body.
  const anchorPoint = new LatLon(anchor.lat, anchor.lon);
  const destination = anchorPoint.destinationPoint(distanceMeters, bearingDeg, targetRadius);

  return [destination.lon, destination.lat];
}

export { EARTH_MEAN_RADIUS_METERS, scaleCoordinate, computeCentroid };
