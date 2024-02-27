###############################################################################
## Copyright (C) 2024 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################

proc i3c_controller_create {{async_clk 0} {offload 1} {max_devs 16}} {
  add_instance i3c_host_interface i3c_controller_host_interface

  set_instance_parameter_value i3c_host_interface {ASYNC_CLK} $async_clk
  set_instance_parameter_value i3c_host_interface {OFFLOAD}   $offload

  add_instance i3c_core i3c_controller_core

  set_instance_parameter_value i3c_core {MAX_DEVS} $max_devs

  add_connection i3c_host_interface.sdo  i3c_core.sdo
  add_connection i3c_host_interface.cmdp i3c_core.cmdp
  add_connection i3c_host_interface.rmap i3c_core.rmap
  add_connection i3c_core.sdi i3c_host_interface.sdi
  add_connection i3c_core.ibi i3c_host_interface.ibi

  add_connection i3c_host_interface.if_reset_n i3c_core.if_reset_n
}
