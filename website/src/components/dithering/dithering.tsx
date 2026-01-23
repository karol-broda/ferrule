'use client';

import { useEffect, useRef, useMemo } from 'react';
import { ditheringFragmentShader, DitheringTypes, type DitheringType } from './shaders';
import { hexToRgba } from '@/lib/color';

const VERTEX_SHADER = `#version 300 es
in vec4 a_position;
void main() {
  gl_Position = a_position;
}
`;

const QUAD_VERTICES = new Float32Array([
  -1, -1,
   1, -1,
  -1,  1,
  -1,  1,
   1, -1,
   1,  1,
]);

type DitheringProps = {
  colorBack?: string;
  colorFront?: string;
  type?: DitheringType;
  size?: number;
  speed?: number;
  scale?: number;
  style?: React.CSSProperties;
  className?: string;
};

export function Dithering({
  colorBack = '#000000',
  colorFront = '#ffffff',
  type = '4x4',
  size = 2,
  speed = 0.15,
  scale = 1,
  style,
  className,
}: DitheringProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const seed = useMemo(() => Math.random() * 1000, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (canvas === null) return;

    const gl = canvas.getContext('webgl2', { 
      antialias: false,
      alpha: true,
      premultipliedAlpha: false,
    });
    if (gl === null) return;

    const vShader = gl.createShader(gl.VERTEX_SHADER);
    if (vShader === null) return;
    gl.shaderSource(vShader, VERTEX_SHADER);
    gl.compileShader(vShader);
    if (!gl.getShaderParameter(vShader, gl.COMPILE_STATUS)) return;

    const fShader = gl.createShader(gl.FRAGMENT_SHADER);
    if (fShader === null) return;
    gl.shaderSource(fShader, ditheringFragmentShader);
    gl.compileShader(fShader);
    if (!gl.getShaderParameter(fShader, gl.COMPILE_STATUS)) return;

    const program = gl.createProgram();
    if (program === null) return;
    gl.attachShader(program, vShader);
    gl.attachShader(program, fShader);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;

    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, QUAD_VERTICES, gl.STATIC_DRAW);

    const posLoc = gl.getAttribLocation(program, 'a_position');
    gl.enableVertexAttribArray(posLoc);
    gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0);

    const uniforms = {
      time: gl.getUniformLocation(program, 'u_time'),
      resolution: gl.getUniformLocation(program, 'u_resolution'),
      pixelRatio: gl.getUniformLocation(program, 'u_pixelRatio'),
      scale: gl.getUniformLocation(program, 'u_scale'),
      pxSize: gl.getUniformLocation(program, 'u_pxSize'),
      seed: gl.getUniformLocation(program, 'u_seed'),
      colorBack: gl.getUniformLocation(program, 'u_colorBack'),
      colorFront: gl.getUniformLocation(program, 'u_colorFront'),
      type: gl.getUniformLocation(program, 'u_type'),
    };

    const startTime = performance.now();
    let frameId = 0;

    const render = () => {
      const dpr = window.devicePixelRatio || 1;
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      
      if (canvas.width !== w * dpr || canvas.height !== h * dpr) {
        canvas.width = w * dpr;
        canvas.height = h * dpr;
        gl.viewport(0, 0, canvas.width, canvas.height);
      }

      gl.useProgram(program);

      const t = (performance.now() - startTime) / 1000 * speed;
      const back = hexToRgba(colorBack);
      const front = hexToRgba(colorFront);

      gl.uniform1f(uniforms.time, t);
      gl.uniform2f(uniforms.resolution, canvas.width, canvas.height);
      gl.uniform1f(uniforms.pixelRatio, dpr);
      gl.uniform1f(uniforms.scale, scale);
      gl.uniform1f(uniforms.pxSize, size);
      gl.uniform1f(uniforms.seed, seed);
      gl.uniform4f(uniforms.colorBack, back[0], back[1], back[2], back[3]);
      gl.uniform4f(uniforms.colorFront, front[0], front[1], front[2], front[3]);
      gl.uniform1f(uniforms.type, DitheringTypes[type]);

      gl.drawArrays(gl.TRIANGLES, 0, 6);
      frameId = requestAnimationFrame(render);
    };

    render();
    return () => cancelAnimationFrame(frameId);
  }, [colorBack, colorFront, type, size, speed, scale, seed]);

  return (
    <canvas
      ref={canvasRef}
      className={className}
      style={{ display: 'block', ...style }}
    />
  );
}
