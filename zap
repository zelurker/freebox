#!/bin/sh

if [ -f list_coords ] || [ -f numero_coords ]; then
	echo zap1 |socat stdio unix:/home/manu/free/sock_list
elif [ -f info_coords ]; then
	echo zap1 | socat stdio sock_info
fi
