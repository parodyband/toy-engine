package asset

import math "core:math"

fill_mip_chain :: proc(pixel_data: [dynamic]byte,
                       dimensions:     Texture_Dimensions,
                       num_mip_levels: int) -> Texture {
	// Ensure we have at least one mip level. Work with a local mutable copy so the
	// original parameter remains immutable.
	levels := num_mip_levels
	if levels <= 0 {
		levels = 1
	}

	// Create a dynamic array sized for the requested mip chain length
	mip_chain := make([dynamic]Mip_Map, levels)

	// Mip level 0 (original texture)
	mip_chain[0] = Mip_Map{
		final_pixels = pixel_data,
	}

	current_width  : int = int(dimensions.width)
	current_height : int = int(dimensions.height)
	current_pixels := pixel_data

	// Generate subsequent mip levels (starting from level 1)
	for i in 1..<levels {
		// Early-out if we have reached the smallest mip (1×1)
		if current_width == 1 && current_height == 1 {
			// Fill remaining mips (if any) with the last valid one
			for j in i..<levels {
				mip_chain[j] = Mip_Map{ final_pixels = current_pixels }
			}
			break
		}

		prev_width   := current_width
		prev_height  := current_height
		prev_pixels  := current_pixels

		// Halve the dimensions, but never go below 1
		current_width  = math.max(1, prev_width  / 2)
		current_height = math.max(1, prev_height / 2)

		// Assuming RGBA8 format (4 bytes per pixel)
		new_size      := int(current_width * current_height * 4)
		new_pixels_dyn := make([dynamic]byte, new_size)

		// ------------------------------------------------------------------
		// Down-sample using a simple 2×2 box filter (average of 4 texels).
		// ------------------------------------------------------------------
		idx_new: int = 0
		for y_new in 0..<current_height {
			for x_new in 0..<current_width {
				x_prev0 := x_new * 2
				y_prev0 := y_new * 2

				// Clamp to edge to safely handle odd dimensions
				x_prev1 := math.min(prev_width  - 1, x_prev0 + 1)
				y_prev1 := math.min(prev_height - 1, y_prev0 + 1)

				idx00: int = int((y_prev0 * prev_width + x_prev0) * 4)
				idx10: int = int((y_prev0 * prev_width + x_prev1) * 4)
				idx01: int = int((y_prev1 * prev_width + x_prev0) * 4)
				idx11: int = int((y_prev1 * prev_width + x_prev1) * 4)

				// Average each channel
				for c in 0..<4 { // RGBA
					idx_off := c
					sum := int(prev_pixels[idx00 + idx_off]) +
						   int(prev_pixels[idx10 + idx_off]) +
						   int(prev_pixels[idx01 + idx_off]) +
						   int(prev_pixels[idx11 + idx_off])
					new_pixels_dyn[idx_new + idx_off] = u8(sum / 4)
				}

				idx_new += 4
			}
		}

		mip_chain[i] = Mip_Map{
			final_pixels = new_pixels_dyn,
		}

		current_pixels = new_pixels_dyn
	}

	return Texture{
		dimensions = dimensions,
		mip_chain  = mip_chain[:],
	}
}