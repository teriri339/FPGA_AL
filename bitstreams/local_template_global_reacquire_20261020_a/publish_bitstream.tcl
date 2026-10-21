foreach f {camera_template_global_reacquire_20261020_a.bit camera_template_global_reacquire_20261020_a_compress.bit} {
    if {[file exists $f]} {error "Refusing to overwrite $f"}
}
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
open_project camera_to_dsi_display.prj -noanalyze
import_db camera_to_dsi_display_pr.db
set_param bitgen compress on
bitgen -bit camera_template_global_reacquire_20261020_a.bit
