#pragma once

// Offline reference input adapter; not a replacement contact solver.
// With no RMMOSurfaceFollowFile parameter the upstream predictor is unchanged.
#include <Utils/PARAMETER.h>
#include <fstream>
#include <cmath>
#include <stdexcept>
#include <vector>

namespace JGSL {
template <class T, int dim>
void RMMO_Apply_Surface_Follow(MESH_NODE<T, dim>& predicted, T dt)
{
    const std::string filename = PARAMETER::Get<std::string>("RMMOSurfaceFollowFile", "");
    if (filename.empty()) return;
    if constexpr (dim != 3) {
        throw std::runtime_error("RMMO surface follow requires 3D");
    } else {
        std::ifstream input(filename);
        int count = 0;
        T reference_dt = 0, max_travel = 0;
        if (!(input >> count >> reference_dt >> max_travel) || count < 0 || count > predicted.size ||
            !std::isfinite(reference_dt) || reference_dt <= 0 ||
            !std::isfinite(max_travel) || max_travel < 0)
            throw std::runtime_error("Invalid RMMO surface follow header");
        std::vector<VECTOR<T, 3>> targets(count);
        std::vector<T> weights(count);
        // Parse and validate the whole packet before mutating the predictor.
        for (int i = 0; i < count; ++i) {
            if (!(input >> targets[i][0] >> targets[i][1] >> targets[i][2] >> weights[i]))
                throw std::runtime_error("Truncated RMMO surface follow packet");
            for (int j = 0; j < 3; ++j)
                if (!std::isfinite(targets[i][j])) throw std::runtime_error("Nonfinite RMMO target");
            if (!std::isfinite(weights[i]) || weights[i] < .01 || weights[i] > 1)
                throw std::runtime_error("RMMO cloth weight outside soft/free range; hard pins require DBC");
        }
        std::string extra;
        if (input >> extra) throw std::runtime_error("Unexpected trailing RMMO follow data");
        for (int i = 0; i < count; ++i) {
            VECTOR<T, 3>& point = std::get<0>(predicted.Get_Unchecked(i));
            const T weight = weights[i];
            const VECTOR<T, 3> difference = point - targets[i];
            const T distance = difference.length();
            const T limit = weight * max_travel;
            if (max_travel > 0 && limit > 1e-7 && distance > limit)
                point = targets[i] + difference * (limit / distance);
            if (weight < .999) {
                const T retention = std::pow(weight, dt / reference_dt);
                point = targets[i] + (point - targets[i]) * retention;
            }
        }
    }
}
}
