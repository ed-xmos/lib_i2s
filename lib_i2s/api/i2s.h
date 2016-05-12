// Copyright (c) 2016, XMOS Ltd, All rights reserved
#ifndef _i2s_h_
#define _i2s_h_
#include <xs1.h>
#include <stdint.h>
#include <stddef.h>

/** I2S mode.
 *
 *  This type is used to describe the I2S mode.
 */
typedef enum i2s_mode_t {
    I2S_MODE_I2S,            ///< The LR clock transitions ahead of the data by one bit clock.
    I2S_MODE_LEFT_JUSTIFIED, ///< The LR clock and data are phase aligned.
} i2s_mode_t;

/** I2S configuration structure.
 *
 *  This structure describes the configuration of an I2S bus.
 */
typedef struct i2s_config_t {
  unsigned mclk_bclk_ratio; ///< The ratio between the master clock and bit clock signals.
  i2s_mode_t mode;          ///< The mode of the LR clock.
} i2s_config_t;

/** TDM configuration structure.
 *
 *  This structure describes the configuration of a TDM bus.
 */
typedef struct tdm_config_t {
  int offset;               ///< The number of bits that the FSYNC signal transitions before the data. Must be a value between 0 and 31.
  unsigned sync_len;        ///< The length that the FSYNC signal stays high counted as ticks of the bit clock.
  unsigned channels_per_frame; ///< The number of channels in a TDM frame. This must be a power of 2.
} tdm_config_t;

/** Restart command type.
 *
 *  Restart commands that can be signalled to the I2S or TDM component.
 */
typedef enum i2s_restart_t {
  I2S_NO_RESTART = 0,      ///< Do not restart.
  I2S_RESTART,             ///< Restart the bus (causes the I2S/TDM to stop and a new init callback to occur allowing reconfiguration of the BUS).
  I2S_SHUTDOWN             ///< Shutdown. This will cause the I2S/TDM component to exit.
} i2s_restart_t;

/** Interface representing callback events that can occur during the
 *   operation of the I2S task
 */
typedef interface i2s_callback_if {

  /**  I2S initialization event callback.
   *
   *   The I2S component will call this
   *   when it first initializes on first run of after a restart.
   *
   *   \param i2s_config        This structure is provided if the connected
   *                            component drives an I2S bus. The members
   *                            of the structure should be set to the
   *                            required configuration.
   *   \param tdm_config        This structure is provided if the connected
   *                            component drives an TDM bus. The members
   *                            of the structure should be set to the
   *                            required configuration.
   */
  void init(i2s_config_t &?i2s_config, tdm_config_t &?tdm_config);

  /**  I2S restart check callback.
   *
   *   This callback is called once per frame. The application must return the
   *   required restart behaviour.
   *
   *   \return          The return value should be set to
   *                    ``I2S_NO_RESTART``, ``I2S_RESTART`` or
   *                    ``I2S_SHUTDOWN``..
   */
  i2s_restart_t restart_check();

  /**  Receive an incoming sample.
   *
   *   This callback will be called when a new sample is read in by the I2S
   *   component.
   *
   *   \param index     The index of the sample in the frame.
   *   \param sample    The sample data as a signed 32-bit value. The component
   *                    may not use all 32 bits of the value (for example, many
   *                    I2S codecs are 24-bit), in which case the bottom bits
   *                    are ignored.
   */
  void receive(size_t num_in, int32_t sample[num_in]);

  /** Request an outgoing sample.
   *
   *  This callback will be called when the I2S component needs a new sample.
   *
   *  \param index      The index of the requested sample in the frame.
   *  \returns          The sample data as a signed 32-bit value.  The component
   *                    may not have 32-bits of accuracy (for example, many
   *                    I2S codecs are 24-bit), in which case the bottom bits
   *                    will be arbitrary values.
   */
  void send(size_t num_out, int32_t sample[num_out]);

} i2s_callback_if;

/** I2S master component.
 *
 *  This task performs I2S on the provided pins. It will perform callbacks over
 *  the i2s_callback_if interface to get/receive data from the application
 *  using this component.
 *
 *  The component performs I2S master so will drive the word clock and
 *  bit clock lines.
 *
 *  \param i2s_i          The I2S callback interface to connect to
 *                        the application
 *  \param p_dout         An array of data output ports
 *  \param num_out        The number of output data ports
 *  \param p_din          An array of data input ports
 *  \param num_in         The number of input data ports
 *  \param p_bclk         The bit clock output port
 *  \param p_lrclk        The word clock output port
 *  \param bclk           A clock that will get configured for use with
 *                        the bit clock
 *  \param mclk           The clock connected to the master clock frequency.
 *                        Usually this should be configured to be driven by
 *                        an incoming master system clock.
 */
void i2s_master(client i2s_callback_if i2s_i,
                out buffered port:32 (&?p_dout)[num_out],
                static const size_t num_out,
                in buffered port:32 (&?p_din)[num_in],
                static const size_t num_in,
                out buffered port:32 p_bclk,
                out buffered port:32 p_lrclk,
                in port p_mclk,
                clock bclk,
                clock mclk);


#include <i2s_master_impl.h>

#endif // _i2s_h_
