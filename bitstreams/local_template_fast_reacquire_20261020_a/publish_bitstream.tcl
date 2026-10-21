foreach f {camera_template_fast_reacquire_20261020_a.bit camera_template_fast_reacquire_20261020_a_compress.bit} {
    if {[file exists $f]} {error "Refusing to overwrite $f"}
}
if {![file exists .opt_route.end.f]} {error "Missing successful route marker"}
if {[llength [glob -nocomplain .*.error.f]] != 0} {error "Build error marker exists"}
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
open_project camera_to_dsi_display.prj -noanalyze
import_db camera_to_dsi_display_pr.db
set_param bitgen compress on
bitgen -bit camera_template_fast_reacquire_20261020_a.bit
