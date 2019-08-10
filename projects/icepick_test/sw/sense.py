#!/usr/bin/env python3


def find_sync(data):
	N = 5*16*3
	ref = [int(round(1.333 * i + 0.2)) for i in  range(48)]
	for i in range(5*16*3):
		sd = [x >> 2 for x in data[i:i+N:5]]
		if sd == ref:
			return i
	return None

def decode_entry(entry):
	chg = (entry[3] << 8) | entry[4]
	dis = ((entry[0] & 3) << 16) | (entry[1] << 8) |  entry[2]
	chan = (entry[0] & 0xf0) >> 4
	pull = (entry[0] & 0x0c) >> 2
	return chan, pull, chg, dis

def decode_all(data):
	return [
		decode_entry(data[i*5:(i+1)*5]) for i in range(len(data) // 5)
	]
	

data = data[find_sync(data):]
dd = [decode_entry(data[i*5:(i+1)*5]) for i in range(750)]


Vs = 3.3
Fsamp = 96e6	# 48 MHz DDR
Csamp = 100e-9	# 100 nF
Rsamp = 5e3		# 5k

K = Fsamp * Csamp * Rsamp

Vchg = lambda t: Vs * (1 - math.exp(-(t / K)))
Vdis = lambda t: Vs * (    math.exp(-(((1 << 18) - t) / K))) if t > 0 else 0


plot(builtins.sum([[Vchg(x[2])*2 for x in dd[3*i::3*16]] for i in range(16)], []))
plot(builtins.sum([[Vdis(x[3])*2 for x in dd[3*i::3*16]] for i in range(16)], []))

def err():
	return sum([
		math.pow(a-b,2) for a,b in zip(
			[average([Vchg(x[2])*2 for x in dd[3*i::3*16]]) for i in range(16)],
			[average([Vdis(x[3])*2 for x in dd[3*i::3*16]]) for i in range(16)]
		)
	])


get_all_chg = lambda n, t=0: [x[2] for x in dd2[3*n+t::3*16]]
get_all_dis = lambda n, t=0: [x[3] for x in dd2[3*n+t::3*16]]

	
# 3v3 chg  32173
#     dis 229942
#	  val  1.641 V

# 1v2 chg   9039
#     dis 180704
#     val  0.601 V


K_c = 47558
e_c = 520

K_d = 49019
e_d = -2050

Vchg = lambda t: Vs * (1 - math.exp(-((t+e_c) / K_c)))
Vdis = lambda t: Vs * (    math.exp(-(((1 << 18) - (t+e_d)) / K_d))) if t > 0 else 0

import time

def read_val():
	fh = open('/dev/ttyUSB0', 'rb')

	while True:
		st = time.time()
		fh.read(100)
		et = time.time()
		if (et - st > 0.1):
			break

	d = [decode_entry(fh.read(5)) for i in range(100)]
	fh.close()
	return (
		average([x[2] for x in d]),
		average([x[3] for x in d]),
	)

calib = []
def record(calib, v):
	calib.append( (v, read_val()) )

