# Package channelizer_dut.v as a Vivado IP Catalog component.
#
# This is the second way to the deliverable: Model Composer writes component.xml
# from a .slx, and this script writes the same kind of component from Verilog with
# no Model Composer involved.  It needs only Vivado, which is installed and known
# good (the first run of this script produced a core whose integrity check passed).
#
# A real project is created on disk for the packaging, because
# ipx::package_project in "in memory" (non project) mode is deprecated:
#   CRITICAL WARNING: [Ipptcl 7-1601] Command ipx::package_project in non project
#   mode is not supported and will be blocked in the future release.
#
# Environment:
#   IP_REPO  where the packaged IP goes         (build/ip_repo)
#   MC_PART  the part to create the core for    (xczu48dr-fsvg1517-2-e)
#   (optional) CHANNIZER_VENDOR, CHANNIZER_LIBRARY, CHANNIZER_VERSION,
#              CHANNIZER_CLOCK_HZ
#
# Output: $IP_REPO/channelizer_ip/component.xml  and  IP_PACKAGE_OK <path>

set here     [file dirname [file normalize [info script]]]
set repoRoot [file dirname $here]
set source   [file join $repoRoot ip model_composer channelizer channelizer_dut.v]

set ipRepo   [expr {[info exists ::env(IP_REPO)] ? $::env(IP_REPO) : [file join $repoRoot build ip_repo]}]
set part     [expr {[info exists ::env(MC_PART)] ? $::env(MC_PART) : "xczu48dr-fsvg1517-2-e"}]
set vendor   [expr {[info exists ::env(CHANNIZER_VENDOR)]   ? $::env(CHANNIZER_VENDOR)   : "doa.v7"}]
set library  [expr {[info exists ::env(CHANNIZER_LIBRARY)]  ? $::env(CHANNIZER_LIBRARY)  : "model_composer"}]
set version  [expr {[info exists ::env(CHANNIZER_VERSION)]  ? $::env(CHANNIZER_VERSION)  : "1.0"}]
set clockHz  [expr {[info exists ::env(CHANNIZER_CLOCK_HZ)] ? $::env(CHANNIZER_CLOCK_HZ) : "200000000"}]

if {![file exists $source]} {
    puts "ERROR: source not found: $source"
    exit 2
}

set outDir  [file join $ipRepo channelizer_ip]
set projDir [file join $ipRepo _ipbuild_channelizer]
file mkdir $outDir
file delete -force $projDir

puts "packaging $source"
puts "  part:    $part"
puts "  output:  $outDir"
puts "  project: $projDir (removed afterwards)"

create_project -force -part $part $projDir
add_files -norecurse $source
set_property top channelizer_dut [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $outDir -vendor $vendor -library $library \
    -taxonomy /UserIP -import_files -set_current true -force_update_compile_order

set core [ipx::current_core]
set_property name                   channelizer                   $core
set_property display_name           "Channelizer DUT"             $core
set_property description            "Four 16-bit channels (sfix16_En14), four-clock delay, 200 MHz" $core
set_property vendor_display_name    "DOA V7 build kit"            $core
set_property version                $version                      $core
set_property supported_families     {zynquplus Production}        $core

# The clock interface gets the frequency the model uses; without it every
# consumer warns "Clock interface 'clk' has no FREQ_HZ parameter".
if {[llength [ipx::get_bus_interfaces clk -of_objects $core]] > 0} {
    set clkIf [ipx::get_bus_interfaces clk -of_objects $core]
    set param [ipx::get_bus_parameters FREQ_HZ -of_objects $clkIf]
    if {$param eq ""} {
        ipx::add_bus_parameter FREQ_HZ $clkIf
        set param [ipx::get_bus_parameters FREQ_HZ -of_objects $clkIf]
    }
    set_property value            $clockHz $param
    set_property value_resolve_type user    $param
    puts "  clk FREQ_HZ = $clockHz"
}

ipx::create_xgui_files $core
ipx::update_checksums  $core
ipx::check_integrity   $core
ipx::save_core         $core
close_project

file delete -force $projDir

set component [file join $outDir component.xml]
if {![file exists $component]} {
    puts "ERROR: packaging finished without $component"
    exit 3
}
puts "IP_PACKAGE_OK $component"
