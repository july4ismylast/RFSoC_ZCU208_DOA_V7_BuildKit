# Usage: vivado -mode batch -source package_generated_rtl.tcl -tclargs <rtl_dir> <top> [part]
if {[llength $argv] < 2} { error "Need rtl_dir and top_module" }
set rtl_dir [file normalize [lindex $argv 0]]
set top [lindex $argv 1]
set part [expr {[llength $argv] > 2 ? [lindex $argv 2] : "xczu48dr-fsvg1517-2-e"}]
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir .. .. ..]]
set ip_repo [expr {[info exists ::env(IP_REPO)] ? $::env(IP_REPO) : [file join $root_dir build ip_repo]}]
set ip_root [file join $ip_repo matlab_channelizer]
file delete -force $ip_root
file mkdir $ip_root
create_project -force matlab_channelizer_pkg [file join $script_dir build matlab_channelizer_pkg] -part $part

# HDL Coder R2024a creates a model-named directory below TargetDirectory.
# Walk the tree so this packager also works with releases/configurations that
# emit RTL directly in TargetDirectory.
proc collect_hdl_files {dir} {
    set result {}
    foreach entry [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $entry]} {
            set result [concat $result [collect_hdl_files $entry]]
        } elseif {[regexp -nocase {\.(v|sv|vhd|vhdl)$} [file extension $entry]]} {
            lappend result $entry
        }
    }
    return $result
}
set files [lsort -unique [collect_hdl_files $rtl_dir]]
if {[llength $files] == 0} { error "No HDL files found recursively under $rtl_dir" }
set top_matches {}
foreach hdl_file $files {
    if {[file rootname [file tail $hdl_file]] eq $top} {
        lappend top_matches $hdl_file
    }
}
if {[llength $top_matches] == 0} {
    error "Top module $top was not found recursively under $rtl_dir"
}
puts "Found [llength $files] HDL files; top source=[lindex $top_matches 0]"
add_files $files
set_property top $top [current_fileset]
update_compile_order -fileset sources_1
# Vendor/library/version from config.mk variables (V00/V01), matching
# config/ip_versions.tcl.  NOTE (stage V06): this packager still defines no
# AXI bus interfaces -- that is the V06 work item, not hidden here.
set ip_vendor [expr {[info exists ::env(CUSTOM_IP_VENDOR)] ? $::env(CUSTOM_IP_VENDOR) : "openai"}]
set ip_library [expr {[info exists ::env(CUSTOM_IP_LIBRARY)] ? $::env(CUSTOM_IP_LIBRARY) : "doa"}]
set ip_version [expr {[info exists ::env(IPVER_CHANNELIZER)] ? $::env(IPVER_CHANNELIZER) : "7.0"}]
ipx::package_project -root_dir $ip_root -vendor $ip_vendor -library $ip_library -taxonomy /UserIP -import_files -set_current false
set core [ipx::open_core [file join $ip_root component.xml]]
set_property name matlab_channelizer $core
set_property display_name "MATLAB DSP HDL Four-Lane Channelizer" $core
set_property version $ip_version $core
ipx::update_checksums $core
ipx::save_core $core
close_project
puts "Packaged MATLAB-generated RTL at $ip_root"
