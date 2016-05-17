// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <xclib.h>
#include "i2s.h"
#include "xassert.h"
#include "debug_print.h"
#include <print.h>



static void i2s_init_ports(
        out buffered port:32 (&?p_dout)[num_out],
        static const size_t num_out,
        in buffered port:32 (&?p_din)[num_in],
        static const size_t num_in,
        out buffered port:32 p_bclk,
        out buffered port:32 p_lrclk,
        clock bclk,
        in port p_mclk,
        const clock mclk,
        unsigned mclk_bclk_ratio){

    set_clock_on(bclk);
#if USE_HW_DIVIDER
#if SIM
    configure_clock_ref(bclk, mclk_bclk_ratio << 1);
#else
    configure_clock_src_divide(bclk, p_mclk, mclk_bclk_ratio >> 1);
#endif
    configure_port_clock_output(p_bclk, bclk);
#else
    configure_clock_src(bclk, p_bclk);
    configure_out_port(p_bclk, mclk, 1);
#endif
    configure_out_port(p_lrclk, bclk, 1);
    for (size_t i = 0; i < num_out; i++)
        configure_out_port(p_dout[i], bclk, 0);
    for (size_t i = 0; i < num_in; i++)
        configure_in_port(p_din[i], bclk);
#if !USE_HW_DIVIDER
    start_clock(bclk);
#endif
}

#define FRAME_WORDS 2

static void inline i2s_output_clock_pair(out buffered port:32 p_bclk,unsigned clk_mask){
#if !USE_HW_DIVIDER
    p_bclk <: clk_mask;
    p_bclk <: clk_mask;
#endif
}


#pragma unsafe arrays
static i2s_restart_t i2s_ratio_n(client i2s_callback_if i2s_i,
        out buffered port:32 (&?p_dout)[num_out],
        static const size_t num_out,
        in buffered port:32 (&?p_din)[num_in],
        static const size_t num_in,
        out buffered port:32 p_bclk,
        clock bclk,
        out buffered port:32 p_lrclk,
        unsigned ratio,
        i2s_mode_t mode){

    int32_t in_samps[8]; //Temp hack. should be num_in << 1 but compiler thinks that isn't const
    int32_t out_samps[8];

    unsigned lr_mask = 0;

    for(size_t i=0;i<num_out;i++)
        clearbuf(p_dout[i]);
    for(size_t i=0;i<num_in;i++)
        clearbuf(p_din[i]);
    clearbuf(p_lrclk);


    //Preload word 0 - send zeros for first half frame
    i2s_i.send(num_out << 1, out_samps);
    for(size_t i=0;i<num_out;i++)
        p_dout[i] @ 2 <: 0;
    partout(p_lrclk, 1, 0);
    for(size_t i=0;i<num_in;i++)
        asm("setpt res[%0], %1"::"r"(p_din[i]), "r"(0 + 1));

    lr_mask = 0x80000000;

    //Start BCLK going
    start_clock(bclk);
    p_lrclk <: lr_mask;


    //body of main loop
    while(1){

        //Main loop
        size_t idx;

        lr_mask = ~lr_mask;
        p_lrclk <: lr_mask;

        //Input i2s evens
        idx = 0;
#pragma loop unroll
        for(size_t i=0;i<num_in;i++){
            int32_t data;
            asm volatile("in %0, res[%1]":"=r"(data):"r"(p_din[i]):"memory");
            in_samps[idx] = bitrev(data);
            idx+=2;
        }


        //output i2s evens
        idx = 0;
#pragma loop unroll
        for(size_t i=0;i<num_out;i++){
            p_dout[i] <: bitrev(out_samps[idx]);
            idx+=2;
        }


        //This will block and from here on I/O will spill into next frame
        lr_mask = ~lr_mask;
        p_lrclk <: lr_mask;

        //Input i2s odds
        idx = 1;
#pragma loop unroll
        for(size_t i=0;i<num_in;i++){
            int32_t data;
            asm volatile("in %0, res[%1]":"=r"(data):"r"(p_din[i]):"memory");
            in_samps[idx] = bitrev(data);
            idx+=2;
        }

        //output i2s odds
        idx = 1;
#pragma loop unroll
        for(size_t i=0;i<num_out;i++){
            p_dout[i] <: bitrev(out_samps[idx]);
            idx+=2;
        }


        //transfer output samps
        i2s_i.send(num_out << 1, out_samps);

        //transfer input samps
        i2s_i.receive(num_in << 1, in_samps);

        // Check for restart
        i2s_restart_t restart = i2s_i.restart_check();

        if (restart != I2S_NO_RESTART) {
            fail("Not yet implemented");
#if !USE_HW_DIVIDER
            sync(p_bclk);
#endif
            return restart;
        }

    }
    return I2S_RESTART;
}

#define i2s_master i2s_master0

static void i2s_master0(client i2s_callback_if i2s_i,
                out buffered port:32 (&?p_dout)[num_out],
                static const size_t num_out,
                in buffered port:32 (&?p_din)[num_in],
                static const size_t num_in,
                out buffered port:32 p_bclk,
                out buffered port:32 p_lrclk,
                in port p_mclk,
                clock bclk,
                clock mclk){
    while(1){
        debug_printf("config.mclk_bclk_ratio=%d\n",config.mclk_bclk_ratio);

#if !USE_HW_DIVIDER
#if SIM
        configure_clock_ref(mclk, 2); //25Mz
#else
        configure_clock_src(mclk, p_mclk);
#endif
        start_clock(mclk);
#endif

        i2s_config_t config;
        unsigned mclk_bclk_ratio_log2;
        i2s_i.init(config, null);

        if (isnull(p_dout) && isnull(p_din)) {
            fail("Must provide non-null p_dout or p_din");
        }

        mclk_bclk_ratio_log2 = clz(bitrev(config.mclk_bclk_ratio));

        //This ensures that the port time on all the ports is at 0
        i2s_init_ports(p_dout, num_out, p_din, num_in, p_bclk, p_lrclk, bclk,
            p_mclk, mclk, config.mclk_bclk_ratio);

        i2s_restart_t restart =
          i2s_ratio_n(i2s_i, p_dout, num_out, p_din,
                      num_in, p_bclk, bclk, p_lrclk,
                      mclk_bclk_ratio_log2, config.mode);
        if (restart == I2S_SHUTDOWN)
          return;
    }
}



// This function is just to avoid unused static function warnings for i2s_tdm_master0,
// it should never be called.
inline void i2s_master1(client interface i2s_callback_if i,
        out buffered port:32 i2s_dout[num_i2s_out],
        static const size_t num_i2s_out,
        in buffered port:32 i2s_din[num_i2s_in],
        static const size_t num_i2s_in,
        out buffered port:32 i2s_bclk,
        out buffered port:32 i2s_lrclk,
        in port p_mclk,
        clock clk_bclk,
        clock clk_mclk) {
    i2s_master0(i, i2s_dout, num_i2s_out, i2s_din, num_i2s_in,
                i2s_bclk, i2s_lrclk, p_mclk,
                clk_bclk, clk_mclk);
}

