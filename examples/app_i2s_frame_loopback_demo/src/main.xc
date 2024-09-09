// Copyright 2014-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <platform.h>
#include <xs1.h>
#include "i2s.h"
#include "i2c.h"
#include "xassert.h"
#include <print.h>
#include <stdlib.h>
#include "xk_audio_316_mc_ab/board.h"


#define SAMPLE_FREQUENCY        192000
#define MASTER_CLOCK_FREQUENCY  24576000
#define DATA_BITS               32
#define CHANS_PER_FRAME         2
#define NUM_I2S_LINES           4

// I2S resources
on tile[1]: in port p_mclk =                                PORT_MCLK_IN;
on tile[1]: buffered out port:32 p_lrclk =                  PORT_I2S_LRCLK;
on tile[1]: out port p_bclk =                               PORT_I2S_BCLK;
on tile[1]: buffered out port:32 p_dac[NUM_I2S_LINES] =     {PORT_I2S_DAC0, PORT_I2S_DAC1, PORT_I2S_DAC2, PORT_I2S_DAC3};
on tile[1]: buffered in port:32 p_adc[NUM_I2S_LINES] =      {PORT_I2S_ADC0 ,PORT_I2S_ADC1, PORT_I2S_ADC2, PORT_I2S_ADC3};
on tile[1]: clock bclk =                                    XS1_CLKBLK_1;

// Board configuration from lib_board_support
static const xk_audio_316_mc_ab_config_t hw_config = {
        CLK_FIXED,              // clk_mode. Drive a fixed MCLK output
        0,                      // 1 = dac_is_clock_master
        MASTER_CLOCK_FREQUENCY,
        0,                      // pll_sync_freq (unused when driving fixed clock)
        AUD_316_PCM_FORMAT_I2S,
        DATA_BITS,
        CHANS_PER_FRAME
};


[[distributable]]
void i2s_loopback(server i2s_frame_callback_if i2s,
                  client i2c_master_if i_i2c
                 )
{
  int32_t samples[8] = {0, 0, 0, 0, 0, 0, 0, 0};

  // Config can be done remotely via i_i2c
  xk_audio_316_mc_ab_AudioHwInit(i_i2c, hw_config);

  while (1) {
    select {
    case i2s.init(i2s_config_t &?i2s_config, tdm_config_t &?tdm_config):
      i2s_config.mode = I2S_MODE_I2S;
      i2s_config.mclk_bclk_ratio = (MASTER_CLOCK_FREQUENCY/SAMPLE_FREQUENCY)/64;

      xk_audio_316_mc_ab_AudioHwConfig(i_i2c, hw_config, SAMPLE_FREQUENCY, MASTER_CLOCK_FREQUENCY, 0, DATA_BITS, DATA_BITS);

      break;

    case i2s.receive(size_t num_chan_in, int32_t sample[num_chan_in]):
      for (size_t i=0; i<num_chan_in; i++) {
          samples[i] = sample[i];
      }
      break;

    case i2s.send(size_t num_chan_out, int32_t sample[num_chan_out]):
      for (size_t i=0; i<num_chan_out; i++){
        sample[i] = samples[i];
      }
      break;


    case i2s.restart_check() -> i2s_restart_t restart:
      restart = I2S_NO_RESTART;
      break;
    }
  }
}


int main()
{
  interface i2c_master_if i_i2c[1];

  par {
    on tile[1]: {
        interface i2s_frame_callback_if i_i2s;

        par {
            // The application - loopback the I2S samples - note callbacks are inlined so does not take a thread
            [[distribute]] i2s_loopback(i_i2s, i_i2c[0]);
            i2s_frame_master(i_i2s, p_dac, NUM_I2S_LINES, p_adc, NUM_I2S_LINES, DATA_BITS, p_bclk, p_lrclk, p_mclk, bclk);
        }
    }

    on tile[0]: {
        xk_audio_316_mc_ab_board_setup(hw_config); // Setup must be done on tile[0]
        xk_audio_316_mc_ab_i2c_master(i_i2c);      // Run I2C master server task to allow control from tile[1]
    }
  }
  return 0;
}
