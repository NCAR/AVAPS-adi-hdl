puts "---------------------------------------------------"
puts "           Start avaps_recv_bd.tcl"

set avapsII_rcvr_start_addr 0x43c00000
set rcvr_uart_start_addr    0x42c00000
# The uart interrupt list will establish how many AVAPSII_rcvr/uart_lite
# pairs we will create. The list is ordered for instance _0, _1, etc.
set rcvr_uart_interrupts {9 5 6 4 3 2 1 0}


#set_param synth.maxThreads 4
#set_param general.maxThreads 16

source ./my_cpu_interconnect.tcl
puts "current lib_dirs: $lib_dirs"
set current_repo_paths [get_property ip_repo_paths [current_fileset]]
puts "current_repo paths: $current_repo_paths"
# Right now we are requiring AVAPS-radio to be at the same level as this repo (ADI hdl). 
# Will need to come up with a more flexible scheme for specifying our custom IP repos.
set_property IP_REPO_PATHS {../../../../AVAPS-radio/avaps-ip-repo ../../../library} [current_fileset]
update_ip_catalog -rebuild
set new_repo_paths [get_property ip_repo_paths [current_fileset]]
puts "updated repo paths: $new_repo_paths"
puts "           Available IP"
foreach p $new_repo_paths {
    foreach n [get_ipdefs -filter REPOSITORY==$p] { puts ">>> $p ip: $n" }
}
puts " "

# Remove unused objects which were instantiated in common/ccbob_bd.tcl

ad_disconnect  axi_pz_xcvrlb/ref_clk gt_ref_clk
ad_disconnect  axi_pz_xcvrlb/rx_p gt_rx_p
ad_disconnect  axi_pz_xcvrlb/rx_n gt_rx_n
ad_disconnect  axi_pz_xcvrlb/tx_p gt_tx_p
ad_disconnect  axi_pz_xcvrlb/tx_n gt_tx_n

delete_bd_objs [get_bd_ports /gt_ref_clk]
delete_bd_objs [get_bd_ports /gt_rx_p]
delete_bd_objs [get_bd_ports /gt_rx_n]
delete_bd_objs [get_bd_ports /gt_tx_p]
delete_bd_objs [get_bd_ports /gt_tx_n]

delete_bd_objs [get_bd_cells axi_pz_xcvrlb]

# Remove Tx functions
delete_bd_objs [get_bd_cells util_ad9361_dac_upack]
delete_bd_objs [get_bd_cells axi_ad9361_dac_dma]
delete_bd_objs [get_bd_cells util_ad9361_dac_upack_fifo]

# Add AVAPS ports
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 iic_carrier
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 gpio_launcher_in
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 gpio_launcher_out
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 gpio_usb
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 rs232_out
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uart_gps
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uart_sonde

# axi_uart16550_gps
ad_ip_instance axi_uart16550 axi_uart16550_gps
ad_connect axi_uart16550_gps/uart uart_gps
ad_cpu_interrupt ps-8 mb-8 axi_uart16550_gps/ip2intc_irpt
ad_cpu_interconnect 0x43D00000 axi_uart16550_gps

# axi_uart16550_rs232
ad_ip_instance axi_uart16550 axi_uart16550_rs232
ad_connect axi_uart16550_rs232/uart rs232_out
ad_cpu_interrupt ps-12 mb-12 axi_uart16550_rs232/ip2intc_irpt
ad_cpu_interconnect 0x43D10000 axi_uart16550_rs232

# axi_uart16550_sonde
ad_ip_instance axi_uart16550 axi_uart16550_sonde
ad_connect axi_uart16550_sonde/uart uart_sonde
ad_cpu_interrupt ps-10 mb-10 axi_uart16550_sonde/ip2intc_irpt
ad_cpu_interconnect 0x43D20000 axi_uart16550_sonde

# axi_iic_carrier
ad_ip_instance      axi_iic             axi_iic_carrier
ad_ip_parameter     axi_iic_carrier     CONFIG.USE_BOARD_FLOW true
ad_ip_parameter     axi_iic_carrier     CONFIG.IIC_BOARD_INTERFACE Custom
ad_connect          axi_iic_carrier/iic iic_carrier 
ad_cpu_interrupt    ps-7 mb-7           axi_iic_carrier/iic2intc_irpt
ad_cpu_interconnect 0x41610000          axi_iic_carrier

# axi_gpio_launcher
ad_ip_instance      axi_gpio          axi_gpio_launcher
ad_ip_parameter     axi_gpio_launcher CONFIG.C_ALL_INPUTS 1
ad_ip_parameter     axi_gpio_launcher CONFIG.C_GPIO_WIDTH 2
ad_ip_parameter     axi_gpio_launcher CONFIG.C_IS_DUAL 1
ad_ip_parameter     axi_gpio_launcher CONFIG.C_ALL_OUTPUTS_2 1
ad_ip_parameter     axi_gpio_launcher CONFIG.C_GPIO2_WIDTH 1
ad_connect          axi_gpio_launcher/gpio  gpio_launcher_in
ad_connect          axi_gpio_launcher/gpio2 gpio_launcher_out
ad_cpu_interconnect 0x41210000        axi_gpio_launcher

