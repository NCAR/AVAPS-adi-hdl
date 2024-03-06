# AVAPS adrv9361z7035_avaps_revc

This is a carrier board project for the AVAPS RevC receiver.
AVAPS is based on the *adrv9361z7035_ccbob_cmos* reference
design. 

For maintinability, we want to use the ADI hdl repository
and tooling with minimal changes. Addition of this
directory is the only modification made to the repository
fork.

It would be nice to have a scheme where this directory
could live outside of the repository tree and still access
the ADI build system.

## Building
```sh
cd hdl/projects/adrv9361z7035/avaps_revc
make clean-all
make
```

The *clean* target will remove the half-dozen generated 
directories, and the thousands of files contained within.

The *clean-all* target will remove the same as above, as well 
as all of the out-of-context IP.

The build process is managed by *make*, which basically runs a number of
Vivado-centric tcl scripts. It is a nicely designed system, which
allows sharing of the tooling amongst the large number of ADI
supported boards and devices.

The build process first builds the out-of-context IP, followed by the build of the top level system.
It will produce output like:
```sh
Building axi_ad9361 library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/axi_ad9361/axi_ad9361_ip.log] ... OK
Building util_cdc library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/util_cdc/util_cdc_ip.log] ... OK
Building util_axis_fifo library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/util_axis_fifo/util_axis_fifo_ip.log] ... OK
Building axi_dmac library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/axi_dmac/axi_dmac_ip.log] ... OK
Building axi_gpreg library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/axi_gpreg/axi_gpreg_ip.log] ... OK
Building axi_sysid library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/axi_sysid/axi_sysid_ip.log] ... OK
Building sysid_rom library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/sysid_rom/sysid_rom_ip.log] ... OK
Building util_cpack2 library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/util_pack/util_cpack2/util_cpack2_ip.log] ... OK
Building util_upack2 library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/util_pack/util_upack2/util_upack2_ip.log] ... OK
Building util_rfifo library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/util_rfifo/util_rfifo_ip.log] ... OK
Building util_tdd_sync library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/util_tdd_sync/util_tdd_sync_ip.log] ... OK
Building util_wfifo library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/util_wfifo/util_wfifo_ip.log] ... OK
Building axi_xcvrlb library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/xilinx/axi_xcvrlb/axi_xcvrlb_ip.log] ... OK
Building util_clkdiv library [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/library/xilinx/util_clkdiv/util_clkdiv_ip.log] ... OK
Building adrv9361z7035_avaps_revc project [/home/martinc/AVAPS-chassis/AVAPS-adi-hdl/projects/adrv9361z7035/avaps_revc/adrv9361z7035_avaps_revc_vivado.log] ...
```

*Hint: `tail -f` the log file to watch the progress and to quickly see the build errors`*

### ADI build system
ADI provides [wiki documentation](https://wiki.analog.com/resources/fpga/docs/hdl/porting_project_quick_start_guide)
(and [a better presentation](https://analogdevicesinc.github.io/hdl/user_guide/architecture.html))
on the build system. Some description of the various project files is given there,
although to get a complete understanding you will likely have to do
some digging around in the code base.

ADI provides a library of tcl convenience functions, which assemble
Vivado tcl commands to accomplish various design needs. These
are defined in *hdl/projects/scripts/adi_board.tcl*, and include
documentation describing their usage.

The ADI 
function names begin with *ad_*. For instance,
```sh
ad_connect()
```
is a wrapper for various configurations of the Xilinx call
```sh
bd_net()
```

## Files
Files from the *adrv9361z7035_ccbob_cmos* design were added, or copied and modified
for this carrier design. Just diff them with the original file to explicitly see
the modifications. These files are located in *avaps_revc/*.

| Original               | AVAPS file|
|----------------------|------------------------|
|                      | avaps_revc_bd.tcl      |
| ccbob_cmos_constr.xdc| avaps_revc_constr.xdc  |
| (adi_board.tcl)      | my_cpu_interconnect.tcl|
| Makefile             | Makefile               |
| system_bd.tcl        | system_bd.tcl          |
| system_project.tcl   | system_project.tcl     |
| system_top.v         | system_top.v           |

### avaps_revc_bd.tcl
This file modifies or makes additions to the board
design from other files in the *ccbob_cmos* project.
It is sourced in *system_bd.tcl*.

### avaps_revc_constr.xdc
The constraints file which defines the FPGA pinout. It
replaces *ccbob_cmos_constr.xdc*. The original definitions
remain in the file for reference; they have just been 
commented out.

### my_cpu_interconnect.tcl
ADI provides the *ad_cpu_interconnect()* function for automatically
creating AXI connections. However, that function assumes that the
IP will be using the *sys_cpu_clk* and *sys_cput_resetn* for clock
and reset. This file contains a modified function *my_cpu_interconnect()*
which replaces these signals with  *util_ad9361_divclk/clk_out* and 
*util_ad9361_divclk_reset/peripheral_aresetn*.

*TODO: add the desired replacement signals to the function signature*

### Makefile
*avaps_revc* files were added to the dependency lists.

### system_bd.tcl
Only added the sourcing of *avaps_revc_bd.tcl*.

### system_project.tcl
Changed the project name, and changed a constraints reference 
from *ccbob_constr.xdc* to *avaps_revc_constr.xdc*.

### system_top.v
Modified to enumerate the FPGA signals used in the AVAPS design.
