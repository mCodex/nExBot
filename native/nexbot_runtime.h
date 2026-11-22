#pragma once

#include <array>
#include <cstddef>
#include <string>

extern "C" std::size_t nexbot_decide_v1(
    const unsigned char* operation, std::size_t operationLength,
    const unsigned char* input, std::size_t inputLength,
    unsigned char* output, std::size_t outputCapacity);

inline std::string nexbotDecide(const std::string& operation, const std::string& input)
{
    // A 33 x 33 corridor can return up to 1088 single-digit directions as JSON.
    std::array<unsigned char, 2 * (33 * 33 - 1) + 1> output;
    const auto size = nexbot_decide_v1(
        reinterpret_cast<const unsigned char*>(operation.data()), operation.size(),
        reinterpret_cast<const unsigned char*>(input.data()), input.size(),
        output.data(), output.size());

    return {reinterpret_cast<const char*>(output.data()), size};
}
