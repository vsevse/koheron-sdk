set board_preset boards/$board_name/config/board_preset.xml


set ps_name ps_0
set xadc_name xadc_wiz_0

source projects/init_bd.tcl
init_bd $ps_name $board_preset $xadc_name

# Add GPIO

add_master_interface $ps_name

set gpio_name axi_gpio_0
cell xilinx.com:ip:axi_gpio:2.0 $gpio_name {
  C_GPIO_WIDTH 8
  C_GPIO2_WIDTH 8
  C_IS_DUAL 1
} {}

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list Master "/${ps_name}/M_AXI_GP0" Clk "Auto"]  [get_bd_intf_pins $gpio_name/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:board  [get_bd_intf_pins $gpio_name/GPIO]
apply_bd_automation -rule xilinx.com:bd_rule:board  [get_bd_intf_pins $gpio_name/GPIO2]
set_property name exp_n [get_bd_intf_ports gpio_rtl]
set_property name exp_p [get_bd_intf_ports gpio_rtl_0]

# Add ADCs and DACs
source boards/red-pitaya/adc_dac.tcl
# Rename clocks
set adc_clk adc_dac/adc_clk
set pwm_clk adc_dac/pwm_clk

# Add Configuration register (synchronous with ADC clock)
source projects/config_register.tcl

# Add Status register
# TODO

# Connect LEDs
set led_offset 0
cell xilinx.com:ip:xlslice:1.0 led_slice \
  [list DIN_WIDTH 1024 DIN_FROM [expr 7+$led_offset] DIN_TO [expr $led_offset]] \
  [list Din axi_cfg_register_0/cfg_data]
connect_bd_net [get_bd_ports led_o] [get_bd_pins led_slice/Dout]

# Add PWM
source boards/red-pitaya/pwm.tcl

# Add address counter
set bram_width 13
cell xilinx.com:ip:c_counter_binary:12.0 base_counter \
  [list Output_Width [expr $bram_width+2] Increment_Value 4 SCLR true] \
  [list CLK $adc_clk]

set reset_offset [expr 6*32]

cell pavel-demin:user:edge_detector:1.0 reset_base_counter {} \
  [list clk $adc_clk dout base_counter/SCLR]

cell xilinx.com:ip:xlslice:1.0 reset_base_counter_slice \
    [list DIN_WIDTH 1024 DIN_FROM $reset_offset DIN_TO $reset_offset] \
    [list Din axi_cfg_register_0/cfg_data Dout reset_base_counter/din]

cell xilinx.com:ip:xlslice:1.0 addr_delay_slice \
  [list DIN_WIDTH 1024 DIN_FROM [expr 15+$reset_offset] DIN_TO [expr 2+$reset_offset]] \
  [list Din /axi_cfg_register_0/cfg_data]

cell xilinx.com:ip:c_shift_ram:12.0 delay_addr \
  [list ShiftRegType Variable_Length_Lossless Width [expr $bram_width+2]] \
  [list D base_counter/Q CLK /$adc_clk A addr_delay_slice/Dout]


# Add DAC BRAM
source scripts/bram.tcl
set dac_bram_name dac_bram
add_bram $dac_bram_name 32K
# Connect port B of BRAM to ADC clock
connect_bd_net [get_bd_pins blk_mem_gen_$dac_bram_name/clkb] [get_bd_pins $adc_clk]
connect_bd_net [get_bd_pins blk_mem_gen_$dac_bram_name/addrb] [get_bd_pins delay_addr/Q]

# Connect BRAM output to DACs
for {set i 0} {$i < 2} {incr i} {
  set channel [lindex {a b} $i]
  cell xilinx.com:ip:xlslice:1.0 dac_${channel}_slice \
    [list DIN_WIDTH 32 DIN_FROM [expr 13+16*$i] DIN_TO [expr 16*$i]] \
    [list Din blk_mem_gen_$dac_bram_name/doutb Dout adc_dac/$dac_name/dac_dat_${channel}_i]
}

# Connect remaining ports of BRAM
cell xilinx.com:ip:xlconstant:1.1 ${dac_bram_name}_dinb {CONST_VAL 0 CONST_WIDTH 32} [list dout blk_mem_gen_$dac_bram_name/dinb]
cell xilinx.com:ip:xlconstant:1.1 ${dac_bram_name}_enb {CONST_VAL 1} [list dout blk_mem_gen_$dac_bram_name/enb]
cell xilinx.com:ip:xlconstant:1.1 ${dac_bram_name}_web {CONST_VAL 0 CONST_WIDTH 4} [list dout blk_mem_gen_$dac_bram_name/web]
connect_bd_net [get_bd_pins blk_mem_gen_$dac_bram_name/rstb] [get_bd_pins rst_ps_0_125M/peripheral_reset]

# Add ADC1 BRAM
set adc1_bram_name adc1_bram
add_bram $adc1_bram_name 32K
# Connect port B of BRAM to ADC clock
connect_bd_net [get_bd_pins blk_mem_gen_$adc1_bram_name/clkb] [get_bd_pins $adc_clk]
cell xilinx.com:ip:xlconstant:1.1 ${adc1_bram_name}_enb {CONST_VAL 1} [list dout blk_mem_gen_$adc1_bram_name/enb]
connect_bd_net [get_bd_pins blk_mem_gen_$adc1_bram_name/addrb] [get_bd_pins delay_addr/Q]
connect_bd_net [get_bd_pins blk_mem_gen_$adc1_bram_name/rstb] [get_bd_pins rst_ps_0_125M/peripheral_reset]

# Add averaging module
source projects/averaging.tcl