# axi_gpio_usb
ad_ip_instance      axi_gpio           axi_gpio_usb
ad_ip_parameter     axi_gpio_usb       CONFIG.C_GPIO_WIDTH 1
ad_ip_parameter     axi_gpio_usb       CONFIG.C_ALL_OUTPUTS 1
ad_connect          axi_gpio_usb/gpio  gpio_usb
ad_cpu_interconnect 0x41220000         axi_gpio_usb

# axi_specwin
ad_ip_instance      specwin                   axi_specwin
ad_connect          axi_specwin/ipcore_clk    util_ad9361_divclk/clk_out                 
ad_connect          axi_specwin/ipcore_resetn util_ad9361_divclk_reset/peripheral_aresetn
ad_connect          axi_specwin/iin           util_ad9361_adc_fifo/dout_data_0           
ad_connect          axi_specwin/qin           util_ad9361_adc_fifo/dout_data_1         
ad_connect          axi_specwin/validin       util_ad9361_adc_fifo/dout_valid_0         
my_cpu_interconnect 0x43C80000 axi_specwin

# axi_spec dma
ad_ip_instance  axi_dmac                         axi_dmac_spec
ad_ip_parameter axi_dmac_spec                    CONFIG.DMA_TYPE_SRC        2
ad_ip_parameter axi_dmac_spec                    CONFIG.DMA_TYPE_DEST       0
ad_ip_parameter axi_dmac_spec                    CONFIG.CYCLIC              0
ad_ip_parameter axi_dmac_spec                    CONFIG.SYNC_TRANSFER_START 0
ad_ip_parameter axi_dmac_spec                    CONFIG.AXI_SLICE_SRC       0
ad_ip_parameter axi_dmac_spec                    CONFIG.AXI_SLICE_DEST      0
ad_ip_parameter axi_dmac_spec                    CONFIG.DMA_2D_TRANSFER     0
ad_ip_parameter axi_dmac_spec                    CONFIG.DMA_DATA_WIDTH_SRC  16
ad_connect      axi_dmac_spec/s_axi_aresetn      sys_cpu_resetn  
ad_connect      axi_dmac_spec/fifo_wr_clk        util_ad9361_divclk/clk_out  
ad_connect      axi_dmac_spec/m_dest_axi_aresetn sys_cpu_resetn  
ad_cpu_interrupt ps-15 mb-15 axi_dmac_spec/irq
ad_cpu_interconnect 0x43C90000                   axi_dmac_spec
ad_mem_hp2_interconnect sys_cpu_clk axi_dmac_spec/m_dest_axi

# Connect specwin to axi_dmac_spec
ad_connect axi_specwin/specout                         axi_dmac_spec/fifo_wr_din
ad_connect axi_specwin/validout                        axi_dmac_spec/fifo_wr_en
#ad_connect axi_specwin/sync                           axi_dmac_spec/fifo_wr_sync

# Create the receiver/uart pairs
set i 0
set rcvr_addr $avapsII_rcvr_start_addr
set uart_addr $rcvr_uart_start_addr
foreach uart_interrupt $rcvr_uart_interrupts {
    set r_addr_str [format "0x%08x" $rcvr_addr]
    set u_addr_str [format "0x%08x" $uart_addr]
    set uart_name [format "axi_uartlite_%d" $i]
    set rcvr_name [format "AVAPSII_rcvr_%d" $i]

    puts "$rcvr_name:$r_addr_str $uart_name:$u_addr_str uart interrupt:$uart_interrupt"

    # AVAPSII_rcvr
    ad_ip_instance AVAPSII_rcvr $rcvr_name
    ad_connect          $rcvr_name/ipcore_clk                 util_ad9361_divclk/clk_out                 
    ad_connect          $rcvr_name/ipcore_resetn              util_ad9361_divclk_reset/peripheral_aresetn
    ad_connect          $rcvr_name/dut_data_valid_in_rx       util_ad9361_adc_fifo/dout_valid_0
    ad_connect          $rcvr_name/dut_data_in_0_rx           util_ad9361_adc_fifo/dout_data_0
    ad_connect          $rcvr_name/dut_data_in_1_rx           util_ad9361_adc_fifo/dout_data_1
    my_cpu_interconnect $r_addr_str                           $rcvr_name

    # axi_uartlite
    ad_ip_instance      axi_uartlite                          $uart_name
    ad_ip_parameter     $uart_name                            CONFIG.C_BAUDRATE 2400
    ad_connect          $uart_name/rx                         $rcvr_name/dut_data_valid_out_rx
    ad_cpu_interrupt    ps-$uart_interrupt mb-$uart_interrupt $uart_name/interrupt
    ad_cpu_interconnect $u_addr_str                           $uart_name

    incr i
    set rcvr_addr [expr "$rcvr_addr+0x10000"]
    set uart_addr [expr "$uart_addr+0x10000"]
}

puts "           End avaps_recv_bd.tcl"
puts "---------------------------------------------------"