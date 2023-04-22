import rayMarchingCompute from './shaders/ray-marching.compute.wgsl';
import postProcessingVertexShader from "./shaders/post-processing.vert.wgsl"
import postProcessingFragmentShader from "./shaders/post-processing.frag.wgsl"
import { Scene } from './scene';
import { vec3 } from 'gl-matrix';

export default class RasterizationRenderer {
    canvas: HTMLCanvasElement;

    // ⚙️ API Data Structures
    adapter: GPUAdapter;
    device: GPUDevice;
    queue: GPUQueue;

    // 🎞️ Frame Backings
    context: GPUCanvasContext;
    colorTexture: GPUTexture;
    colorTextureView: GPUTextureView;

    // 🔺 Resources
    rayMarchingPipeline: GPUComputePipeline;
    rayMarchingGlobalBindGroup: GPUBindGroup;
    rayMarchingObjectBindGroup: GPUBindGroup;
    postProcessingPipeline: GPURenderPipeline;
    postProcessingPipelineBindGroup: GPUBindGroup;
    sampler: GPUSampler;
    applicationDataBuffer: GPUBuffer;
    lightBuffer: GPUBuffer;
    sphereBuffer: GPUBuffer;

    commandEncoder: GPUCommandEncoder;
    passEncoder: GPURenderPassEncoder;

    scene: Scene;

    applicationStart: DOMHighResTimeStamp;

    constructor(canvas: HTMLCanvasElement, scene: Scene) {
        this.scene = scene;
        this.canvas = canvas;
        this.applicationStart = performance.now();
    }

    // 🏎️ Start the rendering engine
    async start() {
        if (await this.initializeAPI()) {
            this.resizeBackings();
            await this.initializeResources();
            this.render();
        }
    }

    // 🌟 Initialize WebGPU
    async initializeAPI(): Promise<boolean> {
        try {
            // 🏭 Entry to WebGPU
            const entry: GPU = navigator.gpu;
            if (!entry) {
                return false;
            }

            // 🔌 Physical Device Adapter
            this.adapter = await entry.requestAdapter();

            // 💻 Logical Device
            this.device = await this.adapter.requestDevice();

            // 📦 Queue
            this.queue = this.device.queue;
        } catch (e) {
            console.error(e);
            return false;
        }

        return true;
    }

