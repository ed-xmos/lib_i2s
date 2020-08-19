#include "i2s.h"
#include "i2s_xcore_ai.h"
#include <print.h>
#include <xccompat.h>

[[distributable]]
void callback_handler(server i2s_frame_callback_if i2s_i){
    while(1){
        select{
            case i2s_i.init(i2s_config_t &?i2s_config, tdm_config_t &?tdm_config):
                printstrln("i2s_i.init");
            break;

            case i2s_i.restart_check() -> i2s_restart_t restart:
                // printstrln("i2s_i.restart_check");
                restart = I2S_NO_RESTART;
            break;

            case i2s_i.receive(size_t num_in, int32_t samples[num_in]):
                // printstrln("i2s_i.receive");
            break;

            case i2s_i.send(size_t num_out, int32_t samples[num_out]):
                // printstrln("i2s_i.send");
            break;
        }
    }
}



void i2s_master_ai(
                out port p_dout[],
                const size_t num_out,
                in port p_din[],
                const size_t num_in,
                out port p_bclk,
                out port p_lrclk,
                in port p_mclk,
                clock bclk){
    printstr("i2s_master wrapper\n");

    i2s_frame_callback_if i2s_i;

    // [[distribute]]
    par{
        {
            out port * movable ppo = p_dout;
            out buffered port:32 * p_dout_recon = reconfigure_port(move(ppo), out buffered port:32);
            in port * movable ppi = p_din;
            in buffered port:32 * p_din_recon = reconfigure_port(move(ppi), in buffered port:32);
            out port * movable ppb = &p_bclk;
            out port * p_bclk_recon = reconfigure_port(move(ppb), out port);
            out port * movable ppl = &p_lrclk;
            out buffered port:32 * p_lrclk_recon = reconfigure_port(move(ppl), out buffered port:32);
            i2s_frame_master(i2s_i,
                p_dout_recon,
                1,//num_out,
                p_din_recon,
                1,//num_in,
                *p_bclk_recon,
                *p_lrclk_recon,
                p_mclk,
                bclk);
        }
        callback_handler(i2s_i);
    }
}