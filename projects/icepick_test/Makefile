# Project config
PROJ = icepick_test

PROJ_DEPS := misc
PROJ_RTL_SRCS := $(addprefix rtl/, \
	sense.v \
)
PROJ_TOP_SRC := rtl/top.v
PROJ_TOP_MOD := top

# Target config
BOARD ?= icepick
DEVICE = up5k
PACKAGE = sg48

NEXTPNR_ARGS = --freq 48 --no-promote-globals

# Include default rules
include ../../build/project-rules.mk
