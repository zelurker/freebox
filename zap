#!/bin/sh

if [ -f list_coords ] || [ -f numero_coords ]; then
	echo zap1 > fifo_list
elif [ -f info_coords ]; then
	echo zap1 > fifo_info
fi
