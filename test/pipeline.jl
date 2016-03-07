
const shader_cache = []

function loadShaderGLSL(fileName, device::api.VkDevice, stage::api.VkShaderStageFlagBits)
	shaderCode = open(fileName) do io
        readbytes(io)
    end
	if (length(shaderCode) < 1)
        error("$filename is empty and doesn't contain a shader!")
    end
    push!(shaderCode, 0) #append 0 terminator
    # Magic SPV number for shader code header
    pcode = UInt32[0x07230203, 0, stage]

    # now append the shader code to the header
    append!(pcode, reinterpret(UInt32, shaderCode))
    # create the shader
    shadermodule = CreateShaderModule(device, C_NULL;
        sType = api.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        codeSize = sizeof(pcode),
        pCode = pcode
    )

    shaderStage = Ref{api.VkPipelineShaderStageCreateInfo}()
    shaderStage[:sType] = api.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    shaderStage[:stage] = stage;
    shaderStage[:_module] = shadermodule
    shaderStage[:pName] = "main"
    shaderStage[:pSpecializationInfo] = C_NULL
    push!(shader_cache, shadermodule)
    push!(shader_cache, pcode)

	return shaderStage[]
end


function preparePipelines(device, pipelineCache, renderPass, pipelineLayout, vertices)
	# Create our rendering pipeline used in this example
	# Vulkan uses the concept of rendering pipelines to encapsulate
	# fixed states
	# This replaces OpenGL's huge (and cumbersome) state machine
	# A pipeline is then stored and hashed on the GPU making
	# pipeline changes much faster than having to set dozens of
	# states
	# In a real world application you'd have dozens of pipelines
	# for every shader set used in a scene
	# Note that there are a few states that are not stored with
	# the pipeline. These are called dynamic states and the
	# pipeline only stores that they are used with this pipeline,
	# but not their states


	# Vertex input state
	# Describes the topoloy used with this pipeline
	inputAssemblyState = Ref{api.VkPipelineInputAssemblyStateCreateInfo}()
    inputAssemblyState[:sType] = api.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	inputAssemblyState[:pNext] = C_NULL
	# This pipeline renders vertex data as triangle lists
	inputAssemblyState[:topology] = api.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST

	# Rasterization state
	rasterizationState = Ref{api.VkPipelineRasterizationStateCreateInfo}()
	rasterizationState[:sType] = api.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
	# Solid polygon mode
	rasterizationState[:polygonMode] = api.VK_POLYGON_MODE_FILL
	# No culling
	rasterizationState[:cullMode] = api.VK_CULL_MODE_NONE
	rasterizationState[:frontFace] = api.VK_FRONT_FACE_COUNTER_CLOCKWISE
	rasterizationState[:depthClampEnable] = api.VK_FALSE
	rasterizationState[:rasterizerDiscardEnable] = api.VK_FALSE
	rasterizationState[:depthBiasEnable] = api.VK_FALSE

	# Color blend state
	# Describes blend modes and color masks
	colorBlendState = Ref{api.VkPipelineColorBlendStateCreateInfo}()
    colorBlendState[:sType] = api.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
	colorBlendState[:pNext] = C_NULL
	# One blend attachment state
	# Blending is not used in this example
	blendAttachmentState = Array(api.VkPipelineColorBlendAttachmentState, 1)
	blendAttachmentState[1, :colorWriteMask] = 0xf
	blendAttachmentState[1, :blendEnable] = api.VK_FALSE
	colorBlendState[:attachmentCount] = 1
	colorBlendState[:pAttachments] = blendAttachmentState

	# Viewport state
	viewportState = Ref{api.VkPipelineViewportStateCreateInfo}()
	viewportState[:sType] = api.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
	# One viewport
	viewportState[:viewportCount] = 1
	# One scissor rectangle
	viewportState[:scissorCount] = 1

	# Enable dynamic states
	# Describes the dynamic states to be used with this pipeline
	# Dynamic states can be set even after the pipeline has been created
	# So there is no need to create new pipelines just for changing
	# a viewport's dimensions or a scissor box
	dynamicState = Ref{api.VkPipelineDynamicStateCreateInfo}()
	# The dynamic state properties themselves are stored in the command buffer
	dynamicStateEnables = api.VkDynamicState[]
	push!(dynamicStateEnables, api.VK_DYNAMIC_STATE_VIEWPORT)
	push!(dynamicStateEnables, api.VK_DYNAMIC_STATE_SCISSOR)
	dynamicState[:sType] = api.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
	dynamicState[:pDynamicStates] = dynamicStateEnables
	dynamicState[:dynamicStateCount] = length(dynamicStateEnables)

	# Depth and stencil state
	# Describes depth and stenctil test and compare ops
	depthStencilState = Ref{api.VkPipelineDepthStencilStateCreateInfo}()
	# Basic depth compare setup with depth writes and depth test enabled
	# No stencil used
	depthStencilState[:sType] = api.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
	depthStencilState[:depthTestEnable] = api.VK_TRUE
	depthStencilState[:depthWriteEnable] = api.VK_TRUE
	depthStencilState[:depthCompareOp] = api.VK_COMPARE_OP_LESS_OR_EQUAL
	depthStencilState[:depthBoundsTestEnable] = api.VK_FALSE

	back = Ref{api.VkStencilOpState}()
	back[:failOp] = api.VK_STENCIL_OP_KEEP
	back[:passOp] = api.VK_STENCIL_OP_KEEP
	back[:compareOp] = api.VK_COMPARE_OP_ALWAYS
	depthStencilState[:back] = back[]

	depthStencilState[:stencilTestEnable] = api.VK_FALSE
	depthStencilState[:front] = back[]

	# Multi sampling state
	multisampleState = Ref{api.VkPipelineMultisampleStateCreateInfo}()
	multisampleState[:sType] = api.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
	multisampleState[:pSampleMask] = C_NULL
	# No multi sampling used in this example
	multisampleState[:rasterizationSamples] = api.VK_SAMPLE_COUNT_1_BIT

	# Load shaders
	shaderStages = Array(api.VkPipelineShaderStageCreateInfo, 2)
    shaderpath = dirname(@__FILE__)
	shaderStages[1] = loadShaderGLSL(
        joinpath(shaderpath, "triangle.vert"),
        device,
        api.VK_SHADER_STAGE_VERTEX_BIT
    )
	shaderStages[2] = loadShaderGLSL(
        joinpath(shaderpath, "triangle.frag"),
        device,
        api.VK_SHADER_STAGE_FRAGMENT_BIT
    )
    # immutable VkGraphicsPipelineCreateInfo
    #   sType :: VkStructureType
    #   pNext :: Ptr{Void}
    #   flags :: VkPipelineCreateFlags
    #   stageCount :: UInt32
    #   pStages :: Ptr{VkPipelineShaderStageCreateInfo}
    #   pVertexInputState :: Ptr{VkPipelineVertexInputStateCreateInfo}
    #   pInputAssemblyState :: Ptr{VkPipelineInputAssemblyStateCreateInfo}
    #   pTessellationState :: Ptr{VkPipelineTessellationStateCreateInfo}
    #   pViewportState :: Ptr{VkPipelineViewportStateCreateInfo}
    #   pRasterizationState :: Ptr{VkPipelineRasterizationStateCreateInfo}
    #   pMultisampleState :: Ptr{VkPipelineMultisampleStateCreateInfo}
    #   pDepthStencilState :: Ptr{VkPipelineDepthStencilStateCreateInfo}
    #   pColorBlendState :: Ptr{VkPipelineColorBlendStateCreateInfo}
    #   pDynamicState :: Ptr{VkPipelineDynamicStateCreateInfo}
    #   layout :: VkPipelineLayout
    #   renderPass :: VkRenderPass
    #   subpass :: UInt32
    #   basePipelineHandle :: VkPipeline
    #   basePipelineIndex :: Int32
    # end
    println(vertices)
    pipelineCreateInfo = Array(api.VkGraphicsPipelineCreateInfo, 1)

    pipelineCreateInfo[1, :sType] = api.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
    pipelineCreateInfo[1, :pNext] = C_NULL
    pipelineCreateInfo[1, :flags] = 0
    # The layout used for this pipeline
    pipelineCreateInfo[1, :layout] = pipelineLayout
    # Renderpass this pipeline is attached to
    pipelineCreateInfo[1, :renderPass] = renderPass
	# Assign states
	# Two shader stages
	pipelineCreateInfo[1, :stageCount] = 2
    pipelineCreateInfo[1, :pStages] = shaderStages

	# Assign pipeline state create information
	pipelineCreateInfo[1, :pVertexInputState] = vertices
	pipelineCreateInfo[1, :pInputAssemblyState] = inputAssemblyState
	pipelineCreateInfo[1, :pRasterizationState] = rasterizationState
	pipelineCreateInfo[1, :pColorBlendState] = colorBlendState
	pipelineCreateInfo[1, :pMultisampleState] = multisampleState
	pipelineCreateInfo[1, :pViewportState] = viewportState
	pipelineCreateInfo[1, :pDepthStencilState] = depthStencilState
    pipelineCreateInfo[1, :pDynamicState] = dynamicState

    pipelineCreateInfo[1, :subpass] = 0
    pipelineCreateInfo[1, :basePipelineIndex] = 0
	pipelineCreateInfo[1, :basePipelineHandle] = C_NULL


	# Create rendering pipeline
    pipeline_ref = Ref{api.VkPipeline}(api.VK_NULL_HANDLE)
	err = api.vkCreateGraphicsPipelines(device, pipelineCache, 1, pipelineCreateInfo, C_NULL, pipeline_ref)
	check(err)
    pipeline_ref[]
end