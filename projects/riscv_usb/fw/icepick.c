/*
 * icepick.c
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

#include <stdint.h>
#include <string.h>

#include "icepick.h"

#include "console.h"
#include "usb.h"


struct misc {
	uint32_t boot;
	uint32_t vio_pdm;
} __attribute__((packed,aligned(4)));


struct calib {
	struct {
		uint32_t data;
		uint32_t oe;
		uint32_t pull_dir;
		uint32_t pull_ena;
	} io;
	struct {
		uint32_t csr;
		uint32_t _rsvd;
		uint32_t chg;
		uint32_t dis;
	} sense;
	struct {
		uint32_t xo;
		uint32_t hf;
		uint32_t lf;
		uint32_t hf_trim;
	} clk;
} __attribute__((packed,aligned(4)));


static volatile struct misc  * const misc_regs  = (void*)0x80000000;
static volatile struct calib * const calib_regs = (void*)0x81000000;


/* Fixed point math helpers */
/* ------------------------ */

/* on 32-bit architectures, there is often an instruction/intrinsic for this */
static int32_t
mulhi(int32_t a, int32_t b)
{
	return (int32_t)(((int64_t)a * (int64_t)b) >> 32);
}

/* compute exp2(a) in s5.26 fixed-point arithmetic */
static int32_t
fp_exp2(int32_t a)
{
	int32_t i, f, r, s;
	/* split a = i + f, such that f in [-0.5, 0.5] */
	i = (a + 0x2000000) & ~0x3ffffff; // 0.5
	f = a - i;
	s = ((5 << 26) - i) >> 26;
	f = f << 5; /* scale up for maximum accuracy in intermediate computation */
	/* approximate exp2(f)-1 for f in [-0.5, 0.5] */
	r =                (int32_t)(1.53303146e-4 * (1LL << 36) + 996);
	r = mulhi (r, f) + (int32_t)(1.33887795e-3 * (1LL << 35) +  99);
	r = mulhi (r, f) + (int32_t)(9.61833261e-3 * (1LL << 34) + 121);
	r = mulhi (r, f) + (int32_t)(5.55036329e-2 * (1LL << 33) +  51);
	r = mulhi (r, f) + (int32_t)(2.40226507e-1 * (1LL << 32) +   8);
	r = mulhi (r, f) + (int32_t)(6.93147182e-1 * (1LL << 31) +   5);
	r = mulhi (r, f);
	/* add 1, scale based on integral portion of argument, round the result */
	r = ((((uint32_t)r * 2) + (uint32_t)(1.0*(1LL << 31)) + ((1U << s) / 2) + 1) >> s);
	/* when argument < -26.5, result underflows to zero */
	if (a < -0x6a000000) r = 0;
	return r;
}


int32_t conv(int32_t v)
{
	v *= 4034;	/* 1.4426950408889634 / K */
	v = fp_exp2(-v);
	v = (1 << 26) - v;
	v >>= 13;
	v *= 6600;
	v >>= 13;
	return v;
}


const enum icepick_sense_chan icepick_io_sense_chan[10] = {
	SC_A0, SC_A1, SC_A2, SC_A3, SC_A4, SC_A5,
	SC_B0, SC_B1, SC_B2, SC_B3,
};



void
icepick_set_vio(uint16_t pdm)
{
	misc_regs->vio_pdm = (1 << 31) | pdm;
}


void
icepick_test_clk(void)
{
	printf("XO %08x\n", calib_regs->clk.xo);
	printf("HF %08x\n", calib_regs->clk.hf);
	printf("LF %08x\n", calib_regs->clk.lf);

	calib_regs->clk.xo = 0x80989680;
	calib_regs->clk.hf = 0x80989680;
	calib_regs->clk.lf = 0x80989680;
}

static void delay()
{
	for (int j=0; j<10; j++)
		calib_regs->sense._rsvd;
}

#if 0
static void
int32_t estimate_Us_Zs(
	int32_t vm, uint32_t vm_pd, uint32_t vm_pu,
	int32_t *Us, int32_t *Zs)
{


}
#endif

static int32_t
sense(enum icepick_sense_chan chan, uint32_t *chg, uint32_t *dis)
{
	calib_regs->sense.csr = (1 << 31) | chan;

	while (!(calib_regs->sense.csr & (1 << 30)));

	*chg = calib_regs->sense.chg & 0x7fffffff;
	*dis = calib_regs->sense.dis & 0x7fffffff;

	return conv(*chg);
}

