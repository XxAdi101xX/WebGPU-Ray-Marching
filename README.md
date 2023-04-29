# WebGPU Ray Marching
A rendering engine created using WebGPU that implements the sphere tracing algorithm with signed distance functions to march rays across the scene. The current implementation supports rendering opaque objects alongside transparent ones. Phong lighting is used to luminate the scene with single scattering utilized to shade transparent volumes. 

A simple camera has been implemented to allow for using WASD to move along the x and y directions and using EQ to move along the z direction. You can orbit the camera by clicking and dragging the mouse on the canvas.

![transparent_ray_marched_volume](https://user-images.githubusercontent.com/18451835/235277701-5bd92a82-ec77-4712-b473-c0c82f09dcc5.gif)

![webgpu-raymarcher](https://user-images.githubusercontent.com/18451835/230788463-42ecb45b-5a65-4384-bc16-a7c83a6506b1.png)

## Build
To run the build, simply run `npm start` from the root folder after conducting a simple clone of the project. Then navigate to `http://127.0.0.1:8080/`.

Ensure that you have WebGPU enabled on your browser. This might require running the application using Chrome Canary.

## Resources
Some of the great learning resources that I've used for technical help and motivation:
- The offical [WebGPU Samples](https://webgpu.github.io/webgpu-samples)
- [Inigo Quizel's](https://iquilezles.org/) plethora of amazing blog posts and shadertoy samples of ray marching
- Raymarching Video Tutorial by the [GetIntoGameDev](https://www.youtube.com/watch?v=EifzQ7YsH2E&list=PLn3eTxaOtL2O6Yr-wpSRiNS9W-ZEAfPjH&index=1) youtube channel
- [Michael Walczyk's blogpost](https://michaelwalczyk.com/blog-ray-marching.html) on raymarching
- [Chris Wallis' blogpost](https://wallisc.github.io/rendering/2020/05/02/Volumetric-Rendering-Part-1.html) on ray marching transparent volumes
