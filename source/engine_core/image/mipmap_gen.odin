package image

// import "vendor:stb/image"
// import "base:runtime"

// import "../render"

// resize_image :: proc (
//     input_image    : render.texture,
//     new_dimensions : render.texture_dimensions,
//     allocator      : runtime.Allocator
// ) -> render.texture {

//     num_channels :i32= 4
//     new_size := new_dimensions.width * new_dimensions.height * num_channels
//     out_data := make([]u8, new_size, allocator)

//     ok := image.resize_uint8(
//         input_image.final_pixels_ptr,
//         input_image.width, input_image.height, 0,
//         cast([^]byte)&out_data[0],
//         new_dimensions.width, new_dimensions.height, 0,
//         num_channels,
//     )

//     assert(ok == 1)

//     return render.texture {
//         width  = new_dimensions.height,
//         height = new_dimensions.width,
//         data   = out_data,
//         final_pixels_ptr = cast([^]byte)&out_data[0],
//         final_pixels_size = uint(new_size),
//     }
// }