    // 🍱 Initialize resources to render triangle (buffers, shaders, pipeline)
    async initializeResources() {
        // Initialize textures, buffers and samplers
        this.colorTexture = this.device.createTexture(
            {
                size: {
                    width: this.canvas.width,
                    height: this.canvas.height,
                },
                format: "rgba8unorm",
                usage: GPUTextureUsage.COPY_DST | GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING
            }
        );

        this.colorTextureView = this.colorTexture.createView();

        const samplerDescriptor: GPUSamplerDescriptor = {
            addressModeU: "repeat",
            addressModeV: "repeat",
            magFilter: "linear",
            minFilter: "nearest",
            mipmapFilter: "nearest",
            maxAnisotropy: 1
        };
        this.sampler = this.device.createSampler(samplerDescriptor);

        const applicationDataBufferDescriptor: GPUBufferDescriptor = {
            label: "Application Data Buffer",
            size: Float32Array.BYTES_PER_ELEMENT * 16, // 4 vec3 + f32 for sphere count + 3 f32 padding = 16 f32 entries; ensure atleast 64 bytes and multiple of 16
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        };

        this.applicationDataBuffer = this.device.createBuffer(
            applicationDataBufferDescriptor
        );

        const lightBufferDescriptor: GPUBufferDescriptor = {
            label: "Light Buffer",
            size: Float32Array.BYTES_PER_ELEMENT * 4, // 3 for light position, 1 padding
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
        };

        this.lightBuffer = this.device.createBuffer(
            lightBufferDescriptor
        );

        const sphereBufferDescriptor: GPUBufferDescriptor = {
            label: "Spheres Buffer",
            size: Float32Array.BYTES_PER_ELEMENT * 16 /* 16 Float entires in struct*/ * this.scene.sphereData.length,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
        };
        this.sphereBuffer = this.device.createBuffer(
            sphereBufferDescriptor
        );

        // Ray-marching global binding setup
        const rayMarchingGlobalBindGroupLayout = this.device.createBindGroupLayout({
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.COMPUTE,
                    storageTexture: {
                        access: "write-only",
                        format: "rgba8unorm",
                        viewDimension: "2d"
                    }
                },
                {
                    binding: 1,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: {
                        type: "uniform",
                    }
                },
                {
                    binding: 2,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: {
                        type: "read-only-storage",
                    }
                }
            ]
        });
    
        this.rayMarchingGlobalBindGroup = this.device.createBindGroup({
            layout: rayMarchingGlobalBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: this.colorTextureView
                },
                {
                    binding: 1,
                    resource: {
                        buffer: this.applicationDataBuffer,
                    }
                },
                {
                    binding: 2,
                    resource: {
                        buffer: this.lightBuffer,
                    }
                }
            ]
        });

        // Ray-marching object binding setup
        const rayMarchingObjectBindGroupLayout = this.device.createBindGroupLayout({
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: {
                        type: "read-only-storage",
                        hasDynamicOffset: false
                    }
                }
            ]
        });
    
        this.rayMarchingObjectBindGroup = this.device.createBindGroup({
            layout: rayMarchingObjectBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: {
                        buffer: this.sphereBuffer,
                    }
                }
            ]
        });
        
        // Create ray marching pipeline layout and pipeline
        const rayMarchingPipelineLayout = this.device.createPipelineLayout({
            bindGroupLayouts: [rayMarchingGlobalBindGroupLayout, rayMarchingObjectBindGroupLayout]
        });

        this.rayMarchingPipeline = await this.device.createComputePipelineAsync({
            layout: rayMarchingPipelineLayout,
            compute: {
                module: this.device.createShaderModule({
                    code: rayMarchingCompute,
                }),
                entryPoint: 'main',
            },
        });

        // Post processing rasterization pipeline setup
        const postProcessingBindGroupLayout = this.device.createBindGroupLayout({
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.FRAGMENT,
                    sampler: {}
                },
                {
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {}
                },
            ]

        });

        this.postProcessingPipelineBindGroup = this.device.createBindGroup({
            layout: postProcessingBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource:  this.sampler
                },
                {
                    binding: 1,
                    resource: this.colorTextureView
                }
            ]
        });

        const postProcessingPipelineLayout = this.device.createPipelineLayout({
            bindGroupLayouts: [postProcessingBindGroupLayout]
        });

        this.postProcessingPipeline = await this.device.createRenderPipelineAsync({
            layout: postProcessingPipelineLayout,
            
            vertex: {
                module: this.device.createShaderModule({
                code: postProcessingVertexShader,
            }),
            entryPoint: 'main',
            },

            fragment: {
                module: this.device.createShaderModule({
                code: postProcessingFragmentShader,
            }),
            entryPoint: 'main',
            targets: [
                {
                    format: "bgra8unorm"
                }
            ]
            },

            primitive: {
                topology: "triangle-list"
            }
        });
    }

    // ↙️ Resize swapchain, frame buffer attachments
    resizeBackings(): void {
        // ⛓️ Swapchain
        if (!this.context) {
            this.context = this.canvas.getContext('webgpu');
            const canvasConfig: GPUCanvasConfiguration = {
                device: this.device,
                format: 'bgra8unorm',
                usage:
                    GPUTextureUsage.RENDER_ATTACHMENT |
                    GPUTextureUsage.COPY_SRC,
                    alphaMode: 'opaque'
            };
            this.context.configure(canvasConfig);
        }
    }

    createScene(): void {
        // If updating these objects, make sure to update the size of the buffer that holds the sceneData
        const applicationData = {
            cameraPosition: this.scene.camera.position,
            lightCount: this.scene.lights.length,
            cameraForward: this.scene.camera.forward,
            sphereCount: this.scene.sphereData.length,
            cameraRight: this.scene.camera.right,
            time: performance.now() - this.applicationStart,
            cameraUp: this.scene.camera.up,
            padding1: 0.0
        }

        // Write application data
        this.device.queue.writeBuffer(
            this.applicationDataBuffer, 0,
            new Float32Array(
                [
                    applicationData.cameraPosition[0],
                    applicationData.cameraPosition[1],
                    applicationData.cameraPosition[2],
                    applicationData.lightCount,
                    applicationData.cameraForward[0],
                    applicationData.cameraForward[1],
                    applicationData.cameraForward[2],
                    applicationData.sphereCount,
                    applicationData.cameraRight[0],
                    applicationData.cameraRight[1],
                    applicationData.cameraRight[2],
                    applicationData.time,
                    applicationData.cameraUp[0],
                    applicationData.cameraUp[1],
                    applicationData.cameraUp[2],
                    applicationData.padding1
                ]
            ), 0, 16
        )

        // Write light data
        const lightStructSize: number = 4;
        const lightData: Float32Array = new Float32Array(lightStructSize * this.scene.lights.length);
        for (let i = 0; i < this.scene.lights.length; i++) {
            lightData[lightStructSize * i] = this.scene.lights[i].position[0];
            lightData[lightStructSize * i + 1] = this.scene.lights[i].position[1];
            lightData[lightStructSize * i + 2] = this.scene.lights[i].position[2];
            lightData[lightStructSize * i + 3] = this.scene.lights[i].padding;
        }
        this.device.queue.writeBuffer(this.lightBuffer, 0, lightData, 0, lightStructSize * this.scene.lights.length);

        // Write sphere data
        const sphereStructSize: number = 8;
        const sphereData: Float32Array = new Float32Array(sphereStructSize * this.scene.sphereData.length);
        for (let i = 0; i < this.scene.sphereData.length; i++) {
            sphereData[sphereStructSize * i] = this.scene.sphereData[i].center[0];
            sphereData[sphereStructSize * i + 1] = this.scene.sphereData[i].center[1];
            sphereData[sphereStructSize * i + 2] = this.scene.sphereData[i].center[2];
            sphereData[sphereStructSize * i + 3] = this.scene.sphereData[i].radius;
            sphereData[sphereStructSize * i + 4] = this.scene.sphereData[i].color[0];
            sphereData[sphereStructSize * i + 5] = this.scene.sphereData[i].color[1];
            sphereData[sphereStructSize * i + 6] = this.scene.sphereData[i].color[2];
            sphereData[sphereStructSize * i + 7] = this.scene.sphereData[i].padding;
        }

        this.device.queue.writeBuffer(this.sphereBuffer, 0, sphereData, 0, sphereStructSize * this.scene.sphereData.length);
    }

    // ✍️ Write commands to send to the GPU
    encodeCommands(): void {
        this.createScene();
        this.scene.camera.update();

        const commandEncoder = this.device.createCommandEncoder();

        const rayMarchingComputePass = commandEncoder.beginComputePass();
        rayMarchingComputePass.setPipeline(this.rayMarchingPipeline);
        rayMarchingComputePass.setBindGroup(0, this.rayMarchingGlobalBindGroup);
        rayMarchingComputePass.setBindGroup(1, this.rayMarchingObjectBindGroup);
        rayMarchingComputePass.dispatchWorkgroups(this.canvas.width, this.canvas.height, 1);
        rayMarchingComputePass.end();

        // TODO we need barrier between compute shader invocation and post processing pass?

        const renderpass : GPURenderPassEncoder = commandEncoder.beginRenderPass({
            colorAttachments: [{
                view: this.colorTextureView,
                clearValue: {r: 0.5, g: 0.0, b: 0.25, a: 1.0},
                loadOp: "clear",
                storeOp: "store"
            }]
        });

        renderpass.setPipeline(this.postProcessingPipeline);
        renderpass.setBindGroup(0, this.postProcessingPipelineBindGroup);
        renderpass.draw(3, 1, 0, 0);
        
        renderpass.end();
    
        this.device.queue.submit([commandEncoder.finish()]);
    }

    render = (): void => {
        const frameRenderStart: number = performance.now();

        // ⏭ Acquire next image from context
        this.colorTexture = this.context.getCurrentTexture();
        this.colorTextureView = this.colorTexture.createView();

        // 📦 Write and submit commands to queue
        this.encodeCommands();

        this.device.queue.onSubmittedWorkDone().then(
            () => {
                const frameRenderEnd: number = performance.now();
                const performanceLabel: HTMLElement =  <HTMLElement> document.getElementById("render-time");
                if (performanceLabel) {
                    performanceLabel.innerText = (frameRenderEnd - frameRenderStart).toFixed(2);
                }
            }
        );

        // ➿ Refresh canvas
        requestAnimationFrame(this.render);
    };
}