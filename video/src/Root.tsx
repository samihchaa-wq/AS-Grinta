import React from 'react';
import {Composition} from 'remotion';
import {LineupPresentation} from './LineupPresentation.tsx';
import {sampleProps} from './data/sample.ts';
import {video} from './theme.ts';
import {buildTimeline} from './timeline.ts';
import type {LineupPresentationProps} from './types.ts';

export const compositionId = 'LineupPresentation';

export const RemotionRoot: React.FC = () => (
  <Composition
    id={compositionId}
    component={LineupPresentation}
    width={video.width}
    height={video.height}
    fps={video.fps}
    durationInFrames={buildTimeline(sampleProps.players.length).duration}
    defaultProps={sampleProps satisfies LineupPresentationProps}
    calculateMetadata={({props}) => ({
      durationInFrames: buildTimeline(props.players.length).duration,
    })}
  />
);