void
icepick_test_sense(void)
{
	uint32_t chg, dis, v;

#if 0
	for (int i=0; i<20; i++) {
		v = sense(SC_1V2, &chg, &dis);
		printf("1v2: %d | %d %d\n", v, chg, dis);
	}
#endif

#if 1
	sense(SC_GND, &chg, &dis);
	printf("GND: %d %d\n", chg, dis);

	v = sense(SC_1V2, &chg, &dis);
	printf("1v2: %d | %d %d\n", v, chg, dis);

	v = sense(SC_3V3, &chg, &dis);
	printf("3v3: %d | %d %d\n", v, chg, dis);

	v = sense(SC_VIO, &chg, &dis);
	printf("Vio: %d | %d %d\n", v, chg, dis);

	v = sense(SC_VSENSE, &chg, &dis);
	v = (v * 70451) >> 16;	// Compensate for 1k5 imput impedance
	printf("Vsense: %d | %d %d\n", v, chg, dis);
#endif

#if 1
	// Raw reading
	v = sense(SC_A0, &chg, &dis);
	printf("A0: %d | %d %d\n", v, chg, dis);

	// Pulled up
	calib_regs->io.pull_dir = 0x001;
	calib_regs->io.pull_ena = 0x001;

	v = sense(SC_A0, &chg, &dis);
	printf("A0: %d | %d %d\n", v, chg, dis);

	// Pulled down
	calib_regs->io.pull_dir = 0x000;

	v = sense(SC_A0, &chg, &dis);
	printf("A0: %d | %d %d\n", v, chg, dis);

	// Raw reading
	calib_regs->io.pull_ena = 0x000;

	v = sense(SC_A0, &chg, &dis);
	printf("A0: %d | %d %d\n", v, chg, dis);
#endif
}

void
icepick_test_io(void)
{
	uint32_t m, x;

	#define CHECK_VAL(s, v) \
		do { \
			x = calib_regs->io.data; \
			if (x != (v)) { \
				printf("[!] IO[%d] - %03x - Err %s\n", i, x, s); \
				continue; \
			} \
		} while (0)

	for (int i=0; i<10; i++) {
		/* Mask */
		m = 1 << i;

		/* Reset state */
		calib_regs->io.data = 0x000;
		calib_regs->io.oe   = 0x000;
		calib_regs->io.pull_dir = 0x000;
		calib_regs->io.pull_ena = 0x000;

		/* Discharge */
		calib_regs->io.data = 0x000;
		calib_regs->io.oe   = 0x3ff;
		calib_regs->io.oe   = 0x000;

		/* Check value */
		CHECK_VAL("Discharge", 0);

		/* Drive high */
		calib_regs->io.data = m;
		calib_regs->io.oe  = m;
		CHECK_VAL("Drive high", m);

		/* Drive low */
		calib_regs->io.data = 0;
		CHECK_VAL("Drive low", 0);

		/* Disable drive */
		calib_regs->io.oe  = 0;

		/* Pull high */
		calib_regs->io.pull_dir = m;
		calib_regs->io.pull_ena = m;
		delay();
		CHECK_VAL("Pull high", m);

		/* Pull low */
		calib_regs->io.pull_dir = 0;
		delay();
		CHECK_VAL("Pull low", 0);
	}
}


/* USB vendor protocol */
/* ------------------- */

#define USB_RT_ICEPICK_SET_VIO		((0 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV))
#define USB_RT_ICEPICK_SET_HFTRIM	((1 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV))

#define USB_RT_ICEPICK_SENSE_START	((2 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV))
#define USB_RT_ICEPICK_SENSE_RESULT	((2 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV | USB_REQ_READ))
#define USB_RT_ICEPICK_CLK_START	((3 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV))
#define USB_RT_ICEPICK_CLK_RESULT	((3 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV | USB_REQ_READ))

#define USB_RT_ICEPICK_GPIO_DATA_IN	((4 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV | USB_REQ_READ))
#define USB_RT_ICEPICK_GPIO_DATA_OUT	((4 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV))
#define USB_RT_ICEPICK_GPIO_DATA_ENA	((5 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV))
#define USB_RT_ICEPICK_GPIO_PULL_OUT	((6 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV))
#define USB_RT_ICEPICK_GPIO_PULL_ENA	((7 << 8) | (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV))


