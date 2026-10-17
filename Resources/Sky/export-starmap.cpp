// Development-only conversion of NASA SVS's linear OpenEXR atlas to sRGB PPM.
// No pixels move, and no exposure adjustment or tone mapping is applied.
#include <OpenEXR/ImfRgbaFile.h>
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: export-starmap source.exr destination.ppm\n";
        return 2;
    }
    try {
        Imf::RgbaInputFile input(argv[1]);
        const auto bounds = input.dataWindow();
        const int width = bounds.max.x - bounds.min.x + 1;
        const int height = bounds.max.y - bounds.min.y + 1;
        if (width != 4096 || height != 2048 || bounds.min.x != 0 || bounds.min.y != 0) {
            std::cerr << "Expected NASA's 4096x2048 atlas with a zero-origin data window.\n";
            return 1;
        }
        std::vector<Imf::Rgba> pixels(width * height);
        input.setFrameBuffer(pixels.data(), 1, width);
        input.readPixels(0, height - 1);
        std::ofstream output(argv[2], std::ios::binary);
        output << "P6\n" << width << " " << height << "\n255\n";
        for (const auto& pixel : pixels) {
            for (const float value : {float(pixel.r), float(pixel.g), float(pixel.b)}) {
                if (!std::isfinite(value) || value < 0 || value > 1) {
                    std::cerr << "Unexpected source sample outside NASA atlas's normalized [0,1] range.\n";
                    return 1;
                }
                const double encoded = value <= 0.0031308
                    ? 12.92 * value : 1.055 * std::pow(double(value), 1.0 / 2.4) - 0.055;
                output.put(char(std::lround(std::clamp(encoded, 0.0, 1.0) * 255)));
            }
        }
        if (!output) {
            std::cerr << "Could not write output image.\n";
            return 1;
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << "\n";
        return 1;
    }
}
