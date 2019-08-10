#!/usr/bin/env python

import struct
from collections import namedtuple

import usb.core
import usb.util


ClockResults = namedtuple('ClockResults', 'xo hf lf')

class iCEpick(object):

	SENSE_CHANS = {
		'gnd': 0,
		'b3': 1,
		'vio': 2,
		'vsense': 3,
		'a0': 4,
		'a1': 5,
		'a2': 6,
		'b2': 7,
		'3v3': 8,
		'b0': 9,
		'b1': 10, 
		'a3': 11,
		'a4': 12,
		'a5': 13,
		'1v2': 14,
		'open': 15,
	}

	def __init__(self):
		self.dev = usb.core.find(idVendor=0x1d50, idProduct=0x6149)
	
	def serial(self):
		return usb.util.get_string(self.dev, self.dev.iSerialNumber)

	def set_vio(self, vio):
		self.dev.ctrl_transfer(0x40, 0, vio, 0, None)

	def set_hftrim(self, trim):
		self.dev.ctrl_transfer(0x40, 1, trim, 0, None)

	def sense_start(self, chans, count=1):
		self._sense_chans = sorted(list(set(chans)))
		self._sense_count = count
		cm = sum([(1 << c) for c in chans])
		self.dev.ctrl_transfer(0x40, 2, cm, count, None)

	def sense_results(self):
		data = self.dev.ctrl_transfer(0xc0, 2, 0, 0, 1024)
		rv = {}
		i = 0
		l = len(self._sense_chans)
		while i < (len(data) // 8):
			r = struct.unpack('<II', data[8*i:8*i+8])
			c = self._sense_chans[i%l]
			rv.setdefault(c, []).append(r)
			i = i + 1
		return rv
	
	def clock_start(self, duration):
		dh = (duration >> 16) & 0xff
		dl = duration & 0xffff
		self.dev.ctrl_transfer(0x40, 3, dl, dh, None)
	
	def clock_results(self):
		data = self.dev.ctrl_transfer(0xc0, 3, 0, 0, 12)
		v = struct.unpack('<III', data)
		if (v[0] & v[1] & v[2] & (1 << 31)) == 0:
			return None
		return ClockResults(
			v[0] & 0x7fffffff,
			v[1] & 0x7fffffff,
			v[2] & 0x7fffffff,
		)

	def gpio_data_in(self):
		data = self.dev.ctrl_transfer(0xc0, 4, 0, 0, 2)
		return struct.unpack('<H', data)[0]

	def gpio_data_out(self, data):
		self.dev.ctrl_transfer(0x40, 4, data, 0, None)
	
	def gpio_data_ena(self, data):
		self.dev.ctrl_transfer(0x40, 5, data, 0, None)

	def gpio_pull_out(self, data):
		self.dev.ctrl_transfer(0x40, 6, data, 0, None)
	
	def gpio_pull_ena(self, data):
		self.dev.ctrl_transfer(0x40, 7, data, 0, None)


import time
import socket
import json

def scan_vio(ip):
	Vs = 3300
	s  = 3300 / 0x1000

	rv = []

	for i in range(1200,3350,50):
		# Set Vio
		x = min(0xfff, int(i / s))
		ip.set_vio(x)

		# Wait a bit
		time.sleep(0.1)

		# Sense
		ip.sense_start([2], 20)

		# Wait for results
		r = None
		while (r is None) or (2 not in r) or (len(r[2]) < 20):
			r = ip.sense_results()

		# Average result for chg / discharge
		chg = int(sum([x[0] for x in r[2]]) / len(r))
		dis = int(sum([x[1] for x in r[2]]) / len(r))

		# Append results
		rv.append( (i, chg, dis) )
	
	return rv


def scan_trim(ip):
	clk = []
	for i in range(1024):
		print(i)
		ip.set_hftrim(i)
		ip.clock_start(1000000)

		r = None
		while r is None:
			r = ip.clock_results()

		clk.append(r.hf * 10)

	return clk

def do_trim_calib(path='/home/tnt/projects/elec/icepick/calib/'):
	ip = iCEpick()
	rv = scan_trim(ip)
	
	with open(path + ip.serial() + '-trim.json', 'w') as fh:
		fh.write(json.dumps(rv))

	del ip

def do_clock_calib(path='/home/tnt/projects/elec/icepick/calib/'):
	ip = iCEpick()
	rv = {}

	for i in range(10):
		# Start measurement
		ip.clock_start(10000000)

		# Get results
		r = None
		while r is None:
			r = ip.clock_results()

		# Collect them
		rv.setdefault('xo', []).append(r.xo)
		rv.setdefault('hf', []).append(r.hf)
		rv.setdefault('lf', []).append(r.lf)
		print(rv)
	
	with open(path + ip.serial() + '-clock.json', 'w') as fh:
		fh.write(json.dumps(rv))
	
	del ip
	


def scan_sense(ip):
	# Connect to DP832
	s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
	s.connect( ('dp832', 5555) )

	# Scan voltage range
	rv = {}

	v = 0
	while v <= 3.4:
		# Set DP832 output voltage
		s.send(b':SOUR3:VOLT %.3f\r\n' % v)

		# Wait a bit
		time.sleep(0.250)

		# Collect 20 measurements on Vsense and A0
		ip.sense_start([3,4], 20)

		r = None
		while (r is None) or (4 not in r) or (len(r[4]) < 20):
			r = ip.sense_results()

		# Save result
		rv[v] = r

		# 50 mV increment
		v += 0.050

	return rv


def do_sense_calib(path='/home/tnt/projects/elec/icepick/calib/'):
	ip = iCEpick()
	rv = scan_sense(ip)
	
	with open(path + ip.serial() + '-sense.json', 'w') as fh:
		fh.write(json.dumps(rv))

	del ip
