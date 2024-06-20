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

#TITLE          : start_cpu_monitoring.sh
#DESCRIPTION    : Continuosly monitors and log the operating frequency, utilization %, and power consumption of a CPU.
#AUTHOR		 	: Carlos Diaz <cdiazavr@gmail.com>
#DATE           : 20240503
#VERSION        : 0.0.1    
#USAGE          : bash run_md_simulation.sh [-p path]
#NOTES          : This is not a standalone application, but only an automatized series of steps that are part of academic research.
#BASH VERSION   : 5.2.21(1)-release


# MANUALLY WRITE HERE THE SUDO PASS:
su_pass="here"

# $1 shall be the number of the replicate being run

# PROPERLY HANDLE TERMINATION SIGNAL:
	handle_sigterm() {
	  exit 0
	}
	trap 'handle_sigterm' TERM

## CREATE FILES FOR LOGGING CPU FREQUENCY, UTILIZATION, AND POWER CONSUMPTION:
	if [ ! -f benchmark_cpu.tsv ]; then
		echo -e "Replicate\tDate_time\tParameter\tCore\tMeassure\tMeassure_unit" > benchmark_cpu.tsv
	fi


# Loop and log until this process is terminated from the parent script:
	while true; do
	
		# Get date+time and CPU status:
		date_time=$(date "+%Y-%m-%d %H:%M:%S.%3N")
		CPU_status=$(sudo -S s-tui -j <<< "su_pass")

		# Isolate the frequencies, utilization and power in different variables:
		frequencies=($(echo "$CPU_status" | jq -r '.Frequency | .[]'))
		utilizations=($(echo "$CPU_status" | jq -r '.Util | .[]'))
		powers=($(echo "$CPU_status" | jq -r '.Power | .[]'))

		# Write cores' frequencies to benchmark_cpu.tsv:
		current_core=0
		for core_frequency in ${frequencies[@]}; do
			# Skip the first frequency (average of cores):
			if [[ "$current_core" -eq 0 ]]; then 
				((current_core++))
				continue
			fi
			# Write measurement to the log:
			echo -e "$1\t$date_time\tfrequency\t$current_core\t$core_frequency\tMHz" >> benchmark_cpu.tsv
			((current_core++))
		done

		# Write cores' utilization to benchmark_cpu.tsv:
		current_core=0
		for core_utilization in ${utilizations[@]}; do
			# Skip the first frequency (average of cores):
			if [[ "$current_core" -eq 0 ]]; then 
				((current_core++))
				continue
			fi
			# Write measurement to the log:
			echo -e "$1\t$date_time\tutilization\t$current_core\t$core_utilization\tpercent" >> benchmark_cpu.tsv
			((current_core++))
		done

		# Write cores' utilization to benchmark_cpu.tsv:
		power_type=0
		## 0: Package power
		## 1: Cores power
		for power in ${powers[@]}; do
			if [[ "$power_type" -eq 0 ]]; then
				echo -e "$1\t$date_time\tpackage_power\tNA\t$power\tW" >> benchmark_cpu.tsv
				((power_type++))
			else
				echo -e "$1\t$date_time\tcore_power\tNA\t$power\tW" >> benchmark_cpu.tsv
			fi
		done

		sleep 0.05
	done
	 
