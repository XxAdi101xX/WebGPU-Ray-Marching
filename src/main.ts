import { Scene } from './scene';
import RayMarchingRenderer from './ray-marching-renderer';

const canvas = document.getElementById('gfx') as HTMLCanvasElement;
canvas.width = canvas.height = 800;

const scene: Scene = new Scene();
const renderer: RayMarchingRenderer = new RayMarchingRenderer(canvas, scene);

renderer.start();