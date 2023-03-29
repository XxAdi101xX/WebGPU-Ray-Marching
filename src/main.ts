import RasterizationRenderer from './rasterization-renderer';

const canvas = document.getElementById('gfx') as HTMLCanvasElement;
canvas.width = canvas.height = 640;
const renderer = new RasterizationRenderer(canvas);
renderer.start();