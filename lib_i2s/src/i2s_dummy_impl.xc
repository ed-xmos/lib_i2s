// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <i2s.h>

#undef i2s_master
void i2s_master(client i2s_callback_if i2s_i,
                out buffered port:32 (&?p_dout)[num_out],
                static const size_t num_out,
                in buffered port:32 (&?p_din)[num_in],
                static const size_t num_in,
                out buffered port:32 p_bclk,
                out buffered port:32 p_lrclk,
                in port p_mclk,
                clock bclk,
                const clock mclk)
{}
