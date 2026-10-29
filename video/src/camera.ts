// Caméra virtuelle : le terrain est un plan filmé par une caméra à sténopé.
//
// L'image d'un plan par une telle caméra est une homographie. On la donne
// telle quelle au navigateur (matrix3d) pour déformer le dessin du terrain,
// et on l'applique aux joueurs pour les poser exactement au bon endroit.
// Vue de dessus (inclinaison de 90°), l'homographie devient une simple mise à
// l'échelle : c'est la vue de l'écran Compo de l'application.
import {pitchRefHeight, pitchRefWidth} from './layout/display.ts';

export type Camera = {
  /** Inclinaison sous l'horizontale, en degrés (90 = vue de dessus). */
  tilt: number;
  /** Point visé, en unités du terrain, depuis le centre du terrain. */
  targetX: number;
  targetY: number;
  /** Distance entre la caméra et le point visé, en unités du terrain. */
  distance: number;
  /** Focale, en pixels de la vidéo. */
  focal: number;
  /** Centre optique dans l'image. */
  centerX: number;
  centerY: number;
  /** Rotation autour de la verticale, en degrés (léger mouvement latéral). */
  yaw?: number;
};

type Vec3 = [number, number, number];
const dot = (a: Vec3, b: Vec3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

const basis = (camera: Camera) => {
  const a = (camera.tilt * Math.PI) / 180;
  const yaw = ((camera.yaw ?? 0) * Math.PI) / 180;
  // Sans lacet : regard vers l'attaque (y décroissant) et vers le sol.
  const forward0: Vec3 = [0, -Math.cos(a), -Math.sin(a)];
  const up0: Vec3 = [0, -Math.sin(a), Math.cos(a)];
  const right0: Vec3 = [1, 0, 0];
  // Lacet autour de l'axe vertical du monde.
  const rot = (v: Vec3): Vec3 => [
    v[0] * Math.cos(yaw) - v[1] * Math.sin(yaw),
    v[0] * Math.sin(yaw) + v[1] * Math.cos(yaw),
    v[2],
  ];
  const forward = rot(forward0);
  const up = rot(up0);
  const right = rot(right0);
  const target: Vec3 = [camera.targetX, camera.targetY, 0];
  const position: Vec3 = [
    target[0] - camera.distance * forward[0],
    target[1] - camera.distance * forward[1],
    target[2] - camera.distance * forward[2],
  ];
  return {forward, up, right, position};
};

/** Homographie 3 × 3 (lignes) du repère du terrain (0..340, 0..500) vers l'image. */
export const pitchHomography = (camera: Camera): number[][] => {
  const {forward: F, up: U, right: R, position: C} = basis(camera);
  const f = camera.focal;
  const cx = camera.centerX;
  const cy = camera.centerY;
  const rowU = [
    f * R[0] + cx * F[0],
    f * R[1] + cx * F[1],
    -f * dot(R, C) - cx * dot(F, C),
  ];
  const rowV = [
    -f * U[0] + cy * F[0],
    -f * U[1] + cy * F[1],
    f * dot(U, C) - cy * dot(F, C),
  ];
  const rowW = [F[0], F[1], -dot(F, C)];
  // Le repère du terrain a son origine dans le coin haut-gauche.
  const ox = -pitchRefWidth / 2;
  const oy = -pitchRefHeight / 2;
  const shift = (row: number[]) => [row[0], row[1], row[0] * ox + row[1] * oy + row[2]];
  return [shift(rowU), shift(rowV), shift(rowW)];
};

export type Projected = {x: number; y: number; scale: number; depth: number};

/** Projette un point du terrain ; `scale` vaut 1 à la distance de référence. */
export const project = (
  h: number[][],
  px: number,
  py: number,
  referenceDepth: number,
): Projected => {
  const w = h[2][0] * px + h[2][1] * py + h[2][2];
  return {
    x: (h[0][0] * px + h[0][1] * py + h[0][2]) / w,
    y: (h[1][0] * px + h[1][1] * py + h[1][2]) / w,
    scale: referenceDepth / w,
    depth: w,
  };
};

/**
 * Transformation CSS d'un élément de `elementWidth` pixels de large dessinant
 * le terrain : sa résolution propre est indépendante de la taille à l'écran.
 */
export const cssMatrix3d = (h: number[][], elementWidth: number): string => {
  const k = pitchRefWidth / elementWidth;
  // Homographie appliquée après la mise à l'échelle de l'élément.
  const m = h.map((row) => [row[0] * k, row[1] * k, row[2]]);
  const values = [
    m[0][0], m[1][0], 0, m[2][0],
    m[0][1], m[1][1], 0, m[2][1],
    0, 0, 1, 0,
    m[0][2], m[1][2], 0, m[2][2],
  ];
  return `matrix3d(${values.map((v) => v.toFixed(9)).join(',')})`;
};

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

export const mixCameras = (a: Camera, b: Camera, t: number): Camera => ({
  tilt: lerp(a.tilt, b.tilt, t),
  targetX: lerp(a.targetX, b.targetX, t),
  targetY: lerp(a.targetY, b.targetY, t),
  distance: lerp(a.distance, b.distance, t),
  focal: lerp(a.focal, b.focal, t),
  centerX: lerp(a.centerX, b.centerX, t),
  centerY: lerp(a.centerY, b.centerY, t),
  yaw: lerp(a.yaw ?? 0, b.yaw ?? 0, t),
});
