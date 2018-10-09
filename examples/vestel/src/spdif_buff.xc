#include "spdif.h"
#define DEBUG_UNIT SPDIF_MGR
#define DEBUG_PRINT_ENABLE_SPDIF_MGR 1
#include "debug_print.h"
#include <xscope.h>

//Task which receives SPDIF samples and transmits packet to ASRC engine/manager when complete
void spdif_rx_buffer(streaming chanend c_spdif, streaming chanend c_spdif_rx){
  int samples[SPDIF_RX_CHANS] = {0};
  int32_t sample = 0;
  size_t index = 0;
  unsigned count = 0;

  while(1){
    select{
      case spdif_receive_sample(c_spdif_rx, sample, index):
        samples[index] = sample;
        if (index == 1){
          xscope_int(2, samples[0]);
          count ++;
          c_spdif <: count;
          //debug_printf("SPDIF PUSH\n");
        }
      break;
    }
  }

}