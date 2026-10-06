#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer    Positions      { vec4 positions[];      };
layout(set = 0, binding = 1, std430) restrict buffer    Predicted      { vec4 predicted[];      };
layout(set = 0, binding = 2, std430) restrict buffer    Velocities     { vec4 velocities[];     };
// x = cloth influence weight [0..1]: 0 = fully skeleton-driven, 1 = fully simulated
layout(set = 0, binding = 5, std430) restrict readonly buffer ClothWeights   { vec4 cloth_weights[];   };
layout(set = 0, binding = 6, std430) restrict readonly buffer SkinnedTargets { vec4 skinned_targets[]; };

layout(push_constant, std430) uniform Params {
    float dt;
    float gravity;
    uint  particle_count;
    uint  constraint_count;
    float damping;
    float max_speed;
    float pad1, pad2;
    float inertia_x, inertia_y, inertia_z, max_travel;
    float pad7, pad8, pad9;
    float inv_substeps;
    // Rotational counter-rotation quaternion — only consumed by predict.
    float counter_qx, counter_qy, counter_qz, counter_qw;
    // Gravity Y, Z, pads — only consumed by predict.
    float pad_gy, pad_gz, pad_g1, pad_g2;
};

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= particle_count) return;

    vec3  old_pos = positions[idx].xyz;
    vec4 q = vec4(counter_qx, counter_qy, counter_qz, counter_qw);
    old_pos += 2.0 * cross(q.xyz, cross(q.xyz, old_pos) + q.w * old_pos);
    old_pos -= vec3(inertia_x, inertia_y, inertia_z);
    vec3  new_pos = predicted[idx].xyz;
    float w       = positions[idx].w;
    float cloth_w = cloth_weights[idx].x;

    // Anchored particles (w == 0) are already snapped to skinned_targets in the
    // predict pass, so skip velocity recovery for them.
    if (w < 0.001) {
        return;
    }

    // Recover velocity from position delta.
    vec3 vel = (new_pos - old_pos) / max(dt, 1e-7);
    vel *= damping;

    // Contacts are final: follow/travel now run in PREDICT.
    positions[idx]  = vec4(new_pos, w);
    velocities[idx] = vec4(vel, 0.0);
}
