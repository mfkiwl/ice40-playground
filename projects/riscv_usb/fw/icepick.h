/*
 * icepick.h
 *
 * Copyright (C) 2019 Sylvain Munaut
 * All rights reserved.
 *
 * LGPL v3+, see LICENSE.lgpl3
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

#pragma once


enum icepick_sense_chan {
	SC_GND = 0,
	SC_B3,
	SC_VIO,
	SC_VSENSE,
	SC_A0,
	SC_A1,
	SC_A2,
	SC_B2,
	SC_3V3,
	SC_B0,
	SC_B1,
	SC_A3,
	SC_A4,
	SC_A5,
	SC_1V2,
	SC_OPEN,
};

const enum icepick_sense_chan icepick_io_sense_chan[10];


void icepick_set_vio(uint16_t pdm);

void icepick_test_clk(void);
void icepick_test_sense(void);
void icepick_test_io(void);


