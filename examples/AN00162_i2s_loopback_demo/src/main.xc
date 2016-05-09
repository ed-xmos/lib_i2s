// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <platform.h>
#include <xs1.h>
#include "i2s.h"
#include "i2c.h"
#include "gpio.h"
#include "xassert.h"
#include <print.h>
#include <stdlib.h>

#define NUM_I2S_LINES   4
#define BURN_THREADS    0
#define SAMPLE_FREQUENCY 192000
#define MASTER_CLOCK_FREQUENCY 24576000


/* Ports and clocks used by the application */
on tile[0]: out buffered port:32 p_lrclk = XS1_PORT_1G;
on tile[0]: out buffered port:32 p_bclk = XS1_PORT_1H;
on tile[0]: in port p_mclk = XS1_PORT_1F;
on tile[0]: out buffered port:32 p_dout[4] = {XS1_PORT_1M, XS1_PORT_1N, XS1_PORT_1O, XS1_PORT_1P};
on tile[0]: in buffered port:32 p_din[4] = {XS1_PORT_1I, XS1_PORT_1J, XS1_PORT_1K, XS1_PORT_1L};

on tile[0]: clock mclk = XS1_CLKBLK_1;
on tile[0]: clock bclk = XS1_CLKBLK_2;

on tile[0]: port p_i2c = XS1_PORT_4A;
on tile[0]: port p_gpio = XS1_PORT_8C;

#define CS5368_ADDR           0x4C // I2C address of the CS5368 DAC
#define CS5368_GCTL_MDE       0x01 // I2C mode control register number
#define CS5368_PWR_DN         0x06

#define CS4384_ADDR           0x18 // I2C address of the CS4384 ADC
#define CS4384_MODE_CTRL      0x02 // I2C mode control register number
#define CS4384_PCM_CTRL       0x03 // I2C PCM control register number

enum gpio_shared_audio_pins {
  GPIO_DAC_RST_N = 1,
  GPIO_PLL_SEL = 5,     // 1 = CS2100, 0 = Phaselink clock source
  GPIO_ADC_RST_N = 6,
  GPIO_MCLK_FSEL = 7,   // Select frequency on Phaselink clock. 0 = 24.576MHz for 48k, 1 = 22.5792MHz for 44.1k.
};

void reset_codecs(client i2c_master_if i2c)
{
  /* Mode Control 1 (Address: 0x02) */
  /* bit[7] : Control Port Enable (CPEN)     : Set to 1 for enable
   * bit[6] : Freeze controls (FREEZE)       : Set to 1 for freeze
   * bit[5] : PCM/DSD Selection (DSD/PCM)    : Set to 0 for PCM
   * bit[4:1] : DAC Pair Disable (DACx_DIS)  : All Dac Pairs enabled
   * bit[0] : Power Down (PDN)               : Powered down
   */
  i2c.write_reg(CS4384_ADDR, CS4384_MODE_CTRL, 0b11000001);

  /* PCM Control (Address: 0x03) */
  /* bit[7:4] : Digital Interface Format (DIF) : 0b1100 for TDM
   * bit[3:2] : Reserved
   * bit[1:0] : Functional Mode (FM) : 0x11 for auto-speed detect (32 to 200kHz)
   */
  i2c.write_reg(CS4384_ADDR, CS4384_PCM_CTRL, 0b00010111);

  /* Mode Control 1 (Address: 0x02) */
  /* bit[7] : Control Port Enable (CPEN)     : Set to 1 for enable
   * bit[6] : Freeze controls (FREEZE)       : Set to 0 for freeze
   * bit[5] : PCM/DSD Selection (DSD/PCM)    : Set to 0 for PCM
   * bit[4:1] : DAC Pair Disable (DACx_DIS)  : All Dac Pairs enabled
   * bit[0] : Power Down (PDN)               : Not powered down
   */
  i2c.write_reg(CS4384_ADDR, CS4384_MODE_CTRL, 0b10000000);

  unsigned adc_dif = 0x01;  // I2S mode
  unsigned adc_mode = 0x03; // Slave mode all speeds

  /* Reg 0x01: (GCTL) Global Mode Control Register */
  /* Bit[7]: CP-EN: Manages control-port mode
   * Bit[6]: CLKMODE: Setting puts part in 384x mode
   * Bit[5:4]: MDIV[1:0]: Set to 01 for /2
   * Bit[3:2]: DIF[1:0]: Data Format: 0x01 for I2S, 0x02 for TDM
   * Bit[1:0]: MODE[1:0]: Mode: 0x11 for slave mode
   */
  i2c.write_reg(CS5368_ADDR, CS5368_GCTL_MDE, 0b10010000 | (adc_dif << 2) | adc_mode);

  /* Reg 0x06: (PDN) Power Down Register */
  /* Bit[7:6]: Reserved
   * Bit[5]: PDN-BG: When set, this bit powers-own the bandgap reference
   * Bit[4]: PDM-OSC: Controls power to internal oscillator core
   * Bit[3:0]: PDN: When any bit is set all clocks going to that channel pair are turned off
   */
  i2c.write_reg(CS5368_ADDR, CS5368_PWR_DN, 0b00000000);
}

int delay = 0;

unsafe{
    int * unsafe delay_ptr = &delay;
}

