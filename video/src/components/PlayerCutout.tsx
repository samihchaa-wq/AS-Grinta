// Grand portrait d'un joueur au moment de sa révélation, sans carte.
//
// Les photos de l'application sont détourées : le joueur apparaît seul, dans
// la lumière, d'abord en ombre chinoise cerclée de lumière, puis éclairé.
// Une photo qui aurait encore son fond est fondue sur les bords, pour ne
// jamais ressembler à une vignette posée là. Sans photo du tout, les
// initiales reprennent le dégradé de l'application.
import React from 'react';
import {Img} from 'remotion';
import {colors, fonts} from '../theme.ts';
import type {LineupPlayer} from '../layout/lineup.ts';

export type PlayerCutoutProps = {
  player: LineupPlayer;
  size: number;
  /** 0 = ombre chinoise, 1 = joueur éclairé. */
  light: number;
  /** Apparition de la silhouette (0 → 1). */
  appear: number;
  zoom: number;
  /** Position du reflet qui balaie le joueur (0 → 1), ou null. */
  gloss: number | null;
  /** Intensité du halo et du liseré lumineux. */
  glow: number;
  /** Fondu du bas du buste : 1 pendant la révélation, 0 une fois posé. */
  fadeBottom: number;
};

export const rimColor = (player: LineupPlayer) =>
  player.isCaptain ? colors.gold : player.band === 'goalkeeper' ? colors.keeper : '#4F86FF';

const hex = (alpha: number) =>
  Math.round(Math.max(0, Math.min(1, alpha)) * 255)
    .toString(16)
    .padStart(2, '0');

export const PlayerCutout: React.FC<PlayerCutoutProps> = ({
  player,
  size,
  light,
  appear,
  zoom,
  gloss,
  glow,
  fadeBottom,
}) => {
  const rim = rimColor(player);
  const cutout = player.photoUrl !== null && player.photoHasAlpha;
  const bottomMask =
    fadeBottom > 0
      ? `linear-gradient(180deg, #000 ${100 - 22 * fadeBottom}%, transparent 100%)`
      : undefined;
  // Une photo avec son fond est fondue en ovale ; une photo détourée garde sa
  // propre forme.
  const ovalMask = 'radial-gradient(ellipse 50% 52% at 50% 46%, #000 62%, transparent 100%)';
  const shapeMask = cutout ? bottomMask : `${ovalMask}${bottomMask ? `, ${bottomMask}` : ''}`;

  const rimFilter = cutout
    ? `drop-shadow(0 0 ${size * 0.012}px ${rim}${hex(0.95 * glow)}) drop-shadow(0 0 ${size * 0.05}px ${rim}${hex(0.55 * glow)})`
    : '';

  return (
    <div style={{position: 'relative', width: size, height: size, opacity: appear}}>
      {/* Halo et faisceau dans le dos du joueur. */}
      <div
        style={{
          position: 'absolute',
          left: -size * 0.35,
          right: -size * 0.35,
          top: -size * 0.25,
          bottom: -size * 0.1,
          background: `radial-gradient(closest-side, ${rim}${hex(0.5 * glow)}, ${rim}${hex(0.16 * glow)} 55%, transparent)`,
        }}
      />
      {/* Douche de lumière venue d'en haut, sans aucun bord net. */}
      <div
        style={{
          position: 'absolute',
          left: -size * 0.1,
          right: -size * 0.1,
          top: -size * 0.75,
          height: size * 1.5,
          background: `radial-gradient(ellipse 34% 50% at 50% 42%, rgba(205,222,255,${0.2 * glow}), transparent 100%)`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: 0,
          transform: `scale(${zoom})`,
          transformOrigin: '50% 65%',
          filter: rimFilter || undefined,
        }}
      >
        <div
          style={{
            position: 'absolute',
            inset: 0,
            WebkitMaskImage: shapeMask,
            maskImage: shapeMask,
            // Ovale et fondu du bas se combinent : seul ce qui est dans les
            // deux reste visible.
            WebkitMaskComposite: 'source-in',
            maskComposite: 'intersect',
            filter: `brightness(${0.04 + 0.96 * light}) saturate(${0.6 + 0.4 * light})`,
          }}
        >
          {player.photoUrl ? (
            <Img
              src={player.photoUrl}
              style={{width: '100%', height: '100%', objectFit: 'cover', display: 'block'}}
            />
          ) : (
            <div
              style={{
                position: 'absolute',
                inset: size * 0.14,
                borderRadius: size * 0.2,
                background: `linear-gradient(135deg, ${player.avatarColors[0]}, ${player.avatarColors[1]})`,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#FFFFFF',
                fontFamily: fonts.display,
                fontWeight: 500,
                fontSize: size * 0.3,
              }}
            >
              {player.initials}
            </div>
          )}
        </div>
        {gloss !== null && player.photoUrl ? (
          <div
            style={{
              position: 'absolute',
              inset: 0,
              WebkitMaskImage: cutout ? `url("${player.photoUrl}")` : ovalMask,
              WebkitMaskSize: '100% 100%',
              background: `linear-gradient(112deg, transparent ${gloss * 150 - 45}%, rgba(255,255,255,0.42) ${gloss * 150 - 32}%, transparent ${gloss * 150 - 19}%)`,
              mixBlendMode: 'screen',
            }}
          />
        ) : null}
      </div>
    </div>
  );
};
