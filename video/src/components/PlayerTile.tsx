// Vignette d'un joueur posé sur le terrain.
//
// En fin de vidéo (`app` = 1), elle reproduit CompositionPlayerTile : photo
// de 52 aux coins arrondis à 28 %, ou initiales sur dégradé dans un carré à
// 84 %, prénom en Roboto 11 sur une étiquette bleu nuit. Avant cela, la même
// vignette est mise en scène dans le stade : plus grande, éclairée, posée sur
// un halo au sol.
import React from 'react';
import {Img} from 'remotion';
import {measureText} from '@remotion/layout-utils';
import {colors, fonts} from '../theme.ts';
import {
  initialsScale,
  nameLabelFontSize,
  nameLabelPadding,
  photoRadiusRatio,
  photoSize,
} from '../layout/display.ts';
import type {LineupPlayer} from '../layout/lineup.ts';

export type TileProps = {
  player: LineupPlayer;
  /** Centre de la photo à l'écran. */
  x: number;
  y: number;
  /** Pixels par unité du terrain de référence (une photo mesure 52 unités). */
  unit: number;
  /** Agrandissement propre à la mise en scène (1 sur l'écran Compo). */
  enlarge: number;
  /** 0 = vignette de stade, 1 = vignette de l'application. */
  app: number;
  /** Éclat passager quand la lumière balaie la vignette. */
  flash: number;
  /** Décalage vertical : la vignette se tient debout au-dessus de son point. */
  lift: number;
  /** Atterrissage : anneau lumineux au sol (0 → 1). */
  impact: number;
  /** Corps (halo, photo) ou étiquette : les étiquettes passent par-dessus tout. */
  part: 'body' | 'label';
  opacity?: number;
};

const appLabelFont = `400 ${nameLabelFontSize}px ${fonts.app}`;

const alphaHex = (alpha: number) =>
  Math.round(Math.max(0, Math.min(1, alpha)) * 255)
    .toString(16)
    .padStart(2, '0');

export const nameLabelWidth = (text: string): number =>
  measureText({
    text,
    fontFamily: fonts.app,
    fontSize: nameLabelFontSize,
    fontWeight: '400',
    validateFontIsLoaded: true,
  }).width;

