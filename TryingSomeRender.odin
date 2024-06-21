package main

import "core:fmt"
import "core:mem"
import "core:os"

import "vendor:glfw"
import vk "vendor:vulkan"

SCREEN_WIDTH : i32 :  800
SCREEN_HEIGHT : i32 : 600

DEVICE_EXTENSIONS := [?]cstring{
	"VK_KHR_swapchain",
};
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"};

Context :: struct {
    instance : vk.Instance,
    physical_device: vk.PhysicalDevice,
    swapchain: Swapchain,
    device: vk.Device,
    queue_indices:   [QueueFamily]int,
	queues:   [QueueFamily]vk.Queue,
    surface:  vk.SurfaceKHR,
    window:   glfw.WindowHandle,
}

QueueFamily :: enum
{
	Graphics,
	Present,
}

Swapchain :: struct
{
    handle: vk.SwapchainKHR,
	images: []vk.Image,
	image_views: []vk.ImageView,
	format: vk.SurfaceFormatKHR,
	extent: vk.Extent2D,
	present_mode: vk.PresentModeKHR,
	image_count: u32,
	support: SwapChainDetails,
	framebuffers: []vk.Framebuffer,
}

SwapChainDetails :: struct
{
    capabilities : vk.SurfaceCapabilitiesKHR,
    formats : []vk.SurfaceFormatKHR,
    presentModes : []vk.PresentModeKHR
}

initVulkan::proc(using ctx: ^Context)
{
    context.user_ptr = &instance;
	get_proc_address :: proc(p: rawptr, name: cstring) 
	{
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name);
	}
	
	vk.load_proc_addresses(get_proc_address);
    createInstance(ctx)
    vk.load_proc_addresses(get_proc_address);

    extensions := GetExtensions();
	for ext in &extensions do fmt.println(cstring(&ext.extensionName[0]));

    CreateSurface(ctx)
    pickPhysicalDevice(ctx)
    findQueueFamilies(ctx)
    createDevice(ctx)

    fmt.println("Queue Indices:");
	for q, f in queue_indices do fmt.printf("  %v: %d\n", f, q);

    for q, f in &queues
	{
		vk.GetDeviceQueue(device, u32(queue_indices[f]), 0, &q);
	}
}

GetExtensions :: proc() -> []vk.ExtensionProperties
{
	n_ext: u32;
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, nil);
	extensions := make([]vk.ExtensionProperties, n_ext);
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, raw_data(extensions));
	
	return extensions;
}

CreateSurface::proc(using ctx: ^Context)
{
    if glfw.CreateWindowSurface(instance, window, nil, &surface) != .SUCCESS
    {
        fmt.eprintf("Failed to create surface!")
        os.exit(1)
    }
    fmt.println("Surface created")
}

createInstance::proc(using ctx: ^Context)
{
    AppInfo : vk.ApplicationInfo = vk.ApplicationInfo{}
    AppInfo.sType = .APPLICATION_INFO
    AppInfo.pNext = nil
    AppInfo.pApplicationName = "Hello Triangle"
    AppInfo.applicationVersion = vk.MAKE_VERSION(0, 0, 1)
    AppInfo.pEngineName = "No Engine";
    AppInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
    AppInfo.apiVersion = vk.API_VERSION_1_0

    CreateInfo : vk.InstanceCreateInfo = vk.InstanceCreateInfo{}
    CreateInfo.sType = .INSTANCE_CREATE_INFO
    CreateInfo.pNext = nil
    CreateInfo.pApplicationInfo = &AppInfo

    glfwExtensions := glfw.GetRequiredInstanceExtensions()
    CreateInfo.enabledExtensionCount = cast(u32)len(glfwExtensions)
    CreateInfo.ppEnabledExtensionNames = raw_data(glfwExtensions)

    when ODIN_DEBUG {
        layerCount : u32
        vk.EnumerateInstanceLayerProperties(&layerCount, nil)
        availableLayers := make([]vk.LayerProperties, layerCount)
        vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(availableLayers))

        for layerName in VALIDATION_LAYERS {
            layerFound : bool = false
            for layerProperties in &availableLayers {
                if layerName == cstring(&layerProperties.layerName[0]) {
                    layerFound = true
                    break
                }
            }
            if !layerFound {
                fmt.eprintf("ERROR: validation layer %q not available\n", layerName)
                os.exit(1);
            }
           
        }

        CreateInfo.enabledLayerCount = len(VALIDATION_LAYERS)
        CreateInfo.ppEnabledLayerNames = &VALIDATION_LAYERS[0];
        fmt.println("Validation Layers Loaded");
    } else {
        CreateInfo.enabledLayerCount = 0
    }

    if (vk.CreateInstance(&CreateInfo, nil, &instance) != .SUCCESS){
        fmt.eprintf("ERROR: Failed to create instance\n");
		return;
    }
    fmt.println("Instance Created");
}