static struct {
	uint16_t chan_mask;

	int c;
	int n_done;
	int n_tot;

	struct {
		uint32_t chg;
		uint32_t dis;
	} meas[128];
} g_state;


static void
_icepick_meas_start(uint16_t chan_mask, int count)
{
	int i;

	/* Reset */
	g_state.chan_mask = chan_mask;
	g_state.c = 0;
	g_state.n_done = 0;
	g_state.n_tot  = 0;

	/* Set the total number of measurements */
	for (i=0; i<16; i++)
		if (chan_mask & (1 << i))
			g_state.n_tot += count;
	
	/* Start first measurement */
	for (i=0; i<16; i++)
		if (chan_mask & (1 << i)) {
			calib_regs->sense.csr = (1 << 31) | i;
			g_state.c = i;
			break;
		}
}

static void
_icepick_sof(void)
{
	int i;

	/* Anything to do ? */
	if (g_state.n_done >= g_state.n_tot)
		return;

	/* Is current measurement done ? */
	if (!(calib_regs->sense.csr & (1 << 30)))
		return;

	/* Save values */
	g_state.meas[g_state.n_done].chg = calib_regs->sense.chg & 0x7fffffff;
	g_state.meas[g_state.n_done].dis = calib_regs->sense.dis & 0x7fffffff;
	g_state.n_done++;

	/* Next measurement */
	for (i=0; i<16; i++) {
		g_state.c = (g_state.c + 1) & 15;
		if (g_state.chan_mask & (1 << g_state.c)) {
			calib_regs->sense.csr = (1 << 31) | g_state.c;
			break;
		}
	}
}

static enum usb_fnd_resp
_icepick_ctrl_req(struct usb_ctrl_req *req, struct usb_xfer *xfer)
{
	uint32_t x;

	/* Only accept vendor device requests */
	if (USB_REQ_TYPE_RCPT(req) != (USB_REQ_TYPE_VENDOR | USB_REQ_RCPT_DEV))
		return USB_FND_CONTINUE;

	/* Handle requests */
	switch (req->wRequestAndType)
	{
	case USB_RT_ICEPICK_SET_VIO:
		icepick_set_vio(req->wValue);
		break;

	case USB_RT_ICEPICK_SET_HFTRIM:
		calib_regs->clk.hf_trim = req->wValue;
		break;

	case USB_RT_ICEPICK_SENSE_START:
		_icepick_meas_start(req->wValue, req->wIndex);
		break;

	case USB_RT_ICEPICK_SENSE_RESULT:
		xfer->data = (void*)&g_state.meas;
		xfer->len = g_state.n_done * 8;
		break;

	case USB_RT_ICEPICK_CLK_START:
		x = (1 << 31) | ((req->wIndex & 0xff) << 16) | req->wValue;
		calib_regs->clk.xo = x;
		calib_regs->clk.hf = x;
		calib_regs->clk.lf = x;
		break;

	case USB_RT_ICEPICK_CLK_RESULT:
		xfer->len = 12;
		x = calib_regs->clk.xo;
		memcpy(&xfer->data[0], &x, 4);
		x = calib_regs->clk.hf;
		memcpy(&xfer->data[4], &x, 4);
		x = calib_regs->clk.lf;
		memcpy(&xfer->data[8], &x, 4);
		break;

	case USB_RT_ICEPICK_GPIO_DATA_IN:
		xfer->len = 2;
		x = calib_regs->io.data;
		memcpy(xfer->data, &x, 2);
		break;

	case USB_RT_ICEPICK_GPIO_DATA_OUT:
		calib_regs->io.data     = req->wValue;
		break;

	case USB_RT_ICEPICK_GPIO_DATA_ENA:
		calib_regs->io.oe       = req->wValue;
		break;

	case USB_RT_ICEPICK_GPIO_PULL_OUT:
		calib_regs->io.pull_dir = req->wValue;
		break;

	case USB_RT_ICEPICK_GPIO_PULL_ENA:
		calib_regs->io.pull_ena = req->wValue;
		break;

	default:
		return USB_FND_ERROR;
	}

	return USB_FND_SUCCESS;
}

static struct usb_fn_drv _icepick_drv = {
	.sof		= _icepick_sof,
	.ctrl_req	= _icepick_ctrl_req,
};

void
icepick_init(void)
{
	usb_register_function_driver(&_icepick_drv);
}
