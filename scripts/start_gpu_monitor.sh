#!/bin/bash

#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#  

#TITLE          : start_gpu_monitoring.sh
#DESCRIPTION    : Continuosly monitors and log the operating frequency, utilization %, and power consumption of an NVIDIA GPU.
#AUTHOR		 	: Carlos Diaz <cdiazavr@gmail.com>
#DATE           : 20240503
#VERSION        : 0.0.1    
#USAGE          : bash run_md_simulation.sh [-p path]
#NOTES          : This is not a standalone application, but only an automatized series of steps that are part of academic research.
#BASH VERSION   : 5.2.21(1)-release


# $1 shall be the number of the replicate being run

# PROPERLY HANDLE TERMINATION SIGNAL:
	handle_sigterm() {
	  exit 0
	}
	trap 'handle_sigterm' TERM


# CREATE FILES FOR LOGGING CPU FREQUENCY, UTILIZATION, AND POWER CONSUMPTION:
	if [ ! -f benchmark_gpu.tsv ]; then
		echo -e "Replicate\tDate_time\tParameter\tMeassure\tMeassure_unit" > benchmark_gpu.tsv
	fi


# Loop and log until this process is terminated from the parent script:
	while true; do
		date_time=$(date "+%Y-%m-%d %H:%M:%S.%3N")

		# Isolate the frequencies, utilization and power in different variables:
		frequency=$(nvidia-smi -q -d CLOCK | grep -m1 "Graphics" | awk '{print $(NF-1)}')
		utilization=$(nvidia-smi -q -d UTILIZATION | grep -m1 "Gpu" | awk '{print $(NF-1)}')
		power=$(nvidia-smi -q -d POWER | grep -m1 "Power Draw" | awk '{print $(NF-1)}')

		# Write to the logs:
		echo -e "$1\t$date_time\tfrequency\t$frequency\tMHz" >> benchmark_gpu.tsv
		echo -e "$1\t$date_time\tutilization\t$utilization\tpercent" >> benchmark_gpu.tsv
		echo -e "$1\t$date_time\tpackage_power\t$power\tW" >> benchmark_gpu.tsv

		sleep 0.05
	done
 