check_device_extension_support :: proc(physical_device: vk.PhysicalDevice) -> bool
{
	ext_count: u32;
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &ext_count, nil);
	
	available_extensions := make([]vk.ExtensionProperties, ext_count);
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &ext_count, raw_data(available_extensions));
	
	for ext in DEVICE_EXTENSIONS
	{
		found: b32;
		for available in &available_extensions
		{
			if cstring(&available.extensionName[0]) == ext
			{
				found = true;
				break;
			}
		}
		if !found do return false;
	}
	return true;
}

pickPhysicalDevice::proc(using ctx: ^Context)
{
    deviceCount : u32 
    vk.EnumeratePhysicalDevices(instance, &deviceCount, nil)

    if deviceCount == 0{
        fmt.eprintf("failed to find GPUs with Vulkan support!");
        os.exit(1);
    }

    devices := make([]vk.PhysicalDevice, deviceCount);
    vk.EnumeratePhysicalDevices(instance, &deviceCount, raw_data(devices))

    isDeviceSuitable::proc(using ctx: ^Context, dev: vk.PhysicalDevice)-> int {
        deviceProperties : vk.PhysicalDeviceProperties
        deviceFeatures : vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceProperties(dev, &deviceProperties)
        vk.GetPhysicalDeviceFeatures(dev, &deviceFeatures)

        score : int = 0
        if deviceProperties.deviceType == .DISCRETE_GPU do score += 1000
        score += cast(int)deviceProperties.limits.maxImageDimension2D;

        if !deviceFeatures.geometryShader do return 0;
		if !check_device_extension_support(dev) do return 0;

        querySwapChainSupport(ctx, dev)
        if len(swapchain.support.formats) == 0 || len(swapchain.support.presentModes) == 0 do return 0

        return score;
    }

    hiscore := 0;
	for dev in devices
	{
		score := isDeviceSuitable(ctx, dev);
		if score > hiscore
		{
			physical_device = dev;
			hiscore = score;
		}
	}
	
	if (hiscore == 0)
	{
		fmt.eprintf("ERROR: Failed to find a suitable GPU\n");
		os.exit(1);
	}
}

findQueueFamilies::proc(using ctx: ^Context)
{
    queueFamilyCount : u32 = 0
    vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queueFamilyCount, nil);
    queueFamilies := make([]vk.QueueFamilyProperties, queueFamilyCount)
    vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queueFamilyCount, raw_data(queueFamilies));

    for v, i in queueFamilies
    {
        if .GRAPHICS in v.queueFlags && queue_indices[.Graphics] == -1 do queue_indices[.Graphics] = i
		
		present_support: b32;
		vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(i), surface, &present_support);
		if present_support && queue_indices[.Present] == -1 do queue_indices[.Present] = i;
		
		for q in queue_indices do if q == -1 do continue;
		break;
    }

}

