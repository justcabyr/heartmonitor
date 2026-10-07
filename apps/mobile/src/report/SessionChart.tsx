import { Circle, Line as SkiaLine, Path, Skia, matchFont, vec } from '@shopify/react-native-skia';
import { CartesianChart } from 'victory-native';

import { warningBPM } from '../domain/heartRateSettings';
import { HeartRateSample, SessionRecording } from '../domain/sessionRecording';

import { aggregate } from './aggregate';
import { dataBucketSegments, splitSamplesAtBreaks } from './chartSegments';
import { downsample } from './downsample';
import { ReportInterval } from './intervals';
import { sessionEndOffset } from './sessionWindow';

type ChartPoint = {
  x: number;
  y: number;
};

type BandPoint = {
  x: number;
  min: number;
  max: number;
  avg: number;
};

type Props = {
  recording: SessionRecording;
  interval: ReportInterval;
};

const axisFont = matchFont({
  fontFamily: 'Helvetica',
  fontSize: 11,
  fontStyle: 'normal',
  fontWeight: '400',
});

const nearestBPM = (offset: number, samples: HeartRateSample[]): number | null => {
  if (samples.length === 0) {
    return null;
  }
  let nearest = samples[0];
  let best = Math.abs(samples[0].offset - offset);
  for (const sample of samples) {
    const distance = Math.abs(sample.offset - offset);
    if (distance < best) {
      nearest = sample;
      best = distance;
    }
  }
  return nearest.bpm;
};

const linePath = (
  points: ChartPoint[],
  xScale: (value: number) => number,
  yScale: (value: number) => number,
) => {
  const path = Skia.Path.Make();
  points.forEach((point, index) => {
    const x = xScale(point.x);
    const y = yScale(point.y);
    if (index === 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  });
  return path;
};

const bandPath = (
  points: BandPoint[],
  xScale: (value: number) => number,
  yScale: (value: number) => number,
) => {
  const path = Skia.Path.Make();
  if (points.length === 0) {
    return path;
  }
  path.moveTo(xScale(points[0].x), yScale(points[0].max));
  for (let index = 1; index < points.length; index += 1) {
    path.lineTo(xScale(points[index].x), yScale(points[index].max));
  }
  for (let index = points.length - 1; index >= 0; index -= 1) {
    path.lineTo(xScale(points[index].x), yScale(points[index].min));
  }
  path.close();
  return path;
};

export const SessionChart = ({ recording, interval }: Props) => {
  const endOffset = sessionEndOffset(recording);
  const warning = warningBPM(recording.settings);
  const target = recording.settings.targetBPM;
  const buckets = interval === 'raw'
    ? []
    : aggregate(recording.samples, recording.events, interval, endOffset);
  const rawSegments = interval === 'raw'
    ? splitSamplesAtBreaks(
      downsample(recording.samples),
      recording.samples,
      recording.events,
      endOffset,
    )
    : [];
  const bucketSegments = interval === 'raw' ? [] : dataBucketSegments(buckets);
  const bandSegments: BandPoint[][] = bucketSegments.map((segment) => segment.flatMap((bucket) => {
    if (bucket.avg === undefined || bucket.min === undefined || bucket.max === undefined) {
      return [];
    }
    return [{
      x: bucket.start,
      min: bucket.min,
      max: bucket.max,
      avg: bucket.avg,
    }];
  }));
  const lineSegments: ChartPoint[][] = interval === 'raw'
    ? rawSegments.map((segment) => segment.map((sample) => ({ x: sample.offset, y: sample.bpm })))
    : bandSegments.map((segment) => segment.map((point) => ({ x: point.x, y: point.avg })));

  const bpmValues = [
    warning,
    target,
    ...recording.samples.map((sample) => sample.bpm),
    ...bandSegments.flatMap((segment) => segment.flatMap((point) => [point.min, point.max])),
  ];
  const lowest = Math.min(...bpmValues);
  const highest = Math.max(...bpmValues);
  const yMin = lowest === highest ? lowest - 10 : lowest;
  const yMax = lowest === highest ? highest + 10 : highest;
  const xMax = Math.max(endOffset, ...recording.samples.map((sample) => sample.offset), 1);
  const data: ChartPoint[] = [
    { x: 0, y: yMin },
    { x: xMax, y: yMax },
  ];
  const markers = recording.events.flatMap((event) => {
    if (event.kind !== 'warning' && event.kind !== 'threshold') {
      return [];
    }
    const bpm = nearestBPM(event.offset, recording.samples);
    if (bpm === null) {
      return [];
    }
    return [{ x: event.offset, y: bpm, kind: event.kind }];
  });

  return (
    <CartesianChart
      data={data}
      xKey="x"
      yKeys={['y']}
      domain={{ x: [0, xMax], y: [yMin, yMax] }}
      domainPadding={{ top: 16, bottom: 8, left: 8, right: 8 }}
      axisOptions={{ font: axisFont }}
    >
      {({ chartBounds, xScale, yScale }) => (
        <>
          <SkiaLine
            p1={vec(chartBounds.left, yScale(warning))}
            p2={vec(chartBounds.right, yScale(warning))}
            color="#c8960a"
            strokeWidth={1}
          />
          <SkiaLine
            p1={vec(chartBounds.left, yScale(target))}
            p2={vec(chartBounds.right, yScale(target))}
            color="#b42828"
            strokeWidth={1}
          />
          {bandSegments.map((segment, index) => (
            <Path
              key={`band-${segment[0]?.x ?? index}`}
              path={bandPath(segment, xScale, yScale)}
              color="rgba(180, 40, 40, 0.18)"
              style="fill"
            />
          ))}
          {lineSegments.filter((segment) => segment.length > 0).map((segment) => {
            const first = segment[0];
            if (!first) {
              return null;
            }
            if (segment.length === 1) {
              return (
                <Circle
                  key={`point-${first.x}`}
                  cx={xScale(first.x)}
                  cy={yScale(first.y)}
                  r={3}
                  color="#b42828"
                />
              );
            }
            return (
              <Path
                key={`line-${first.x}`}
                path={linePath(segment, xScale, yScale)}
                color="#b42828"
                style="stroke"
                strokeWidth={2}
              />
            );
          })}
          {markers.map((marker) => (
            <Circle
              key={`${marker.kind}-${marker.x}`}
              cx={xScale(marker.x)}
              cy={yScale(marker.y)}
              r={4}
              color={marker.kind === 'warning' ? '#c8960a' : '#7a1020'}
            />
          ))}
        </>
      )}
    </CartesianChart>
  );
};
