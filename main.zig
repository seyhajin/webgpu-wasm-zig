const std = @import("std");

const c = @cImport({
    @cInclude("emscripten.h");
    @cInclude("emscripten/html5.h");
    @cInclude("emscripten/html5_webgpu.h");
    @cInclude("webgpu/webgpu.h");
});

const State = struct {
    // canvas
    canvas: struct {
        name: []const u8 = "",
        width: i32 = 0,
        height: i32 = 0,
    } = .{},

    // wgpu
    wgpu: struct {
        instance: c.WGPUInstance = null,
        device: c.WGPUDevice = null,
        queue: c.WGPUQueue = null,
        swapchain: c.WGPUSwapChain = null,
        pipeline: c.WGPURenderPipeline = null,
    } = .{},
    
    // resources
    res: struct {
        vbuffer: c.WGPUBuffer = null,
        ibuffer: c.WGPUBuffer = null,
        ubuffer: c.WGPUBuffer = null,
        bindgroup: c.WGPUBindGroup = null,
    } = .{},

    // vars
    vars: struct {
        rot: f32 = 0.0,
    } = .{},
};

var state = State{};

//--------------------------------------------------
// vertex and fragment shaders
//--------------------------------------------------

const wgsl_triangle = 
\\  /* attribute/uniform decls */
\\  
\\  struct VertexIn {
\\      @location(0) aPos : vec2<f32>,
\\      @location(1) aCol : vec3<f32>,
\\  };
\\  struct VertexOut {
\\      @location(0) vCol : vec3<f32>,
\\      @builtin(position) Position : vec4<f32>,
\\  };
\\  struct Rotation {
\\      @location(0) degs : f32,
\\  };
\\  @group(0) @binding(0) var<uniform> uRot : Rotation;
\\  
\\  /* vertex shader */
\\  
\\  @vertex
\\  fn vs_main(input : VertexIn) -> VertexOut {
\\      var rads : f32 = radians(uRot.degs);
\\      var cosA : f32 = cos(rads);
\\      var sinA : f32 = sin(rads);
\\      var rot : mat3x3<f32> = mat3x3<f32>(
\\          vec3<f32>( cosA, sinA, 0.0),
\\          vec3<f32>(-sinA, cosA, 0.0),
\\          vec3<f32>( 0.0,  0.0,  1.0));
\\      var output : VertexOut;
\\      output.Position = vec4<f32>(rot * vec3<f32>(input.aPos, 1.0), 1.0);
\\      output.vCol = input.aCol;
\\      return output;
\\  }
\\  
\\  /* fragment shader */
\\  
\\  @fragment
\\  fn fs_main(@location(0) vCol : vec3<f32>) -> @location(0) vec4<f32> {
\\      return vec4<f32>(vCol, 1.0);
\\  }
;

//--------------------------------------------------
//
// main
//
//--------------------------------------------------

