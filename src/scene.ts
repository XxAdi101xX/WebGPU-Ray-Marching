import { vec3 } from "gl-matrix";

import { Sphere } from "./primatives";
import { Camera } from "./camera";

export class Scene {
    sphereData: Sphere[];
    camera: Camera;
    mouseClicked: boolean

    constructor() {
        this.sphereData = new Array(10);
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
            
            this.sphereData[i] = new Sphere(center, radius, color);
        }
        
        this.camera = new Camera([-10.0, 0.0, 0.0], 0.0, 0.0);
        this.mouseClicked = false;

        document.addEventListener("keydown", this.#handleKeyDown);
        document.addEventListener("mousedown", this.#handleMouseDown);
        document.addEventListener("mouseup", this.#handleMouseUp);
        document.addEventListener("mousemove", this.#handleMouseEvent);
    }

    #handleKeyDown = (event: KeyboardEvent): void => {
        const movementFactor: number = 0.4;

        if (event.code == "KeyW") {
            this.camera.pan(movementFactor, 0.0);
        }
        if (event.code == "KeyS") {
            this.camera.pan(-movementFactor, 0.0);
        }
        if (event.code == "KeyA") {
            this.camera.pan(0.0, -movementFactor);
        }
        if (event.code == "KeyD") {
            this.camera.pan(0.0, movementFactor);
        }
    }

    #handleMouseDown = (event: MouseEvent): void => {
        this.mouseClicked = true;
    }

    #handleMouseUp = (event: MouseEvent): void => {
        this.mouseClicked = false;
    }

    #handleMouseEvent = (event: MouseEvent): void => {
        if (!this.mouseClicked) {
            return;
        }

        const dampningFactor: number = 40000;
        const dx: number = event.movementX / dampningFactor;
        const dy: number = event.movementY / dampningFactor;

        this.camera.euler[2] = (this.camera.euler[2] + dx) % 360;
        this.camera.euler[1] = Math.min(
            89.0,
            Math.max(
                -89.0,
                this.camera.euler[1] + dy
            )
        );
    }
}