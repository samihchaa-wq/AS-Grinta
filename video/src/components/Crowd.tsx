// Le public en tribune, derrière le but adverse.
//
// Des silhouettes anonymes, dessinées : aucune vraie personne. Les gradins
// montent en rangées serrées ; certains supporters lèvent leur téléphone,
// d'autres une écharpe aux couleurs du club, et les flashs des photos
// crépitent pendant toute la présentation. La tribune est légèrement floue,
// comme filmée avec peu de profondeur de champ : l'œil reste sur les joueurs.
import React, {useMemo} from 'react';
import {random} from 'remotion';
import {colors, video} from '../theme.ts';

type Fan = {
  row: number;
  x: number;
  y: number;
  size: number;
  shade: number;
  phone: boolean;
  scarf: 'gold' | 'royal' | null;
  arms: boolean;
  phase: number;
};

type Row = {y: number; size: number};

const rowCount = 8;

const buildRows = (): Row[] => {
  const rows: Row[] = [];
  let y = 0;
  for (let row = 0; row < rowCount; row += 1) {
    const size = 112 * Math.pow(0.84, row);
    rows.push({y, size});
    y -= size * 0.56;
  }
  return rows;
};

/** Les supporters, rangée par rangée, de la plus proche à la plus haute. */
const buildFans = (rows: Row[]): Fan[] => {
  const fans: Fan[] = [];
  rows.forEach(({y, size}, row) => {
    const spacing = size * 0.68;
    const count = Math.ceil((video.width + 240) / spacing);
    const offset = random(`row-${row}`) * spacing;
    for (let i = 0; i < count; i += 1) {
      const seed = `fan-${row}-${i}`;
      const scarf = random(`${seed}-f`);
      fans.push({
        row,
        x: -120 + offset + i * spacing + (random(`${seed}-x`) - 0.5) * spacing * 0.5,
        y: y + (random(`${seed}-y`) - 0.5) * size * 0.14,
        size: size * (0.86 + random(`${seed}-s`) * 0.28),
        shade: random(`${seed}-c`),
        phone: random(`${seed}-p`) < 0.05,
        scarf: scarf < 0.025 ? 'gold' : scarf < 0.05 ? 'royal' : null,
        arms: random(`${seed}-a`) < 0.06,
        phase: random(`${seed}-t`) * Math.PI * 2,
      });
    }
  });
  // Les plus lointains d'abord : les plus proches les masquent en partie.
  return fans.reverse();
};

type Flash = {start: number; x: number; row: number; size: number};

/** Flashs d'appareils photo, tirés une fois pour toute la vidéo. */
const buildFlashes = (duration: number): Flash[] =>
  Array.from({length: Math.round(duration * 0.2)}, (_, i) => ({
    start: Math.floor(random(`flash-t-${i}`) * duration),
    x: 40 + random(`flash-x-${i}`) * (video.width - 80),
    row: Math.floor(random(`flash-r-${i}`) * rowCount),
    size: 0.8 + random(`flash-s-${i}`) * 0.7,
  }));

/** Tête et épaules : un supporter vu de face, sans visage. */
const fanPath = (x: number, y: number, s: number) => {
  const head = s * 0.17;
  const shoulders = s * 0.42;
  const neckY = y + s * 0.2;
  return (
    `M ${x - shoulders} ${y + s * 0.7} ` +
    `C ${x - shoulders} ${neckY + s * 0.02} ${x - shoulders * 0.55} ${neckY} ${x - head * 0.8} ${neckY} ` +
    `L ${x + head * 0.8} ${neckY} ` +
    `C ${x + shoulders * 0.55} ${neckY} ${x + shoulders} ${neckY + s * 0.02} ${x + shoulders} ${y + s * 0.7} Z ` +
    `M ${x - head} ${y} a ${head} ${head * 1.15} 0 1 0 ${head * 2} 0 a ${head} ${head * 1.15} 0 1 0 ${-head * 2} 0 Z`
  );
};

export type CrowdProps = {
  frame: number;
  duration: number;
  /** Bas de la tribune à l'écran : le bord du terrain le plus lointain. */
  baseY: number;
  /** Présence de la tribune (0 = invisible). */
  presence: number;
};