export const PhotoBox: React.FC<{
  player: LineupPlayer;
  size: number;
  radiusRatio: number;
  borderUnit: number;
}> = ({player, size, radiusRatio, borderUnit}) => {
  if (player.photoUrl) {
    return (
      <div
        style={{
          width: size,
          height: size,
          borderRadius: size * radiusRatio,
          overflow: 'hidden',
        }}
      >
        <Img
          src={player.photoUrl}
          style={{width: '100%', height: '100%', objectFit: 'cover', display: 'block'}}
        />
      </div>
    );
  }
  const inner = size * initialsScale;
  return (
    <div
      style={{
        width: size,
        height: size,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <div
        style={{
          width: inner,
          height: inner,
          boxSizing: 'border-box',
          borderRadius: inner * radiusRatio,
          border: `${2 * borderUnit}px solid ${player.isGoalkeeper ? colors.keeper : '#FFFFFF'}`,
          background: `linear-gradient(135deg, ${player.avatarColors[0]}, ${player.avatarColors[1]})`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          overflow: 'hidden',
          color: '#FFFFFF',
          fontFamily: fonts.app,
          fontWeight: 400,
          fontSize: inner * 0.32,
          lineHeight: 1,
          textShadow: `0 0 ${2 * borderUnit}px rgba(0,0,0,0.26)`,
        }}
      >
        {player.initials}
      </div>
    </div>
  );
};

export const PlayerTile: React.FC<TileProps> = ({
  player,
  x,
  y,
  unit,
  enlarge,
  app,
  flash,
  lift,
  impact,
  part,
  opacity = 1,
}) => {
  const u = unit * enlarge;
  const size = photoSize * u;
  const keeper = player.band === 'goalkeeper';
  const glowColor = player.isCaptain
    ? colors.gold
    : keeper
      ? colors.keeper
      : '#4F86FF';
  const stadium = 1 - app;
  const top = y - size / 2 - lift;
  const cutout = player.photoUrl !== null && player.photoHasAlpha;

  // Étiquette de l'application : Roboto 11, réduite si le prénom dépasse
  // la largeur de la case (64 − 2 × 5), comme le FittedBox de l'écran.
  const label = player.displayName.trim();
  const textWidth = nameLabelWidth(label);
  const maxText = 64 - 2 * nameLabelPadding.x;
  const fit = Math.min(1, maxText / textWidth);
  const labelFont = nameLabelFontSize * fit * u;
  const labelTop = top + size + 2 * u;

  if (part === 'label') {
    return (
      <div
        style={{
          position: 'absolute',
          left: x,
          top: labelTop,
          transform: 'translateX(-50%)',
          whiteSpace: 'nowrap',
          opacity,
        }}
      >
        <div
          style={{
            background: colors.nameLabel,
            borderRadius: 6 * u,
            padding: `${nameLabelPadding.y * u}px ${nameLabelPadding.x * u}px`,
            color: '#FFFFFF',
            font: appLabelFont,
            fontSize: labelFont,
            lineHeight: `${labelFont * 1.172}px`,
            opacity: app,
          }}
        >
          {label}
        </div>
        {stadium > 0.001 ? (
          <div
            style={{
              position: 'absolute',
              left: '50%',
              top: 0,
              transform: 'translateX(-50%)',
              background: 'rgba(2, 8, 20, 0.78)',
              borderRadius: 5 * u,
              borderBottom: `${1.4 * u}px solid ${keeper ? colors.keeper : colors.gold}`,
              padding: `${1.2 * u}px ${5 * u}px`,
              color: '#FFFFFF',
              fontFamily: fonts.display,
              fontWeight: 500,
              fontSize: 11.5 * u * Math.min(1, 1.08 * fit),
              letterSpacing: '0.06em',
              textTransform: 'uppercase',
              lineHeight: 1.15,
              opacity: stadium,
            }}
          >
            {label}
          </div>
        ) : null}
      </div>
    );
  }

  return (
    <div style={{position: 'absolute', left: 0, top: 0, opacity}}>
      {stadium > 0.001 ? (
        <div
          style={{
            position: 'absolute',
            left: x - size * 0.95,
            top: y + size * 0.36 - size * 0.2,
            width: size * 1.9,
            height: size * 0.4,
            borderRadius: '50%',
            background: `radial-gradient(closest-side, ${glowColor}88, ${glowColor}22 60%, transparent)`,
            opacity: stadium * (0.55 + 0.45 * flash),
          }}
        />
      ) : null}
      {impact > 0 && impact < 1 ? (
        <div
          style={{
            position: 'absolute',
            left: x - size * (0.6 + impact * 1.4),
            top: y + size * 0.36 - size * (0.12 + impact * 0.28),
            width: size * (1.2 + impact * 2.8),
            height: size * (0.24 + impact * 0.56),
            borderRadius: '50%',
            border: `${Math.max(1, 3 * u * (1 - impact))}px solid ${glowColor}`,
            opacity: (1 - impact) * stadium,
            boxShadow: `0 0 ${18 * u}px ${glowColor}`,
          }}
        />
      ) : null}
      <div
        style={{
          position: 'absolute',
          left: x - size / 2,
          top,
          width: size,
          height: size,
          borderRadius: size * photoRadiusRatio,
          // Joueur détouré : le liseré lumineux suit sa silhouette. Une photo
          // avec son fond, ou des initiales, gardent la case de l'application.
          boxShadow:
            stadium > 0.001 && !cutout
              ? `0 0 ${(14 + 26 * flash) * u}px ${glowColor}${alphaHex(
                  (0.45 + 0.4 * flash) * stadium,
                )}, 0 ${6 * u}px ${14 * u}px rgba(0,0,0,${0.5 * stadium})`
              : undefined,
          filter:
            [
              stadium > 0.001 && cutout
                ? `drop-shadow(0 0 ${(2 + 3 * flash) * u}px ${glowColor}${alphaHex(
                    (0.85 + 0.15 * flash) * stadium,
                  )}) drop-shadow(0 ${3 * u}px ${5 * u}px rgba(0,0,0,${0.55 * stadium}))`
                : '',
              flash > 0 ? `brightness(${1 + 0.35 * flash})` : '',
            ]
              .filter(Boolean)
              .join(' ') || undefined,
        }}
      >
        <PhotoBox
          player={player}
          size={size}
          radiusRatio={photoRadiusRatio}
          borderUnit={u}
        />
        {player.isCaptain && stadium > 0.001 ? (
          <div
            style={{
              position: 'absolute',
              right: -size * 0.12,
              top: -size * 0.12,
              width: size * 0.34,
              height: size * 0.34,
              borderRadius: '50%',
              background: colors.gold,
              color: colors.night,
              fontFamily: fonts.display,
              fontWeight: 700,
              fontSize: size * 0.22,
              lineHeight: `${size * 0.34}px`,
              textAlign: 'center',
              opacity: stadium,
              boxShadow: `0 0 ${8 * u}px ${colors.gold}`,
            }}
          >
            C
          </div>
        ) : null}
      </div>
    </div>
  );
};
