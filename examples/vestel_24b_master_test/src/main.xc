// Copyright (c) 2014-2018, XMOS Ltd, All rights reserved
#include <platform.h>
#include <xs1.h>
#include "i2s.h"
#include "i2c.h"
#include "gpio.h"
#include "xassert.h"
#include <stdlib.h>
#include <debug_print.h>
#include <string.h>
#include <xscope.h>


#define TEST_LENGTH     8 //Number of I2S frames to check

#ifndef NUM_I2S_LINES
#define NUM_I2S_LINES   1
#endif
#ifndef SAMPLE_FREQUENCY
#define SAMPLE_FREQUENCY 48000
#endif
#ifndef MASTER_CLOCK_FREQUENCY
#define MASTER_CLOCK_FREQUENCY 24576000
//#define MASTER_CLOCK_FREQUENCY 49152000
#endif
#ifndef SIM_LOOPBACK_TEST
#define SIM_LOOPBACK_TEST 0
#endif


/* Ports and clocks used by the application */
on tile[0]: out buffered port:32 p_lrclk    = XS1_PORT_1G;
on tile[0]: out port p_bclk                 = XS1_PORT_1H;
on tile[0]: out buffered port:32 p_dout[4] = {XS1_PORT_1M, XS1_PORT_1N, XS1_PORT_1O, XS1_PORT_1P};
on tile[0]: in buffered port:32 p_din[4]   = {XS1_PORT_1I, XS1_PORT_1J, XS1_PORT_1K, XS1_PORT_1L};
on tile[0]: clock clk_bclk = XS1_CLKBLK_2;
on tile[0]: in port p_mclk                 = XS1_PORT_1D; //Coax Tx



on tile[0]: port p_i2c = XS1_PORT_4A;
on tile[0]: port p_gpio = XS1_PORT_8C;

on tile[1]: in port p_spdif = XS1_PORT_1O; //Optical in
on tile[1]: clock spdif_clk = XS1_CLKBLK_4;


enum gpio_shared_audio_pins {
  GPIO_DAC_RST_N = 1,
  GPIO_PLL_SEL = 5,     // 1 = CS2100, 0 = Phaselink clock source
  GPIO_ADC_RST_N = 6,
  GPIO_MCLK_FSEL = 7,   // Select frequency on Phaselink clock. 0 = 24.576MHz for 48k, 1 = 22.5792MHz for 44.1k.
};

#define CS5368_ADDR           0x4C // I2C address of the CS5368 DAC
#define CS5368_GCTL_MDE       0x01 // I2C mode control register number
#define CS5368_PWR_DN         0x06

#define CS4384_ADDR           0x18 // I2C address of the CS4384 ADC
#define CS4384_MODE_CTRL      0x02 // I2C mode control register number
#define CS4384_PCM_CTRL       0x03 // I2C PCM control register number

//Simulator master I2S waveform gen
on tile[0]: out port p_mclk_gen       = XS1_PORT_1E; //Optical TX
on tile[0]: clock clk_audio_mclk_gen  = XS1_CLKBLK_3;


void setup_clocks(void){

  const unsigned core_clk = 440000000;
  const unsigned core_mclk_div = 36;

  //Ratio of MCLK : BCLK is 5.333333333
  //The lowest common denominator (div 2) of 2,304,000Hz (BCLK) and 12,288,000Hz (MCLK) is 73,728,000Hz
  //73,728,000Hz * 6 = 442,368,000Hz so use 440MHz core clock

  debug_printf("MCLK: %d\n", core_clk / (core_mclk_div /2));

  //mclk generator
  configure_clock_xcore(clk_audio_mclk_gen, core_mclk_div / 2);
  configure_port_clock_output(p_mclk_gen, clk_audio_mclk_gen);
  start_clock(clk_audio_mclk_gen);
}

static char gpio_pin_map[4] =  {
  GPIO_DAC_RST_N,
  GPIO_ADC_RST_N,
  GPIO_PLL_SEL,
  GPIO_MCLK_FSEL
};


[[distributable]]
#pragma unsafe arrays
void i2s_handler(server i2s_frame_callback_if i_i2s, client i2c_master_if i_i2c, 
                 client output_gpio_if dac_reset,
                 client output_gpio_if adc_reset,
                 client output_gpio_if pll_select,
                 client output_gpio_if mclk_select)
{
  unsigned i2s_sample_count = 0;

  int32_t loopback[NUM_I2S_LINES * 2] = {0};

  //const int32_t mask = 0xffffffff << (32 - N_BITS);

  while (1) {
    select {
    case i_i2s.init(i2s_config_t &?i2s_config, tdm_config_t &?tdm_config):
      i2s_config.mode = I2S_MODE_I2S;
      i2s_config.mclk_bclk_ratio = (MASTER_CLOCK_FREQUENCY/SAMPLE_FREQUENCY)/64;

      // Set CODECs in reset
      dac_reset.output(0);
      adc_reset.output(0);
      break;

    case i_i2s.receive(size_t num_chan_in, int32_t sample[num_chan_in]):
      memcpy(loopback, sample, num_chan_in * sizeof(int32_t));

      break;

    case i_i2s.send(size_t num_chan_out, int32_t sample[num_chan_out]):
      memcpy(sample, loopback, num_chan_out * sizeof(int32_t));
      xscope_int(0, sample[0]);
      //debug_printf("%d\n", sample[0]);
      sample[0] = 0xf0aaf000;
      break;

    case i_i2s.restart_check() -> i2s_restart_t restart:
      restart = I2S_NO_RESTART;
      //delay_microseconds(1);
      i2s_sample_count ++;
      break;
    }
  }
}


int main()
{
  interface i2s_frame_callback_if i_i2s;
  interface i2c_master_if i_i2c[1];
  interface output_gpio_if i_gpio[4];



  par {
    on tile[0]: while(1){
      setup_clocks();
      i2s_frame_master(i_i2s, p_dout, NUM_I2S_LINES, p_din, NUM_I2S_LINES, p_bclk, p_lrclk, p_mclk, clk_bclk);
      debug_printf("Exit\n");
    }

    on tile[0]: [[distribute]] i2c_master_single_port(i_i2c, 1, p_i2c, 100, 0, 1, 0);
    on tile[0]: [[distribute]] output_gpio(i_gpio, 4, p_gpio, gpio_pin_map);

    /* The application - loopback the I2S samples */
    on tile[0]: [[distribute]] i2s_handler(i_i2s, i_i2c[0], i_gpio[0], i_gpio[1], i_gpio[2], i_gpio[3]);



  } 
  return 0;
}