pub fn main() !void {
    
    //-----------------
    // init
    //-----------------
    state.canvas.name = "canvas";
    state.wgpu.instance = c.wgpuCreateInstance(null);
    state.wgpu.device = c.emscripten_webgpu_get_device();
    state.wgpu.queue = c.wgpuDeviceGetQueue(state.wgpu.device);

    _ = resize(0, null, null);
    _ = c.emscripten_set_resize_callback(2, null, 0, resize); //FIXME: use `EMSCRIPTEN_EVENT_TARGET_WINDOW` const

    //-----------------
    // Setup pipeline
    //-----------------

    // Compile shaders
    const shader_triangle = createShader(wgsl_triangle, "triangle");

    // Describe buffer layouts
    const vertex_attributes = [2]c.WGPUVertexAttribute{
        .{
            .format = c.WGPUVertexFormat_Float32x2,
            .offset = 0,
            .shaderLocation = 0,
        },
        .{
            .format = c.WGPUVertexFormat_Float32x3,
            .offset = 2 * @sizeOf(f32),
            .shaderLocation = 1,
        },
    };
    const vertex_buffer_layout = c.WGPUVertexBufferLayout{
        .arrayStride = 5 * @sizeOf(f32),
        .attributeCount = 2,
        .attributes = &vertex_attributes,
    };

    // Describe pipeline layout
    const bindgroup_layout = c.wgpuDeviceCreateBindGroupLayout(state.wgpu.device, &c.WGPUBindGroupLayoutDescriptor{
        .entryCount = 1,
        // Bind group layout entry
        .entries = &c.WGPUBindGroupLayoutEntry{
            .binding = 0,
            .visibility = c.WGPUShaderStage_Vertex,
            // Buffer binding layout
            .buffer = .{
                .type = c.WGPUBufferBindingType_Uniform,
            }
        }
    });
    const pipeline_layout = c.wgpuDeviceCreatePipelineLayout(state.wgpu.device, &c.WGPUPipelineLayoutDescriptor{
        .bindGroupLayoutCount = 1,
        .bindGroupLayouts = &bindgroup_layout,
    });

    // Create pipeline
    state.wgpu.pipeline = c.wgpuDeviceCreateRenderPipeline(state.wgpu.device, &c.WGPURenderPipelineDescriptor{
        // Pipeline layout
        .layout = pipeline_layout,
        // Primitive state
        .primitive = .{
            .frontFace = c.WGPUFrontFace_CCW,
            .cullMode = c.WGPUCullMode_None,
            .topology = c.WGPUPrimitiveTopology_TriangleList,
            .stripIndexFormat = c.WGPUIndexFormat_Undefined,
        },
        // Vertex state
        .vertex = .{
            .module = shader_triangle,
            .entryPoint = "vs_main",
            .bufferCount = 1,
            .buffers = &vertex_buffer_layout,
        },
        // Fragment state
        .fragment = &c.WGPUFragmentState{
            .module = shader_triangle,
            .entryPoint = "fs_main",
            .targetCount = 1,
            // color target state
            .targets = &c.WGPUColorTargetState{
                .format = c.WGPUTextureFormat_BGRA8Unorm,
                .writeMask = c.WGPUColorWriteMask_All,
                // blend state
                .blend = &c.WGPUBlendState{
                    .color = .{
                        .operation = c.WGPUBlendOperation_Add,
                        .srcFactor = c.WGPUBlendFactor_One,
                        .dstFactor = c.WGPUBlendFactor_One,
                    },
                    .alpha = .{
                        .operation = c.WGPUBlendOperation_Add,
                        .srcFactor = c.WGPUBlendFactor_One,
                        .dstFactor = c.WGPUBlendFactor_One,
                    },
                },
            },
        },
        // Multi-sampling state
        .multisample = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
            .alphaToCoverageEnabled = false,
        },
        // Depth-stencil state
        .depthStencil = null,
    });

    c.wgpuBindGroupLayoutRelease(bindgroup_layout);
    c.wgpuPipelineLayoutRelease(pipeline_layout);
    c.wgpuShaderModuleRelease(shader_triangle);

    //-----------------
    // Setup scene
    //-----------------

    // Create the vertex buffer (x, y, r, g, b) and index buffer
    const vertex_data = [_]f32{
        // x, y          // r, g, b
       -0.5, -0.5,     1.0, 0.0, 0.0, // bottom-left
        0.5, -0.5,     0.0, 1.0, 0.0, // bottom-right
        0.5,  0.5,     0.0, 0.0, 1.0, // top-right
       -0.5,  0.5,     1.0, 1.0, 0.0, // top-left
    };
    const index_data = [_]u16{
        0, 1, 2,
        0, 2, 3,
    };
    state.res.vbuffer = createBuffer(&vertex_data, @sizeOf(@TypeOf(vertex_data)), c.WGPUBufferUsage_Vertex);
    state.res.ibuffer = createBuffer(&index_data, @sizeOf(@TypeOf(index_data)), c.WGPUBufferUsage_Index);
    
    // Create the uniform bind group
    state.res.ubuffer = createBuffer(&state.vars.rot, @sizeOf(@TypeOf(state.vars.rot)), c.WGPUBufferUsage_Uniform);
    state.res.bindgroup = c.wgpuDeviceCreateBindGroup(state.wgpu.device, &c.WGPUBindGroupDescriptor{
        .layout = c.wgpuRenderPipelineGetBindGroupLayout(state.wgpu.pipeline, 0),
        .entryCount = 1,
        // Bind group entry
        .entries = &c.WGPUBindGroupEntry{
            .binding = 0,
            .offset = 0,
            .buffer = state.res.ubuffer,
            .size = @sizeOf(@TypeOf(state.vars.rot)),
        },
    });

    //-----------------
    // Main loop
    //-----------------

    c.emscripten_set_main_loop(draw, 0, 1);

    //-----------------
    // Quit
    //-----------------

    c.wgpuRenderPipelineRelease(state.wgpu.pipeline);
    c.wgpuSwapChainRelease(state.wgpu.swapchain);
    c.wgpuQueueRelease(state.wgpu.queue);
    c.wgpuDeviceRelease(state.wgpu.device);
    c.wgpuInstanceRelease(state.wgpu.instance);
}


//--------------------------------------------------
// callbacks and functions
//--------------------------------------------------

