#!/usr/bin/env python

import struct

import usb.core
import usb.util


class iCEpick(object):

	def __init__(self):
		self.dev = usb.core.find(idVendor=0x1d50, idProduct=0x6148)

	def serial(self):
		return usb.util.get_string(self.dev, self.dev.iSerialNumber)

	def version(self):
		return self.dev.ctrl_transfer(0xc1, 0, 0, 0, 2)

	def spi_xfer(self, buf):
		l = len(buf)
		self.dev.ctrl_transfer(0x41, 1, 0, 0, buf)
		return self.dev.ctrl_transfer(0xc1, 2, 0, 0, l)

	def read_sr(self):
		sr1 = self.spi_xfer('\x05\x00')[1]
		sr2 = self.spi_xfer('\x35\x00')[1]
		return (sr2 << 8) | sr1

	def write_sr(self, sr):
		self.spi_xfer(struct.pack('<BH', 0x01, sr))

	def write_ena(self):
		self.spi_xfer('\x06')

	def write_ena_volatile(self):
		self.spi_xfer('\x50')

