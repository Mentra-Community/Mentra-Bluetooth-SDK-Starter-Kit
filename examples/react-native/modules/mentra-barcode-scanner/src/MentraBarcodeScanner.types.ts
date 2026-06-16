export type BarcodeBounds = {
  height: number;
  width: number;
  x: number;
  y: number;
};

export type BarcodeCornerPoint = {
  x: number;
  y: number;
};

export type BarcodeScanResult = {
  bounds?: BarcodeBounds;
  cornerPoints?: BarcodeCornerPoint[];
  displayValue?: string | null;
  format: string;
  scanner?: 'mlkit' | 'zxing-cpp';
  rawValue?: string | null;
  valueType?: string;
};

export type ImageFovEstimate = {
  basis: '35mm_equivalent';
  diagonalDegrees: number;
  focalLength35mm: number;
  horizontalDegrees: number;
  verticalDegrees: number;
};

export type ImageImuSample = {
  accel?: [number, number, number] | null;
  gyro?: [number, number, number] | null;
  relativeTimeMs?: number | null;
};

export type ImageImuMetadata = {
  clockSource?: string | null;
  durationMs?: number | null;
  exifTruncated?: boolean | null;
  firstSample?: ImageImuSample | null;
  lastSample?: ImageImuSample | null;
  recordingStartElapsedRealtimeNs?: string | null;
  sampleCount?: number | null;
  samplingRateHz?: number | null;
  startTimeNs?: string | null;
  version?: number | null;
  videoStartElapsedRealtimeNs?: string | null;
};

export type ImageMetadata = {
  estimatedFov?: ImageFovEstimate | null;
  focalLength35mm?: number | null;
  height?: number | null;
  imuMetadata?: ImageImuMetadata | null;
  width?: number | null;
};

export type TestBarcodeImage = {
  byteCount: number;
  fileUri: string;
  value: string;
};
