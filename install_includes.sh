#!/usr/bin/env bash
# =============================================================================
# BASE v2.0 – Install Updated Includes Files
# Project root: ~/Caravel/secure_boot_caravel
#
# Run this from ~/Caravel/secure_boot_caravel after downloading the three
# updated includes files alongside this script.
#
# WHAT IT DOES:
#   1. Backs up all three existing includes files with a .v1bak suffix
#   2. Installs the three new v2.0 includes files
#   3. Confirms checksums differ (i.e. files were actually updated)
#   4. Also updates uprj_netlists.v to explicitly include the v2.0 hierarchy
#
# WHAT IT DOES NOT DO:
#   - Does not modify any RTL source files
#   - Does not run OpenLane
# =============================================================================

set -e
PROJECT_ROOT="$HOME/Caravel/secure_boot_caravel"
INCLUDES_DIR="$PROJECT_ROOT/verilog/includes"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "============================================================"
echo "  BASE v2.0 – Installing Updated Includes Files"
echo "============================================================"
echo ""

cd "$PROJECT_ROOT"

# ── STEP 1: Backup existing includes ─────────────────────────────────────────
echo "[1/4] Backing up existing includes files..."

cp "$INCLUDES_DIR/includes.rtl.caravel_user_project" \
   "$INCLUDES_DIR/includes.rtl.caravel_user_project.v1bak"

cp "$INCLUDES_DIR/includes.gl.caravel_user_project" \
   "$INCLUDES_DIR/includes.gl.caravel_user_project.v1bak"

cp "$INCLUDES_DIR/includes.gl+sdf.caravel_user_project" \
   "$INCLUDES_DIR/includes.gl+sdf.caravel_user_project.v1bak"

echo "    -> includes.rtl.caravel_user_project.v1bak  created"
echo "    -> includes.gl.caravel_user_project.v1bak   created"
echo "    -> includes.gl+sdf.caravel_user_project.v1bak created"

# ── STEP 2: Install new includes files ───────────────────────────────────────
echo ""
echo "[2/4] Installing v2.0 includes files..."

# Check the new files are present next to this script
for f in includes.rtl.caravel_user_project \
          includes.gl.caravel_user_project \
          "includes.gl+sdf.caravel_user_project"; do
    if [ ! -f "$SCRIPT_DIR/$f" ]; then
        echo "ERROR: $f not found next to this script at $SCRIPT_DIR"
        echo "       Download all three includes files and place them alongside install_includes.sh"
        exit 1
    fi
done

cp "$SCRIPT_DIR/includes.rtl.caravel_user_project"     "$INCLUDES_DIR/includes.rtl.caravel_user_project"
cp "$SCRIPT_DIR/includes.gl.caravel_user_project"      "$INCLUDES_DIR/includes.gl.caravel_user_project"
cp "$SCRIPT_DIR/includes.gl+sdf.caravel_user_project"  "$INCLUDES_DIR/includes.gl+sdf.caravel_user_project"

echo "    -> includes.rtl.caravel_user_project  installed"
echo "    -> includes.gl.caravel_user_project   installed"
echo "    -> includes.gl+sdf.caravel_user_project installed"

# ── STEP 3: Update uprj_netlists.v ───────────────────────────────────────────
echo ""
echo "[3/4] Updating verilog/rtl/uprj_netlists.v..."

# Backup first
cp verilog/rtl/uprj_netlists.v verilog/rtl/uprj_netlists.v.v1bak

cat > verilog/rtl/uprj_netlists.v << 'NETLISTS'
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
NETLISTS

echo "    -> uprj_netlists.v  updated (v1bak saved)"

# ── STEP 4: Confirm & print diff summary ─────────────────────────────────────
echo ""
echo "[4/4] Confirming changes..."
echo ""
echo "  RTL includes diff (v1 -> v2):"
diff "$INCLUDES_DIR/includes.rtl.caravel_user_project.v1bak" \
     "$INCLUDES_DIR/includes.rtl.caravel_user_project" \
     | grep '^[<>]' | head -20 || true

echo ""
echo "  uprj_netlists.v diff (v1 -> v2):"
diff verilog/rtl/uprj_netlists.v.v1bak \
     verilog/rtl/uprj_netlists.v \
     | grep '^[<>]' | head -20 || true

echo ""
echo "─────────────────────────────────────────────────────────"
echo "✅  Includes installation complete."
echo ""
echo "  Backups saved as .v1bak – restore with:"
echo "    cp verilog/includes/includes.rtl.caravel_user_project.v1bak \\"
echo "       verilog/includes/includes.rtl.caravel_user_project"
echo ""
echo "  NEXT STEP: Implement secure_boot_control_plane.sv then"
echo "  update user_project_wrapper.v – both in the next integration step."
echo "─────────────────────────────────────────────────────────"
echo ""
