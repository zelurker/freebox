#!/bin/sh

if [ -f list_coords ] || [ -f numero_coords ]; then
	echo zap1 |socat stdio unix:./sock_list
elif [ -f info_coords ]; then
	echo zap1 | socat stdio unix:sock_info
fi
