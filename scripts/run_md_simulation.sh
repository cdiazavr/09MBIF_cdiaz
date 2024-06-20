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

#TITLE          : run_md_simulation.sh
#DESCRIPTION    : Run production MD simulation with GROMACS for a path with prepared system with prepare_protein.sh
#AUTHOR		 	: Carlos Diaz <cdiazavr@gmail.com>
#DATE           : 20240503
#VERSION        : 0.0.1    
#USAGE          : bash run_md_simulation.sh [-r replicates] [-p path]
#NOTES          : This is not a standalone application, but only an automatized series of steps that are part of academic research.
#BASH VERSION   : 5.2.21(1)-release


# USAGE HELP:
	usage() {
	    echo -e "\nUsage: $0 [-r replicates] [-p path]"
	    echo "Options:"
	    echo "  -r replicates        Number of replicates to run per combination of flags."
	    echo -e "  -p path              Path where the 'preparation_files' are located.\n"
	    exit 1
	}


# PARSE FLAGS:
	replicates=""
	main_path=""
	while getopts "r:p:" opt; do
	    case "$opt" in
	        r)
	            replicates="$OPTARG"
	            ;;
	        p)
	            main_path="$OPTARG"
	            main_path="${main_path%/}"
	            ;;
	        \?)
	            usage
	            ;;
            :)
				usage
				;;	
	    esac
	done

	## Handle absence of mandatory argument:
	if [ -z "$replicates" ] || [ -z "$main_path" ]; then
	  echo -e "\nBoth -r and -p flags with arguments are mandatory." >&2
	  usage
	  exit 1
	fi

	## Check if $main_path really exists:
	if [ ! -e "$main_path" ]; then
	    echo "Path does not exist." >&2
	    usage
	    exit 1
	fi
	

	## Create a name for the protein (from its path):
	protein_name=$(basename "$main_path")
		# this is used to label the data in the benckmark files


# HELPER FUNCTION TO GET GROMACS PERFORMANCE FROM LOG FILE:
	process_log_file(){
		line_with_times=$(grep "^ *Time:" mdrun.log)
	    line_with_performance=$(grep "^ *Performance:" mdrun.log)
	    
	    if [ -n "$line_with_times" ] && [ -n "$line_with_performance" ]; then
	        # Remove leading and trailing spaces:
	        line_with_time="${line_with_times##*( )}"
	        line_with_time="${line_with_times%%*( )}"
	        line_with_performance="${line_with_performance##*( )}"
	        line_with_performance="${line_with_performance%%*( )}"
	        # Split the line into three variables:
	        read -r time_cpu time_wall time_cpu_usage_pct <<< $(awk '{print $2, $3, $4}' <<< "$line_with_times")
	        read -r ns_day hours_ns <<< $(awk '{print $2, $3}' <<< "$line_with_performance")
	        # Append to the final benchmark file:
	        echo -e "$protein_name\t$r\t$time_cpu\t$time_wall\t$time_cpu_usage_pct\t$ns_day\t$hours_ns" >> benchmark_mdrun.tsv
	    else
	        echo "Line with time or performance not found in mdrun.log"
	        exit 1
	    fi
	}


# OMIT FILE BACKUP DURING REPLICATED RUNS
	export GMX_MAXBACKUP=-1


# OPTIONS TO PASS TO VARIABLE FLAGS TO BENCHMARK:
	options_variable_flags=('cpu' 'gpu')
	

