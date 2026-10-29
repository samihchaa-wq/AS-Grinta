// Le terrain de l'écran Compo, redessiné à l'identique.
//
// Portage de FootballPitchPainter (football_pitch.dart) et du cadre de
// CompositionPitch : mêmes bandes de tonte, mêmes éclairages, mêmes tracés
// aux proportions d'un terrain de 105 × 68 m. Les seuls ajouts — pénombre du
// stade, lueur des lignes, balayage lumineux — s'effacent avant la dernière
// image, qui doit se confondre avec l'application.
import React from 'react';
import {colors} from '../theme.ts';
import {
  pitchBorderWidth,
  pitchInnerRadius,
  pitchOuterRadius,
  pitchRefHeight,
  pitchRefWidth,
} from '../layout/display.ts';

const W = pitchRefWidth;
const H = pitchRefHeight;
const b = pitchBorderWidth;
// Surface peinte : l'intérieur du cadre.
const surface = {x: b, y: b, w: W - 2 * b, h: H - 2 * b};
const stripeCount = 9;
const inset = Math.min(surface.w, surface.h) * 0.045;
const pitch = {
  x: surface.x + inset,
  y: surface.y + inset,
  w: surface.w - inset * 2,
  h: surface.h - inset * 2,
};
const mx = pitch.w / 68;
const my = pitch.h / 105;
const stroke = Math.max(1.2, pitch.w * 0.005);
const centreX = pitch.x + pitch.w / 2;
const centreY = pitch.y + pitch.h / 2;

const arc = (
  cx: number,
  cy: number,
  r: number,
  start: number,
  sweep: number,
): string => {
  const x0 = cx + r * Math.cos(start);
  const y0 = cy + r * Math.sin(start);
  const x1 = cx + r * Math.cos(start + sweep);
  const y1 = cy + r * Math.sin(start + sweep);
  return `M ${x0} ${y0} A ${r} ${r} 0 ${sweep > Math.PI ? 1 : 0} 1 ${x1} ${y1}`;
};

const rectPath = (x: number, y: number, w: number, h: number) =>
  `M ${x} ${y} H ${x + w} V ${y + h} H ${x} Z`;

const markingsParts = (() => {
  const parts: string[] = [];
  parts.push(rectPath(pitch.x, pitch.y, pitch.w, pitch.h));
  parts.push(`M ${pitch.x} ${centreY} H ${pitch.x + pitch.w}`);
  const centreRadius = 9.15 * mx;
  parts.push(arc(centreX, centreY, centreRadius, 0, Math.PI));
  parts.push(arc(centreX, centreY, centreRadius, Math.PI, Math.PI));
  for (const top of [true, false]) {
    const goalLine = top ? pitch.y : pitch.y + pitch.h;
    const inward = top ? 1 : -1;
    const box = {w: 40.32 * mx, h: 16.5 * my};
    const boxCy = goalLine + (inward * box.h) / 2;
    parts.push(rectPath(centreX - box.w / 2, boxCy - box.h / 2, box.w, box.h));
    const small = {w: 18.32 * mx, h: 5.5 * my};
    const smallCy = goalLine + (inward * small.h) / 2;
    parts.push(
      rectPath(centreX - small.w / 2, smallCy - small.h / 2, small.w, small.h),
    );
    const spotY = goalLine + inward * 11 * my;
    const radius = 9.15 * mx;
    const boxGap = 5.5 * my;
    if (boxGap < radius) {
      const half = Math.asin(boxGap / radius);
      parts.push(
        arc(centreX, spotY, radius, top ? half : Math.PI + half, Math.PI - 2 * half),
      );
    }
  }
  const cornerRadius = 1.2 * mx;
  const corners: [number, number, number][] = [
    [pitch.x, pitch.y, 0],
    [pitch.x + pitch.w, pitch.y, Math.PI / 2],
    [pitch.x + pitch.w, pitch.y + pitch.h, Math.PI],
    [pitch.x, pitch.y + pitch.h, (3 * Math.PI) / 2],
  ];
  for (const [x, y, start] of corners) {
    parts.push(arc(x, y, cornerRadius, start, Math.PI / 2));
  }
  return parts;
})();
const markingsPath = markingsParts.join(' ');

const spots: [number, number][] = [
  [centreX, centreY],
  [centreX, pitch.y + 11 * my],
  [centreX, pitch.y + pitch.h - 11 * my],
];
const spotRadius = Math.max(1.6, stroke * 0.9);

/**
 * Les lignes du terrain. Pendant le dessin progressif, chaque tracé avance en
 * même temps que les autres au lieu de s'enchaîner l'un après l'autre.
 */
const Markings: React.FC<{
  draw: number;
  stroke: string;
  strokeWidth: number;
  strokeOpacity?: number;
  round?: boolean;
}> = ({draw, stroke, strokeWidth, strokeOpacity, round}) => {
  const common = {
    fill: 'none',
    stroke,
    strokeWidth,
    strokeOpacity,
    strokeLinejoin: round ? ('round' as const) : undefined,
    strokeLinecap: round ? ('round' as const) : undefined,
  };
  if (draw >= 1) return <path d={markingsPath} {...common} />;
  if (draw <= 0) return null;
  return (
    <>
      {markingsParts.map((d, index) => (
        <path
          key={index}
          d={d}
          {...common}
          pathLength={1}
          strokeDasharray="1 1"
          strokeDashoffset={1 - draw}
        />
      ))}
    </>
  );
};

