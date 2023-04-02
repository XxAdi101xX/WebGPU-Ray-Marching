import { vec3 } from "gl-matrix"

export class Camera {
    position: vec3
    theta: number
    phi: number
    forward: vec3
    right: vec3
    up: vec3

    constructor(position: vec3) {
        this.position = position;
        this.theta = 0.0; // Rotation in the horizonal plane
        this.phi = 0.0; // Rotation in the vertical plane

        this.forward = [
            Math.cos(this.theta * 180.0 / Math.PI) * Math.cos(this.phi * 180.0 / Math.PI),
            Math.sin(this.theta * 180.0 / Math.PI) * Math.cos(this.phi * 180.0 / Math.PI),
            Math.sin(this.phi * 180.0 / Math.PI)
        ];
        
        this.right = [0.0, 0.0, 0.0];
        vec3.cross(this.right, this.forward, [0.0, 0.0, 1.0]);
        this.up = [0.0, 0.0, 0.0];
        vec3.cross(this.up, this.right, this.forward);
    }

    moveCamera(dx: number, dy: number) {
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
}