// Présentation cinématique du onze de départ AS Grinta.
//
// Une seule scène, pilotée image par image : la caméra virtuelle, le terrain,
// les révélations et les vignettes partagent la même géométrie, ce qui permet
// de terminer exactement sur l'écran Compo de l'application.
import React, {useMemo} from 'react';
import {AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {fitText} from '@remotion/layout-utils';
import {Atmosphere} from './components/Atmosphere.tsx';
import {PitchSurface} from './components/PitchSurface.tsx';
import {PlayerTile} from './components/PlayerTile.tsx';
import {PlayerCutout, rimColor} from './components/PlayerCutout.tsx';
import {Crowd} from './components/Crowd.tsx';
import {
  cssMatrix3d,
  lerp,
  mixCameras,
  pitchHomography,
  project,
  type Camera,
} from './camera.ts';
import {useFontsReady} from './fonts.ts';
import {photoCenter, photoSize} from './layout/display.ts';
import {buildLineup, type LineupPlayer} from './layout/lineup.ts';
import {matchLines} from './matchText.ts';
import {colors, fonts, video} from './theme.ts';
import {buildTimeline, finalHold, progress, type Timeline} from './timeline.ts';
import type {LineupPresentationProps} from './types.ts';

/** Largeur propre du dessin du terrain : assez fine pour rester net de près. */
const pitchPixelWidth = 1520;

/** Vue finale : celle de l'écran Compo, terrain de 760 px centré. */
export const finalPitchRect = {x: 160, y: 960 - (760 / 0.68) / 2, width: 760, height: 760 / 0.68};
const finalCamera: Camera = {
  tilt: 90,
  targetX: 0,
  targetY: 0,
  distance: 1000,
  focal: (1000 * finalPitchRect.width) / 340,
  centerX: video.width / 2,
  centerY: video.height / 2,
  yaw: 0,
};

const ease = Easing.bezier(0.45, 0, 0.2, 1);
const easeOut = Easing.bezier(0.16, 1, 0.3, 1);
const easeIn = Easing.bezier(0.55, 0, 1, 0.45);

const keyCameras = (t: Timeline) => {
  const establishing: Camera = {
    tilt: 14, targetX: 0, targetY: 230, distance: 1500, focal: 2000,
    centerX: 540, centerY: 1560, yaw: 0,
  };
  const keeper: Camera = {
    tilt: 44, targetX: 0, targetY: 70, distance: 900, focal: 2150,
    centerX: 540, centerY: 1480, yaw: 0,
  };
  const attack: Camera = {
    tilt: 48, targetX: 0, targetY: 30, distance: 930, focal: 2150,
    centerX: 540, centerY: 1460, yaw: 0,
  };
  const overview: Camera = {
    tilt: 56, targetX: 0, targetY: 10, distance: 1000, focal: 2150,
    centerX: 540, centerY: 1320, yaw: 0,
  };
  return [
    {frame: 52, camera: establishing},
    {frame: t.revealStart(0) + 24, camera: keeper},
    {frame: t.revealsEnd, camera: attack},
    {frame: t.formationStart + 30, camera: overview},
    {frame: t.finaleStart - 4, camera: overview},
    {frame: t.duration - finalHold, camera: finalCamera},
  ];
};

const cameraAt = (frame: number, t: Timeline): Camera => {
  const keys = keyCameras(t);
  if (frame <= keys[0].frame) return keys[0].camera;
  for (let i = 1; i < keys.length; i += 1) {
    if (frame <= keys[i].frame) {
      const a = keys[i - 1];
      const b = keys[i];
      const p = progress(frame, a.frame, b.frame);
      return mixCameras(a.camera, b.camera, ease(p));
    }
  }
  return keys[keys.length - 1].camera;
};

/** Passage progressif à l'apparence exacte de l'application. */
const appness = (frame: number, t: Timeline) =>
  ease(progress(frame, t.finaleStart - 4, t.duration - finalHold));

type TileState = {x: number; y: number; unit: number; enlarge: number; lift: number; size: number};

const tileState = (
  player: LineupPlayer,
  h: number[][],
  camera: Camera,
  app: number,
): TileState => {
  const c = photoCenter(player.point);
  const p = project(h, c.x, c.y, camera.focal);
  const enlarge = lerp(0.92, 1, app);
  const size = photoSize * p.scale * enlarge;
  return {x: p.x, y: p.y, unit: p.scale, enlarge, lift: size * 0.22 * (1 - app), size};
};

// Révélation d'un joueur, en images depuis son départ.
const R = {
  zoom: [0, 24],
  gloss: [9, 22],
  nameIn: [5, 14],
  textOut: [18, 24],
  flight: [20, 38],
  impact: [38, 52],
} as const;
const cardCenter = {x: 540, y: 560};
const cardSize = 600;

/**
 * Les photos d'une vraie présentation sont téléchargées à côté du rendu
 * (chemin relatif) ; celles de l'aperçu sont des adresses complètes.
 */
const resolvePhotoUrl = (url: string | null): string | null => {
  if (!url) return null;
  return /^(https?:|data:|blob:)/.test(url) ? url : staticFile(url);
};

export const LineupPresentation: React.FC<LineupPresentationProps> = (props) => {
  const frame = useCurrentFrame();
  const ready = useFontsReady();
  const lineup = useMemo(
    () =>
      buildLineup({
        ...props,
        players: props.players.map((p) => ({...p, photoUrl: resolvePhotoUrl(p.photoUrl)})),
      }),
    [props],
  );
  const t = useMemo(() => buildTimeline(lineup.players.length), [lineup]);
  if (!ready) return <AbsoluteFill style={{background: colors.abyss}} />;

  const camera = cameraAt(frame, t);
  const h = pitchHomography(camera);
  const app = appness(frame, t);
  const calm = ease(progress(frame, t.finaleStart - 4, t.finaleStart + 20));
  const horizon = project(h, 170, 0, camera.focal);

  // Terrain : tracé dessiné, puis pelouse, puis pénombre qui se lève à la fin.
  const draw = easeOut(progress(frame, 55, 88));
  const turf = progress(frame, 58, 84);
  const night = 0.42 * (1 - calm);
  const glow = 1 - calm;
  const sweepFrame = progress(frame, t.formationStart + 16, t.formationStart + 58);
  const sweep = sweepFrame > 0 && sweepFrame < 1 ? ease(sweepFrame) : null;

  const landed = (p: LineupPlayer) => t.revealStart(p.order) + R.flight[1];

  const formationIn = ease(progress(frame, t.formationStart + 24, t.formationStart + 42));
  const formationOut = ease(progress(frame, t.finaleStart - 16, t.finaleStart - 2));
  const bugOpacity =
    progress(frame, 56, 64) * (1 - progress(frame, t.formationStart + 18, t.formationStart + 30));

  return (
    <AbsoluteFill style={{background: colors.abyss, overflow: 'hidden'}}>
      <Atmosphere
        frame={frame}
        lights={progress(frame, 2, 24)}
        horizonY={turf > 0 ? horizon.y : null}
        calm={calm}
      />

      {/* Le public, derrière le but adverse : il apparaît avec la lumière et
          s'efface quand l'image devient l'écran Compo. */}
      <Crowd
        frame={frame}
        duration={t.duration}
        baseY={horizon.y}
        presence={lerp(0.14, 1, progress(frame, 40, 64)) * (1 - calm)}
      />

      {/* Le terrain, déformé par la caméra. */}
      <div
        style={{
          position: 'absolute',
          left: 0,
          top: 0,
          width: pitchPixelWidth,
          transformOrigin: '0 0',
          transform: cssMatrix3d(h, pitchPixelWidth),
          boxShadow: `0 ${10 * (pitchPixelWidth / 340)}px ${22 * (pitchPixelWidth / 340)}px rgba(0,0,0,${0.2 * turf})`,
          borderRadius: 28 * (pitchPixelWidth / 340),
        }}
      >
        <PitchSurface
          id="pitch"
          pixelWidth={pitchPixelWidth}
          night={night}
          glow={glow}
          draw={draw}
          turf={turf}
          sweep={sweep}
        />
      </div>

      <FormationLines lineup={lineup.players} frame={frame} t={t} h={h} camera={camera} app={app} />

      {/* Vignettes déjà posées, de la plus lointaine à la plus proche ; les
          prénoms passent ensuite par-dessus toutes les photos. */}
      {(['body', 'label'] as const).map((part) =>
        lineup.players
          .filter((p) => frame >= landed(p))
          .map((p) => ({p, s: tileState(p, h, camera, app)}))
          .sort((a, b) => a.s.unit - b.s.unit)
          .map(({p, s}) => {
            const sinceLanding = frame - landed(p);
            const along = 1 - p.point.y;
            const swept = sweep === null ? 0 : Math.exp(-(((sweep - along) / 0.07) ** 2));
            const pulse = Math.exp(-(((frame - (t.formationStart + 62)) / 6) ** 2)) * 0.6;
            const landingFlash = Math.max(0, 1 - sinceLanding / 10);
            return (
              <PlayerTile
                key={`${part}-${p.id}`}
                part={part}
                player={p}
                x={s.x}
                y={s.y}
                unit={s.unit}
                enlarge={s.enlarge}
                app={app}
                lift={s.lift}
                flash={Math.min(1, swept + pulse + landingFlash) * (1 - app)}
                impact={progress(frame, landed(p), landed(p) + (R.impact[1] - R.impact[0]))}
              />
            );
          }),
      )}

      {/* Révélations en cours. */}
      {lineup.players.map((p) => {
        const start = t.revealStart(p.order);
        const local = frame - start;
        if (local < 0 || local >= R.flight[1]) return null;
        const target = tileState(p, h, camera, app);
        return (
          <Reveal key={p.id} player={p} local={local} target={target} />
        );
      })}

      <Intro frame={frame} props={props} />
      <CrestBug frame={frame} props={props} opacity={bugOpacity} />
      <FormationTitle
        teamName={props.teamName}
        formation={lineup.formationLabel}
        visible={formationIn * (1 - formationOut)}
        enter={formationIn}
      />
    </AbsoluteFill>
  );
};

const Reveal: React.FC<{
  player: LineupPlayer;
  local: number;
  target: TileState;
}> = ({player, local, target}) => {
  // La silhouette apparaît dans l'ombre, cerclée de lumière, puis s'éclaire.
  const appear = easeOut(progress(local, 0, 6));
  const light = ease(progress(local, 5, 14));
  const zoom = lerp(1.12, 1, easeOut(progress(local, R.zoom[0], R.zoom[1])));
  const glossP = progress(local, R.gloss[0], R.gloss[1]);
  const flight = progress(local, R.flight[0], R.flight[1]);
  const f = Easing.bezier(0.6, 0.02, 0.25, 1)(flight);

  // Trajectoire en arc : le joueur plonge vers son poste.
  const end = {x: target.x, y: target.y - target.lift};
  const control = {
    x: lerp(cardCenter.x, end.x, 0.15) + (end.x - cardCenter.x) * 0.35,
    y: Math.min(cardCenter.y, end.y) - 60,
  };
  const pos = {
    x: (1 - f) * (1 - f) * cardCenter.x + 2 * (1 - f) * f * control.x + f * f * end.x,
    y: (1 - f) * (1 - f) * cardCenter.y + 2 * (1 - f) * f * control.y + f * f * end.y,
  };
  const size = cardSize * Math.pow(target.size / cardSize, f);

  const nameIn = easeOut(progress(local, R.nameIn[0], R.nameIn[1]));
  const textOut = easeIn(progress(local, R.textOut[0], R.textOut[1]));
  const accent = rimColor(player);

  const name = player.displayName.trim().toUpperCase();
  const nameSize = Math.min(
    150,
    fitText({text: name, withinWidth: 860, fontFamily: fonts.display, fontWeight: '700'}).fontSize,
  );
  const textY = cardCenter.y + cardSize / 2 + 6;

  return (
    <>
      {/* Point d'arrivée : la place du joueur s'allume avant qu'il la rejoigne. */}
      <div
        style={{
          position: 'absolute',
          left: target.x - target.size * 0.9,
          top: target.y + target.size * 0.36 - target.size * 0.22,
          width: target.size * 1.8,
          height: target.size * 0.44,
          borderRadius: '50%',
          border: `3px solid ${accent}`,
          boxShadow: `0 0 26px ${accent}, inset 0 0 18px ${accent}66`,
          opacity: progress(local, 8, 16) * (0.55 + 0.45 * Math.sin(local / 2.2)) * (1 - progress(local, R.flight[1] - 3, R.flight[1])),
          transform: `scale(${lerp(1.25, 0.9, progress(local, 8, R.flight[1]))})`,
        }}
      />
      {/* Voile sombre derrière le prénom : le bas du buste s'y fond, et le
          prénom reste lisible devant la tribune. */}
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: textY - 210,
          height: nameSize * 1.12 + 300,
          background:
            'linear-gradient(180deg, transparent 0%, rgba(2,8,20,0.82) 40%, rgba(2,8,20,0.82) 72%, transparent 100%)',
          opacity: appear * (1 - textOut) * (1 - flight),
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: pos.x - size / 2,
          top: pos.y - size / 2,
          width: size,
          height: size,
          transform: `perspective(1400px) rotateX(${Math.sin(Math.PI * f) * 20}deg)`,
          filter:
            flight > 0 && flight < 1
              ? `blur(${(6 * Math.sin(Math.PI * flight) ** 2).toFixed(2)}px)`
              : undefined,
        }}
      >
        <PlayerCutout
          player={player}
          size={size}
          appear={appear}
          light={light}
          zoom={zoom}
          gloss={glossP > 0 && glossP < 1 ? glossP : null}
          glow={lerp(1, 0.5, f)}
          fadeBottom={1 - f}
        />
      </div>

      {/* Le prénom seul, sans poste : le terrain dit déjà où il joue. */}
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: textY,
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          gap: 22,
          opacity: 1 - textOut,
          transform: `translateY(${textOut * 30}px)`,
        }}
      >
        <div style={{overflow: 'hidden', height: nameSize * 1.12}}>
          <div
            style={{
              fontFamily: fonts.display,
              fontWeight: 700,
              fontSize: nameSize,
              lineHeight: 1.12,
              color: colors.white,
              letterSpacing: `${lerp(0.16, 0.02, nameIn)}em`,
              transform: `translateY(${(1 - nameIn) * 100}%)`,
              textShadow: '0 10px 40px rgba(0,0,0,0.6)',
              whiteSpace: 'nowrap',
            }}
          >
            {name}
          </div>
        </div>
        {player.isCaptain ? (
          <div
            style={{
              width: nameSize * 0.46,
              height: nameSize * 0.46,
              borderRadius: '50%',
              background: `radial-gradient(circle at 35% 30%, #F6DD8E, ${colors.gold} 60%, #9C7A22)`,
              boxShadow: `0 0 ${nameSize * 0.2}px ${colors.gold}`,
              color: colors.night,
              fontFamily: fonts.display,
              fontWeight: 700,
              fontSize: nameSize * 0.3,
              lineHeight: `${nameSize * 0.46}px`,
              textAlign: 'center',
              transform: `scale(${nameIn})`,
            }}
          >
            C
          </div>
        ) : null}
      </div>
    </>
  );
};

