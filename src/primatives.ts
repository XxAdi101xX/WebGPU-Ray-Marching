import { vec3 } from "gl-matrix";

// Considering the padding when adding/removing member variables and make sure to update the buffer sizes in the renderer
export class Sphere {
    center: vec3
    radius: number
    color: vec3
    padding: number // padding to 32 bytes

    constructor(center: vec3, radius: number, color: vec3) {
        this.center = center;
        this.radius = radius;
        this.color = color;
        this.padding = 0.0;
    }
}