fn draw() callconv(.C) void {
    // Update rotation
    state.vars.rot += 0.1;
    state.vars.rot = if (state.vars.rot >= 360) 0.0 else state.vars.rot;
    c.wgpuQueueWriteBuffer(state.wgpu.queue, state.res.ubuffer, 0, &state.vars.rot, @sizeOf(@TypeOf(state.vars.rot)));

    // Create Texture View
    const back_buffer = c.wgpuSwapChainGetCurrentTextureView(state.wgpu.swapchain);

    // Create Command Encoder
    const cmd_encoder = c.wgpuDeviceCreateCommandEncoder(state.wgpu.device, null);

    // Begin Render Pass
    const render_pass = c.wgpuCommandEncoderBeginRenderPass(cmd_encoder, &c.WGPURenderPassDescriptor{
        .colorAttachmentCount = 1,
        .colorAttachments = &c.WGPURenderPassColorAttachment{
            .view = back_buffer,
            .loadOp = c.WGPULoadOp_Clear,
            .storeOp = c.WGPUStoreOp_Store,
            .clearValue = c.WGPUColor{ .r = 0.2, .g = 0.2, .b = 0.3, .a = 1.0 },
        },
    });

    // Draw quad (comment these five lines to simply clear the screen)
    c.wgpuRenderPassEncoderSetPipeline(render_pass, state.wgpu.pipeline);
    c.wgpuRenderPassEncoderSetBindGroup(render_pass, 0, state.res.bindgroup, 0, 0);
    c.wgpuRenderPassEncoderSetVertexBuffer(render_pass, 0, state.res.vbuffer, 0, c.WGPU_WHOLE_SIZE);
    c.wgpuRenderPassEncoderSetIndexBuffer(render_pass, state.res.ibuffer, c.WGPUIndexFormat_Uint16, 0, c.WGPU_WHOLE_SIZE);
    c.wgpuRenderPassEncoderDrawIndexed(render_pass, 6, 1, 0, 0, 0);

    // End Render Pass
    c.wgpuRenderPassEncoderEnd(render_pass);

    // Create Command Buffer
    const cmd_buffer = c.wgpuCommandEncoderFinish(cmd_encoder, null); // after 'end render pass'

    // Submit commands    
    c.wgpuQueueSubmit(state.wgpu.queue, 1, &cmd_buffer);

    // Release all
    c.wgpuRenderPassEncoderRelease(render_pass);
    c.wgpuCommandEncoderRelease(cmd_encoder);
    c.wgpuCommandBufferRelease(cmd_buffer);
    c.wgpuTextureViewRelease(back_buffer);
}

fn resize(event_type: i32, ui_event: ?*const c.EmscriptenUiEvent, user_data: ?*anyopaque) callconv(.C) i32 {
    _ = event_type; _ = ui_event; _ = user_data; // unused

    var w: f64 = 0;
    var h: f64 = 0;
    _ = c.emscripten_get_element_css_size(state.canvas.name.ptr, &w, &h);


    state.canvas.width = @intFromFloat(w);
    state.canvas.height = @intFromFloat(h);
    _ = c.emscripten_set_canvas_element_size(state.canvas.name.ptr, @intCast(state.canvas.width), @intCast(state.canvas.height));
    //c.emscripten_console_logf("canvas.size: %d x %d\n", state.canvas.width, state.canvas.height);

    if (state.wgpu.swapchain != null) {
        c.wgpuSwapChainRelease(state.wgpu.swapchain);
        state.wgpu.swapchain = null;
    }

    state.wgpu.swapchain = createSwapchain();

    return 1;
}

fn createSwapchain() c.WGPUSwapChain {
    const surface = c.wgpuInstanceCreateSurface(state.wgpu.instance, &c.WGPUSurfaceDescriptor{
        .nextInChain = @ptrCast(&c.WGPUSurfaceDescriptorFromCanvasHTMLSelector{
            .chain = .{ .sType = c.WGPUSType_SurfaceDescriptorFromCanvasHTMLSelector },
            .selector = state.canvas.name.ptr,
        }),
    });

    return c.wgpuDeviceCreateSwapChain(state.wgpu.device, surface, &c.WGPUSwapChainDescriptor{
        .usage = c.WGPUTextureUsage_RenderAttachment,
        .format = c.WGPUTextureFormat_BGRA8Unorm,
        .width = @intCast(state.canvas.width),
        .height = @intCast(state.canvas.height),
        .presentMode = c.WGPUPresentMode_Fifo,
    });
}

fn createShader(code: [*:0]const u8, label: [*:0]const u8) c.WGPUShaderModule {
    const wgsl = c.WGPUShaderModuleWGSLDescriptor{
        .chain = .{ .sType = c.WGPUSType_ShaderModuleWGSLDescriptor },
        .code = code,
    };

    return c.wgpuDeviceCreateShaderModule(state.wgpu.device, &c.WGPUShaderModuleDescriptor{
        .nextInChain = @ptrCast(&wgsl),
        .label = label
    });
}

fn createBuffer(data: ?*const anyopaque, size: usize, usage: c.WGPUBufferUsage) c.WGPUBuffer {
    const buffer = c.wgpuDeviceCreateBuffer(state.wgpu.device, &c.WGPUBufferDescriptor{
        .usage = @as(c.enum_WGPUBufferUsage, c.WGPUBufferUsage_CopyDst) | usage,
        .size = size,
    });
    c.wgpuQueueWriteBuffer(state.wgpu.queue, buffer, 0, data, size);
    return buffer;
}