const crestSource = staticFile('crest.webp');
const crestAspect = 741 / 680;

const Intro: React.FC<{frame: number; props: LineupPresentationProps}> = ({frame, props}) => {
  if (frame > 64) return null;
  const appear = easeOut(progress(frame, 4, 30));
  const leave = ease(progress(frame, 44, 62));
  const sweep = progress(frame, 14, 36);
  const crestWidth = lerp(360, 92, leave);
  const crestX = lerp(540, 120 + 46, leave);
  const crestY = lerp(640, 132, leave);
  const titleIn = easeOut(progress(frame, 14, 32));
  const subIn = easeOut(progress(frame, 24, 38));
  const infoIn = easeOut(progress(frame, 30, 44));
  const textLeave = easeIn(progress(frame, 42, 54));
  const lines = matchLines(props.match);
  const flare = Math.exp(-(((frame - 54) / 5) ** 2));
  // Lente poussée de caméra pendant que le titre se pose.
  const push = lerp(1, 1.045, ease(progress(frame, 0, 50)));
  return (
    <div style={{position: 'absolute', inset: 0, transform: `scale(${push})`, transformOrigin: '50% 45%'}}>
      <div
        style={{
          position: 'absolute',
          left: 540 - 520,
          top: 640 - 520,
          width: 1040,
          height: 1040,
          background: 'radial-gradient(closest-side, rgba(40,90,230,0.55), rgba(5,41,157,0.18) 55%, transparent)',
          opacity: appear * (1 - leave),
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: crestX - crestWidth / 2,
          top: crestY - (crestWidth * crestAspect) / 2,
          width: crestWidth,
          height: crestWidth * crestAspect,
          opacity: Math.min(1, appear * 1.4),
          transform: `scale(${lerp(0.84, 1, appear)})`,
          filter: `blur(${(1 - appear) * 14}px) drop-shadow(0 20px 50px rgba(0,0,0,0.55))`,
        }}
      >
        <Img src={crestSource} style={{width: '100%', height: '100%'}} />
        {sweep > 0 && sweep < 1 ? (
          <div
            style={{
              position: 'absolute',
              inset: 0,
              WebkitMaskImage: `url("${crestSource}")`,
              WebkitMaskSize: '100% 100%',
              background: `linear-gradient(104deg, transparent ${sweep * 170 - 60}%, rgba(255,255,255,0.75) ${sweep * 170 - 50}%, transparent ${sweep * 170 - 40}%)`,
            }}
          />
        ) : null}
      </div>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: 1010,
          textAlign: 'center',
          opacity: 1 - textLeave,
          transform: `translateY(${-textLeave * 50}px)`,
        }}
      >
        <div style={{overflow: 'hidden', height: 150}}>
          <div
            style={{
              fontFamily: fonts.display,
              fontWeight: 700,
              fontSize: 136,
              lineHeight: '150px',
              color: colors.white,
              letterSpacing: `${lerp(0.42, 0.08, titleIn)}em`,
              transform: `translateY(${(1 - titleIn) * 100}%)`,
              textShadow: '0 12px 40px rgba(0,0,0,0.5)',
            }}
          >
            {props.teamName.toUpperCase()}
          </div>
        </div>
        <div
          style={{
            marginTop: 16,
            display: 'flex',
            justifyContent: 'center',
            alignItems: 'center',
            gap: 24,
            opacity: subIn,
          }}
        >
          <div style={{width: 110 * subIn, height: 3, background: colors.gold}} />
          <div
            style={{
              fontFamily: fonts.display,
              fontWeight: 400,
              fontSize: 44,
              letterSpacing: `${lerp(0.6, 0.38, subIn)}em`,
              color: colors.gold,
            }}
          >
            LE ONZE DE DÉPART
          </div>
          <div style={{width: 110 * subIn, height: 3, background: colors.gold}} />
        </div>
        {lines.opponent ? (
          <div style={{marginTop: 54, opacity: infoIn, transform: `translateY(${(1 - infoIn) * 20}px)`}}>
            <div
              style={{
                fontFamily: fonts.display,
                fontWeight: 300,
                fontSize: 28,
                letterSpacing: '0.4em',
                color: colors.textFaint,
              }}
            >
              CONTRE
            </div>
            <div
              style={{
                fontFamily: fonts.display,
                fontWeight: 500,
                fontSize: Math.min(
                  58,
                  fitText({
                    text: lines.opponent.toUpperCase(),
                    withinWidth: 820,
                    fontFamily: fonts.display,
                    fontWeight: '500',
                  }).fontSize,
                ),
                letterSpacing: '0.04em',
                color: colors.white,
                marginTop: 4,
                whiteSpace: 'nowrap',
              }}
            >
              {lines.opponent.toUpperCase()}
            </div>
          </div>
        ) : null}
        {lines.when || lines.competition ? (
          <div
            style={{
              marginTop: lines.opponent ? 18 : 54,
              fontFamily: fonts.display,
              fontWeight: 300,
              fontSize: 30,
              letterSpacing: '0.16em',
              color: colors.textFaint,
              opacity: infoIn,
            }}
          >
            {[lines.competition, lines.when].filter(Boolean).join('  ·  ').toUpperCase()}
          </div>
        ) : null}
      </div>
      {/* Éclat horizontal qui ouvre sur le terrain. */}
      <div
        style={{
          position: 'absolute',
          left: -200,
          right: -200,
          top: 1120,
          height: 260,
          background: 'radial-gradient(ellipse 50% 22% at 50% 50%, rgba(220,232,255,0.9), rgba(110,147,246,0.35) 45%, transparent 75%)',
          opacity: flare,
        }}
      />
    </div>
  );
};

