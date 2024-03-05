## Create an AXI4 Lite memory mapped interface connection for register maps,
#  instantiates an interconnect and reconfigure it at every process call.
#
#  \param[p_address] - address offset of the IP register map
#  \param[p_name] - name of the IP
#  \param[p_intf_name] - name of the AXI MM Slave interface (optional)
#
proc my_cpu_interconnect {p_address p_name {p_intf_name {}}} {

  global sys_zynq
  global sys_cpu_interconnect_index
  global use_smartconnect

  set i_str "M$sys_cpu_interconnect_index"
  if {$sys_cpu_interconnect_index < 10} {
    set i_str "M0$sys_cpu_interconnect_index"
  }

  if {$sys_cpu_interconnect_index == 0} {

    if {$use_smartconnect == 1} {
      ad_ip_instance smartconnect axi_cpu_interconnect [ list \
        NUM_MI 1 \
        NUM_SI 1 \
      ]
      ad_connect util_ad9361_divclk/clk_out axi_cpu_interconnect/aclk
      ad_connect util_ad9361_divclk_reset/peripheral_aresetn axi_cpu_interconnect/aresetn
    } else {
      ad_ip_instance axi_interconnect axi_cpu_interconnect
      ad_connect util_ad9361_divclk/clk_out axi_cpu_interconnect/ACLK
      ad_connect util_ad9361_divclk/clk_out axi_cpu_interconnect/S00_ACLK
      ad_connect util_ad9361_divclk_reset/peripheral_aresetn axi_cpu_interconnect/ARESETN
      ad_connect util_ad9361_divclk_reset/peripheral_aresetn axi_cpu_interconnect/S00_ARESETN
    }

    if {$sys_zynq == 3} {
      ad_connect util_ad9361_divclk/clk_out sys_cips/m_axi_fpd_aclk
      ad_connect axi_cpu_interconnect/S00_AXI sys_cips/M_AXI_FPD
    }
    if {$sys_zynq == 2} {
      ad_connect util_ad9361_divclk/clk_out sys_ps8/maxihpm0_lpd_aclk
      ad_connect axi_cpu_interconnect/S00_AXI sys_ps8/M_AXI_HPM0_LPD
    }
    if {$sys_zynq == 1} {
      ad_connect util_ad9361_divclk/clk_out sys_ps7/M_AXI_GP0_ACLK
      ad_connect axi_cpu_interconnect/S00_AXI sys_ps7/M_AXI_GP0
    }
    if {$sys_zynq == 0} {
      ad_connect axi_cpu_interconnect/S00_AXI sys_mb/M_AXI_DP
    }
    if {$sys_zynq == -1} {
      ad_connect axi_cpu_interconnect/S00_AXI mng_axi_vip/M_AXI
    }
  }

  if {$sys_zynq == 3} {
    set sys_addr_cntrl_space [get_bd_addr_spaces /sys_cips/M_AXI_FPD]
  }
  if {$sys_zynq == 2} {
    set sys_addr_cntrl_space [get_bd_addr_spaces sys_ps8/Data]
  }
  if {$sys_zynq == 1} {
    set sys_addr_cntrl_space [get_bd_addr_spaces sys_ps7/Data]
  }
  if {$sys_zynq == 0} {
    set sys_addr_cntrl_space [get_bd_addr_spaces sys_mb/Data]
  }
  if {$sys_zynq == -1} {
    set sys_addr_cntrl_space [get_bd_addr_spaces mng_axi_vip/Master_AXI]
  }

  set sys_cpu_interconnect_index [expr $sys_cpu_interconnect_index + 1]


  set p_cell [get_bd_cells $p_name]
  set p_intf [get_bd_intf_pins -filter \
    "MODE == Slave && VLNV == xilinx.com:interface:aximm_rtl:1.0 && NAME =~ *$p_intf_name*"\
    -of_objects $p_cell]

  set p_hier_cell $p_cell
  set p_hier_intf $p_intf

  while {$p_hier_intf != "" && [get_property TYPE $p_hier_cell] == "hier"} {
    set p_hier_intf [find_bd_objs -boundary_type lower \
      -relation connected_to $p_hier_intf]
    if {$p_hier_intf != {}} {
      set p_hier_cell [get_bd_cells -of_objects $p_hier_intf]
    } else {
      set p_hier_cell {}
    }
  }

  set p_intf_clock ""
  set p_intf_reset ""

  if {$p_hier_cell != {}} {
    set p_intf_name [lrange [split $p_hier_intf "/"] end end]

    set p_intf_clock [get_bd_pins -filter "TYPE == clk && \
      (CONFIG.ASSOCIATED_BUSIF == ${p_intf_name} || \
      CONFIG.ASSOCIATED_BUSIF =~ ${p_intf_name}:* || \
      CONFIG.ASSOCIATED_BUSIF =~ *:${p_intf_name} || \
      CONFIG.ASSOCIATED_BUSIF =~ *:${p_intf_name}:*)" \
      -quiet -of_objects $p_hier_cell]
    set p_intf_reset [get_bd_pins -filter "TYPE == rst && \
      (CONFIG.ASSOCIATED_BUSIF == ${p_intf_name} || \
       CONFIG.ASSOCIATED_BUSIF =~ ${p_intf_name}:* ||
       CONFIG.ASSOCIATED_BUSIF =~ *:${p_intf_name} || \
       CONFIG.ASSOCIATED_BUSIF =~ *:${p_intf_name}:*)" \
       -quiet -of_objects $p_hier_cell]

    if {($p_intf_clock ne "") && ($p_intf_reset eq "")} {
      set p_intf_reset [get_property CONFIG.ASSOCIATED_RESET [get_bd_pins ${p_intf_clock}]]
      if {$p_intf_reset ne ""} {
        set p_intf_reset [get_bd_pins -filter "NAME == $p_intf_reset" -of_objects $p_hier_cell]
      }
    }

    # Trace back up
    set p_hier_cell2 $p_hier_cell

    while {$p_intf_clock != {} && $p_hier_cell2 != $p_cell && $p_hier_cell2 != {}} {
      puts $p_intf_clock
      puts $p_hier_cell2
      set p_intf_clock [find_bd_objs -boundary_type upper \
        -relation connected_to $p_intf_clock]
      if {$p_intf_clock != {}} {
        set p_intf_clock [get_bd_pins [get_property PATH $p_intf_clock]]
        set p_hier_cell2 [get_bd_cells -of_objects $p_intf_clock]
      }
    }

    set p_hier_cell2 $p_hier_cell

    while {$p_intf_reset != {} && $p_hier_cell2 != $p_cell && $p_hier_cell2 != {}} {
      set p_intf_reset [find_bd_objs -boundary_type upper \
        -relation connected_to $p_intf_reset]
      if {$p_intf_reset != {}} {
        set p_intf_reset [get_bd_pins [get_property PATH $p_intf_reset]]
        set p_hier_cell2 [get_bd_cells -of_objects $p_intf_reset]
      }
    }
  }


  if {[find_bd_objs -quiet -relation connected_to $p_intf_clock] ne ""} {
    set p_intf_clock ""
  }
  if {$p_intf_reset ne ""} {
    if {[find_bd_objs -quiet -relation connected_to $p_intf_reset] ne ""} {
      set p_intf_reset ""
    }
  }

  set_property CONFIG.NUM_MI $sys_cpu_interconnect_index [get_bd_cells axi_cpu_interconnect]

  if {$use_smartconnect == 0} {
    ad_connect util_ad9361_divclk/clk_out axi_cpu_interconnect/${i_str}_ACLK
    ad_connect util_ad9361_divclk_reset/peripheral_aresetn axi_cpu_interconnect/${i_str}_ARESETN
  }
  if {$p_intf_clock ne ""} {
    ad_connect util_ad9361_divclk/clk_out ${p_intf_clock}
  }
  if {$p_intf_reset ne ""} {
    ad_connect util_ad9361_divclk_reset/peripheral_aresetn ${p_intf_reset}
  }
  ad_connect axi_cpu_interconnect/${i_str}_AXI ${p_intf}

  set p_seg [get_bd_addr_segs -of [get_bd_addr_spaces -of [get_bd_intf_pins -filter "NAME=~ *${p_intf_name}*" -of $p_hier_cell]]]
  set p_index 0
  foreach p_seg_name $p_seg {
    if {$p_index == 0} {
      set p_seg_range [get_property range $p_seg_name]
      if {$p_seg_range < 0x1000} {
        set p_seg_range 0x1000
      }
      if {$sys_zynq == 3} {
        if {($p_address >= 0x44000000) && ($p_address <= 0x4fffffff)} {
          # place axi peripherics in A400_0000-AFFF_FFFF range
          set p_address [expr ($p_address + 0x60000000)]
        } elseif {($p_address >= 0x70000000) && ($p_address <= 0x7fffffff)} {
          # place axi peripherics in B000_0000-BFFF_FFFF range
          set p_address [expr ($p_address + 0x40000000)]
        } else {
          error "ERROR: ad_cpu_interconnect : Cannot map ($p_address) to aperture, \
                Addess out of range 0x4400_0000 - 0X4FFF_FFFF; 0x7000_0000 - 0X7FFF_FFFF !"
        }
      }
      if {$sys_zynq == 2} {
        if {($p_address >= 0x40000000) && ($p_address <= 0x4fffffff)} {
          set p_address [expr ($p_address + 0x40000000)]
        }
        if {($p_address >= 0x70000000) && ($p_address <= 0x7fffffff)} {
          set p_address [expr ($p_address + 0x20000000)]
        }
      }
      create_bd_addr_seg -range $p_seg_range \
        -offset $p_address $sys_addr_cntrl_space \
        $p_seg_name "SEG_data_${p_name}"
    } else {
      assign_bd_address $p_seg_name
    }
    incr p_index
  }
}

