// language=GLSL
// based on @paper-design/shaders-react
// https://github.com/paper-design/shaders

const declarePI = `
#define TWO_PI 6.28318530718
#define PI 3.14159265358979323846
`;

// language=GLSL
const proceduralHash21 = `
float hash21(vec2 p) {
  p = fract(p * vec2(0.3183099, 0.3678794)) + 0.1;
  p += dot(p, p + 19.19);
  return fract(p.x * p.y);
}
`;

// language=GLSL
export const ditheringFragmentShader: string = `#version 300 es
precision mediump float;

uniform float u_time;
uniform vec2 u_resolution;
uniform float u_pixelRatio;
uniform float u_pxSize;
uniform vec4 u_colorBack;
uniform vec4 u_colorFront;
uniform float u_type;
uniform float u_scale;
uniform float u_seed;

out vec4 fragColor;

${ declarePI }
${ proceduralHash21 }

const int bayer2x2[4] = int[4](0, 2, 3, 1);
const int bayer4x4[16] = int[16](
  0, 8, 2, 10,
  12, 4, 14, 6,
  3, 11, 1, 9,
  15, 7, 13, 5
);
const int bayer8x8[64] = int[64](
  0, 32, 8, 40, 2, 34, 10, 42,
  48, 16, 56, 24, 50, 18, 58, 26,
  12, 44, 4, 36, 14, 46, 6, 38,
  60, 28, 52, 20, 62, 30, 54, 22,
  3, 35, 11, 43, 1, 33, 9, 41,
  51, 19, 59, 27, 49, 17, 57, 25,
  15, 47, 7, 39, 13, 45, 5, 37,
  63, 31, 55, 23, 61, 29, 53, 21
);

float getBayerValue(vec2 uv, int size) {
  ivec2 pos = ivec2(fract(uv / float(size)) * float(size));
  int index = pos.y * size + pos.x;

  if (size == 2) {
    return float(bayer2x2[index]) / 4.0;
  } else if (size == 4) {
    return float(bayer4x4[index]) / 16.0;
  } else if (size == 8) {
    return float(bayer8x8[index]) / 64.0;
  }
  return 0.0;
}

void main() {
  float t = 0.5 * u_time;

  float pxSize = u_pxSize * u_pixelRatio;
  vec2 pxSizeUV = gl_FragCoord.xy - 0.5 * u_resolution;
  pxSizeUV /= pxSize;
  vec2 canvasPixelizedUV = (floor(pxSizeUV) + 0.5) * pxSize;
  vec2 ditheringNoiseUV = canvasPixelizedUV;

  vec2 uv = (canvasPixelizedUV - 0.5 * u_resolution) / min(u_resolution.x, u_resolution.y);
  uv /= u_scale;

  float seed = u_seed * 100.0;
  vec2 seedOffset = vec2(sin(seed), cos(seed * 1.3)) * 10.0;

  vec2 p = uv * 3.0 + seedOffset;
  for (float i = 1.0; i < 5.0; i++) {
    p.x += 0.6 / i * sin(i * 2.5 * p.y + t + 0.4 * cos(t / i) + seed * 0.1);
    p.y += 0.6 / i * cos(i * 2.0 * p.x + t * 1.1 + seed * 0.13);
  }
  float flow = sin(p.x + p.y + seed) * 0.5 + 0.5;
  flow += sin(p.x * 2.0 - p.y + t * 0.4) * 0.25;
  flow += sin(length(p) * 2.5 - t * 0.8) * 0.25;
  
  vec2 m = uv * 2.0 + seedOffset * 0.1;
  float c1 = sin(length(m) * 10.0 - t * 0.6 + seed * 0.2);
  float c2 = sin(length(m - vec2(0.25 + sin(seed) * 0.1, 0.15 + cos(seed) * 0.1)) * 10.0 + t * 0.5);
  float moire = c1 * c2 * 0.5 + 0.5;
  
  float shape = flow * 0.65 + moire * 0.35;
  shape = smoothstep(0.15, 0.85, shape);

  int type = int(floor(u_type));
  float dithering = 0.0;

  if (type == 1) {
    dithering = step(hash21(ditheringNoiseUV), shape);
  } else if (type == 2) {
    dithering = getBayerValue(pxSizeUV, 2);
  } else if (type == 3) {
    dithering = getBayerValue(pxSizeUV, 4);
  } else {
    dithering = getBayerValue(pxSizeUV, 8);
  }

  dithering -= 0.5;
  float res = step(0.5, shape + dithering);

  vec3 fgColor = u_colorFront.rgb * u_colorFront.a;
  float fgOpacity = u_colorFront.a;
  vec3 bgColor = u_colorBack.rgb * u_colorBack.a;
  float bgOpacity = u_colorBack.a;

  vec3 color = fgColor * res;
  float opacity = fgOpacity * res;

  color += bgColor * (1.0 - opacity);
  opacity += bgOpacity * (1.0 - opacity);

  fragColor = vec4(color, opacity);
}
`;

export const DitheringTypes = {
  'random': 1,
  '2x2': 2,
  '4x4': 3,
  '8x8': 4,
} as const;

export type DitheringType = keyof typeof DitheringTypes;
