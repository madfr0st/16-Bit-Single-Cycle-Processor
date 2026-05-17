## =============================================================================
## create_project.tcl  --  one-shot Vivado project re-generator
## =============================================================================
## Builds a Vivado project for all three cores. The scp16 core has Basys 3
## constraints and is selected as the synth top; the 32-bit cores are added as
## additional source files (useful for behavioural sim inside Vivado), but you
## can swap the synth top to either one if you've added your own xdc.
##
## Why this exists:
##   The *.xpr / *.cache / *.runs / *.hw / etc. are NOT committed to git --
##   they are huge, machine-specific, and break on Vivado version bumps.
##   This script re-creates a clean project from the RTL that IS committed.
##
## Usage:
##   1. Open Vivado.
##   2. Tcl Console (or  vivado -mode batch -source scripts/create_project.tcl)
##   3.   cd <repo-root>
##   4.   source scripts/create_project.tcl
##
## Target board: Digilent Basys 3  (Artix-7 XC7A35TCPG236-1).
## =============================================================================

set proj_name "three_cpus"
set proj_dir  [file normalize "./build"]
set part      "xc7a35tcpg236-1"

# Wipe any previous build so the next run starts clean
file delete -force $proj_dir

create_project $proj_name $proj_dir -part $part -force

# ---- Design sources (scp16 is the default synth top) -----------------------
add_files -fileset sources_1 [glob ./cores/scp16/rtl/*.v]
set_property top cpu [get_filesets sources_1]

# Add the other cores as auxiliary sources (in their own VHDL "libraries" to
# avoid module-name clashes since they share names like `cpu`, `alu`, etc.).
# To synthesise one of the 32-bit cores instead, remove the scp16 add_files
# above and instead add ./cores/x86lite32/rtl/*.v (or armlite32), and provide
# a matching constraints file.
#
# add_files -fileset sources_1 [glob ./cores/x86lite32/rtl/*.v]
# add_files -fileset sources_1 [glob ./cores/armlite32/rtl/*.v]

# ---- Simulation sources ----------------------------------------------------
add_files -fileset sim_1 [glob ./cores/scp16/sim/cpu_tb.v]
set_property top cpu_tb [get_filesets sim_1]

# ---- Constraints (Basys 3 pinout for scp16) --------------------------------
add_files -fileset constrs_1 ./cores/scp16/constraints/basys3.xdc

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "================================================================="
puts " Project ready at: $proj_dir"
puts " Synth top (default): cpu  (scp16)"
puts " Sim top   (default): cpu_tb"
puts ""
puts " To synthesise x86lite32 or armlite32, edit this script:"
puts "   1. Comment the scp16 add_files line"
puts "   2. Uncomment the corresponding 32-bit add_files line"
puts "   3. Add an xdc that maps your top-level ports to FPGA pins"
puts ""
puts " Next steps:"
puts "   * Run Synthesis -> Implementation -> Generate Bitstream"
puts "   * Open Hardware Manager and program your Basys 3"
puts "================================================================="
