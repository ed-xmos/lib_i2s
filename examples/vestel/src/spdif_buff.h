#ifndef _SPDIF_MGR_H_
#define _SPDIF_MGR_H_

//Interface to SPDIF ASRC worker thread
typedef interface spdif_asrc_engine_if{
  void push_input_block(int input_block[], unsigned input_block_size);
} spdif_asrc_engine_if;


void spdif_rx_buffer(streaming chanend c_spdif, streaming chanend c_spdif_rx);

#endif