const CrestBug: React.FC<{frame: number; props: LineupPresentationProps; opacity: number}> = ({
  props,
  opacity,
}) => {
  if (opacity <= 0) return null;
  const lines = matchLines(props.match);
  return (
    <div
      style={{
        position: 'absolute',
        left: 120,
        top: 82,
        display: 'flex',
        alignItems: 'center',
        gap: 22,
        opacity,
      }}
    >
      <Img src={crestSource} style={{width: 92, height: 92 * crestAspect}} />
      <div>
        <div
          style={{
            fontFamily: fonts.display,
            fontWeight: 700,
            fontSize: 40,
            letterSpacing: '0.08em',
            color: colors.white,
            lineHeight: 1.1,
          }}
        >
          {props.teamName.toUpperCase()}
        </div>
        <div
          style={{
            fontFamily: fonts.display,
            fontWeight: 400,
            fontSize: 24,
            letterSpacing: '0.22em',
            color: colors.gold,
            lineHeight: 1.4,
            maxWidth: 640,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {lines.opponent ? `CONTRE ${lines.opponent.toUpperCase()}` : 'LE ONZE DE DÉPART'}
        </div>
      </div>
    </div>
  );
};

const FormationTitle: React.FC<{
  teamName: string;
  formation: string | null;
  visible: number;
  enter: number;
}> = ({teamName, formation, visible, enter}) => {
  if (visible <= 0) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        top: 132,
        textAlign: 'center',
        opacity: visible,
        transform: `translateY(${(1 - enter) * -30}px)`,
      }}
    >
      <Img
        src={crestSource}
        style={{width: 150, height: 150 * crestAspect, filter: 'drop-shadow(0 16px 40px rgba(0,0,0,0.5))'}}
      />
      <div
        style={{
          marginTop: 18,
          fontFamily: fonts.display,
          fontWeight: 700,
          fontSize: 112,
          lineHeight: 1.05,
          letterSpacing: `${lerp(0.3, 0.08, enter)}em`,
          color: colors.white,
          textShadow: '0 12px 40px rgba(0,0,0,0.55)',
        }}
      >
        {teamName.toUpperCase()}
      </div>
      {formation ? (
        <div
          style={{
            marginTop: 6,
            fontFamily: fonts.display,
            fontWeight: 500,
            fontSize: 76,
            letterSpacing: '0.12em',
            color: colors.gold,
            textTransform: 'uppercase',
          }}
        >
          {formation}
        </div>
      ) : null}
      <div
        style={{
          marginTop: 8,
          fontFamily: fonts.display,
          fontWeight: 400,
          fontSize: 30,
          letterSpacing: '0.42em',
          color: colors.textFaint,
        }}
      >
        LE ONZE DE DÉPART
      </div>
    </div>
  );
};

