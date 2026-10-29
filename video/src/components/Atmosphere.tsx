// Le stade de nuit : fond bleu nuit, projecteurs, poussière dans la lumière.
// Tout est dessiné en dégradés, sans flou coûteux : le rendu reste rapide.
import React from 'react';
import {random} from 'remotion';
import {colors, video} from '../theme.ts';

const particles = Array.from({length: 38}, (_, i) => ({
  x: random(`px${i}`),
  y: random(`py${i}`),
  depth: random(`pd${i}`),
  drift: random(`pv${i}`),
  phase: random(`pp${i}`) * Math.PI * 2,
}));

export type AtmosphereProps = {
  frame: number;
  /** Présence des projecteurs (0 = noir complet). */
  lights: number;
  /** Ligne d'horizon du stade à l'écran (lueur des tribunes), ou null. */
  horizonY: number | null;
  /** Fondu vers le simple bleu nuit de l'application. */
  calm: number;
};

export const Atmosphere: React.FC<AtmosphereProps> = ({frame, lights, horizonY, calm}) => {
  const {width, height} = video;
  const live = lights * (1 - calm);
  const sway = Math.sin(frame / 38) * 40;
  return (
    <div style={{position: 'absolute', inset: 0, overflow: 'hidden', background: colors.abyss}}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: `linear-gradient(180deg, ${colors.abyss} 0%, ${colors.night} 52%, #06182F 100%)`,
          opacity: lights,
        }}
      />
      {/* Projecteurs : deux faisceaux qui descendent des coins du stade. */}
      {[-1, 1].map((side) => (
        <div
          key={side}
          style={{
            position: 'absolute',
            left: side < 0 ? -420 + sway : width - 760 - sway,
            top: -620,
            width: 1180,
            height: 2900,
            background: `conic-gradient(from ${side < 0 ? 150 : 175}deg at ${side < 0 ? '35%' : '65%'} 18%, transparent 0deg, rgba(150,185,255,0.10) 14deg, transparent 32deg)`,
            // Le faisceau s'éteint en descendant : aucun bord visible.
            WebkitMaskImage: 'linear-gradient(180deg, #000 0%, #000 40%, transparent 85%)',
            opacity: live,
          }}
        />
      ))}
      <div
        style={{
          position: 'absolute',
          left: -200,
          right: -200,
          top: -380,
          height: 900,
          background: `radial-gradient(ellipse at 50% 40%, rgba(70,110,230,0.30), transparent 62%)`,
          opacity: live,
        }}
      />
      {horizonY !== null ? (
        <div
          style={{
            position: 'absolute',
            left: -100,
            right: -100,
            top: horizonY - 260,
            height: 520,
            background:
              'radial-gradient(ellipse 60% 40% at 50% 50%, rgba(120,160,255,0.22), transparent 70%)',
            opacity: live,
          }}
        />
      ) : null}
      {particles.map((p, i) => {
        const speed = 0.4 + p.drift * 1.1;
        const y = ((p.y * height - frame * speed * (0.6 + p.depth)) % height + height) % height;
        const x = p.x * width + Math.sin(frame / 50 + p.phase) * 18 * (1 + p.depth);
        const size = 3 + p.depth * 9;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: x - size,
              top: y - size,
              width: size * 2,
              height: size * 2,
              borderRadius: '50%',
              background: `radial-gradient(closest-side, rgba(200,220,255,${0.55 - p.depth * 0.3}), transparent)`,
              opacity: live * (0.35 + 0.65 * (0.5 + 0.5 * Math.sin(frame / 25 + p.phase))),
            }}
          />
        );
      })}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: 'radial-gradient(ellipse 85% 70% at 50% 45%, transparent 55%, rgba(0,0,0,0.6) 100%)',
          opacity: 1 - calm,
        }}
      />
      <div
        style={{position: 'absolute', inset: 0, background: colors.night, opacity: calm}}
      />
    </div>
  );
};
