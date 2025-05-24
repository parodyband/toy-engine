package debug
import ren "../renderer"

Vec3 :: [3]f32

Depth_Test_Mode :: enum {
    Front,  // Draw if farther (GREATER_EQUAL) 
    Off,   // Always draw (ALWAYS)
}

Debug_Draw_Call :: struct {
    data: union {
        Line_Segment_Data,
        Wire_Sphere_Data,
        Wire_Cube_Data,
    },
}

Wire_Sphere_Data :: struct {
    center: [3]f32,
    radius: f32,
    color: [4]f32,
    depth_test: Depth_Test_Mode,
}

Wire_Cube_Data :: struct {
    transform: ren.Transform,
    color: [4]f32,
    depth_test: Depth_Test_Mode,
}

Line_Segment_Data :: struct {
    start: [3]f32,
    end: [3]f32,
    color: [4]f32,
    depth_test: Depth_Test_Mode,
}