/** Lignes du dispositif, tracées entre les joueurs d'une même ligne. */
const FormationLines: React.FC<{
  lineup: LineupPlayer[];
  frame: number;
  t: Timeline;
  h: number[][];
  camera: Camera;
  app: number;
}> = ({lineup, frame, t, h, camera}) => {
  const drawP = ease(progress(frame, t.formationStart + 26, t.formationStart + 50));
  const fade = 1 - progress(frame, t.finaleStart - 18, t.finaleStart - 4);
  if (drawP <= 0 || fade <= 0) return null;
  const groups = new Map<string, LineupPlayer[]>();
  for (const p of lineup) {
    if (p.band === 'goalkeeper') continue;
    // Une ligne = des joueurs à la même profondeur, à 0,06 près.
    const key = `${p.band}:${Math.round(p.point.y / 0.06)}`;
    groups.set(key, [...(groups.get(key) ?? []), p]);
  }
  const segments: [{x: number; y: number}, {x: number; y: number}][] = [];
  for (const group of groups.values()) {
    const sorted = [...group].sort((a, b) => a.point.x - b.point.x);
    for (let i = 1; i < sorted.length; i += 1) {
      const a = photoCenter(sorted[i - 1].point);
      const b = photoCenter(sorted[i].point);
      segments.push([project(h, a.x, a.y, camera.focal), project(h, b.x, b.y, camera.focal)]);
    }
  }
  return (
    <svg
      width={video.width}
      height={video.height}
      style={{position: 'absolute', left: 0, top: 0, opacity: fade}}
    >
      {segments.map(([a, b], index) => (
        <line
          key={index}
          x1={a.x}
          y1={a.y}
          x2={lerp(a.x, b.x, drawP)}
          y2={lerp(a.y, b.y, drawP)}
          stroke={colors.gold}
          strokeOpacity={0.75}
          strokeWidth={3}
          strokeLinecap="round"
          style={{filter: 'drop-shadow(0 0 6px rgba(217,178,74,0.9))'}}
        />
      ))}
    </svg>
  );
};