export const Crowd: React.FC<CrowdProps> = ({frame, duration, baseY, presence}) => {
  const rows = useMemo(buildRows, []);
  const fans = useMemo(() => buildFans(rows), [rows]);
  const flashes = useMemo(() => buildFlashes(duration), [duration]);
  if (presence <= 0.001) return null;
  const standTop = rows[rows.length - 1].y - rows[rows.length - 1].size;

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        top: 0,
        width: video.width,
        height: video.height,
        opacity: presence,
      }}
    >
      <svg
        width={video.width}
        height={video.height}
        style={{position: 'absolute', left: 0, top: 0, filter: 'blur(1.1px)'}}
      >
        <defs>
          {/* Contre-jour des projecteurs : haut des silhouettes éclairé. */}
          <linearGradient id="fan-light" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#3C5C9C" />
            <stop offset="0.35" stopColor="#14284F" />
            <stop offset="1" stopColor="#060E1E" />
          </linearGradient>
          <linearGradient id="stand-haze" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#0B1B38" stopOpacity="0" />
            <stop offset="0.25" stopColor="#14305E" stopOpacity="0.85" />
            <stop offset="1" stopColor="#0A1A33" stopOpacity="1" />
          </linearGradient>
        </defs>
        <g transform={`translate(0 ${baseY - 30})`}>
          {/* Les gradins eux-mêmes, dans le voile lumineux des projecteurs. */}
          <rect
            x={0}
            y={standTop - 120}
            width={video.width}
            height={-standTop + 160}
            fill="url(#stand-haze)"
          />
          {fans.map((fan, index) => {
            // Le public vit : chacun bouge un peu, à son rythme.
            const bob = Math.sin(frame / 8 + fan.phase) * fan.size * 0.025;
            const y = fan.y + bob;
            const haze = fan.row / rowCount;
            return (
              <g key={index} opacity={1 - haze * 0.35}>
                {fan.arms ? (
                  <path
                    d={`M ${fan.x - fan.size * 0.3} ${y + fan.size * 0.3} L ${fan.x - fan.size * 0.42} ${y - fan.size * (0.45 + 0.08 * Math.sin(frame / 5 + fan.phase))} M ${fan.x + fan.size * 0.3} ${y + fan.size * 0.3} L ${fan.x + fan.size * 0.42} ${y - fan.size * (0.45 + 0.08 * Math.cos(frame / 5 + fan.phase))}`}
                    stroke="#0B1730"
                    strokeWidth={fan.size * 0.09}
                    strokeLinecap="round"
                  />
                ) : null}
                <path d={fanPath(fan.x, y, fan.size)} fill="url(#fan-light)" />
                {fan.scarf ? (
                  <rect
                    x={fan.x - fan.size * 0.6}
                    y={y - fan.size * (0.42 + 0.06 * Math.sin(frame / 6 + fan.phase))}
                    width={fan.size * 1.2}
                    height={fan.size * 0.13}
                    rx={fan.size * 0.03}
                    fill={fan.scarf === 'gold' ? colors.gold : colors.royal}
                    opacity={0.85}
                  />
                ) : null}
                {fan.phone ? (
                  <>
                    <line
                      x1={fan.x + fan.size * 0.25}
                      y1={y + fan.size * 0.32}
                      x2={fan.x + fan.size * 0.3}
                      y2={y - fan.size * 0.22}
                      stroke="#0B1730"
                      strokeWidth={fan.size * 0.09}
                      strokeLinecap="round"
                    />
                    <rect
                      x={fan.x + fan.size * 0.2}
                      y={y - fan.size * 0.52}
                      width={fan.size * 0.18}
                      height={fan.size * 0.3}
                      rx={fan.size * 0.03}
                      fill="#E3ECFF"
                      opacity={0.75 + 0.25 * Math.sin(frame / 12 + fan.phase)}
                    />
                  </>
                ) : null}
              </g>
            );
          })}
        </g>
      </svg>
      {/* Flashs : un éclat bref, avec la croix de diffraction des objectifs. */}
      {flashes.map((flash, index) => {
        const age = frame - flash.start;
        if (age < 0 || age > 5) return null;
        const intensity = [1, 0.7, 0.42, 0.22, 0.1, 0.04][age];
        const row = rows[flash.row];
        const x = flash.x;
        const y = baseY - 30 + row.y - row.size * 0.1;
        const s = row.size * 0.55 * flash.size;
        return (
          <div key={index} style={{position: 'absolute', left: 0, top: 0, opacity: intensity}}>
            <div
              style={{
                position: 'absolute',
                left: x - s * 2,
                top: y - s * 2,
                width: s * 4,
                height: s * 4,
                borderRadius: '50%',
                background:
                  'radial-gradient(closest-side, rgba(255,255,255,1) 0%, rgba(235,242,255,0.8) 14%, rgba(170,200,255,0.25) 42%, transparent 100%)',
              }}
            />
            <div
              style={{
                position: 'absolute',
                left: x - s * 3.5,
                top: y - 1.5,
                width: s * 7,
                height: 3,
                background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.95), transparent)',
              }}
            />
            <div
              style={{
                position: 'absolute',
                left: x - 1.5,
                top: y - s * 2.2,
                width: 3,
                height: s * 4.4,
                background: 'linear-gradient(180deg, transparent, rgba(255,255,255,0.8), transparent)',
              }}
            />
          </div>
        );
      })}
    </div>
  );
};
