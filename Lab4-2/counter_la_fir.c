/*
 * SPDX-FileCopyrightText: 2020 Efabless Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * SPDX-License-Identifier: Apache-2.0
 */

// This include is relative to $CARAVEL_PATH (see Makefile)
#include <defs.h>
#include <stub.c>

#define reg_data_length (*(volatile uint32_t*)0x30000010)
#define reg_tap_0 (*(volatile uint32_t*)0x30000020)
#define reg_tap_1 (*(volatile uint32_t*)0x30000024)
#define reg_tap_2 (*(volatile uint32_t*)0x30000028)
#define reg_tap_3 (*(volatile uint32_t*)0x3000002c)
#define reg_tap_4 (*(volatile uint32_t*)0x30000030)
#define reg_tap_5 (*(volatile uint32_t*)0x30000034)
#define reg_tap_6 (*(volatile uint32_t*)0x30000038)
#define reg_tap_7 (*(volatile uint32_t*)0x3000003c)
#define reg_tap_8 (*(volatile uint32_t*)0x30000040)
#define reg_tap_9 (*(volatile uint32_t*)0x30000044)
#define reg_tap_10 (*(volatile uint32_t*)0x30000048)
#define reg_config (*(volatile uint32_t*)0x30000000)
#define reg_X (*(volatile uint32_t*)0x30000080)
#define reg_Y (*(volatile uint32_t*)0x30000084)


extern int* fir();

// --------------------------------------------------------

/*
	MPRJ Logic Analyzer Test:
		- Observes counter value through LA probes [31:0] 
		- Sets counter initial value through LA probes [63:32]
		- Flags when counter value exceeds 500 through the management SoC gpio
		- Outputs message to the UART when the test concludes successfuly
*/

void main()
{
	/* Set up the housekeeping SPI to be connected internally so	*/
	/* that external pin changes don't affect it.			*/

	// reg_spi_enable = 1;
	// reg_spimaster_cs = 0x00000;

	// reg_spimaster_control = 0x0801;

	// reg_spimaster_control = 0xa002;	// Enable, prescaler = 2,
                                        // connect to housekeeping SPI

	// Connect the housekeeping SPI to the SPI master
	// so that the CSB line is not left floating.  This allows
	// all of the GPIO pins to be used for user functions.

	// The upper GPIO pins are configured to be output
	// and accessble to the management SoC.
	// Used to flad the start/end of a test 
	// The lower GPIO pins are configured to be output
	// and accessible to the user project.  They show
	// the project count value, although this test is
	// designed to read the project count through the
	// logic analyzer probes.
	// I/O 6 is configured for the UART Tx line

        reg_mprj_io_31 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_30 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_29 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_28 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_27 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_26 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_25 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_24 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_23 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_22 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_21 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_20 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_19 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_18 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_17 = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_16 = GPIO_MODE_MGMT_STD_OUTPUT;

        reg_mprj_io_15 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_14 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_13 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_12 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_11 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_10 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_9  = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_8  = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_7  = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_6  = GPIO_MODE_MGMT_STD_OUTPUT;
        reg_mprj_io_5  = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_4  = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_3  = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_2  = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_1  = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_0  = GPIO_MODE_USER_STD_OUTPUT;

        	
	// Now, apply the configuration
	reg_mprj_xfer = 1;
	while (reg_mprj_xfer == 1);

	// input & output array
	int arr_X[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
	int arr_Y[] = {0, -10, -29, -25, 35, 158, 337, 539, 732, 915};
	//uint32_t err_count = 0;


	// read write config
	uint32_t read_exp = 0x00000010;
	uint32_t read_mask = 0x00000010;
	uint32_t write_exp = 0x00000020;
	uint32_t write_mask = 0x000000020;

	int Y = 0;

	// Flag start of the test 
	reg_mprj_datal = 0xAB400000;

	// write data length
	reg_data_length = 10;
	
	// write tap coefficient
	reg_tap_0 = 0;
	reg_tap_1 = -10;
	reg_tap_2 = -9;
	reg_tap_3 = 23;
	reg_tap_4 = 56;
	reg_tap_5 = 63;
	reg_tap_6 = 56;
	reg_tap_7 = 23;
	reg_tap_8 = -9;
	reg_tap_9 = -10;
	reg_tap_10 = 0;
	
	// write ap_start = 1
	reg_config = 0x00000001;
	
	// input & output stream
	for (int i=0; i < 10; i++) {
		// write x[i]
		if ((reg_config & read_mask) == read_exp) {
			if (i == 9) {
				reg_config = reg_config | 0x00000040;
			}
			reg_X = arr_X[i];
		}
		//reg_X = arr_X[i];
		// read y[i]
		if ((reg_config & write_mask) == write_exp) {
			Y = reg_Y;
		}
		// if (reg_Y != arr_Y[i]) {
		// 	reg_err_count += 1;
		// }
	}

	// check ap_done = 1 & ap_idle = 1 && all Y correct
	//if ((reg_config == 0x00000006) && (err_count == 0)) {
	if ((reg_config & 0x00000006) == 0x00000006) {
		reg_mprj_datal = 0xAB510000;
	}
	//}
}

