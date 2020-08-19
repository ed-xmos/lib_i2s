// Copyright (c) 2020, XMOS Ltd, All rights reserved
#ifndef _i2s_xcore_ai_h_
#define _i2s_xcore_ai_h_
#include <xs1.h>
#include <stdint.h>
#include <stddef.h>
#define port_t unsigned
#define xclock_t unsigned

#ifndef __XC__
/** I2S mode.
 *
 *  This type is used to describe the I2S mode.
 */
typedef enum i2s_mode_t {
    I2S_MODE_I2S,            ///< The LR clock transitions ahead of the data by one bit clock.
    I2S_MODE_LEFT_JUSTIFIED, ///< The LR clock and data are phase aligned.
} i2s_mode_t;

/** I2S slave bit clock polarity.
 *
 *  Standard I2S is positive, that is toggle data and LR clock on falling
 *  edge of bit clock and sample them on rising edge of bit clock. Some
 *  masters have it the other way around.
 */
typedef enum i2s_slave_bclk_polarity_t {
    I2S_SLAVE_SAMPLE_ON_BCLK_RISING,   ///<< Toggle falling, sample rising (default if not set)
    I2S_SLAVE_SAMPLE_ON_BCLK_FALLING,  ///<< Toggle rising, sample falling
} i2s_slave_bclk_polarity_t;

/** I2S configuration structure.
 *
 *  This structure describes the configuration of an I2S bus.
 */
typedef struct i2s_config_t {
  unsigned mclk_bclk_ratio; ///< The ratio between the master clock and bit clock signals.
  i2s_mode_t mode;          ///< The mode of the LR clock.
  i2s_slave_bclk_polarity_t slave_bclk_polarity;  ///< Slave bit clock polarity.
} i2s_config_t;

/** Restart command type.
 *
 *  Restart commands that can be signalled to the I2S or TDM component.
 */
typedef enum i2s_restart_t {
  I2S_NO_RESTART = 0,      ///< Do not restart.
  I2S_RESTART,             ///< Restart the bus (causes the I2S/TDM to stop and a new init callback to occur allowing reconfiguration of the BUS).
  I2S_SHUTDOWN             ///< Shutdown. This will cause the I2S/TDM component to exit.
} i2s_restart_t;

#endif

/**  I2S frame-based initialization event callback.
*
*   The I2S component will call this
*   when it first initializes on first run of after a restart.
*
*   \param i2s_config        This structure is provided if the connected
*                            component drives an I2S bus. The members
*                            of the structure should be set to the
*                            required configuration.
*/
void i2s_master_init(i2s_config_t *i2s_config);

/**  I2S frame-based restart check callback.
*
*   This callback is called once per frame. The application must return the
*   required restart behaviour.
*
*   \return          The return value should be set to
*                    ``I2S_NO_RESTART``, ``I2S_RESTART`` or
*                    ``I2S_SHUTDOWN``.
*/
i2s_restart_t i2s_master_restart_check();

/**  Receive an incoming frame of samples.
*
*   This callback will be called when a new frame of samples is read in by the I2S
*   frame-based component.
*
*  \param num_in     The number of input channels contained within the array.
*  \param samples    The samples data array as signed 32-bit values.  The component
*                    may not have 32-bits of accuracy (for example, many
*                    I2S codecs are 24-bit), in which case the bottom bits
*                    will be arbitrary values.
*/
void i2s_master_receive(size_t num_in, int32_t samples[num_in]);

/** Request an outgoing frame of samples.
*
*  This callback will be called when the I2S frame-based component needs
*  a new frame of samples.
*
*  \param num_out    The number of output channels contained within the array.
*  \param samples    The samples data array as signed 32-bit values.  The component
*                    may not have 32-bits of accuracy (for example, many
*                    I2S codecs are 24-bit), in which case the bottom bits
*                    will be arbitrary values.
*/
void i2s_master_send(size_t num_out, int32_t samples[num_out]);

#ifndef __XC__
/** I2S frame-based master component
 *
 *  This task performs I2S on the provided pins. It will perform callbacks over
 *  the i2s_frame_callback_if interface to get/receive frames of data from the
 *  application using this component.
 *
 *  The component performs I2S master so will drive the word clock and
 *  bit clock lines.
 *
 *  This is a more efficient version of i2s master which reduces callback
 *  frequency and allows useful processing to be done in distributable i2s handler tasks.
 *  It also uses xCORE200 specific features to remove the need for software
 *  BCLK generation which decreases processor overhead.
 *
 *  \param p_dout         An array of data output ports
 *  \param num_out        The number of output data ports
 *  \param p_din          An array of data input ports
 *  \param num_in         The number of input data ports
 *  \param p_bclk         The bit clock output port
 *  \param p_lrclk        The word clock output port
 *  \param p_mclk         Input port which supplies the master clock
 *  \param bclk           A clock that will get configured for use with
 *                        the bit clock
 */
void i2s_master_ai(
                port_t p_dout[],
                const size_t num_out,
                port_t p_din[],
                const size_t num_in,
                port_t p_bclk,
                port_t p_lrclk,
                port_t p_mclk,
                xclock_t bclk);



/** I2S slave component.
 *
 *  This task performs I2S on the provided pins. It will perform callbacks over
 *  the i2s_callback_if interface to get/receive data from the application
 *  using this component.
 *
 *  The component performs I2S slave so will expect the word clock and
 *  bit clock to be driven externally.
 *

 *  \param p_dout         An array of data output ports
 *  \param num_out        The number of output data ports
 *  \param p_din          An array of data input ports
 *  \param num_in         The number of input data ports
 *  \param p_bclk         The bit clock input port
 *  \param p_lrclk        The word clock input port
 *  \param bclk           A clock that will get configured for use with
 *                        the bit clock
 */
void i2s_slave_ai(
        port_t p_dout [],
        const size_t num_out,
        port_t p_din [],
        const size_t num_in,
        port_t p_bclk,
        port_t p_lrclk,
        xclock_t bclk);
#endif


#endif // _i2s_xcore_ai_h_
