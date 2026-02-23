// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

// ============================================================
// BASE v2.0 – uprj_netlists.v
// Updated from v1.0: explicit hierarchy replaces implicit chaining.
// Order: leaf modules first, top-level wrapper last.
// ============================================================

`include "defines.v"
`define USE_POWER_PINS

`ifdef GL
    // GL mode: use gate-level netlists produced by OpenLane
    `default_nettype wire
    `include "gl/user_project_wrapper.v"
    // NOTE: caravel_secure_boot.v is no longer a top-level module in v2.0.
    // If needed for GL sim comparison, uncomment:
    // `include "gl/caravel_secure_boot.v"
    // `include "gl/secure_boot_system_wrapper.v"
`else
    // RTL mode: explicit file list, leaf-first
    `include "secure_boot_core/secure_boot_fsm.sv"
    `include "secure_boot_core/group_fsm.sv"
    `include "secure_boot_core/secure_boot_system_wrapper.sv"
    `include "control_plane/secure_boot_control_plane.sv"
    `include "user_project_wrapper.v"
`endif