[[distributable]]
void i2s_loopback(server i2s_callback_if i2s,
                  client i2c_master_if i2c,
                  client output_gpio_if dac_reset,
                  client output_gpio_if adc_reset,
                  client output_gpio_if pll_select,
                  client output_gpio_if mclk_select)
{
  int32_t samples[8] = {0, 0, 0, 0, 0, 0, 0, 0};
  while (1) {
    select {
    case i2s.init(i2s_config_t &?i2s_config, tdm_config_t &?tdm_config):
      i2s_config.mode = I2S_MODE_I2S;
      i2s_config.mclk_bclk_ratio = (MASTER_CLOCK_FREQUENCY/SAMPLE_FREQUENCY)/64;

#if !SIM
      // Set CODECs in reset
      dac_reset.output(0);
      adc_reset.output(0);

      // Select 48Khz family clock (24.576Mhz)
      mclk_select.output(1);
      pll_select.output(0);

      // Allow the clock to settle
      delay_milliseconds(2);

      // Take CODECs out of reset
      dac_reset.output(1);
      adc_reset.output(1);

      reset_codecs(i2c);
#endif
      break;

/* Delay tolerance log before 192KHz broken @ 100MHz
 * Vanilla, 2ch, 192KHz - 86
 * Vanilla, 4ch, 192KHz - 32
 * Vanilla, 6ch, 192KHz - 15
 * Vanilla, 8ch, 192KHz - 6
 * HW_CLK,  2ch, 192KHz - 104
 * HW_CLK,  4ch, 192KHz - 44
 * HW_CLK,  6ch, 192KHz - 24
 * HW_CLK,  8ch, 192KHz - 14
 */

/* Delay tolerance log before 192KHz broken @ 62.5MHz
* Vanilla, 2ch, 192KHz - 4
* Vanilla, 4ch, 192KHz - 9
* Vanilla, 6ch, 192KHz - N/A
* Vanilla, 8ch, 192KHz - N/A
* HW_CLK,  2ch, 192KHz - 8
* HW_CLK,  4ch, 192KHz - 8
* HW_CLK,  6ch, 192KHz - 1
* HW_CLK,  8ch, 192KHz - N/A
*/


    case i2s.receive(size_t index, int32_t sample):
      timer t;
      int time;
      t :> time;
      samples[index] = sample;
      t when timerafter(time + delay) :> void;
      break;

    case i2s.send(size_t index) -> int32_t sample:
      timer t;
      int time;
      t :> time;
#if SIM
      sample = 0xFFFFFFFF;
#else
      sample = samples[index];
#endif
      t when timerafter(time + delay) :> void;
      break;

    case i2s.restart_check() -> i2s_restart_t restart:
      restart = I2S_NO_RESTART;
      break;
    }
  }
}

static char gpio_pin_map[4] =  {
  GPIO_DAC_RST_N,
  GPIO_ADC_RST_N,
  GPIO_PLL_SEL,
  GPIO_MCLK_FSEL
};

#if SIM
#define DIFF_WRAP_16(new, old)  (new > old ? new - old : new + 0x10000 - old)
on tile[0]: port p_lr_test = XS1_PORT_1A;
unsafe void test_lr_period(void){
    set_core_fast_mode_on();    //Burn all MIPS

    int time, time_old;
    int diff;
    for(int i=0; i<4;i++){
        p_lr_test when pinseq(0) :> void;
        p_lr_test when pinseq(1) :> void;
    }
    const int period = (XS1_TIMER_HZ/(25000000/(MASTER_CLOCK_FREQUENCY/SAMPLE_FREQUENCY)));
    printintln(period);
    p_lr_test :> void @ time;
    time_old = time;
    while(1){
        p_lr_test when pinseq(0) :> void;
        p_lr_test when pinseq(1) :> void @ time;
        //diff = sext(time, 16) - sext(time_old, 16);
        diff = DIFF_WRAP_16(time, time_old);
        if (diff > period){
            printstr("LR_CLOCK period timing fail at delay = ");
            printuintln(*delay_ptr);
            printintln(diff);
            printintln(period);
            delay_milliseconds(1);
            _Exit(0);
        }
        time_old = time;
        (*delay_ptr)++;
    }
}
#endif

void burn(void){
    while(1);
}

int main()
{
  interface i2s_callback_if i_i2s;
  interface i2c_master_if i_i2c[1];
  interface output_gpio_if i_gpio[4];
  par {
    on tile[0]: {
      /* System setup, I2S + Codec control over I2C */
      i2s_master(i_i2s, p_dout, NUM_I2S_LINES, p_din, NUM_I2S_LINES, p_bclk, p_lrclk, p_mclk, bclk, mclk);
    }

    on tile[0]: [[distribute]] i2c_master_single_port(i_i2c, 1, p_i2c, 100, 0, 1, 0);
    on tile[0]: [[distribute]] output_gpio(i_gpio, 4, p_gpio, gpio_pin_map);

    /* The application - loopback the I2S samples */
    on tile[0]: [[distribute]] i2s_loopback(i_i2s, i_i2c[0], i_gpio[0], i_gpio[1], i_gpio[2], i_gpio[3]);

#if SIM
    on tile[0]: unsafe{test_lr_period();}
#endif
    on tile[0]: par (int i=0; i<(BURN_THREADS > 0 ? BURN_THREADS - SIM : 0); i++) {burn();};
  }
  return 0;
}