export type PitchSurfaceProps = {
  /** Largeur de l'élément en pixels : sa résolution propre. */
  pixelWidth: number;
  /** Pénombre du stade posée sur la pelouse (0 = pelouse de l'application). */
  night: number;
  /** Lueur des lignes (0 = tracé de l'application). */
  glow: number;
  /** Proportion des lignes déjà tracées (dessin progressif). */
  draw: number;
  /** Opacité de la pelouse (le tracé peut apparaître avant elle). */
  turf: number;
  /** Balayage lumineux : position le long du terrain (0 = notre but, 1 = attaque). */
  sweep: number | null;
  sweepStrength?: number;
  id: string;
};

export const PitchSurface: React.FC<PitchSurfaceProps> = ({
  pixelWidth,
  night,
  glow,
  draw,
  turf,
  sweep,
  sweepStrength = 1,
  id,
}) => {
  const stripeHeight = surface.h / stripeCount;
  const sweepY = sweep === null ? null : surface.y + surface.h * (1 - sweep);
  return (
    <svg
      width={pixelWidth}
      height={(pixelWidth * H) / W}
      viewBox={`0 0 ${W} ${H}`}
      style={{display: 'block', overflow: 'visible'}}
    >
      <defs>
        <clipPath id={`${id}-clip`}>
          <rect
            x={surface.x}
            y={surface.y}
            width={surface.w}
            height={surface.h}
            rx={pitchInnerRadius}
          />
        </clipPath>
        <linearGradient id={`${id}-light`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#FFFFFF" stopOpacity={0x1f / 255} />
          <stop offset="0.45" stopColor="#FFFFFF" stopOpacity={0} />
          <stop offset="1" stopColor="#000000" stopOpacity={0x1a / 255} />
        </linearGradient>
        <radialGradient
          id={`${id}-vignette`}
          gradientUnits="userSpaceOnUse"
          cx={surface.x + surface.w / 2}
          cy={surface.y + surface.h / 2}
          r={0.9 * Math.min(surface.w, surface.h)}
        >
          <stop offset="0.35" stopColor="#000000" stopOpacity={0} />
          <stop offset="0.65" stopColor="#000000" stopOpacity={0x0f / 255} />
          <stop offset="1" stopColor="#000000" stopOpacity={0x73 / 255} />
        </radialGradient>
        {sweepY !== null ? (
          <linearGradient
            id={`${id}-sweep`}
            gradientUnits="userSpaceOnUse"
            x1="0"
            y1={sweepY - 70}
            x2="0"
            y2={sweepY + 70}
          >
            <stop offset="0" stopColor="#BFD3FF" stopOpacity={0} />
            <stop offset="0.5" stopColor="#E8F0FF" stopOpacity={0.42 * sweepStrength} />
            <stop offset="1" stopColor="#BFD3FF" stopOpacity={0} />
          </linearGradient>
        ) : null}
        <filter id={`${id}-glow`} x="-10%" y="-10%" width="120%" height="120%">
          <feGaussianBlur stdDeviation="2.4" />
        </filter>
      </defs>

      <g opacity={turf}>
        <rect x={0} y={0} width={W} height={H} rx={pitchOuterRadius} fill={colors.pitchFill} />
        <g clipPath={`url(#${id}-clip)`}>
          <rect x={surface.x} y={surface.y} width={surface.w} height={surface.h} fill={colors.turfDark} />
          {Array.from({length: Math.ceil(stripeCount / 2)}, (_, k) => (
            <rect
              key={k}
              x={surface.x}
              y={surface.y + 2 * k * stripeHeight}
              width={surface.w}
              height={stripeHeight}
              fill={colors.turfLight}
            />
          ))}
          <rect x={surface.x} y={surface.y} width={surface.w} height={surface.h} fill={`url(#${id}-light)`} />
          <rect x={surface.x} y={surface.y} width={surface.w} height={surface.h} fill={`url(#${id}-vignette)`} />
          {night > 0 ? (
            <rect
              x={surface.x}
              y={surface.y}
              width={surface.w}
              height={surface.h}
              fill="#020814"
              opacity={night}
            />
          ) : null}
        </g>
      </g>

      <g clipPath={`url(#${id}-clip)`}>
        {glow > 0 ? (
          <g opacity={0.55 * glow} filter={`url(#${id}-glow)`}>
            <Markings draw={draw} stroke="#CFE0FF" strokeWidth={stroke * 3.2} />
          </g>
        ) : null}
        <Markings
          draw={draw}
          stroke="#FFFFFF"
          strokeOpacity={0x26 / 255}
          strokeWidth={stroke * 3}
          round
        />
        <Markings
          draw={draw}
          stroke="#FFFFFF"
          strokeOpacity={0x33 / 255}
          strokeWidth={stroke * 1.9}
          round
        />
        <Markings
          draw={draw}
          stroke="#FFFFFF"
          strokeOpacity={0xe8 / 255}
          strokeWidth={stroke}
        />
        {spots.map(([x, y], index) => (
          <circle
            key={index}
            cx={x}
            cy={y}
            r={spotRadius}
            fill="#FFFFFF"
            fillOpacity={(0xe8 / 255) * Math.min(1, draw * 1.5)}
          />
        ))}
        {sweepY !== null ? (
          <rect
            x={surface.x}
            y={surface.y}
            width={surface.w}
            height={surface.h}
            fill={`url(#${id}-sweep)`}
            style={{mixBlendMode: 'screen'}}
          />
        ) : null}
      </g>

      <rect
        x={b / 2}
        y={b / 2}
        width={W - b}
        height={H - b}
        rx={pitchOuterRadius - b / 2}
        fill="none"
        stroke={colors.pitchBorder}
        strokeWidth={b}
        opacity={turf}
      />
    </svg>
  );
};
