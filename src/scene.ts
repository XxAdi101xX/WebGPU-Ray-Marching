import { vec3 } from "gl-matrix";

import { Sphere } from "./primatives";
import { Camera } from "./camera";

export class Light {
    position: vec3;
    padding: number;

    constructor(position: vec3) {
        this.position = position;
        this.padding = 0.0;
    }
}

export class Scene {
    sphereData: Sphere[];
    camera: Camera;
    lights: Light[];

    mouseClicked: boolean

    constructor() {
        // Setup spheres
        this.sphereData = new Array(1);
        // Hardcode first sphere
        const center: vec3 = [0.0, 3.0, 0.0];
        const radius: number = 1.1;
        const color: vec3 = [0.0, 0.5, 0.8];
        this.sphereData[0] = new Sphere(center, radius, color);

        for (let i = 1; i < this.sphereData.length; ++i) {
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
        
        // Setup camera
        this.camera = new Camera([-10.0, 0.0, 0.0], 0.0, 0.0);

        // Setup lights
        this.lights = new Array(1);
        this.lights[0] = new Light([11.0, -15.0, -12.0]);

        this.mouseClicked = false;

        document.addEventListener("keydown", this.#handleKeyDown);
        document.addEventListener("mousedown", this.#handleMouseDown);
        document.addEventListener("mouseup", this.#handleMouseUp);
        document.addEventListener("mousemove", this.#handleMouseEvent);

        // TODO: this code only expects one light to control atm
        const lightX = document.getElementById("lightX");
        const lightY = document.getElementById("lightY");
        const lightZ = document.getElementById("lightZ");
        
        lightX.value = this.lights[0].position[0];
        lightY.value = this.lights[0].position[1];
        lightZ.value = this.lights[0].position[2];

        lightX.addEventListener("input", this.#updateLight);
        lightY.addEventListener("input", this.#updateLight);
        lightZ.addEventListener("input", this.#updateLight);
    }

    #handleKeyDown = (event: KeyboardEvent): void => {
        const movementFactor: number = 0.4;

        if (event.code == "KeyW") {
            this.camera.pan(movementFactor, 0.0, 0.0);
        }
        if (event.code == "KeyS") {
            this.camera.pan(-movementFactor, 0.0, 0.0);
        }
        if (event.code == "KeyA") {
            this.camera.pan(0.0, -movementFactor, 0.0);
        }
        if (event.code == "KeyD") {
            this.camera.pan(0.0, movementFactor, 0.0);
        }
        if (event.code == "KeyE") {
            this.camera.pan(0.0, 0.0, movementFactor);
        }
        if (event.code == "KeyQ") {
            this.camera.pan(0.0, 0.0, -movementFactor);
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

    #updateLight = (event) => {
        const inputId = event.target.id;
        const inputValue = event.target.value;
        if (inputId === "lightX") {
            this.lights[0].position[0] = inputValue;
        } else if (inputId === "lightY") {
            this.lights[0].position[1] = inputValue;
        } else if (inputId === "lightZ") {
            this.lights[0].position[2] = inputValue;
        }
    }
}