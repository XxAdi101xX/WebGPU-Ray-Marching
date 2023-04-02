import { vec3 } from "gl-matrix";

import { Sphere } from "./primatives";
import { Camera } from "./camera";

export class Scene {
    sphereData: Sphere[];
    camera: Camera;

    constructor() {
        this.sphereData = new Array(64);
        for (let i = 0; i < this.sphereData.length; ++i) {
            const center: vec3 = [
                3.0 + 7.0 * Math.random(),
                -5.0 + 10.0 * Math.random(),
                -5.0 + 10.0 * Math.random()
            ];

            const radius: number = 0.1 + 1.9 * Math.random();

            const color: vec3 = [
                0.3 + 0.7 * Math.random(),
                0.3 + 0.7 * Math.random(),
                0.3 + 0.7 * Math.random()
            ];

            this.sphereData[i] = new Sphere(center, radius,color);
        }

        this.camera = new Camera([-80.0, 0.0, 0.0]);
    }
}