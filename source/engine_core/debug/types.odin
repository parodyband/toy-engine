package debug
import trans "../transform"

Vec3 :: [3]f32

Depth_Test_Mode :: enum {
    Front,
    Off,
}

Debug_Draw_Call :: struct {
    data: union {
        Line_Segment_Data,
        Wire_Sphere_Data,
        Wire_Cube_Data,
    },
}

Wire_Sphere_Data :: struct {
    transform: trans.Transform,
    radius: f32,
    color: [4]f32,
    depth_test: Depth_Test_Mode,
    simple_mode: bool,  // If true, use simple 3-circle rendering
}

Wire_Cube_Data :: struct {
    transform: trans.Transform,
    color: [4]f32,
    depth_test: Depth_Test_Mode,
}

Line_Segment_Data :: struct {
    start: [3]f32,
    end: [3]f32,
    color: [4]f32,
    depth_test: Depth_Test_Mode,
}