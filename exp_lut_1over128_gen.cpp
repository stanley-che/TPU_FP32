#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <cstring> 
// Write IEEE-754 float as big-endian hex (8 chars)
static uint32_t float_to_u32(float v) {
    uint32_t u;
    std::memcpy(&u, &v, sizeof(u));    // ✅ 正確
    return u;
}

int main() {
    const int    STEPS = 1024;   // 0..1024 inclusive => 1025 entries
    const double STEP  = 1.0 / 128.0;

    std::ofstream ofs("exp_lut_1over128.hex");
    if (!ofs) {
        std::cerr << "Failed to open output file.\n";
        return 1;
    }

    ofs << std::hex << std::setfill('0');

    for (int k = 0; k <= STEPS; ++k) {
        double x = -k * STEP;           // x in [-8, 0]
        float  y = static_cast<float>(std::exp(x));
        uint32_t u = float_to_u32(y);
        ofs << std::setw(8) << u << "\n";
    }

    ofs.close();
    std::cout << "Generated exp_lut_1over128.hex with 1025 entries.\n";
    return 0;
}