createDevice::proc(using ctx: ^Context)
{
    indices : map[int]b8
    defer delete(indices)
    for i in queue_indices do indices[i] = true

    queue_priority := f32(1.0)
    queueCreateInfos : [dynamic]vk.DeviceQueueCreateInfo
    defer delete(queueCreateInfos)

    for k, _ in indices
    {
        queueCreateInfo : vk.DeviceQueueCreateInfo
        queueCreateInfo.sType = .DEVICE_QUEUE_CREATE_INFO
        queueCreateInfo.queueFamilyIndex = u32(queue_indices[.Graphics])
        queueCreateInfo.queueCount = 1
        queueCreateInfo.pQueuePriorities = &queue_priority
        append(&queueCreateInfos, queueCreateInfo)
    }

    deviceFeatures : vk.PhysicalDeviceFeatures
    deviceCreateInfo : vk.DeviceCreateInfo
    deviceCreateInfo.sType = .DEVICE_CREATE_INFO
    deviceCreateInfo.enabledExtensionCount = u32(len(DEVICE_EXTENSIONS));
	deviceCreateInfo.ppEnabledExtensionNames = &DEVICE_EXTENSIONS[0];
    deviceCreateInfo.queueCreateInfoCount = u32(len(queueCreateInfos))
    deviceCreateInfo.pQueueCreateInfos = raw_data(queueCreateInfos)
    deviceCreateInfo.pEnabledFeatures = &deviceFeatures
    deviceCreateInfo.enabledLayerCount = 0

    //deviceCreateInfo.enabledLayerCount = u32(len(VALIDATION_LAYERS))
    //deviceCreateInfo.ppEnabledLayerNames = raw_data(VALIDATION_LAYERS)

    if vk.CreateDevice(physical_device, &deviceCreateInfo, nil, &device) != .SUCCESS
    {
        fmt.eprintf("ERROR: Failed to create device!\n");
		os.exit(1);
    }
    fmt.println("Device created")
}

querySwapChainSupport :: proc(using ctx: ^Context, dev: vk.PhysicalDevice)
{
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(dev, surface, &swapchain.support.capabilities);

    formatCount : u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &formatCount, nil)

    if formatCount != 0
    {
        swapchain.support.formats = make([]vk.SurfaceFormatKHR, format_count);
        vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &formatCount, raw_data(swapchain.support.formats));
    }

    presentModeCount : u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &presentModeCount, nil)
    if presentModeCount != 0
    {
        swapchain.support.presentModes = make([]vk.PresentModeKHR, presentModeCount);
        vk.GetPhysicalDevicePresentModesKHR(dev, surface, &presentModeCount, raw_data(swapchain.support.presentModes));
    }
}

chooseSwapSurfaceFormat :: proc(using ctx: ^Context) -> vk.SurfaceFormatKHR
{
    for v in swapchain.support.format
    {
        if v.format == .B8G8R8A8_SRGB && v.colorSpace == .SRGB_NONLINEAR_KHR do return v
    }
    return swapchain.support.formats[0]
}

chooseSwapPresentMode :: proc(using ctx: ^Context) -> vk.PresentModeKHR
{
    for v in swapchain.support.presentModes
    {
        if v == .MAILBOX do return v
    }
    return .FIFO
}
chooseSwapExtent :: proc(using ctx: ^Context) -> vk.Extent2D
{
    
}

cleanupVulkan::proc(using ctx: ^Context)
{
    vk.DestroySurfaceKHR(instance, surface, nil)
    vk.DestroyDevice(device, nil)
    vk.DestroyInstance(instance, nil)
    fmt.println("Instance Destroyed");
}

main::proc()
{
    using ctx: Context;

    glfw.Init()
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, 0)

	window = glfw.CreateWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Haha", nil, nil) //4th - for monitor, 5th - OpenGL only

    for q in &queue_indices do q = -1;

    defer glfw.DestroyWindow(window)
    defer glfw.Terminate()

    initVulkan(&ctx)
    defer cleanupVulkan(&ctx)

    for !glfw.WindowShouldClose(window)
    {
        glfw.PollEvents();
    }
}