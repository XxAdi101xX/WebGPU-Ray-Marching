import { vec2, vec3 } from "gl-matrix"

export class Camera {
    position: vec3
    euler: vec3
    forward: vec3
    right: vec3
    up: vec3

    constructor(position: vec3, verticalRotation: number, horizontalRotation: number) {
        this.position = position;
        this.euler = [0.0, verticalRotation, horizontalRotation]
        this.right = [0.0, 0.0, 0.0];
        this.up = [0.0, 0.0, 0.0];

        this.update();
    }

    update(): void {
        this.forward = [
            Math.cos(this.#degreesToRadians(this.euler[2])) * Math.cos(this.#degreesToRadians(this.euler[1])),
            Math.sin(this.#degreesToRadians(this.euler[2])) * Math.cos(this.#degreesToRadians(this.euler[1])),
            Math.sin(this.#degreesToRadians(this.euler[1]))
        ];
        vec3.cross(this.right, this.forward, [0.0, 0.0, 1.0]);
        vec3.cross(this.up, this.right, this.forward);
    }

    pan(dx: number, dy: number): void {
        // Moving front/back
        vec3.scaleAndAdd(
            this.position, this.position, 
            this.forward, dx
        );

        // Moving right/left
        vec3.scaleAndAdd(
            this.position, this.position, 
            this.right, dy
        );
    }

    #degreesToRadians(degrees: number): number {
        return degrees * 180.0 / Math.PI;
    }
}