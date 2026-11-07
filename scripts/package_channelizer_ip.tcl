# Package channelizer_dut.v as a Vivado IP Catalog component.
#
# This is the second way to the deliverable: Model Composer writes component.xml
# from a .slx, and this script writes the same kind of component from Verilog with
# no Model Composer involved.  It needs only Vivado, which is installed and known
# good (Model Composer itself uses it to compile).
#
# Environment:
#   IP_REPO  where the packaged IP goes    (build/ip_repo)
#   MC_PART  the part to create the core for (xczu48dr-fsvg1517-2-e)
#   (optional) CHANNIZER_VENDOR, CHANNIZER_LIBRARY, CHANNIZER_VERSION
#
# Output: $IP_REPO/channelizer_ip/component.xml

set here     [file dirname [file normalize [info script]]]
set repoRepo [file dirname $here]
set source   [file join $repoRepo ip model_composer channelizer channelizer_dut.v]

set ipRepo [expr {[info exists ::env(IP_REPO)] ? $::env(IP_REPO) : [file join $repoRepo build ip_repo]}]
set part   [expr {[info exists ::env(MC_PART)] ? $::env(MC_PART) : "xczu48dr-fsvg1517-2-e"}]
set vendor  [expr {[info exists ::env(CHANNIZER_VENDOR)]  ? $::env(CHANNIZER_VENDOR)  : "doa.v7"}]
set library [expr {[info exists ::env(CHANNIZER_LIBRARY)] ? $::env(CHANNIZER_LIBRARY) : "model_composer"}]
set version [expr {[info exists ::env(CHANNIZER_VERSION)] ? $::env(CHANNIZER_VERSION) : "1.0"}]

if {![file exists $source]} {
    puts "ERROR: source not found: $source"
    exit 2
}

set outDir [file join $ipRepo channelizer_ip]
file mkdir $outDir
puts "packaging $source"
puts "  part:    $part"
puts "  output:  $outDir"

create_project -in_memory -part $part
add_files -norecurse $source
set_property top channelizer_dut [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $outDir -vendor $vendor -library $library \
    -taxonomy /UserIP -import_files -set_current true

set core [ipx::current_core]
set_property name            channelizer        $core
set_property display_name    "Channelizer DUT"  $core
set_property description     "Four 16-bit channels, four-clock delay, sfix16_En14, 200 MHz" $core
set_property vendor_display_name "DOA V7 build kit" $core
set_property version         $version           $core
set_property supported_families {zynquplus Production} $core

ipx::create_xgui_files $core
ipx::update_checksums  $core
ipx::check_integrity   $core
ipx::save_core         $core

set component [file join $outDir component.xml]
if {![file exists $component]} {
    puts "ERROR: packaging finished without $component"
    exit 3
}
puts "IP_PACKAGE_OK $component"