# GET INTO THE DIRECTORY OF THE PROTEIN AND ITERATIVELY RUN THE SIMULATIONS:
	cd $main_path

	## First run the test of strong/scaling by using an increasing number of cores:
	path="strong_scaling_test"
	eval "mkdir -p \"$path\""
	cd "$path"

	### Create the file to log the performance reported by Gromacs:
	echo -e "Protein_name\tReplicate\tCPU_time_s\tWall_time_s\tCPU_usage_pct\tns/day\thours/ns" > benchmark_mdrun.tsv

	### Actually running the test:
	#### Disable GPU usage (run this test only on CPU):
	export GMX_DISABLE_GPU_DETECTION=1

	for ((cores=1; cores <= 18; cores++)); do
		for ((r = 1; r <= replicates; r++  )); do

			# Launch simulation:
			gmx -quiet mdrun \
			-s ../preparation_files/md.tpr \
			-deffnm md \
			-g mdrun.log \
			-tunepme \
			-ntomp_pme 0 \
			-dd 0 0 0 \
			-ntmpi 1 \
			-pin on \
			-ntomp $cores

			# Process the log created by Gromacs:
			process_log_file

		done
	done

	#### Restore automatic GPU detection:
	unset GMX_DISABLE_GPU_DETECTION


	cd ..


	## Now run the the control, with automatic CPU-GPU balancing:
	path="nb=auto pme=auto pmefft=auto bonded=auto update=auto"
	eval "mkdir -p \"$path\""
	cd "$path"

	### Create the file to log the performance reported by Gromacs:
	echo -e "Protein_name\tReplicate\tCPU_time_s\tWall_time_s\tCPU_usage_pct\tns/day\thours/ns" > benchmark_mdrun.tsv

	### Actually run the control replicates (auto CPU-GPU balancing):
	for ((r = 1; r <= replicates; r++)); do
		# Start CPU monitoring:
		../../start_cpu_monitor.sh $r & > /dev/null 2>&1
		cpu_log_PID=$!
		
		# Start GPU monitoring:
		../../start_gpu_monitor.sh $r & > /dev/null 2>&1
		gpu_log_PID=$!

		# Launch simulation:
		gmx -quiet mdrun \
		-s ../preparation_files/md.tpr \
		-deffnm md \
		-g mdrun.log \
		-tunepme \
		-ntomp_pme 0 \
		-dd 0 0 0 \
		-ntmpi 1 \
		-pin on \
		-ntomp 12
		
		# Stop CPU monitoring:
		kill -TERM $cpu_log_PID

		# Stop GPU monitoring>
		kill -TERM $gpu_log_PID

		# Process the log created by Gromacs:
		process_log_file

		# Extract RMSD data from md.edr:
		## First, convert the trajectory to center the protein:
		printf "1\n0" | gmx -quiet trjconv -s ../preparation_files/md.tpr -f md.xtc -o md_noPBC_$r.xtc -tu ps -pbc mol -center
		## Then, extract the RMSD data:
		printf "4\n4" | gmx -quiet rms -s ../preparation_files/md.tpr -f md_noPBC_$r.xtc -o md_rmsd_$r.xvg -tu ps
	    
	done

	
	cd ..


	## Then, iteratively run simulations exploring all acceptable combinations of CPU-GPU unloading:
	for nb in ${options_variable_flags[@]}; do
	for pme in ${options_variable_flags[@]}; do
	for pmefft in ${options_variable_flags[@]}; do
	for bonded in ${options_variable_flags[@]}; do
	for update in ${options_variable_flags[@]}; do

		## Skip combinations of CPU-GPU unloading that are not acceptable:
		if [[ "$update" == "gpu" && "$pme" == "cpu" && "$nb" == "cpu" ]]; then continue; fi
		if [[ "$bonded" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
		if [[ "$pmefft" == "gpu" && "$pme" == "cpu" ]]; then continue; fi
		if [[ "$pme" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
		
		## Create a directory for the simulation and get into that directory:
		path="nb=$nb pme=$pme pmefft=$pmefft bonded=$bonded update=$update"
		eval "mkdir -p \"$path\""
		cd "$path"

		### Create the file to log the performance reported by Gromacs:
		echo -e "Protein_name\tReplicate\tCPU_time_s\tWall_time_s\tCPU_usage_pct\tns/day\thours/ns" > benchmark_mdrun.tsv

		## Simulate the replicates
		for ((r = 1; r <= replicates; r++)); do

			# Start CPU monitoring:
			../../start_cpu_monitor.sh $r & > /dev/null 2>&1
			cpu_log_PID=$!

			# Start GPU monitoring:
			../../start_gpu_monitor.sh $r & > /dev/null 2>&1
			gpu_log_PID=$!

			# Launch simulation:
			variable_flags="-nb $nb -pme $pme -pmefft $pmefft -bonded $bonded -update $update"
			gmx -quiet mdrun \
			-s ../preparation_files/md.tpr \
			-deffnm md \
			-g mdrun.log \
			-tunepme \
			-ntomp_pme 0 \
			-dd 0 0 0 \
			-ntmpi 1 \
			-pin on \
			-ntomp 12 \
			$variable_flags

			# Stop CPU monitoring:
			kill -TERM $cpu_log_PID

			# Stop GPU monitoring:
			kill -TERM $gpu_log_PID

			# Process the log file 'mdrun.log':
			process_log_file

			# Extract RMSD data from md.edr:
			## First, convert the trajectory to center the protein:
			printf "1\n0" | gmx -quiet trjconv -s ../preparation_files/md.tpr -f md.xtc -o md_noPBC_$r.xtc -tu ps -pbc mol -center
			## Then, extract the RMSD data:
			printf "4\n4" | gmx -quiet rms -s ../preparation_files/md.tpr -f md_noPBC_$r.xtc -o md_rmsd_$r.xvg -tu ps

		done
		
		## Return to main path of the protein:
		cd ..
		
	done
	done
	done
	done
	done


exit 0
