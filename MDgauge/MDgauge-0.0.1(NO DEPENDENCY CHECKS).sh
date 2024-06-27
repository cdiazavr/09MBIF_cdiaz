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

#title          : MDgauge-0.0.1.sh
#description    : Benchmark performance and energy consumption of molecular dynamics simulations with Gromacs on CPU and Nvidia GPU.
#author		 	: Carlos Diaz <cdiazavr@gmail.com>
#date           : 20240512
#version        : 0.0.1    
#usage (GUI)    : ./MDgauge-0.0.1.sh [-h]
#usage (shell)  : ./MDgauge-0.0.1.sh [-h] [-t] [-p protein] [-b {time_energy|time}] [-s steps] [-r replicates] [-c custom_params] [-g]
#notes          : Install 'Gromacs' (compiled with NVIDIA® CUDA® support), 'yad' (for GUI execution), 'jq', 'S-tui' (for energy optimization), and Nvidia-SMI.
#bash_version   : 5.2.21(1)-release


# GLOBAL SETUPS:

	app_name="MDgauge"
	cpu_monitoring_freq_s=0.05 # number of seconds betweeen meassurements of cpu_monitoring
	gpu_monitoring_freq_s=0.15 # number of seconds betweeen meassurements of gpu_monitoring
	debug_printing=false # print a file with all the calculated performance and energy results in each simulation directory
	export GMX_MAXBACKUP=-1 # Omit file backups during replicated runs of Gromacs
	

# AUXILIARY FUNCTIONS:
	## Usage help:
	show_usage() {
		echo -e "\nUSAGE: $0 [-h] [-t] [-p protein] [-b {time_energy|time}] [-s steps] [-r replicates] [-c custom_params] [-g]"
		echo -e "\nOPTIONS:"
		echo    "  -h                       Show this help."	    
		echo    "  -t                       Run only on console (do not launch GUI)."
		echo    "  -p protein               Path of the protein file to be simulated (PDB format)."
		echo    "  -b {time_energy|time}    time_energy : benchmarks both time performance and energy consumption."
		echo    "                           time : benchmarks only time performance."
		echo    "  -s steps                 Number of time steps to simulate in each replicate."
		echo    "  -r replicates            Number of replicates to simulate."
		echo    "  -c custom_params         Custom parameters to be passed to GROMACS' mdrun."
		echo    "                           The parameters need to be passed with the same syntax of mdrun."
		#~ echo    "  -i                       Ignore available GPU devices and benchmark simulations only on CPU."
		#~ echo    "  -f                       Save the results to a file."
		echo    "  -g                       Preserve the intermediate files created during the simulations."
		echo -e "\nNOTE: if the option -t is specified, then the following parameters are mandatory:"
		echo    "      [-p protein] [-b {time_energy|time}] [-s steps] [-r replicates]"
		echo -e "\n      The following parameters are optional: [-c custom_params] [-i] [-f] [-g]"
		echo    "      (if any of these is not specified, these will be set to false)"
	}

	
	## Validate if last executed command had exit code 0:
	validate_exit_status() {
	# This function requires the variable exit_status to have
		# the exit status of the last command executed and that the
		# file stderr.out contains the error message to show to the
		# user as an GUI error before exiting.
		
		if [ "$no_gui" = true ]; then
			if [ "$exit_status" -ne 0 ]; then
				echo "Last command did not end correctly. Look for error messages above."
				exit 1
			fi
		else
			if [ "$exit_status" -ne 0 ]; then
				# Show full content of stderr.out as an error:
				local error_msg=$(cat stderr.out)
				yad --title="Error" \
					--image=dialog-error \
					--button=Close:0 \
					--center \
					--text="ERROR\n$error_msg"
				exit 1
			fi
		fi
	}


	## Replace the number of steps in a GROMACS' molecular dynamics parameters (.mdp) options file:
	replace_nsteps() {
		# This functions takes as first argument the path of the '.mdp' file to edit,
		# and as a second argument the new number of steps to write to the file.
		local mdp_file="$1"
		local new_nsteps="$2"

		# Use sed to replace the number
		sed -i "s/\(nsteps[[:space:]]*=[[:space:]]*\)[0-9]\+/\1$new_nsteps/" "$mdp_file"
	}
		

	## Continuosly and periodically monitor the energy consumption in the CPU:
	cpu_monitoring() {
		# Handle incoming SIGTERM to terminate cpu_monitoring()
		# without causing broken pipe issues.
		handle_sigterm() {
			exec 3>&-
			exit 0
		}
		trap 'handle_sigterm' TERM
		
		# Retrieve the desired period to meassure the CPU status:
		local period=$1
		
		# Get number of replicate being run:
		local replicate=$2
		
		# Create file where the CPU power consumption will be stored:
		if [ ! -f benchmark_cpu.tsv ]; then
			touch benchmark_cpu.tsv
		fi
		
		# Infinite loop to log periodically the CPU power consumption:
		local CPU_status=''
		local powers=''
		while true; do
			# Get all the CPU current parameters in JSON format:
			local CPU_status=$(s-tui -j)
			
			# Parse only the package and core power:
			local powers=($(echo "$CPU_status" | jq -r '.Power | .[]'))
			
			# Save only the package power consumption to benchmark_cpu.tsv:
			printf "$replicate\t${powers[0]}\n" >> benchmark_cpu.tsv
			
			sleep $period
		done
	}


	## Continuosly and periodically monitor the energy consumption in the GPU:
	gpu_monitoring() {
		# Handle incoming SIGTERM to terminate gpu_monitoring()
		# without causing broken pipe issues.
		handle_sigterm() {
			exec 3>&-
			exit 0
		}
		trap 'handle_sigterm' TERM
		
		# Retrieve the desired period to meassure the GPU status:
		local period=$1
		
		# Get number of replicate being run:
		local replicate=$2
		
		# Create file where the CPU power consumption will be stored:
		if [ ! -f benchmark_gpu.tsv ]; then
			touch benchmark_gpu.tsv
		fi
		
		# Infinite loop to log periodically the GPU power consumption:
		local power=''
		while true; do
			# Get the current power consumption of NVIDIA GPU:
			power=$(nvidia-smi -q -d POWER | grep -m1 "Power Draw" | awk '{print $(NF-1)}')
			# Save the power consumption to benchmark_gpu.tsv:
			printf "$replicate\t$power\n" >> benchmark_gpu.tsv
			
			sleep $period
		done
	}


	## Process the log files created by GROMACS into a custom .tsv file with time performance of replicates:
	process_log_file() {
		local line_with_times=$(grep "^ *Time:" mdrun.log)
		local line_with_performance=$(grep "^ *Performance:" mdrun.log)
		
		if [ -n "$line_with_performance" ]; then
			# Remove leading and trailing spaces:
			line_with_time="${line_with_times##*( )}"
			line_with_time="${line_with_times%%*( )}"
			line_with_performance="${line_with_performance##*( )}"
			line_with_performance="${line_with_performance%%*( )}"
			# Split the line into variables:
			read -r time_wall <<< $(awk '{print $3}' <<< "$line_with_times")
			read -r ns_day hours_ns <<< $(awk '{print $2, $3}' <<< "$line_with_performance")
			# Append time wall, ns/day and hours_ns to the final benchmark file:
			printf "$time_wall\t$ns_day\t$hours_ns\n" >> benchmark_mdrun.tsv
		else
			exit 1
		fi
	}

	
	## Calculate the arithmetic mean of all the values stored in an array.
	mean() {
		# It should be called as `mean "${my_array[@]}"`
		local values=("$@")  # Capture all arguments as an array
		local n="${#values[@]}"
		local sum=0
		for value in "${values[@]}"; do
			sum=$(echo "scale=4; $sum + $value" | bc -l)
		done
		mean_result=$(echo "scale=4; $sum / $n" | bc -l)  # Calculate the mean with 4 decimal places and store in mean_result
	}
	
		
	## Calcula the sample standard deviation of all the values stored in an array:
	std_dev_sample() {
		# It should be called as `std_dev_sample "${my_array[@]}"`
		local values=("$@")  # Capture all arguments as an array
		local n="${#values[@]}"
		
		# Calculate mean:
		mean "${values[@]}"
		local values_mean="$mean_result"
		unset mean_result # unset reusable global variable for safety reasons
		
		# Calculate the squared sum of differences between values and values_mean
		squared_sum=0
		for (( i = 0; i < n; i++ )); do
			local difference=$(bc -l <<< "${values[i]} - $values_mean")
			local squared_sum=$(bc -l <<< "$squared_sum + ($difference * $difference)")
		done
		
		# Divide by n-1 and calculate the squared root:
		std_dev_sample_result=$(bc -l <<< "sqrt( $squared_sum/($n-1) )")
	}
	
	
	## Calculate energy consumption:
	energy_consumption() {
		# This function received n arguments, where n is an even numbers.
		# The first n/2 arguments should be the wall times (s).
		# The remaining n/2 arguments should be the powers consumed (W).
		
		# Parse arguments:
		local arguments=("$@")
		local n="$(( $# / 2 ))"
		
		# Slice `arguments` to get the wall times and powers in diferent arrays
		local wall_time=("${arguments[@]:0:$n}")
		local power=("${arguments[@]:$n}")
		
		# Perform element-wise multiplication and store in global variable:
		energy_consumption_result=()
		
		for (( i = 0; i < n; i++ )); do
			energy_consumption_result+=( $(bc -l <<< "${wall_time[i]} * ${power[i]}") )
		done			
	}
	
	
	## Save performance partial results (for debugging purposes):
	save_performance_debug() {
		## This function received a single argument, which is the detination file
		## where the performance partial results should be stored.
		
		echo "" >> "$1"
		echo "SIMULATION PARAMETERS: $simulation_directory" >> "$1"
		echo "Simulated steps:                      :  $steps" >> "$1"
		echo "------------------------------- PERFORMANCE ------------------------------" >> "$1"
	
		echo "Wall times (s)                        :  ${all_wall_time_s[@]}" >> "$1"
		echo "Avg. wall time (s)                    :  $avg_wall_time_s" >> "$1"
		echo "SD wall time (s)                      :  $sd_wall_time_s" >> "$1"
		echo "Wall time (s) per 10k steps           :  $avg_wall_time_s_10k" >> "$1"
		
		echo "Performances (ns/day)                 :  ${all_ns_day[@]}" >> "$1"
		echo "Avg. performances (ns/day)            :  $avg_ns_day" >> "$1"
		echo "SD performances (ns/day)              :  $sd_ns_day" >> "$1"
		
		echo "Performances (h/ns)                   :  ${all_hour_ns[@]}" >> "$1"
		echo "Avg. performances (h/ns)              :  $avg_hour_ns" >> "$1"
		echo "SD performances (h/ns)                :  $sd_hour_ns" >> "$1"
		
		if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
			echo "Avg. CPU power (W)                    :  ${all_avg_cpu_power_W[@]}" >> "$1"
			echo "Avg. GPU power (W)                    :  ${all_avg_gpu_power_W[@]}" >> "$1"
		fi
	}
	
	
	## Save energy partial results (for debugging purposes):
	save_energy_debug() {
		## This function received a single argument, which is the detination file
		## where the energy partial results should be stored.
		echo "--------------------------------- ENERGY ---------------------------------" >> "$1"
		
		echo "CPU energies (J)                      :  ${all_cpu_energy_J[@]}" >> "$1"
		echo "Avg. CPU energy (J)                   :  $avg_cpu_energy_J" >> "$1"
		echo "SD CPU energy (J)                     :  $sd_cpu_energy_J" >> "$1"
		
		echo "GPU energies (J)                      :  ${all_gpu_energy_J[@]}" >> "$1"
		echo "Avg. GPU energy (J)                   :  $avg_gpu_energy_J" >> "$1"
		echo "SD GPU energy (J)                     :  $sd_gpu_energy_J" >> "$1"
		
		echo "Total energies (J)                    :  ${all_total_energy_J[@]}" >> "$1"
		echo "Avg. total energy (J)                 :  $avg_total_energy_J" >> "$1"
		echo "SD total energy (J)                   :  $sd_total_energy_J" >> "$1"
		echo "Avg. total energy (J) per 10 k steps  :  $avg_total_energy_J_10k" >> "$1"
	}
	
	
	## Save analyzed results to a file:
	save_analyzed_results() {
		## This function received a single argument, which is the detination file
		## where the performance partial results should be stored.
		
		echo -e "Avg. wall time (s)\t$avg_wall_time_s" >> "$1"
		echo -e "Avg. wall time (s) per 10k steps\t$avg_wall_time_s_10k" >> "$1"
		echo -e "SD wall time (s)\t$sd_wall_time_s" >> "$1"
		echo -e "Avg. performance (ns/day)\t$avg_ns_day" >> "$1"
		echo -e "SD performance (ns/day)\t$sd_ns_day" >> "$1"
		echo -e "Avg. performance (h/ns)\t$avg_hour_ns" >> "$1"
		echo -e "SD performance (h/ns)\t$sd_hour_ns" >> "$1"
		
		if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
			echo -e "Avg. CPU energy (J)\t$avg_cpu_energy_J" >> "$1"
			echo -e "SD CPU energy (J)\t$sd_cpu_energy_J" >> "$1"
			echo -e "Avg. GPU energy (J)\t$avg_gpu_energy_J" >> "$1"
			echo -e "SD CPU energy (J)\t$sd_gpu_energy_J" >> "$1"
			echo -e "Avg. total energy (J)\t$avg_total_energy_J" >> "$1"
			echo -e "SD total energy (J)\t$sd_total_energy_J" >> "$1"
			echo -e "Avg. total energy (J) per 10 k steps\t$avg_total_energy_J_10k" >> "$1"
		fi
	}
	


# PARSE AND VALIDATE OPTIONS PASSED BY USER DURING INITIAL TERMINAL CALL:
	## Set default values for some of the variables:
	help_required=false
	no_gui=false
	ignore_GPU=false
	save_results=true
	preserve_gromacs_files=false
	
	## Parse and update from the initial terminal call:
	while getopts "htp:b:s:r:c:g" opt; do
		case $opt in
			h)
				help_required=true
				;;
			t)
				no_gui=true
				;;
			p)
				protein="$OPTARG"
				protein=$(realpath "$protein")
				protein_name=$(basename "$protein")
				protein_path=$(dirname "$protein")
				;;
			b)
				benchmark="$OPTARG"
				;;
			s)
				steps="$OPTARG"
				;;
			r)
				replicates="$OPTARG"
				;;
			c)
				custom_params="$OPTARG"
				;;
			#~ i)
				#~ ignore_GPU=true
				#~ ;;
			#~ f)
				#~ save_results=true
				#~ ;;
			g)
				preserve_gromacs_files=true
				;;
			\?)
				echo "" >&2
				show_usage
				exit 1
				;;
			:)
				echo "" >&2
				show_usage
				exit 1
				;;
		esac
	done

	## If requested, provide help to the user:
	if [ "$help_required" = true ]; then
		# TODO: expand this into a propper help for the user.
		echo "HELP WAS REQUESTED"
		show_usage
		exit 0
	fi

	## Validate parsed options and arguments:
	if [ "$no_gui" = true ]; then
		# Validate protein:
			## Check that an argument was passed to -p:
			if [ -z "$protein" ];then
				echo "ERROR: No protein file was passed." >&2
				echo "       (check that the file is passed after -p)" >&2
				show_usage
				exit 1
			fi
			## Check that the file exists:
			if [ ! -f "$protein" ]; then
				echo "ERROR: Protein file $protein not found." >&2
				echo "       (check the file passed after -p)" >&2
				show_usage
				exit 1
			fi

		# Validate benchmark:
			## Check that an argument was passed to -b:
			if [ -z "$benchmark" ];then
				echo "ERROR: No benchmark to run was detected." >&2
				echo "       (check that either 'time_energy' or" >&2
				echo "       'time' is passed after -b)" >&2
				show_usage
				exit 1
			fi
			
			## The passed argument is either 'time_energy' or 'time':
			if [ "$benchmark" != "time_energy" ] && [ "$benchmark" != "time" ]; then
				echo "ERROR: Invalid benchmark to run: $benchmark" >&2
				echo "       (check that either 'time_energy' or" >&2
				echo "       'time' is passed after -b)" >&2
				show_usage
				exit 1
			fi

		# Validate steps:
			## Check that an argument was passed to -s:
			if [ -z "$steps" ];then
				echo "ERROR: No number of steps to run was detected." >&2
				echo "       (check that the number of steps is passed after -s)" >&2
				show_usage
				exit 1
			fi
			
			## Check that the argument is an integer:
			if [[ ! $steps =~ ^[0-9]+$ ]]; then
				echo "ERROR: Invalid number of steps: $steps." >&2
				echo "       (check that an integer number of steps is passed after -s)" >&2
			fi
			
			## Check that the number of greater than zero:
			if [ "$steps" -le 0 ];then
				echo "ERROR: Number of steps to run cannot be 0." >&2
				echo "       (check that an integer number greater than 0 is passed after -s)" >&2
				show_usage
				exit 1
			fi

			## Check that the number is not too small:
			if [ "$steps" -lt 1000 ];then
				echo "WARNING: Number of steps potentially too small." >&2
				echo "       (Note that using a small number of steps might cause errors during the simulations.)" >&2
			fi

		# Validate replicates:
			## Check that an argument was passed to -r:
			if [ -z "$replicates" ];then
				echo "ERROR: No number of replicates to run was detected." >&2
				echo "       (check that the number of replicates is passed after -r)" >&2
				show_usage
				exit 1
			fi
			
			## Check that the argument is an integer:
			if [[ ! $replicates =~ ^[0-9]+$ ]]; then
				echo "ERROR: Invalid number of replicates: $replicates." >&2
				echo "       (check that an integer number of replicates is passed after -r)" >&2
			fi

			## Check that the number is not too small:
			if [ "$steps" -lt 3 ];then
				echo "WARNING: Number of replicates potentially too small." >&2
				echo "       (Note that results using a small number of replicates might be inaccurate and unreliable.)" >&2
			fi
	fi


# DETECT IF RUNNING WITH ROOT PRIVILEGES:
	## Get effective user ID:
		uid=$(id -u)

		if [ "$uid" -eq 0 ]; then
			run_without_root=false  # Effective user is root
		fi
		
		if [ "$uid" -ne 0 ]; then
			run_without_root=true # Effective used is not root
		fi
		


#~ # VALIDATE THAT ALL NEEDED SOFTWARE IS INSTALLED AND AVAILABLE:
	#~ ## Yad (mandatory only if running in GUI mode):
		#~ if [ "$no_gui" == false ] && ! command -v yad &> /dev/null; then
			#~ echo -e "\nERROR: 'yad' is needed for the GUI, but it was not found." >&2
			#~ echo    "       Install 'yad', or run in terminal mode." >&2
			#~ show_usage
			#~ exit 1
		#~ fi
	
	#~ ## GROMACS (mandatory):
		#~ ### If running in root mode, get the path of gmx to use:
		#~ if [ "$run_without_root" == true ]; then
			#~ # Get path of executable gmx:
			#~ gmx_path=$(which gmx)
		#~ else
			#~ # Case when the script is being executed with root privileges:
			#~ ## Get user name:
			#~ if [ -n "$SUDO_USER" ]; then
				#~ user=$SUDO_USER
			#~ elif [ -n "$LOGNAME" ]; then
				#~ user=$LOGNAME
				#~ # NOTE: `LOGNAME` stores the name of the user, even if `su` is not used to run the script.
			#~ fi

			#~ ## Handle the case when the user name could not be found...
			#~ ### ...when running in GUI mode:
			#~ error_gmx_not_found="ERROR: Path to the GROMACS wrapper gmx wat not found\nThis error cannot be solved by user an it is likely a bug.\nPlease consider reporting this to the developer."
			
			#~ if [ "$no_gui" == false ] && [ -z "$user" ]; then
				#~ yad --width=400 --height=100 \
					#~ --center \
					#~ --title="$app_name - Error" \
					#~ --image=dialog-error \
					#~ --button=Close:0 \
					#~ --text="$error_gmx_not_found"
				#~ exit 1
			#~ fi

			#~ ### ...when runing in terminal mode:
			#~ if [ "$no_gui" == true ] && [ -z "$user" ]; then
				#~ echo "$error_gmx_not_found"
				#~ exit 1
			#~ fi

			#~ ## Get path of executable gmx:
			#~ script_path=$(dirname "$(readlink -f "$0")")
			#~ su -l $user -c "which gmx > $script_path/gmx_path.out; exit"
			#~ gmx_path=$(cat "$script_path/gmx_path.out")
			#~ rm "$script_path/gmx_path.out"
			
		#~ fi
	
		#~ ### Check if gmx is accesible through gmx_path:
		#~ if ! command -v "$gmx_path" &> /dev/null; then
			#~ echo -e "\nERROR: GROMACS was not found." >&2
			#~ echo -e "       Please verify that you have installed GROMACS and the command 'gmx' can be used." >&2
			#~ show_usage
			#~ exit 1
		#~ fi
	
	#~ ## NVIDIA-SMI (mandatory):
		#~ if ! command -v nvidia-smi &> /dev/null; then
			#~ echo -e "\nERROR: The System Management Interface (SMI) of NVIDIA® was not found." >&2
			#~ echo -e "       Please verify that you have installed NVIDIA® SMI and the command 'nvidia-smi' can be used." >&2
			#~ show_usage
			#~ exit 1
		#~ fi
	
	#~ ## S-tui (mandatory only if energy consumption is being performed):
		#~ if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ] && ! command -v s-tui &> /dev/null; then
			#~ echo -e "\nERROR: 'S-tui' is needed for the analyzing energy consumptions, but it was not found." >&2
			#~ echo    "       Install 'S-tui', or benchmark only time performance." >&2
			#~ show_usage
			#~ exit 1
		#~ fi
	
	#~ ## jq (mandatory only if energy consumption is being performed):
		#~ if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ] && ! command -v jq &> /dev/null; then
			#~ echo -e "\nERROR: 'jq' is needed for the analyzing energy consumptions, but it was not found." >&2
			#~ echo    "       Install 'jq', or benchmark only time performance." >&2
			#~ show_usage
			#~ exit 1
		#~ fi



# IF NOT RUNNING WITH ROOT PRIVILEGES, ASK USER HOW TO PROCEED:
	## In GUI mode:
	if [ "$no_gui" == false ] && [ "$uid" -ne 0 ]; then
		# Effective user is NOT root, ask the user if continue:
		yad --title="$app_name - Warning" \
			--image=dialog-warning \
			--button=Continue:0 \
			--button=Close:1 \
			--center \
			--text-align=center \
			--text="Root privileges are required for measuring energy consumption.\nContinue without root privileges?"
		answer=$?

		# Handle close (user choose not to continue):
		if [ "$answer" -ne 0 ]; then
			echo "Execution aborted by user"
			exit 0
		else
			run_without_root=true # user decided to run without root privileges
		fi
	fi
	
	## In terminal mode:
	if [ "$no_gui" == true ] && [ "$uid" -ne 0 ] && [ "$benchmark" == "time_energy" ] ; then
		# Throw an error only if user wants to meassure energy consumption without root privileges:
		echo "ERROR: Root privileges are required for measuring energy consumption."
		echo "       (run with root privileges, or benchmark time only [-b time])"
		exit 1
	fi



# RUN IN TERMINAL MODE:
	if [ $no_gui == true ]; then
		# Create working directory:
			echo "CREATING WORKING DIRECTORY"
			cd $protein_path
			datetime=$(date +%Y%m%d_%H%M%S%Z)
			working_directory="$protein_name-simulation-$datetime"
			mkdir -p "$working_directory"
		
		
		# Extract atoms from protein:
			echo "EXTRACTING ATOMS FROM PROTEIN"
			grep ^ATOM "$protein" > "$working_directory/clean_protein.pdb"
			cd "$working_directory"
		
		
		# Create coordinates and topology files:
			echo "CREATING COORDINATES AND TOPOLOGY FILES"
			$gmx_path -quiet pdb2gmx \
			-f clean_protein.pdb \
			-o protein.gro \
			-ignh
			## Get and validate that the last command was successfully executed:
			exit_status=$?
			validate_exit_status
		
		
		# Create simulation box:
			echo "CREATING SIMULATION BOX"
			$gmx_path -quiet editconf \
			-f protein.gro \
			-o protein_box.gro \
			-c -d 1.0 \
			-bt dodecahedron
			## Get and validate that the last command was successfully executed:
			exit_status=$?
			validate_exit_status
		
		
		# Solvate the system:
			echo "SOLVATING THE SYSTEM"
			$gmx_path -quiet solvate \
			-cp protein_box.gro \
			-cs spc216.gro \
			-o protein_solv.gro \
			-p topol.top
			## Get and validate that the last command was successfully executed:
			exit_status=$?
			validate_exit_status
		
		
		# Add ions to the system to neutralize it:
			echo "ADDING IONS TO NEUTRALIZE THE SYSTEM"
			## Search for the file 'ions.mdp'...
				### ...where the starting protein is:
				if [[ -f "$protein_path/ions.mdp" ]]; then
					ions_mdp_file="$protein_path/ions.mdp"
				### ...in a directory called 'mdp', which is in the same directory of the starting protein:
				elif [[ -f "$protein_path/mdp/ions.mdp" ]]; then
					ions_mdp_file="$protein_path/mdp/ions.mdp"
				# If 'ions.mdp' was not found, then throw error, and ask user to copy the mdp file to of the paths searched above:
				else
					echo "ERROR: A file 'ions.mdp' was not found."
					echo "       Please copy the molecular dynamics parameters file 'ions.mdp' to the same directory where"
					echo "       the protein is, or to a folder called 'mdp' which should be in the same directory of the protein."
					echo ""
					echo "       Paths where the file 'ions.mdp' should be:"
					echo "       Option 1:  $protein_path/ions.mdp"
					echo "       Option 2:  $protein_path/mdp/ions.mdp"
					exit 1
				fi			

			## Proceed to add ions:
				# Pre-process:
				$gmx_path -quiet grompp \
				-f "$ions_mdp_file" \
				-c protein_solv.gro \
				-p topol.top \
				-o ions.tpr > stdout.out 2> stderr.out

				# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status

				# Actually add ions:
				# TODO: make this option "13" dynamic, according to the version of GROMACS
				# 13: SOL
				printf "13" | $gmx_path -quiet genion \
							  -s ions.tpr \
							  -o protein_ions.gro \
							  -p topol.top \
							  -pname NA -nname CL \
							  -neutral \
							  -conc 0.15 > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status
		
		
		# Minimize energy:
			echo "MINIMIZING ENERGY OF THE SYSTEM"
			## Search for the file 'minim.mdp':
			### Where the starting protein is:
				if [[ -f "$protein_path/minim.mdp" ]]; then
					minim_mdp_file="$protein_path/minim.mdp"
				# In a folder called 'mdp' where the starting protein is:
				elif [[ -f "$protein_path/mdp/minim.mdp" ]]; then
					minim_mdp_file="$protein_path/mdp/minim.mdp"
				# If 'minim.mdp' was not found, then ask user to manually provide the path:
				else
					echo "ERROR: A file 'minim.mdp' was not found."
					echo "       Please copy the molecular dynamics parameters file 'minim.mdp' to the same directory where"
					echo "       the protein is, or to a folder called 'mdp' which should be in the same directory of the protein."
					echo ""
					echo "       Paths where the file 'minim.mdp' should be:"
					echo "       Option 1:  $protein_path/minim.mdp"
					echo "       Option 2:  $protein_path/mdp/minim.mdp"
					exit 1
				fi
			
			## Proceed with energy minimization:
				# Pre-process:
					$gmx_path -quiet grompp \
					-f "$minim_mdp_file" \
					-c protein_ions.gro \
					-p topol.top \
					-o em.tpr > stdout.out 2> stderr.out

				# Get and validate that the last command was successfully executed:
					exit_status=$?
					validate_exit_status

				# Actually minimize the energy of the system:
					$gmx_path -quiet mdrun -deffnm em > stdout.out 2> stderr.out

				# Get and validate that the last command was successfully executed:
					exit_status=$?
					validate_exit_status
		
		
		# Save evolution of potential energy during energy minimization:
			echo "SAVING POTENTIAL ENERGY DURING ENERGY MINIMIZATION"
			# TODO: make this option "10" dynamic, according to the version of GROMACS
			# 10: potential energy
			printf "10\n0" | $gmx_path -quiet energy \
								-f em.edr \
								-o em_potential.xvg > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status
		
		
		# Run NVT equilibration:
			echo "RUNNING NVT EQUILIBRATION"
			## Search for the file 'nvt.mdp':
			### Where the starting protein is:
				if [[ -f "$protein_path/nvt.mdp" ]]; then
					nvt_mdp_file="$protein_path/nvt.mdp"
				# In a folder called 'mdp' where the starting protein is:
				elif [[ -f "$protein_path/mdp/nvt.mdp" ]]; then
					nvt_mdp_file="$protein_path/mdp/nvt.mdp"
				# If 'nvt.mdp' was not found, then ask user to manually provide the path:
				else
					echo "ERROR: A file 'nvt.mdp' was not found."
					echo "       Please copy the molecular dynamics parameters file 'nvt.mdp' to the same directory where"
					echo "       the protein is, or to a folder called 'mdp' which should be in the same directory of the protein."
					echo ""
					echo "       Paths where the file 'nvt.mdp' should be:"
					echo "       Option 1:  $protein_path/nvt.mdp"
					echo "       Option 2:  $protein_path/mdp/nvt.mdp"
					exit 1
				fi

			### Update the number of steps as per preference of user:
				replace_nsteps "$nvt_mdp_file" "$steps"

			### Proceed with NVT equilibration:
				# Pre-process:
					$gmx_path -quiet grompp \
					-f "$nvt_mdp_file" \
					-c em.gro \
					-r em.gro \
					-p topol.top \
					-o nvt.tpr > stdout.out 2> stderr.out

				# Get and validate that the last command was successfully executed:
					exit_status=$?
					validate_exit_status

				# Actually run NVT minimization:
					$gmx_path -quiet mdrun -deffnm nvt > stdout.out 2> stderr.out

				# Get and validate that the last command was successfully executed:
					exit_status=$?
					validate_exit_status
		
		
		# Save evolution of temperature during NVT equilibration:
			echo "SAVING TEMPERATURES DURING NVT EQUILIBRATION"
			# TODO: make this options "16" dynamic, according to the version of GROMACS
			printf "16\n0" | $gmx_path -quiet energy \
								-f nvt.edr \
								-o nvt_temperature.xvg > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status
		
		
		# Run NPT equilibration:
			echo "SAVING NPT EQUILIBRATION"
			### Search for the file 'npt.mdp':
			# Where the starting protein is:
				if [[ -f "$protein_path/npt.mdp" ]]; then
					npt_mdp_file="$protein_path/npt.mdp"
				# In a folder called 'mdp' where the starting protein is:
				elif [[ -f "$protein_path/mdp/npt.mdp" ]]; then
					npt_mdp_file="$protein_path/mdp/npt.mdp"
				# If 'npt.mdp' was not found, then ask user to manually provide the path:
				else
					echo "ERROR: A file 'npt.mdp' was not found."
					echo "       Please copy the molecular dynamics parameters file 'npt.mdp' to the same directory where"
					echo "       the protein is, or to a folder called 'mdp' which should be in the same directory of the protein."
					echo ""
					echo "       Paths where the file 'npt.mdp' should be:"
					echo "       Option 1:  $protein_path/npt.mdp"
					echo "       Option 2:  $protein_path/mdp/npt.mdp"
					exit 1
				fi

			### Update the number of steps as per preference of user:
				replace_nsteps "$npt_mdp_file" "$steps"

			### Proceed with NPT equilibration:
				# Pre-process:
					$gmx_path -quiet grompp \
					-f "$npt_mdp_file" \
					-c nvt.gro \
					-r nvt.gro \
					-t nvt.cpt \
					-p topol.top \
					-o npt.tpr > stdout.out 2> stderr.out

				# Get and validate that the last command was successfully executed:
					exit_status=$?
					validate_exit_status

				# Actually run NPT minimization:
					$gmx_path -quiet mdrun -deffnm npt > stdout.out 2> stderr.out

				# Get and validate that the last command was successfully executed:
					exit_status=$?
					validate_exit_status
		
		
		# Save evolution of pressure and density during NPT equilibration:
			echo "SAVING PRESSURE DENSITY DURING NPT EQUILIBRATION"
			# TODO: make these options "18" and "24" dynamic, according to the version of GROMACS
			printf "18\n0" | $gmx_path -quiet energy \
								-f npt.edr \
								-o npt_pressure.xvg > stdout.out 2> stderr.out
			# Get and validate that the last command was successfully executed:
			exit_status=$?
			validate_exit_status
				
			printf "24\n0" | $gmx_path -quiet energy \
										-f npt.edr \
										-o npt_density.xvg > stdout.out 2> stderr.out
			# Get and validate that the last command was successfully executed:
			exit_status=$?
			validate_exit_status
		
		
		# Pre-process the system for production runs:
			echo "PRE-PROCESSING FOR PRODUCTION RUNS"
			## Search for the file 'md.mdp':
			### Where the starting protein is:
				if [[ -f "$protein_path/md.mdp" ]]; then
					md_mdp_file="$protein_path/md.mdp"
				# In a folder called 'mdp' where the starting protein is:
				elif [[ -f "$protein_path/mdp/md.mdp" ]]; then
					md_mdp_file="$protein_path/mdp/md.mdp"
				# If 'md.mdp' was not found, then ask user to manually provide the path:
				else
					echo "ERROR: A file 'md.mdp' was not found."
					echo "       Please copy the molecular dynamics parameters file 'md.mdp' to the same directory where"
					echo "       the protein is, or to a folder called 'mdp' which should be in the same directory of the protein."
					echo ""
					echo "       Paths where the file 'md.mdp' should be:"
					echo "       Option 1:  $protein_path/md.mdp"
					echo "       Option 2:  $protein_path/mdp/md.mdp"
					exit 1
				fi

			## Update the number of steps as per preference of user:
				replace_nsteps "$md_mdp_file" "$steps"

			### Actually pre-process for production runs:
				$gmx_path -quiet grompp \
				-f "$md_mdp_file" \
				-c npt.gro \
				-t npt.cpt \
				-p topol.top \
				-o md.tpr > stdout.out 2> stderr.out
				
				# Get and validate that the last command was successfully executed:
					exit_status=$?
					validate_exit_status
		
		
		# Save preparation files to new directory:
			echo "SAVING PREPARATION FILES TO A NEW DIRECTORY"
			mkdir -p 'preparation_files'
			mv -f $(ls clean_protein.pdb *.edr *.gro *.log *.tpr *.trr *.itp *.top *.cpt *.mdp *.xvg *.out) preparation_files
		
		
		# Run control simulations:
			echo "RUNNING CONTROL SIMULATIONS"
			## Create directory for control simulation (auto CPU-GPU balancing):
				simulation_directory="nb=auto pme=auto pmefft=auto bonded=auto update=auto"
				eval "mkdir -p \"$simulation_directory\""
				cd "$simulation_directory"

			## Actually run the control replicates (auto CPU-GPU balancing):
				for ((r = 1; r <= replicates; r++)); do
					# If energy consumption is to be benchmarked, launch CPU and GPU monitoring:
					if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
						# Launch CPU monitoring:
						cpu_monitoring $cpu_monitoring_freq_s $r & > /dev/null 2>&1
						cpu_monitoring_PID=$!

						if [ "$ignore_GPU" == false ]; then
							# Launch GPU monitoring:
							gpu_monitoring $gpu_monitoring_freq_s $r & > /dev/null 2>&1
							gpu_monitoring_PID=$!
						fi
					fi
					

					# Lauch simulation of replicate $r:
					$gmx_path -quiet mdrun \
					-s ../preparation_files/md.tpr \
					-deffnm md \
					-g mdrun.log \
					-dlb yes \
					-tunepme \
					-dd 0 0 0 \
					-ntmpi 1 \
					-pin on \
					$custom_params > stdout.out 2> stderr.out

					if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
						# Stop CPU monitoring:
						kill -TERM $cpu_monitoring_PID

						if [ "$ignore_GPU" == false ]; then
							# Stop GPU monitoring:
							kill -TERM $gpu_monitoring_PID
						fi
					fi

					# Process log file created by GROMACS:
					process_log_file
				done
			
			## Return to the working directory:
				cd $protein_path/$working_directory
		
		
		# Run tuning simulations:
			echo "RUNNING TUNING SIMULATIONS (EXPLORING ALL CPU-GPU LOAD BALANCES)"
			## Define devices to specify to GROMACS gmx:
				options_variable_flags=('cpu' 'gpu')
		
			## Iterate over all possible combinations of parameters to pass to GROMACS gmx:
				for nb in ${options_variable_flags[@]}; do
				for pme in ${options_variable_flags[@]}; do
				for pmefft in ${options_variable_flags[@]}; do
				for bonded in ${options_variable_flags[@]}; do
				for update in ${options_variable_flags[@]}; do
					
					# Skip combinations of CPU-GPU unloading that are not acceptable:
					if [[ "$update" == "gpu" && "$pme" == "cpu" && "$nb" == "cpu" ]]; then continue; fi
					if [[ "$bonded" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
					if [[ "$pmefft" == "gpu" && "$pme" == "cpu" ]]; then continue; fi
					if [[ "$pme" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
					
					# Create a directory for the simulation and get into that directory:
					simulation_directory="nb=$nb pme=$pme pmefft=$pmefft bonded=$bonded update=$update"
					eval "mkdir -p \"$simulation_directory\""
					cd "$simulation_directory"
					
					# Actually run the tuning simulations for currrent CPU-GPU load balance:
					for ((r = 1; r <= replicates; r++)); do
						# If energy consumption is to be benchmarked, launch CPU and GPU monitoring:
						if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
							# Launch CPU monitoring:
							cpu_monitoring $cpu_monitoring_freq_s $r & > /dev/null 2>&1
							cpu_monitoring_PID=$!

							if [ "$ignore_GPU" == false ]; then
								# Launch GPU monitoring:
								gpu_monitoring $gpu_monitoring_freq_s $r & > /dev/null 2>&1
								gpu_monitoring_PID=$!
							fi
						fi


						# Lauch simulation of replicate $r:
						variable_flags="-nb $nb -pme $pme -pmefft $pmefft -bonded $bonded -update $update"
						
						$gmx_path -quiet mdrun \
						-s ../preparation_files/md.tpr \
						-deffnm md \
						-g mdrun.log \
						-dlb yes \
						-tunepme \
						-ntomp_pme 0 \
						-dd 0 0 0 \
						-ntmpi 1 \
						-pin on \
						$variable_flags \
						$custom_params > stdout.out 2> stderr.out
						

						if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
							# Stop CPU monitoring:
							kill -TERM $cpu_monitoring_PID

							if [ "$ignore_GPU" == false ]; then
								# Stop GPU monitoring:
								kill -TERM $gpu_monitoring_PID
							fi
						fi

						# Process log file created by GROMACS:
						process_log_file
					done
					
					
					# Return to the working directory
						cd $protein_path/$working_directory
					
				done
				done
				done
				done
				done
		
		
		# Analyze performance data:
			echo "ANALIZING PERFORMANCE DATA"
			## Create associative arrays to store the final ranked results to user:
				# Performance - wall time:
				declare -A final_report_avg_wall_time_s
				declare -A final_report_sd_wall_time_s
				declare -A final_report_avg_wall_time_s_10k
				# Performance - ns/day:
				declare -A final_report_avg_ns_day
				declare -A final_report_sd_ns_day
				# Performance - hours/ns:
				declare -A final_report_avg_hour_ns
				declare -A final_report_sd_hour_ns
				# Energy - total:
				declare -A final_report_avg_total_energy_J
				declare -A final_report_sd_total_energy_J
				declare -A final_report_avg_total_energy_J_10k	
	
			## Analyze data of control simulation:
				# Stablish simulation directory to analyze:
					simulation_directory="nb=auto pme=auto pmefft=auto bonded=auto update=auto"
				
				# Analyze benchmark_mdrun.tsv:
					benchmark_mdrun_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_mdrun.tsv"
				
					# Get all the replicates results stored in benchmark_mdrun.tsv:
					while read -r wall_time_element ns_day_element hours_ns_element; do 
						all_wall_time_s+=("$wall_time_element")
						all_ns_day+=("$ns_day_element")
						all_hour_ns+=("$hours_ns_element")
					done < "$benchmark_mdrun_tsv"
					
					# Calculate the average and standard deviation of the wall time, ns/day, and hours/ns:
					## Wall time, average:
					mean "${all_wall_time_s[@]}"
					avg_wall_time_s=$(printf "%.3f" $mean_result)
					unset mean_result # unset reusable global variable for safety reasons
					## Wall time, standard deviation:
					std_dev_sample "${all_wall_time_s[@]}"
					sd_wall_time_s=$(printf "%.3f" $std_dev_sample_result)
					unset std_dev_sample_result # unset reusable global variable for safety reasons
					## Wall time, normalization by 10000 steps:
					avg_wall_time_s_10k=$(printf "%.2f" $(bc -l <<< "$avg_wall_time_s * 10000 / $steps"))
					## Save to final associative array for final ranked results:
					final_report_avg_wall_time_s["$simulation_directory"]="$avg_wall_time_s"
					final_report_sd_wall_time_s["$simulation_directory"]="$sd_wall_time_s"
					final_report_avg_wall_time_s_10k["$simulation_directory"]="$avg_wall_time_s_10k"
					
					## ns/day, average:
					mean "${all_ns_day[@]}"
					avg_ns_day=$(printf "%.3f" $mean_result)
					unset mean_result # unset reusable global variable for safety reasons
					## ns/day, standard deviation:
					std_dev_sample "${all_ns_day[@]}"
					sd_ns_day=$(printf "%.3f" $std_dev_sample_result)
					unset std_dev_sample_result # unset reusable global variable for safety reasons
					## Save to final associative array for final ranked results:
					final_report_avg_ns_day["$simulation_directory"]="$avg_ns_day"
					final_report_sd_ns_day["$simulation_directory"]="$sd_ns_day"
					
					## hours/ns, average:
					mean "${all_hour_ns[@]}"
					avg_hour_ns=$(printf "%.3f" $mean_result)
					unset mean_result # unset reusable global variable for safety reasons
					## hours/ns, standard deviation:
					std_dev_sample "${all_hour_ns[@]}"
					sd_hour_ns=$(printf "%.3f" $std_dev_sample_result)
					unset std_dev_sample_result # unset reusable global variable for safety reasons
					## Save to final associative array for final ranked results:
					final_report_avg_hour_ns["$simulation_directory"]="$avg_hour_ns"
					final_report_sd_hour_ns["$simulation_directory"]="$sd_hour_ns"
					
					# Unset reusable global variables for safety reasons:
					unset wall_time_element
					unset ns_day_element
					unset hours_ns_element
					
				# Analyze benchmark_cpu.tsv and, if applicable, benchmark_gpu.tsv
				# (Only if energy consumption was benchmarked, analyze CPU and GPU energy consumption):
					if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
						for (( r = 1; r <= replicates; r++ )); do
							benchmark_cpu_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_cpu.tsv"
							
							# Filter the results for replicate r:
							while read -r replicate power; do
								# Append only the powers of replica r to an array:
								if [ "$replicate" -eq "$r" ]; then
									all_cpu_power_r_W+=("$power")
								fi
							done < "$benchmark_cpu_tsv"
							
							# Calculate the mean power consumption for replicate r:
							mean "${all_cpu_power_r_W[@]}"
							all_avg_cpu_power_W+=( "$(printf "%.4f" "$mean_result")" )

							# Unset reusable global variables for safety reasons:
							unset replicate
							unset power
							unset all_cpu_power_r_W
							unset benchmark_cpu_tsv
							unset mean_result

							if [ "$ignore_GPU" == false ]; then
								benchmark_gpu_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_gpu.tsv"
								
								# Filter the results for replicate r:
								while read -r replicate power; do
									# Append only the powers of replica r to an array:
									if [ "$replicate" -eq "$r" ]; then
										all_gpu_power_r_W+=("$power")
									fi
								done < "$benchmark_gpu_tsv"
								
								# Calculate the mean power consumption for replicate r:
								mean "${all_gpu_power_r_W[@]}"
								all_avg_gpu_power_W+=( "$(printf "%.4f" "$mean_result")" )
								
								# Unset reusable global variables for safety reasons:
								unset replicate
								unset power
								unset all_gpu_power_r_W
								unset benchmark_gpu_tsv
								unset mean_result
							fi
						done
					fi
				
				
				# Summary of relevant variables created up to this point:
				## all_wall_time_s     : Array with runnning times of each replicate, in seconds
				## avg_wall_time_s     : Average running time over all replicates, in s
				## sd_wall_time_s      : Sample standard deviation of running time over all replicates, in s
				## all_ns_day          : Array with perfomances of each replicate, in nanoseconds per day
				## avg_ns_day          : Average performance over all replicates, in nanoseconds per day
				## sd_ns_day           : Sample standard deviation of performance over all replicates, in nanoseconds per day
				## all_hour_ns         : Array with performances of each replicate, in hours per nanosecond
				## avg_hour_ns         : Average performance over all replicates, in hours per nanosecond
				## sd_hour_ns          : Sample standard deviation of performance over all replicates, in hours per nanosecond
				## all_avg_cpu_power_W : Array of average CPU power consumptions of each replicate in W
				## all_avg_gpu_power_W : Array of average GPU power consumptions of each replicate in W
				
				# DEBUG PRINTING:
				if [ "$debug_printing" = true ]; then
					save_performance_debug "debug.out"
				fi
				
				if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
					# Calculate CPU energy consumption of each replicate:
					energy_consumption "${all_wall_time_s[@]}" "${all_avg_cpu_power_W[@]}"
					all_cpu_energy_J=("${energy_consumption_result[@]}")
					unset energy_consumption_result # unset reusable global variable for safety reasons
				
					# Calculate GPU energy consumption of each replicate:
						energy_consumption "${all_wall_time_s[@]}" "${all_avg_gpu_power_W[@]}"
						all_gpu_energy_J=("${energy_consumption_result[@]}")
						unset energy_consumption_result # unset reusable global variable for safety reasons
					
					# Calculate total (i.e. CPU + GPU) energy consumption of each replicate:
						all_total_energy_J=()
						for (( i = 0; i < replicates; i++ )); do 
							all_total_energy_J+=( $(bc -l <<< "${all_cpu_energy_J[i]} + ${all_gpu_energy_J[i]}") )
						done
					
					# Calculate average and standard deviation of CPU, GPU and total energies across replicates:
						## CPU, average:
						mean "${all_cpu_energy_J[@]}"
						avg_cpu_energy_J=$(printf "%.2f" $mean_result)
						unset mean_result
						## CPU, standard deviation:
						std_dev_sample "${all_cpu_energy_J[@]}"
						sd_cpu_energy_J=$(printf "%.2f" $std_dev_sample_result)
						unset std_dev_sample_result
						
						## GPU, average:
						mean "${all_gpu_energy_J[@]}"
						avg_gpu_energy_J=$(printf "%.2f" $mean_result)
						unset mean_result
						## GPU, standard deviation:
						std_dev_sample "${all_gpu_energy_J[@]}"
						sd_gpu_energy_J=$(printf "%.2f" $std_dev_sample_result)
						unset std_dev_sample_result
						
						## Total energy, average:
						mean "${all_total_energy_J[@]}"
						avg_total_energy_J=$(printf "%.2f" $mean_result)
						unset mean_result
						## Total energy, standard deviation:
						std_dev_sample "${all_total_energy_J[@]}"
						sd_total_energy_J=$(printf "%.2f" $std_dev_sample_result)
						unset std_dev_sample_result
						## Total energy, normalization by 10000 steps:
						avg_total_energy_J_10k=$(printf "%.1f" $(bc -l <<< "$avg_total_energy_J * 10000 / $steps"))
						## Save to final associative array for final ranked results:
						final_report_avg_total_energy_J["$simulation_directory"]="$avg_total_energy_J"
						final_report_sd_total_energy_J["$simulation_directory"]="$sd_total_energy_J"
						final_report_avg_total_energy_J_10k["$simulation_directory"]="$avg_total_energy_J_10k"
						
					# DEBUG PRINTING:
					if [ "$debug_printing" = true ]; then
						save_energy_debug "debug.out"
					fi
				fi
				
				## Save all relevant results to a file:
					save_analyzed_results "$protein_path/$working_directory/$simulation_directory/analyzed_results.tsv"
				
				## Unset reusable global variables for safety reasons:
					unset all_wall_time_s
					unset avg_wall_time_s
					unset sd_wall_time_s
					unset avg_wall_time_s_10k
					unset all_ns_day
					unset avg_ns_day
					unset all_hour_ns
					unset avg_hour_ns
					unset all_avg_cpu_power_W
					unset all_avg_gpu_power_W
					unset all_cpu_energy_J
					unset avg_cpu_energy_J
					unset sd_cpu_energy_J
					unset all_gpu_energy_J
					unset avg_gpu_energy_J
					unset sd_gpu_energy_J
					unset all_total_energy_J
					unset avg_total_energy_J
					unset sd_total_energy_J
					unset avg_total_energy_J_10k
					unset simulation_directory
					unset benchmark_mdrun_tsv
				
				
				
			## Analyze data of tuning simulations:
				# Define devices to specify to GROMACS gmx:
				options_variable_flags=('cpu' 'gpu')
			
				# Iterate over all possible combinations of parameters to pass to GROMACS gmx:
				for nb in ${options_variable_flags[@]}; do
				for pme in ${options_variable_flags[@]}; do
				for pmefft in ${options_variable_flags[@]}; do
				for bonded in ${options_variable_flags[@]}; do
				for update in ${options_variable_flags[@]}; do
					
					# Skip combinations of CPU-GPU unloading that are not acceptable:
					if [[ "$update" == "gpu" && "$pme" == "cpu" && "$nb" == "cpu" ]]; then continue; fi
					if [[ "$bonded" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
					if [[ "$pmefft" == "gpu" && "$pme" == "cpu" ]]; then continue; fi
					if [[ "$pme" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
					
					# Stablish simulation directory to analyze:
					simulation_directory="nb=$nb pme=$pme pmefft=$pmefft bonded=$bonded update=$update"
					
					# Analyze benchmark_mdrun.tsv:
					benchmark_mdrun_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_mdrun.tsv"
					
					# Get all the replicates results stored in benchmark_mdrun.tsv:
					while read -r wall_time_element ns_day_element hours_ns_element; do 
						all_wall_time_s+=("$wall_time_element")
						all_ns_day+=("$ns_day_element")
						all_hour_ns+=("$hours_ns_element")
					done < "$benchmark_mdrun_tsv"
					
					# Calculate the average and standard deviation of the wall time, ns/day, and hours/ns:
					## Wall time, average:
					mean "${all_wall_time_s[@]}"
					avg_wall_time_s=$(printf "%.3f" $mean_result)
					unset mean_result # unset reusable global variable for safety reasons
					## Wall time, standard deviation:
					std_dev_sample "${all_wall_time_s[@]}"
					sd_wall_time_s=$(printf "%.3f" $std_dev_sample_result)
					unset std_dev_sample_result # unset reusable global variable for safety reasons
					## Wall time, normalization by 10000 steps:
					avg_wall_time_s_10k=$(printf "%.2f" $(bc -l <<< "$avg_wall_time_s * 10000 / $steps"))
					## Save to final associative array for final ranked results:
					final_report_avg_wall_time_s["$simulation_directory"]="$avg_wall_time_s"
					final_report_sd_wall_time_s["$simulation_directory"]="$sd_wall_time_s"
					final_report_avg_wall_time_s_10k["$simulation_directory"]="$avg_wall_time_s_10k"
					
					## ns/day, average:
					mean "${all_ns_day[@]}"
					avg_ns_day=$(printf "%.3f" $mean_result)
					unset mean_result # unset reusable global variable for safety reasons
					## ns/day, standard deviation:
					std_dev_sample "${all_ns_day[@]}"
					sd_ns_day=$(printf "%.3f" $std_dev_sample_result)
					unset std_dev_sample_result # unset reusable global variable for safety reasons
					## Save to final associative array for final ranked results:
					final_report_avg_ns_day["$simulation_directory"]="$avg_ns_day"
					final_report_sd_ns_day["$simulation_directory"]="$sd_ns_day"
					
					## hours/ns, average:
					mean "${all_hour_ns[@]}"
					avg_hour_ns=$(printf "%.3f" $mean_result)
					unset mean_result # unset reusable global variable for safety reasons
					## hours/ns, standard deviation:
					std_dev_sample "${all_hour_ns[@]}"
					sd_hour_ns=$(printf "%.3f" $std_dev_sample_result)
					unset std_dev_sample_result # unset reusable global variable for safety reasons
					## Save to final associative array for final ranked results:
					final_report_avg_hour_ns["$simulation_directory"]="$avg_hour_ns"
					final_report_sd_hour_ns["$simulation_directory"]="$sd_hour_ns"
					
					# Unset reusable global variables for safety reasons:
					unset wall_time_element
					unset ns_day_element
					unset hours_ns_element
					
					# Analyze benchmark_cpu.tsv and, if applicable, benchmark_gpu.tsv
					# (Only if energy consumption was benchmarked, analyze CPU and GPU energy consumption):
						if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
							for (( r = 1; r <= replicates; r++ )); do
								benchmark_cpu_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_cpu.tsv"
								
								# Filter the results for replicate r:
								while read -r replicate power; do
									# Append only the powers of replica r to an array:
									if [ "$replicate" -eq "$r" ]; then
										all_cpu_power_r_W+=("$power")
									fi
								done < "$benchmark_cpu_tsv"
								
								# Calculate the mean power consumption for replicate r:
								mean "${all_cpu_power_r_W[@]}"
								all_avg_cpu_power_W+=( "$(printf "%.4f" "$mean_result")" )

								# Unset reusable global variables for safety reasons:
								unset replicate
								unset power
								unset all_cpu_power_r_W
								unset benchmark_cpu_tsv
								unset mean_result

								if [ "$ignore_GPU" == false ]; then
									benchmark_gpu_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_gpu.tsv"
									
									# Filter the results for replicate r:
									while read -r replicate power; do
										# Append only the powers of replica r to an array:
										if [ "$replicate" -eq "$r" ]; then
											all_gpu_power_r_W+=("$power")
										fi
									done < "$benchmark_gpu_tsv"
									
									# Calculate the mean power consumption for replicate r:
									mean "${all_gpu_power_r_W[@]}"
									all_avg_gpu_power_W+=( "$(printf "%.4f" "$mean_result")" )
									
									# Unset reusable global variables for safety reasons:
									unset replicate
									unset power
									unset all_gpu_power_r_W
									unset benchmark_gpu_tsv
									unset mean_result
								fi
							done
						fi
				
				# DEBUG PRINTING:
				if [ "$debug_printing" = true ]; then
					save_performance_debug "debug.out"
				fi
				
				if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
					# Calculate CPU energy consumption of each replicate:
						energy_consumption "${all_wall_time_s[@]}" "${all_avg_cpu_power_W[@]}"
						all_cpu_energy_J=("${energy_consumption_result[@]}")
						unset energy_consumption_result # unset reusable global variable for safety reasons
				
					# Calculate GPU energy consumption of each replicate:
						energy_consumption "${all_wall_time_s[@]}" "${all_avg_gpu_power_W[@]}"
						all_gpu_energy_J=("${energy_consumption_result[@]}")
						unset energy_consumption_result # unset reusable global variable for safety reasons
					
					# Calculate total (i.e. CPU + GPU) energy consumption of each replicate:
						all_total_energy_J=()
						for (( i = 0; i < replicates; i++ )); do 
							all_total_energy_J+=( $(bc -l <<< "${all_cpu_energy_J[i]} + ${all_gpu_energy_J[i]}") )
						done

					
					# Calculate average and standard deviation of CPU, GPU and total energies across replicates:
						## CPU, average:
						mean "${all_cpu_energy_J[@]}"
						avg_cpu_energy_J=$(printf "%.2f" $mean_result)
						unset mean_result
						## CPU, standard deviation:
						std_dev_sample "${all_cpu_energy_J[@]}"
						sd_cpu_energy_J=$(printf "%.2f" $std_dev_sample_result)
						unset std_dev_sample_result
						
						## GPU, average:
						mean "${all_gpu_energy_J[@]}"
						avg_gpu_energy_J=$(printf "%.2f" $mean_result)
						unset mean_result
						## GPU, standard deviation:
						std_dev_sample "${all_gpu_energy_J[@]}"
						sd_gpu_energy_J=$(printf "%.2f" $std_dev_sample_result)
						unset std_dev_sample_result
						
						## Total energy, average:
						mean "${all_total_energy_J[@]}"
						avg_total_energy_J=$(printf "%.2f" $mean_result)
						unset mean_result
						## Total energy, standard deviation:
						std_dev_sample "${all_total_energy_J[@]}"
						sd_total_energy_J=$(printf "%.2f" $std_dev_sample_result)
						unset std_dev_sample_result
						## Total energy, normalization by 10000 steps:
						avg_total_energy_J_10k=$(printf "%.1f" $(bc -l <<< "$avg_total_energy_J * 10000 / $steps"))
						## Save to final associative array for final ranked results:
						final_report_avg_total_energy_J["$simulation_directory"]="$avg_total_energy_J"
						final_report_sd_total_energy_J["$simulation_directory"]="$sd_total_energy_J"
						final_report_avg_total_energy_J_10k["$simulation_directory"]="$avg_total_energy_J_10k"
						
					# DEBUG PRINTING:
					if [ "$debug_printing" = true ]; then
						save_energy_debug "debug.out"
					fi
				fi
				
				# Save all relevant results to a file:
				save_analyzed_results "$protein_path/$working_directory/$simulation_directory/analyzed_results.tsv"

				# Unset reusable global variables for safety reasons:
				unset all_wall_time_s
				unset avg_wall_time_s
				unset sd_wall_time_s
				unset avg_wall_time_s_10k
				unset all_ns_day
				unset avg_ns_day
				unset all_hour_ns
				unset avg_hour_ns
				unset all_avg_cpu_power_W
				unset all_avg_gpu_power_W
				unset all_cpu_energy_J
				unset avg_cpu_energy_J
				unset sd_cpu_energy_J
				unset all_gpu_energy_J
				unset avg_gpu_energy_J
				unset sd_gpu_energy_J
				unset all_total_energy_J
				unset avg_total_energy_J
				unset sd_total_energy_J
				unset avg_total_energy_J_10k
				unset simulation_directory
				unset benchmark_mdrun_tsv
					
				done
				done
				done
				done
				done
		

		# Ranking results:
			## Sort based on performance (i.e. wall time):
				if [ "$debug_printing" == true ]; then
					echo "" >> debug.out
					echo "FINAL SORTED RESULTS - TIME PERFORMANCE:" >> debug.out
					echo "  UNSORTED (Avg. wall time ± SD):" >> debug.out
					for key in "${!final_report_avg_wall_time_s[@]}"; do
						echo -e "  $key\t(${final_report_avg_wall_time_s[$key]} s ± ${final_report_sd_wall_time_s[$key]} s)" >> debug.out
					done
				fi
				
				sorted_final_report_avg_wall_time_s=()
				min_key=""
				min_value=999999999999.9
				num_simulations="${#final_report_avg_wall_time_s[@]}"
				
				
				for (( i = 0; i < num_simulations; i++ )); do
					for key in "${!final_report_avg_wall_time_s[@]}"; do
						# Check if the current key has been found before:
						if [[ "${sorted_final_report_avg_wall_time_s[@]}" =~ "$key" ]]; then
							continue
						fi
						
						# Get value:
						value=${final_report_avg_wall_time_s["$key"]}
						
						# Compare value with min_value, and update if needed:
						if [[ $(echo "$value < $min_value" | bc) -eq 1 ]]; then 
							min_key=$key
							min_value=$value
						fi
					done
					
					# Append the locally found minimum key to
					sorted_final_report_avg_wall_time_s+=("$min_key")
					
					# Unset reusable global variables for safety reasons:
					unset value
					unset min_key
					
					# Reset min_value
					min_value=999999999999.9
					
				done
				
				# Unset reusable global variables for safety reasons:
				unset num_simulations
				
				if [ "$debug_printing" == true ]; then
					echo "  SORTED (Avg. wall time ± SD):" >> debug.out
					for key in "${sorted_final_report_avg_wall_time_s[@]}"; do
						echo -e "  $key\t(${final_report_avg_wall_time_s[$key]} s ± ${final_report_sd_wall_time_s[$key]} s)" >> debug.out
					done
				fi
		
			## Sort based on energy:
				if [ "$debug_printing" == true ]; then
					echo "" >> debug.out
					echo "FINAL SORTED RESULTS - ENERGY CONSUMPTION:" >> debug.out
					echo "  UNSORTED (Avg. energy consumed ± SD):" >> debug.out
					for key in "${!final_report_avg_total_energy_J[@]}"; do
						echo -e "  $key\t(${final_report_avg_total_energy_J["$key"]} J ± ${final_report_sd_total_energy_J[$key]} J)" >> debug.out
					done
				fi
				
				sorted_final_report_avg_total_energy_J=()
				min_key=""
				min_value=999999999999.9
				num_simulations="${#final_report_avg_total_energy_J[@]}"
				
				
				for (( i = 0; i < num_simulations; i++ )); do
					for key in "${!final_report_avg_total_energy_J[@]}"; do
						# Check if the current key has been found before:
						if [[ "${sorted_final_report_avg_total_energy_J[@]}" =~ "$key" ]]; then
							continue
						fi
						
						# Get value:
						value=${final_report_avg_total_energy_J["$key"]}
						
						# Compare value with min_value, and update if needed:
						if [[ $(echo "$value < $min_value" | bc) -eq 1 ]]; then 
							min_key=$key
							min_value=$value
						fi
					done
					
					# Append the locally found minimum key to
					sorted_final_report_avg_total_energy_J+=("$min_key")
					
					# Unset reusable global variables for safety reasons:
					unset value
					unset min_key
					
					# Reset min_value
					min_value=999999999999.9
					
				done
				
				# Unset reusable global variables for safety reasons:
				unset num_simulations
				
				if [ "$debug_printing" == true ]; then
					echo "  SORTED (Avg. energy consumed ± SD):" >> debug.out
					for key in "${sorted_final_report_avg_total_energy_J[@]}"; do
						echo -e "  $key\t(${final_report_avg_total_energy_J[$key]} J ± ${final_report_sd_total_energy_J[$key]} J)" >> debug.out
					done
				fi
		
		# Saving ranked results:
			echo "SAVING RESULTS"
			
			cd "$protein_path"
			final_results_file="$app_name-Final_results-$protein_name-$datetime.txt"
			
			datetime_formatted=$(date +'%Y-%m-%d %H:%M:%S UTC%Z')
			
			echo "************************** $app_name **************************" >> "$final_results_file"
			echo ""                             >> "$final_results_file"
			echo "PROTEIN: $protein_name"       >> "$final_results_file"
			echo "PATH:    $protein_path"       >> "$final_results_file"
			echo "TIME:    $datetime_formatted" >> "$final_results_file"
			echo ""                             >> "$final_results_file"
			
			echo "SIMULATION PARAMETERS:" >> "$final_results_file"
			
			if [ "$no_gui" == true ]; then
				echo "Terminal/GUI:                    terminal mode" >> "$final_results_file"
			else
				echo "Terminal/GUI:                    GUI mode" >> "$final_results_file"
			fi
			
			echo "Benchmark:                       $benchmark"              >> "$final_results_file"
			echo "Steps simulated (per replicate): $steps"                  >> "$final_results_file"
			echo "Replicates:                      $replicates"             >> "$final_results_file"
			echo "Preserve intermediate files:     $preserve_gromacs_files" >> "$final_results_file"
			echo "Custom GROMACS parameters:      $custom_params"          >> "$final_results_file"
			echo ""                                                         >> "$final_results_file"
			
			echo "RANKED RESULTS - TIME PERFORMANCE" >> "$final_results_file"
			
			printf "%-4s%-54s%-27s" "" "CPU-GPU task load balance" "Avg. wall time (±SD) (s)" >> "$final_results_file"
			printf "%-29s" "Wall time per 10k steps (s)"                                      >> "$final_results_file"
			printf "%-34s" "Avg. performance (±SD) (ns/day)"                                  >> "$final_results_file"
			printf "%-29s\n" "Avg. performance (±SD) (h/ns)"                                  >> "$final_results_file"
			
			iteration=1
			for key in "${sorted_final_report_avg_wall_time_s[@]}"; do
				printf "%02g) %-54s%-27s" "$iteration" "$key" "${final_report_avg_wall_time_s[$key]} (±${final_report_sd_wall_time_s[$key]})" >> "$final_results_file"
				printf "%-29s" "${final_report_avg_wall_time_s_10k[$key]}"                                                                    >> "$final_results_file"
				printf "%-34s" "${final_report_avg_ns_day[$key]} (±${final_report_sd_ns_day[$key]})"                                          >> "$final_results_file"
				printf "%-29s\n" "${final_report_avg_hour_ns[$key]} (±${final_report_sd_hour_ns[$key]})"                                      >> "$final_results_file"
				((iteration++))
			done
			
			echo "" >> "$final_results_file"
			
			if [ "$benchmark" == "time_energy" ]; then
				echo "RANKED RESULTS - ENERGY CONSUMPTION" >> "$final_results_file"
			
				printf "%-4s%-54s%-30s" "" "CPU-GPU task load balance" "Avg. total energy (±SD) (J)"   >> "$final_results_file"
				printf "%-30s\n" "Total energy per 10k steps (J)"                                 >> "$final_results_file"
				
				iteration=1
				for key in "${sorted_final_report_avg_total_energy_J[@]}"; do
					#~ echo "  Entering for loop to write ranked energy results"
					printf "%02g) %-54s%-30s" "$iteration" "$key" "${final_report_avg_total_energy_J[$key]} (±${final_report_sd_total_energy_J[$key]})" >> "$final_results_file"
					printf "%-30s\n" "${final_report_avg_total_energy_J_10k[$key]}"                                                                     >> "$final_results_file"
					((iteration++))
				done
			fi
			echo "" >> "$final_results_file"
			
			echo "NOTES:" >> "$final_results_file"
			echo "  All the results showed above were calculated across the replicates selected by the user." >> "$final_results_file"
			echo "  SD: standard deviation of the sample." >> "$final_results_file"
			echo "  Avg. wall time: Average of wall time that the production run took, given the number of steps set by the user." >> "$final_results_file"
			echo "  Wall time per 10k steps: Estimated wall time of production run, per each 10,000 simulation steps." >> "$final_results_file"
			echo "  Avg. performance (ns/day): Average performance of production run, expressed as nanoseconds of simulation per wall time days." >> "$final_results_file"
			echo "  Avg. performance (h/ns): Average performance of production run, expressed as wall time hours per nanoseconds of simulation." >> "$final_results_file"
			if [ "$benchmark" == "time_energy" ]; then
				echo "  Avg. total energy: Average of total (CPU+GPU) energy consumption of the production run, given the number of steps set by the user." >> "$final_results_file"
				echo "  Avg. total energy per 10k steps: Estimated total (CPU+GPU) energy consumption of the production run, per each 10,000 simulation steps." >> "$final_results_file"
			fi
			echo "" >> "$final_results_file"
		
		
		# Restoring permits to user:
		echo "RESTORING PERMITS TO USER"
		if [ "$run_without_root" == false ]; then
			sudo chown -R $(logname):$(id -gn $(logname)) "$protein_path/$working_directory"
			sudo chown $(logname):$(id -gn $(logname)) "$protein_path/$final_results_file"
		fi

		
		# Cleaning intermediate files:
			echo "HANDLING INTERMENDIATE FILES"
			if [ "$preserve_gromacs_files" == false ]; then
				rm -rf "$protein_path/$working_directory"
			fi
		
		# Exit script executed in terminal mode:
		exit 0
	fi


# LAUNCH LANDING GUI:
	if [ $no_gui == false ]; then
		## Adjust the available benchmarks according to the root privileges:
		if [ "$run_without_root" == true ]; then
			options_benchmark=$(echo "Time performance")
		else
			options_benchmark=$(echo "Time performance and energy consumption!Time performance")
		fi

		## Show the landing GUI:
		GUI_parameters=$(yad --width=600 \
			--title="$app_name" \
			--form \
			--field="Protein:FL" \
			--field="Benchmark:CB" \
			--field="Steps to simulate (per replicate):NUM" \
			--field="Replicates:NUM" \
			--field="Custom GROMACS mdrun parameters:TXT" \
			--field="Preserve intermediate files:CHK" \
			"" "$options_benchmark" "2000" "3" "" "FALSE")
			
			#~ Backup version with optional ignore GPU and save results to a file
			#~ GUI_parameters=$(yad --width=600 \
			#~ --title="$app_name" \
			#~ --form \
			#~ --field="Protein:FL" \
			#~ --field="Benchmark:CB" \
			#~ --field="Steps to simulate (per replicate):NUM" \
			#~ --field="Replicates:NUM" \
			#~ --field="Custom GROMACS mdrun parameters:TXT" \
			#~ --field="Ignore GPU (benchmark only on CPU):CHK" \
			#~ --field="Save results to a file:CHK" \
			#~ --field="Preserve intermediate GROMACS files:CHK" \
			#~ "" "$options_benchmark" "2000" "3" "" "FALSE" "TRUE" "FALSE")

		## Guard in case the user selects the Cancel buttom of the landing GUI:
		exit_status=$?
		if [ "$exit_status" -ne 0 ]; then
			echo "Execution aborted by user"
			exit 0
		fi
		
		## Parse the GUI parameters selected by user:
		### Extract the values of GUI_parameters into an array:
		original_IFS=$IFS
		IFS="|"
		read -ra parsed_parameters <<< "$GUI_parameters"
		IFS=$original_IFS
		
		### Traverse the array of parsed parameters and assign the values into corresponding variables:
		iteration=0
		for value in "${parsed_parameters[@]}"; do
			case $iteration in
				0) 
					protein=$value
					# Validate protein:
						if [ -z "$protein" ];then
							yad --width=400 --height=100 \
								--center \
								--title="$app_name - Error" \
								--image=dialog-error \
								--button=Close:0 \
								--text="ERROR: Invalid protein\nCheck that a valid file is entered in the field 'Protein'."
							exit 1
						fi
					protein_name=$(basename "$protein")
					protein_path=$(dirname "$protein")
					;;
				1)
					benchmark=$value
					;;
				2)
					steps=$value
					# Validate number of steps:
						## Steps is 0 or negative:
						if [ "$steps" -le 0 ];then
							yad --width=400 --height=100 \
								--center \
								--title="$app_name - Error" \
								--image=dialog-error \
								--button=Close:0 \
								--text="ERROR: Invalid number of steps\nCheck that an integer number greater than 0 is entered in the field 'Steps'."
							exit 1
						fi

						## Number of steps potentially too small:
						if [ "$steps" -lt 1000 ];then
							yad --width=400 --height=100 \
								--center \
								--title="$app_name - Warning" \
								--image=dialog-warning \
								--button=Close:0 \
								--text="Warning: Number of steps potentially too small\nNote that using a small number of steps might cause errors during the simulations."
						fi
					;;
				3)
					replicates=$value
					# Validate number of replicates:
						## Steps is 0 or negative:
						if [ "$replicates" -le 0 ];then
							yad --width=400 --height=100 \
								--center \
								--title="$app_name - Error" \
								--image=dialog-error \
								--button=Close:0 \
								--text="ERROR: Invalid number of replicates\nCheck that an integer number greater than 0 is entered in the field 'Replicates'."
							exit 1
						fi

						## Number of replicates potentially too small:
						if [ "$replicates" -lt 3 ];then
							yad --width=400 --height=100 \
								--center \
								--title="$app_name - Warning" \
								--image=dialog-warning \
								--button=Close:0 \
								--text="Warning: Number of replicates potentially too small\nNote that results using a small number of replicates might be inaccurate and unreliable."
						fi
					;;
				4)
					custom_params=$value
					;;
				#~ 5)
					#~ if [ "$value" == "TRUE" ]; then
						#~ ignore_GPU=true
					#~ else
						#~ ignore_GPU=false
					#~ fi
					#~ ;;
				#~ 6)
					#~ if [ "$value" == "TRUE" ]; then
						#~ save_results=true
					#~ else
						#~ save_results=false
					#~ fi
					#~ ;;
				5)
					if [ "$value" == "TRUE" ]; then
						preserve_gromacs_files=true
					else
						preserve_gromacs_files=false
					fi
					;;
			esac
			((iteration++))
		done
	fi 



# LAUNCH PROGRESS GUI:
	(
	echo "1"
	echo "# Creating working directory"
		cd $protein_path
		datetime=$(date +%Y%m%d_%H%M%S%Z)
		working_directory="$protein_name-simulation-$datetime"
		mkdir -p "$working_directory"

	echo "2"
	echo "# Extracting atoms from protein"
		grep ^ATOM "$protein" > "$working_directory/clean_protein.pdb"
		cd "$working_directory"

	echo "3"
	echo "# Searching for available force fields and water models"
		### First, use the first option of force field and water model available, whichever they are:
		printf "1\n1" | $gmx_path -quiet pdb2gmx \
						-f clean_protein.pdb \
						-o protein.gro \
						-ignh > stdout.out 2> stderr.out
		### Validate if last command was successfully executed:
		exit_status=$?
		### Delete unnecesary files, while preserving only the ones with the redirected stdout and stderr:
		rm posre.itp protein.gro topol.top
		### Handle case where pdb2gmx ended with error:
		validate_exit_status
		
		### Get force fields available in stdout.out:
			# Search for the line containing "Select the Force Field:":
			start_line=$(grep -n "Select the Force Field:" stdout.out | cut -d: -f1)
			# Calculate the line where the actual options begin:
			current_line=$((start_line + 4)) # actual options begin 4 lines below 

			# Iterate over the lines until an invalid option is found:
			is_valid_option=true
			while [ "$is_valid_option" == true ]; do
				# Read line:
				line=$(sed -n "${current_line}p" stdout.out)
				trimmed_line="${line#"${line%%[![:space:]]*}"}"
			
				# Check if the trimmed line starts with a number followed by ":":
				if [[ $trimmed_line =~ ^[0-9]+: ]]; then
					# Get the option number and force field name:
					option_number=$(echo "$trimmed_line" | sed 's/^\([0-9]\+\): \(.*\)/\1/')
					option_name=$(echo "$trimmed_line" | sed 's/^\([0-9]\+\): \(.*\)/\2/')

					# Save the force field options into a file:
					echo "$option_number" >> force_field_options.out
					echo "$option_name" >> force_field_options.out
					## Replace the ampersand symbols (&) in the file to avoid GTK warnings
					sed -i 's/&/and/g' force_field_options.out

					# Update the line number (jump two lines below):
					((current_line+=2))
				else
					# Handle case when the line is no longer a force field option:
					is_valid_option==false
				fi
			done

		### Get water models available in stdout.out:
			# Search for the line containing "Select the Water Model:":
			start_line=$(grep -n "Select the Water Model:" stdout.out | cut -d: -f1)
			# Calculate the line where the actual options begin:
			current_line=$((start_line + 2)) # actual options begin 2 lines below 

			# Iterate over the lines until an invalid option is found:
			is_valid_option=true
			while [ "$is_valid_option" == true ]; do
				# Read line:
				line=$(sed -n "${current_line}p" stdout.out)
				trimmed_line="${line#"${line%%[![:space:]]*}"}"
			
				# Check if the trimmed line starts with a number followed by ":":
				if [[ $trimmed_line =~ ^[0-9]+: ]]; then
					# Get the option number and water model name:
					option_number=$(echo "$trimmed_line" | sed 's/^\([0-9]\+\): \(.*\)/\1/')
					option_name=$(echo "$trimmed_line" | sed 's/^\([0-9]\+\): \(.*\)/\2/')

					# Save the water model options into a file:
					echo "$option_number" >> water_model_options.out
					echo "$option_name" >> water_model_options.out
					## Duplicate the ampersands in the file to avoy GTK warnings
					sed -i 's/&/and/g' water_model_options.out
					
					# Update the line number:
					((current_line+=2))
				else
					# Handle case when the line is no longer a water model option:
					is_valid_option==false
				fi
			done

		### Ask the user to select the force field to use:
			force_field_selected=$(yad --width=750 --height=550 \
									--list --title="$app_name - Select force field to use" \
									--hide-column=1 \
									--column="Option" \
									--column="Force fields available" \
									< force_field_options.out)

		### Parse the option number to pass to Gromacs:
			if [[ $force_field_selected =~ ^([0-9]+) ]]; then
				force_field_option="${BASH_REMATCH[1]}"
			else
				echo "ERROR: Invalid force field."
				exit 1
			fi

		### Ask the user to select the water model to use:
			water_model_selected=$(yad --width=550 --height=350 \
									--list --title="$app_name - Select water model to use" \
									--hide-column=1 \
									--column="Option" \
									--column="Water models available" \
									< water_model_options.out)

		### Parse the option number to pass to Gromacs:
			if [[ $force_field_selected =~ ^([0-9]+) ]]; then
				water_model_option="${BASH_REMATCH[1]}"
			else
				echo "ERROR: Invalid water model."
				exit 1
			fi

		### Remove temporary files storing force fields and water models options:
			rm force_field_options.out water_model_options.out
		

	echo "4"
	echo "# Creating coordinates and topology files"
		printf "$force_field_option\n$water_model_option" | $gmx_path -quiet pdb2gmx \
															-f clean_protein.pdb \
															-o protein.gro \
															-ignh > stdout.out 2> stderr.out

		### Get and validate that the last command was successfully executed:
		exit_status=$?
		validate_exit_status

	
	echo "5"
	echo "# Creating simulation box"
		$gmx_path -quiet editconf \
		-f protein.gro \
		-o protein_box.gro \
		-c -d 1.0 \
		-bt dodecahedron > stdout.out 2> stderr.out

		### Get and validate that the last command was successfully executed:
		exit_status=$?
		validate_exit_status


	echo "6"
	echo "# Solvating the system"
		$gmx_path -quiet solvate \
		-cp protein_box.gro \
		-cs spc216.gro \
		-o protein_solv.gro \
		-p topol.top > stdout.out 2> stderr.out

		### Get and validate that the last command was successfully executed:
		exit_status=$?
		validate_exit_status


	echo "7"
	echo "# Adding ions to the system to neutralize it"
	#TODO: document where the .mdp files are searched by default (parent folder and mdp folder in parent folder)
		### Search for the file 'ions.mdp':
			# Where the starting protein is:
			if [[ -f "$protein_path/ions.mdp" ]]; then
				ions_mdp_file="$protein_path/ions.mdp"
			# In a folder called 'mdp' where the starting protein is:
			elif [[ -f "$protein_path/mdp/ions.mdp" ]]; then
				ions_mdp_file="$protein_path/mdp/ions.mdp"
			# If 'ions.mdp' was not found, then ask user to manually provide the path:
			else
				ions_mdp_file=$(yad --width=600 \
									--title="$app_name" \
									--text="A file 'ions.mdp' was not found.\nPlease select the molecular dynamics parameter to use for neutralization (.mdp)." \
									--form \
									--field=".mdp for neutralization:FL" \
									"")
				# Remove the field separator '|' of yad:
				ions_mdp_file="${ions_mdp_file%|}"
			fi
		
		### Check if `ions_mdp_file` was successfully created, and exit if not:
			if [ ! -f "$ions_mdp_file" ]; then
				yad --title="Error" \
					--image=dialog-error \
					--button=Close:0 \
					--center \
					--text="ERROR\nThe file with molecular dynamics parameters (.mpd) was not found.\nIt is not possible to proceed with the addition of ions to the system."
				exit 1
			fi
		
		

		### Proceed to add ions:
			# Pre-process:
				$gmx_path -quiet grompp \
				-f "$ions_mdp_file" \
				-c protein_solv.gro \
				-p topol.top \
				-o ions.tpr > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status

			# Actually add ions:
				# TODO: make this option "13" dynamic, according to the version of GROMACS
				# 13: SOL
				printf "13" | $gmx_path -quiet genion \
							  -s ions.tpr \
							  -o protein_ions.gro \
							  -p topol.top \
							  -pname NA -nname CL \
							  -neutral \
							  -conc 0.15 > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status


	echo "8"
	echo "# Minimizing energy"
		### Search for the file 'minim.mdp':
			# Where the starting protein is:
			if [[ -f "$protein_path/minim.mdp" ]]; then
				minim_mdp_file="$protein_path/minim.mdp"
			# In a folder called 'mdp' where the starting protein is:
			elif [[ -f "$protein_path/mdp/minim.mdp" ]]; then
				minim_mdp_file="$protein_path/mdp/minim.mdp"
			# If 'minim.mdp' was not found, then ask user to manually provide the path:
			else
				minim_mdp_file=$(yad --width=600 \
									 --title="$app_name" \
									 --text="A file 'minim.mdp' was not found.\nPlease select the molecular dynamics parameter to use for the energy minimization (.mdp)." \
									 --form \
									 --field=".mdp for energy minimization:FL" \
									 "")
				# Remove the field separator '|' of yad:
				minim_mdp_file="${minim_mdp_file%|}"
			fi
		
		### Check if `minim_mdp_file` was successfully created, and exit if not:
			if [ ! -f "$minim_mdp_file" ]; then
				yad --title="Error" \
					--image=dialog-error \
					--button=Close:0 \
					--center \
					--text="ERROR\nThe file with molecular dynamics parameters (.mpd) was not found.\nIt is not possible to proceed with energy minimization of the system."
				exit 1
			fi
		
		### Proceed with energy minimization:
			# Pre-process:
				$gmx_path -quiet grompp \
				-f "$minim_mdp_file" \
				-c protein_ions.gro \
				-p topol.top \
				-o em.tpr > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status

			# Actually minimize the energy of the system:
				$gmx_path -quiet mdrun -deffnm em > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status


	echo "9"
	echo "# Saving evolution of potential energy during energy minimization"
		# TODO: make this option "10" dynamic, according to the version of GROMACS
		# 10: potential energy
		printf "10\n0" | $gmx_path -quiet energy \
							-f em.edr \
							-o em_potential.xvg > stdout.out 2> stderr.out

		# Get and validate that the last command was successfully executed:
			exit_status=$?
			validate_exit_status


	echo "10"
	echo "# Running NVT equilibration"
		### Search for the file 'nvt.mdp':
			# Where the starting protein is:
			if [[ -f "$protein_path/nvt.mdp" ]]; then
				nvt_mdp_file="$protein_path/nvt.mdp"
			# In a folder called 'mdp' where the starting protein is:
			elif [[ -f "$protein_path/mdp/nvt.mdp" ]]; then
				nvt_mdp_file="$protein_path/mdp/nvt.mdp"
			# If 'nvt.mdp' was not found, then ask user to manually provide the path:
			else
				nvt_mdp_file=$(yad --width=600 \
									 --title="$app_name" \
									 --text="A file 'nvt.mdp' was not found.\nPlease select the molecular dynamics parameter to use for the NVT equilibration (.mdp)." \
									 --form \
									 --field=".mdp for NVT equilibration:FL" \
									 "")
				# Remove the field separator '|' of yad:
				nvt_mdp_file="${nvt_mdp_file%|}"
			fi
		
		### Check if `nvt_mdp_file` was successfully created, and exit if not:
			if [ ! -f "$nvt_mdp_file" ]; then
				yad --title="Error" \
					--image=dialog-error \
					--button=Close:0 \
					--center \
					--text="ERROR\nThe file with molecular dynamics parameters (.mpd) was not found.\nIt is not possible to proceed with the NVT equilibration."
				exit 1
			fi

		### Update the number of steps as per preference of user:
			replace_nsteps "$nvt_mdp_file" "$steps"

		### Proceed with NVT equilibration:
			# Pre-process:
				$gmx_path -quiet grompp \
				-f "$nvt_mdp_file" \
				-c em.gro \
				-r em.gro \
				-p topol.top \
				-o nvt.tpr > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status

			# Actually run NVT minimization:
				$gmx_path -quiet mdrun -deffnm nvt > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status


	echo "11"
	echo "# Saving evolution of temperature during NVT equilibration"
		# TODO: make this options "16" dynamic, according to the version of GROMACS
		printf "16\n0" | $gmx_path -quiet energy \
							-f nvt.edr \
							-o nvt_temperature.xvg > stdout.out 2> stderr.out

		# Get and validate that the last command was successfully executed:
			exit_status=$?
			validate_exit_status
				

	echo "12"
	echo "# Running NPT equilibration"
		### Search for the file 'npt.mdp':
			# Where the starting protein is:
			if [[ -f "$protein_path/npt.mdp" ]]; then
				npt_mdp_file="$protein_path/npt.mdp"
			# In a folder called 'mdp' where the starting protein is:
			elif [[ -f "$protein_path/mdp/npt.mdp" ]]; then
				npt_mdp_file="$protein_path/mdp/npt.mdp"
			# If 'npt.mdp' was not found, then ask user to manually provide the path:
			else
				npt_mdp_file=$(yad --width=600 \
									 --title="$app_name" \
									 --text="A file 'npt.mdp' was not found.\nPlease select the molecular dynamics parameter to use for the NPT equilibration (.mdp)." \
									 --form \
									 --field=".mdp for NPT equilibration:FL" \
									 "")
				# Remove the field separator '|' of yad:
				npt_mdp_file="${npt_mdp_file%|}"
			fi
		
		### Check if `npt_mdp_file` was successfully created, and exit if not:
			if [ ! -f "$npt_mdp_file" ]; then
				yad --title="Error" \
					--image=dialog-error \
					--button=Close:0 \
					--center \
					--text="ERROR\nThe file with molecular dynamics parameters (.mpd) was not found.\nIt is not possible to proceed with the NPT equilibration."
				exit 1
			fi

		### Update the number of steps as per preference of user:
			replace_nsteps "$npt_mdp_file" "$steps"

		### Proceed with NPT equilibration:
			# Pre-process:
				$gmx_path -quiet grompp \
				-f "$npt_mdp_file" \
				-c nvt.gro \
				-r nvt.gro \
				-t nvt.cpt \
				-p topol.top \
				-o npt.tpr > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status

			# Actually run NPT minimization:
				$gmx_path -quiet mdrun -deffnm npt > stdout.out 2> stderr.out

			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status
					

	echo "13"
	echo "# Saving evolution of pressure and density during NPT equilibration"
		# TODO: make these options "18" and "24" dynamic, according to the version of GROMACS
		printf "18\n0" | $gmx_path -quiet energy \
							-f npt.edr \
							-o npt_pressure.xvg > stdout.out 2> stderr.out
		# Get and validate that the last command was successfully executed:
		exit_status=$?
		validate_exit_status
			
		printf "24\n0" | $gmx_path -quiet energy \
									-f npt.edr \
									-o npt_density.xvg > stdout.out 2> stderr.out
		# Get and validate that the last command was successfully executed:
		exit_status=$?
		validate_exit_status
	

	echo "14"
	echo "# Pre-processing system for production runs"
		### Search for the file 'md.mdp':
			# Where the starting protein is:
			if [[ -f "$protein_path/md.mdp" ]]; then
				md_mdp_file="$protein_path/md.mdp"
			# In a folder called 'mdp' where the starting protein is:
			elif [[ -f "$protein_path/mdp/md.mdp" ]]; then
				md_mdp_file="$protein_path/mdp/md.mdp"
			# If 'md.mdp' was not found, then ask user to manually provide the path:
			else
				md_mdp_file=$(yad --width=600 \
					--title="$app_name" \
					--text="A file 'md.mdp' was not found.\nPlease select the molecular dynamics parameter to use for the simulation runs (.mdp)." \
					--form \
					--field=".mdp for molecular dynamics simulation runs:FL" \
					"")
				# Remove the field separator '|' of yad:
				md_mdp_file="${md_mdp_file%|}"
			fi
		
		### Check if `md_mdp_file` was successfully created, and exit if not:
			if [ ! -f "$md_mdp_file" ]; then
				yad --title="Error" \
					--image=dialog-error \
					--button=Close:0 \
					--center \
					--text="ERROR\nThe file with molecular dynamics parameters (.mpd) was not found.\nIt is not possible to proceed with the pre-processing of the system."
				exit 1
			fi

		### Update the number of steps as per preference of user:
			replace_nsteps "$md_mdp_file" "$steps"

		### Actually pre-process for production runs:
			$gmx_path -quiet grompp \
			-f "$md_mdp_file" \
			-c npt.gro \
			-t npt.cpt \
			-p topol.top \
			-o md.tpr > stdout.out 2> stderr.out
			
			# Get and validate that the last command was successfully executed:
				exit_status=$?
				validate_exit_status


	echo "15"
	echo "# Saving preparation files to new directory"
		mkdir -p 'preparation_files'
		mv -f $(ls clean_protein.pdb *.edr *.gro *.log *.tpr *.trr *.itp *.top *.cpt *.mdp *.xvg *.out) preparation_files


	echo "16"
	echo "# Running control simulations"
		### Create directory for control simulation (auto CPU-GPU balancing):
			simulation_directory="nb=auto pme=auto pmefft=auto bonded=auto update=auto"
			eval "mkdir -p \"$simulation_directory\""
			cd "$simulation_directory"

		### Actually run the control replicates (auto CPU-GPU balancing):
			for ((r = 1; r <= replicates; r++)); do
				# If energy consumption is to be benchmarked, launch CPU and GPU monitoring:
				if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
					# Launch CPU monitoring:
					cpu_monitoring $cpu_monitoring_freq_s $r & > /dev/null 2>&1
					cpu_monitoring_PID=$!

					if [ "$ignore_GPU" == false ]; then
						# Launch GPU monitoring:
						gpu_monitoring $gpu_monitoring_freq_s $r & > /dev/null 2>&1
						gpu_monitoring_PID=$!
					fi
				fi
				

				# Lauch simulation of replicate $r:
				$gmx_path -quiet mdrun \
				-s ../preparation_files/md.tpr \
				-deffnm md \
				-g mdrun.log \
				-dlb yes \
				-tunepme \
				-dd 0 0 0 \
				-ntmpi 1 \
				-pin on \
				$custom_params > stdout.out 2> stderr.out

				if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
					# Stop CPU monitoring:
					kill -TERM $cpu_monitoring_PID

					if [ "$ignore_GPU" == false ]; then
						# Stop GPU monitoring:
						kill -TERM $gpu_monitoring_PID
					fi
				fi

				# Process log file created by GROMACS:
				process_log_file
			done
		
		### Return to the working directory:
			cd $protein_path/$working_directory
	
	echo "17"
	echo "# Running tuning simulations (exploring all CPU-GPU load balances)"
		### Define devices to specify to GROMACS gmx:
			options_variable_flags=('cpu' 'gpu')
		
		### Iterate over all possible combinations of parameters to pass to GROMACS gmx:
			for nb in ${options_variable_flags[@]}; do
			for pme in ${options_variable_flags[@]}; do
			for pmefft in ${options_variable_flags[@]}; do
			for bonded in ${options_variable_flags[@]}; do
			for update in ${options_variable_flags[@]}; do
				
				# Skip combinations of CPU-GPU unloading that are not acceptable:
				if [[ "$update" == "gpu" && "$pme" == "cpu" && "$nb" == "cpu" ]]; then continue; fi
				if [[ "$bonded" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
				if [[ "$pmefft" == "gpu" && "$pme" == "cpu" ]]; then continue; fi
				if [[ "$pme" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
				
				# Create a directory for the simulation and get into that directory:
				simulation_directory="nb=$nb pme=$pme pmefft=$pmefft bonded=$bonded update=$update"
				eval "mkdir -p \"$simulation_directory\""
				cd "$simulation_directory"
				
				# Actually run the tuning simulations for currrent CPU-GPU load balance:
				for ((r = 1; r <= replicates; r++)); do
					# If energy consumption is to be benchmarked, launch CPU and GPU monitoring:
					if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
						# Launch CPU monitoring:
						cpu_monitoring $cpu_monitoring_freq_s $r & > /dev/null 2>&1
						cpu_monitoring_PID=$!

						if [ "$ignore_GPU" == false ]; then
							# Launch GPU monitoring:
							gpu_monitoring $gpu_monitoring_freq_s $r & > /dev/null 2>&1
							gpu_monitoring_PID=$!
						fi
					fi


					# Lauch simulation of replicate $r:
					variable_flags="-nb $nb -pme $pme -pmefft $pmefft -bonded $bonded -update $update"
					
					$gmx_path -quiet mdrun \
					-s ../preparation_files/md.tpr \
					-deffnm md \
					-g mdrun.log \
					-dlb yes \
					-tunepme \
					-ntomp_pme 0 \
					-dd 0 0 0 \
					-ntmpi 1 \
					-pin on \
					$variable_flags \
					$custom_params > stdout.out 2> stderr.out
					

					if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
						# Stop CPU monitoring:
						kill -TERM $cpu_monitoring_PID

						if [ "$ignore_GPU" == false ]; then
							# Stop GPU monitoring:
							kill -TERM $gpu_monitoring_PID
						fi
					fi

					# Process log file created by GROMACS:
					process_log_file
				done
				
				
				# Return to the working directory
					cd $protein_path/$working_directory
				
			done
			done
			done
			done
			done


	echo "18"
	echo "# Analyzing data"
		### Create associative arrays to store the final ranked results to user:
			# Performance - wall time:
			declare -A final_report_avg_wall_time_s
			declare -A final_report_sd_wall_time_s
			declare -A final_report_avg_wall_time_s_10k
			# Performance - ns/day:
			declare -A final_report_avg_ns_day
			declare -A final_report_sd_ns_day
			# Performance - hours/ns:
			declare -A final_report_avg_hour_ns
			declare -A final_report_sd_hour_ns
			# Energy - total:
			declare -A final_report_avg_total_energy_J
			declare -A final_report_sd_total_energy_J
			declare -A final_report_avg_total_energy_J_10k	
	
	
	
		### Analyze data of control simulation:
			# Stablish simulation directory to analyze:
			simulation_directory="nb=auto pme=auto pmefft=auto bonded=auto update=auto"
			
			# Analyze benchmark_mdrun.tsv:
				benchmark_mdrun_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_mdrun.tsv"
			
				# Get all the replicates results stored in benchmark_mdrun.tsv:
				while read -r wall_time_element ns_day_element hours_ns_element; do 
					all_wall_time_s+=("$wall_time_element")
					all_ns_day+=("$ns_day_element")
					all_hour_ns+=("$hours_ns_element")
				done < "$benchmark_mdrun_tsv"
				
				# Calculate the average and standard deviation of the wall time, ns/day, and hours/ns:
				## Wall time, average:
				mean "${all_wall_time_s[@]}"
				avg_wall_time_s=$(printf "%.3f" $mean_result)
				unset mean_result # unset reusable global variable for safety reasons
				## Wall time, standard deviation:
				std_dev_sample "${all_wall_time_s[@]}"
				sd_wall_time_s=$(printf "%.3f" $std_dev_sample_result)
				unset std_dev_sample_result # unset reusable global variable for safety reasons
				## Wall time, normalization by 10000 steps:
				avg_wall_time_s_10k=$(printf "%.2f" $(bc -l <<< "$avg_wall_time_s * 10000 / $steps"))
				## Save to final associative array for final ranked results:
				final_report_avg_wall_time_s["$simulation_directory"]="$avg_wall_time_s"
				final_report_sd_wall_time_s["$simulation_directory"]="$sd_wall_time_s"
				final_report_avg_wall_time_s_10k["$simulation_directory"]="$avg_wall_time_s_10k"
				
				## ns/day, average:
				mean "${all_ns_day[@]}"
				avg_ns_day=$(printf "%.3f" $mean_result)
				unset mean_result # unset reusable global variable for safety reasons
				## ns/day, standard deviation:
				std_dev_sample "${all_ns_day[@]}"
				sd_ns_day=$(printf "%.3f" $std_dev_sample_result)
				unset std_dev_sample_result # unset reusable global variable for safety reasons
				## Save to final associative array for final ranked results:
				final_report_avg_ns_day["$simulation_directory"]="$avg_ns_day"
				final_report_sd_ns_day["$simulation_directory"]="$sd_ns_day"
				
				## hours/ns, average:
				mean "${all_hour_ns[@]}"
				avg_hour_ns=$(printf "%.3f" $mean_result)
				unset mean_result # unset reusable global variable for safety reasons
				## hours/ns, standard deviation:
				std_dev_sample "${all_hour_ns[@]}"
				sd_hour_ns=$(printf "%.3f" $std_dev_sample_result)
				unset std_dev_sample_result # unset reusable global variable for safety reasons
				## Save to final associative array for final ranked results:
				final_report_avg_hour_ns["$simulation_directory"]="$avg_hour_ns"
				final_report_sd_hour_ns["$simulation_directory"]="$sd_hour_ns"
				
				# Unset reusable global variables for safety reasons:
				unset wall_time_element
				unset ns_day_element
				unset hours_ns_element
				
				
			# Analyze benchmark_cpu.tsv and, if applicable, benchmark_gpu.tsv
			# (Only if energy consumption was benchmarked, analyze CPU and GPU energy consumption):
				if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
					for (( r = 1; r <= replicates; r++ )); do
						benchmark_cpu_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_cpu.tsv"
						
						# Filter the results for replicate r:
						while read -r replicate power; do
							# Append only the powers of replica r to an array:
							if [ "$replicate" -eq "$r" ]; then
								all_cpu_power_r_W+=("$power")
							fi
						done < "$benchmark_cpu_tsv"
						
						# Calculate the mean power consumption for replicate r:
						mean "${all_cpu_power_r_W[@]}"
						all_avg_cpu_power_W+=( "$(printf "%.4f" "$mean_result")" )

						# Unset reusable global variables for safety reasons:
						unset replicate
						unset power
						unset all_cpu_power_r_W
						unset benchmark_cpu_tsv
						unset mean_result

						if [ "$ignore_GPU" == false ]; then
							benchmark_gpu_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_gpu.tsv"
							
							# Filter the results for replicate r:
							while read -r replicate power; do
								# Append only the powers of replica r to an array:
								if [ "$replicate" -eq "$r" ]; then
									all_gpu_power_r_W+=("$power")
								fi
							done < "$benchmark_gpu_tsv"
							
							# Calculate the mean power consumption for replicate r:
							mean "${all_gpu_power_r_W[@]}"
							all_avg_gpu_power_W+=( "$(printf "%.4f" "$mean_result")" )
							
							# Unset reusable global variables for safety reasons:
							unset replicate
							unset power
							unset all_gpu_power_r_W
							unset benchmark_gpu_tsv
							unset mean_result
						fi
					done
				fi
			
			
			# Summary of relevant variables created up to this point:
			## all_wall_time_s     : Array with runnning times of each replicate, in seconds
			## avg_wall_time_s     : Average running time over all replicates, in s
			## sd_wall_time_s      : Sample standard deviation of running time over all replicates, in s
			## all_ns_day          : Array with perfomances of each replicate, in nanoseconds per day
			## avg_ns_day          : Average performance over all replicates, in nanoseconds per day
			## sd_ns_day           : Sample standard deviation of performance over all replicates, in nanoseconds per day
			## all_hour_ns         : Array with performances of each replicate, in hours per nanosecond
			## avg_hour_ns         : Average performance over all replicates, in hours per nanosecond
			## sd_hour_ns          : Sample standard deviation of performance over all replicates, in hours per nanosecond
			## all_avg_cpu_power_W : Array of average CPU power consumptions of each replicate in W
			## all_avg_gpu_power_W : Array of average GPU power consumptions of each replicate in W
			
			# DEBUG PRINTING:
			if [ "$debug_printing" = true ]; then
				save_performance_debug "debug.out"
			fi
			
			if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
				# Calculate CPU energy consumption of each replicate:
				energy_consumption "${all_wall_time_s[@]}" "${all_avg_cpu_power_W[@]}"
				all_cpu_energy_J=("${energy_consumption_result[@]}")
				unset energy_consumption_result # unset reusable global variable for safety reasons
			
				# Calculate GPU energy consumption of each replicate:
					energy_consumption "${all_wall_time_s[@]}" "${all_avg_gpu_power_W[@]}"
					all_gpu_energy_J=("${energy_consumption_result[@]}")
					unset energy_consumption_result # unset reusable global variable for safety reasons
				
				# Calculate total (i.e. CPU + GPU) energy consumption of each replicate:
					all_total_energy_J=()
					for (( i = 0; i < replicates; i++ )); do 
						all_total_energy_J+=( $(bc -l <<< "${all_cpu_energy_J[i]} + ${all_gpu_energy_J[i]}") )
					done

				
				# Calculate average and standard deviation of CPU, GPU and total energies across replicates:
					## CPU, average:
					mean "${all_cpu_energy_J[@]}"
					avg_cpu_energy_J=$(printf "%.2f" $mean_result)
					unset mean_result
					## CPU, standard deviation:
					std_dev_sample "${all_cpu_energy_J[@]}"
					sd_cpu_energy_J=$(printf "%.2f" $std_dev_sample_result)
					unset std_dev_sample_result
					
					## GPU, average:
					mean "${all_gpu_energy_J[@]}"
					avg_gpu_energy_J=$(printf "%.2f" $mean_result)
					unset mean_result
					## GPU, standard deviation:
					std_dev_sample "${all_gpu_energy_J[@]}"
					sd_gpu_energy_J=$(printf "%.2f" $std_dev_sample_result)
					unset std_dev_sample_result
					
					## Total energy, average:
					mean "${all_total_energy_J[@]}"
					avg_total_energy_J=$(printf "%.2f" $mean_result)
					unset mean_result
					## Total energy, standard deviation:
					std_dev_sample "${all_total_energy_J[@]}"
					sd_total_energy_J=$(printf "%.2f" $std_dev_sample_result)
					unset std_dev_sample_result
					## Total energy, normalization by 10000 steps:
					avg_total_energy_J_10k=$(printf "%.1f" $(bc -l <<< "$avg_total_energy_J * 10000 / $steps"))
					## Save to final associative array for final ranked results:
					final_report_avg_total_energy_J["$simulation_directory"]="$avg_total_energy_J"
					final_report_sd_total_energy_J["$simulation_directory"]="$sd_total_energy_J"
					final_report_avg_total_energy_J_10k["$simulation_directory"]="$avg_total_energy_J_10k"
					
					
				# DEBUG PRINTING:
				if [ "$debug_printing" = true ]; then
					save_energy_debug "debug.out"
				fi
			fi
			
			
			
			# Save all relevant results to a file:
			save_analyzed_results "$protein_path/$working_directory/$simulation_directory/analyzed_results.tsv"
			
			# Unset reusable global variables for safety reasons:
			unset all_wall_time_s
			unset avg_wall_time_s
			unset sd_wall_time_s
			unset avg_wall_time_s_10k
			unset all_ns_day
			unset avg_ns_day
			unset all_hour_ns
			unset avg_hour_ns
			unset all_avg_cpu_power_W
			unset all_avg_gpu_power_W
			unset all_cpu_energy_J
			unset avg_cpu_energy_J
			unset sd_cpu_energy_J
			unset all_gpu_energy_J
			unset avg_gpu_energy_J
			unset sd_gpu_energy_J
			unset all_total_energy_J
			unset avg_total_energy_J
			unset sd_total_energy_J
			unset avg_total_energy_J_10k
			unset simulation_directory
			unset benchmark_mdrun_tsv
			
			
			
		### Analyze data of tuning simulations:
			# Define devices to specify to GROMACS gmx:
			options_variable_flags=('cpu' 'gpu')
		
			# Iterate over all possible combinations of parameters to pass to GROMACS gmx:
			for nb in ${options_variable_flags[@]}; do
			for pme in ${options_variable_flags[@]}; do
			for pmefft in ${options_variable_flags[@]}; do
			for bonded in ${options_variable_flags[@]}; do
			for update in ${options_variable_flags[@]}; do
				
				# Skip combinations of CPU-GPU unloading that are not acceptable:
				if [[ "$update" == "gpu" && "$pme" == "cpu" && "$nb" == "cpu" ]]; then continue; fi
				if [[ "$bonded" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
				if [[ "$pmefft" == "gpu" && "$pme" == "cpu" ]]; then continue; fi
				if [[ "$pme" == "gpu" && "$nb" == "cpu" ]]; then continue; fi
				
				# Stablish simulation directory to analyze:
				simulation_directory="nb=$nb pme=$pme pmefft=$pmefft bonded=$bonded update=$update"
				
				# Analyze benchmark_mdrun.tsv:
				benchmark_mdrun_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_mdrun.tsv"
				
				# Get all the replicates results stored in benchmark_mdrun.tsv:
				while read -r wall_time_element ns_day_element hours_ns_element; do 
					all_wall_time_s+=("$wall_time_element")
					all_ns_day+=("$ns_day_element")
					all_hour_ns+=("$hours_ns_element")
				done < "$benchmark_mdrun_tsv"
				
				# Calculate the average and standard deviation of the wall time, ns/day, and hours/ns:
				## Wall time, average:
				mean "${all_wall_time_s[@]}"
				avg_wall_time_s=$(printf "%.3f" $mean_result)
				unset mean_result # unset reusable global variable for safety reasons
				## Wall time, standard deviation:
				std_dev_sample "${all_wall_time_s[@]}"
				sd_wall_time_s=$(printf "%.3f" $std_dev_sample_result)
				unset std_dev_sample_result # unset reusable global variable for safety reasons
				## Wall time, normalization by 10000 steps:
				avg_wall_time_s_10k=$(printf "%.2f" $(bc -l <<< "$avg_wall_time_s * 10000 / $steps"))
				## Save to final associative array for final ranked results:
				final_report_avg_wall_time_s["$simulation_directory"]="$avg_wall_time_s"
				final_report_sd_wall_time_s["$simulation_directory"]="$sd_wall_time_s"
				final_report_avg_wall_time_s_10k["$simulation_directory"]="$avg_wall_time_s_10k"
				
				## ns/day, average:
				mean "${all_ns_day[@]}"
				avg_ns_day=$(printf "%.3f" $mean_result)
				unset mean_result # unset reusable global variable for safety reasons
				## ns/day, standard deviation:
				std_dev_sample "${all_ns_day[@]}"
				sd_ns_day=$(printf "%.3f" $std_dev_sample_result)
				unset std_dev_sample_result # unset reusable global variable for safety reasons
				## Save to final associative array for final ranked results:
				final_report_avg_ns_day["$simulation_directory"]="$avg_ns_day"
				final_report_sd_ns_day["$simulation_directory"]="$sd_ns_day"
				
				## hours/ns, average:
				mean "${all_hour_ns[@]}"
				avg_hour_ns=$(printf "%.3f" $mean_result)
				unset mean_result # unset reusable global variable for safety reasons
				## hours/ns, standard deviation:
				std_dev_sample "${all_hour_ns[@]}"
				sd_hour_ns=$(printf "%.3f" $std_dev_sample_result)
				unset std_dev_sample_result # unset reusable global variable for safety reasons
				## Save to final associative array for final ranked results:
				final_report_avg_hour_ns["$simulation_directory"]="$avg_hour_ns"
				final_report_sd_hour_ns["$simulation_directory"]="$sd_hour_ns"
				
				
				# Unset reusable global variables for safety reasons:
				unset wall_time_element
				unset ns_day_element
				unset hours_ns_element
				
				
				# Analyze benchmark_cpu.tsv and, if applicable, benchmark_gpu.tsv
				# (Only if energy consumption was benchmarked, analyze CPU and GPU energy consumption):
					if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
						for (( r = 1; r <= replicates; r++ )); do
							benchmark_cpu_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_cpu.tsv"
							
							# Filter the results for replicate r:
							while read -r replicate power; do
								# Append only the powers of replica r to an array:
								if [ "$replicate" -eq "$r" ]; then
									all_cpu_power_r_W+=("$power")
								fi
							done < "$benchmark_cpu_tsv"
							
							# Calculate the mean power consumption for replicate r:
							mean "${all_cpu_power_r_W[@]}"
							all_avg_cpu_power_W+=( "$(printf "%.4f" "$mean_result")" )

							# Unset reusable global variables for safety reasons:
							unset replicate
							unset power
							unset all_cpu_power_r_W
							unset benchmark_cpu_tsv
							unset mean_result

							if [ "$ignore_GPU" == false ]; then
								benchmark_gpu_tsv="$protein_path/$working_directory/$simulation_directory/benchmark_gpu.tsv"
								
								# Filter the results for replicate r:
								while read -r replicate power; do
									# Append only the powers of replica r to an array:
									if [ "$replicate" -eq "$r" ]; then
										all_gpu_power_r_W+=("$power")
									fi
								done < "$benchmark_gpu_tsv"
								
								# Calculate the mean power consumption for replicate r:
								mean "${all_gpu_power_r_W[@]}"
								all_avg_gpu_power_W+=( "$(printf "%.4f" "$mean_result")" )
								
								# Unset reusable global variables for safety reasons:
								unset replicate
								unset power
								unset all_gpu_power_r_W
								unset benchmark_gpu_tsv
								unset mean_result
							fi
						done
					fi
			
			
			# DEBUG PRINTING:
			if [ "$debug_printing" = true ]; then
				save_performance_debug "debug.out"
			fi
			
			
			if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
				# Calculate CPU energy consumption of each replicate:
				energy_consumption "${all_wall_time_s[@]}" "${all_avg_cpu_power_W[@]}"
				all_cpu_energy_J=("${energy_consumption_result[@]}")
				unset energy_consumption_result # unset reusable global variable for safety reasons
			
				# Calculate GPU energy consumption of each replicate:
					energy_consumption "${all_wall_time_s[@]}" "${all_avg_gpu_power_W[@]}"
					all_gpu_energy_J=("${energy_consumption_result[@]}")
					unset energy_consumption_result # unset reusable global variable for safety reasons
				
				# Calculate total (i.e. CPU + GPU) energy consumption of each replicate:
					all_total_energy_J=()
					for (( i = 0; i < replicates; i++ )); do 
						all_total_energy_J+=( $(bc -l <<< "${all_cpu_energy_J[i]} + ${all_gpu_energy_J[i]}") )
					done

				
				# Calculate average and standard deviation of CPU, GPU and total energies across replicates:
					## CPU, average:
					mean "${all_cpu_energy_J[@]}"
					avg_cpu_energy_J=$(printf "%.2f" $mean_result)
					unset mean_result
					## CPU, standard deviation:
					std_dev_sample "${all_cpu_energy_J[@]}"
					sd_cpu_energy_J=$(printf "%.2f" $std_dev_sample_result)
					unset std_dev_sample_result
					
					## GPU, average:
					mean "${all_gpu_energy_J[@]}"
					avg_gpu_energy_J=$(printf "%.2f" $mean_result)
					unset mean_result
					## GPU, standard deviation:
					std_dev_sample "${all_gpu_energy_J[@]}"
					sd_gpu_energy_J=$(printf "%.2f" $std_dev_sample_result)
					unset std_dev_sample_result
					
					## Total energy, average:
					mean "${all_total_energy_J[@]}"
					avg_total_energy_J=$(printf "%.2f" $mean_result)
					unset mean_result
					## Total energy, standard deviation:
					std_dev_sample "${all_total_energy_J[@]}"
					sd_total_energy_J=$(printf "%.2f" $std_dev_sample_result)
					unset std_dev_sample_result
					## Total energy, normalization by 10000 steps:
					avg_total_energy_J_10k=$(printf "%.1f" $(bc -l <<< "$avg_total_energy_J * 10000 / $steps"))
					## Save to final associative array for final ranked results:
					final_report_avg_total_energy_J["$simulation_directory"]="$avg_total_energy_J"
					final_report_sd_total_energy_J["$simulation_directory"]="$sd_total_energy_J"
					final_report_avg_total_energy_J_10k["$simulation_directory"]="$avg_total_energy_J_10k"
					
					
				# DEBUG PRINTING:
				if [ "$debug_printing" = true ]; then
					save_energy_debug "debug.out"
				fi
			fi
			
			
			# Save all relevant results to a file:
			save_analyzed_results "$protein_path/$working_directory/$simulation_directory/analyzed_results.tsv"

			
			# Unset reusable global variables for safety reasons:
			unset all_wall_time_s
			unset avg_wall_time_s
			unset sd_wall_time_s
			unset avg_wall_time_s_10k
			unset all_ns_day
			unset avg_ns_day
			unset all_hour_ns
			unset avg_hour_ns
			unset all_avg_cpu_power_W
			unset all_avg_gpu_power_W
			unset all_cpu_energy_J
			unset avg_cpu_energy_J
			unset sd_cpu_energy_J
			unset all_gpu_energy_J
			unset avg_gpu_energy_J
			unset sd_gpu_energy_J
			unset all_total_energy_J
			unset avg_total_energy_J
			unset sd_total_energy_J
			unset avg_total_energy_J_10k
			unset simulation_directory
			unset benchmark_mdrun_tsv
				
			done
			done
			done
			done
			done
		
		
	echo "19"
	echo "# Ranking results"
		### Sort based on performance (i.e. wall time):
			if [ "$debug_printing" == true ]; then
				echo "" >> debug.out
				echo "FINAL SORTED RESULTS - TIME PERFORMANCE:" >> debug.out
				echo "  UNSORTED (Avg. wall time ± SD):" >> debug.out
				for key in "${!final_report_avg_wall_time_s[@]}"; do
					echo -e "  $key\t(${final_report_avg_wall_time_s[$key]} s ± ${final_report_sd_wall_time_s[$key]} s)" >> debug.out
				done
			fi
			
			sorted_final_report_avg_wall_time_s=()
			min_key=""
			min_value=999999999999.9
			num_simulations="${#final_report_avg_wall_time_s[@]}"
			
			
			for (( i = 0; i < num_simulations; i++ )); do
				for key in "${!final_report_avg_wall_time_s[@]}"; do
					# Check if the current key has been found before:
					if [[ "${sorted_final_report_avg_wall_time_s[@]}" =~ "$key" ]]; then
						continue
					fi
					
					# Get value:
					value=${final_report_avg_wall_time_s["$key"]}
					
					# Compare value with min_value, and update if needed:
					if [[ $(echo "$value < $min_value" | bc) -eq 1 ]]; then 
						min_key=$key
						min_value=$value
					fi
				done
				
				# Append the locally found minimum key to
				sorted_final_report_avg_wall_time_s+=("$min_key")
				
				# Unset reusable global variables for safety reasons:
				unset value
				unset min_key
				
				# Reset min_value
				min_value=999999999999.9
				
			done
			
			# Unset reusable global variables for safety reasons:
			unset num_simulations
			
			if [ "$debug_printing" == true ]; then
				echo "  SORTED (Avg. wall time ± SD):" >> debug.out
				for key in "${sorted_final_report_avg_wall_time_s[@]}"; do
					echo -e "  $key\t(${final_report_avg_wall_time_s[$key]} s ± ${final_report_sd_wall_time_s[$key]} s)" >> debug.out
				done
			fi
		
		### Sort based on energy:
			if [ "$debug_printing" == true ]; then
				echo "" >> debug.out
				echo "FINAL SORTED RESULTS - ENERGY CONSUMPTION:" >> debug.out
				echo "  UNSORTED (Avg. energy consumed ± SD):" >> debug.out
				for key in "${!final_report_avg_total_energy_J[@]}"; do
					echo -e "  $key\t(${final_report_avg_total_energy_J["$key"]} J ± ${final_report_sd_total_energy_J[$key]} J)" >> debug.out
				done
			fi
			
			sorted_final_report_avg_total_energy_J=()
			min_key=""
			min_value=999999999999.9
			num_simulations="${#final_report_avg_total_energy_J[@]}"
			
			
			for (( i = 0; i < num_simulations; i++ )); do
				for key in "${!final_report_avg_total_energy_J[@]}"; do
					# Check if the current key has been found before:
					if [[ "${sorted_final_report_avg_total_energy_J[@]}" =~ "$key" ]]; then
						continue
					fi
					
					# Get value:
					value=${final_report_avg_total_energy_J["$key"]}
					
					# Compare value with min_value, and update if needed:
					if [[ $(echo "$value < $min_value" | bc) -eq 1 ]]; then 
						min_key=$key
						min_value=$value
					fi
				done
				
				# Append the locally found minimum key to
				sorted_final_report_avg_total_energy_J+=("$min_key")
				
				# Unset reusable global variables for safety reasons:
				unset value
				unset min_key
				
				# Reset min_value
				min_value=999999999999.9
				
			done
			
			# Unset reusable global variables for safety reasons:
			unset num_simulations
			
			if [ "$debug_printing" == true ]; then
				echo "  SORTED (Avg. energy consumed ± SD):" >> debug.out
				for key in "${sorted_final_report_avg_total_energy_J[@]}"; do
					echo -e "  $key\t(${final_report_avg_total_energy_J[$key]} J ± ${final_report_sd_total_energy_J[$key]} J)" >> debug.out
				done
			fi
	
	
	echo "20"
	echo "# Saving results"
		
		cd "$protein_path"
		final_results_file="$app_name-Final_results-$protein_name-$datetime.txt"
		
		datetime_formatted=$(date +'%Y-%m-%d %H:%M:%S UTC%Z')
		
		echo "************************** $app_name **************************" >> "$final_results_file"
		echo ""                             >> "$final_results_file"
		echo "PROTEIN: $protein_name"       >> "$final_results_file"
		echo "PATH:    $protein_path"       >> "$final_results_file"
		echo "TIME:    $datetime_formatted" >> "$final_results_file"
		echo ""                             >> "$final_results_file"
		
		echo "SIMULATION PARAMETERS:" >> "$final_results_file"
		
		if [ "$no_gui" == true ]; then
			echo "Terminal/GUI:                    terminal mode" >> "$final_results_file"
		else
			echo "Terminal/GUI:                    GUI mode" >> "$final_results_file"
		fi
		
		echo "Benchmark:                       $benchmark"              >> "$final_results_file"
		echo "Steps simulated (per replicate): $steps"                  >> "$final_results_file"
		echo "Replicates:                      $replicates"             >> "$final_results_file"
		echo "Preserve intermediate files:     $preserve_gromacs_files" >> "$final_results_file"
		echo "Custom GROMACS parameters:      $custom_params"          >> "$final_results_file"
		echo ""                                                         >> "$final_results_file"
		
		echo "RANKED RESULTS - TIME PERFORMANCE" >> "$final_results_file"
		
		printf "%-4s%-54s%-27s" "" "CPU-GPU task load balance" "Avg. wall time (±SD) (s)" >> "$final_results_file"
		printf "%-29s" "Wall time per 10k steps (s)"                                 >> "$final_results_file"
		printf "%-34s" "Avg. performance (±SD) (ns/day)"                                  >> "$final_results_file"
		printf "%-29s\n" "Avg. performance (±SD) (h/ns)"                                  >> "$final_results_file"
		
		iteration=1
		for key in "${sorted_final_report_avg_wall_time_s[@]}"; do
			printf "%02g) %-54s%-27s" "$iteration" "$key" "${final_report_avg_wall_time_s[$key]} (±${final_report_sd_wall_time_s[$key]})" >> "$final_results_file"
			printf "%-29s" "${final_report_avg_wall_time_s_10k[$key]}"                                                                    >> "$final_results_file"
			printf "%-34s" "${final_report_avg_ns_day[$key]} (±${final_report_sd_ns_day[$key]})"                                          >> "$final_results_file"
			printf "%-29s\n" "${final_report_avg_hour_ns[$key]} (±${final_report_sd_hour_ns[$key]})"                                      >> "$final_results_file"
			((iteration++))
		done
		
		echo "" >> "$final_results_file"
		
		if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
			echo "RANKED RESULTS - ENERGY CONSUMPTION" >> "$final_results_file"
		
			printf "%-4s%-54s%-30s" "" "CPU-GPU task load balance" "Avg. total energy (±SD) (J)"   >> "$final_results_file"
			printf "%-30s\n" "Total energy per 10k steps (J)"                                 >> "$final_results_file"
			
			iteration=1
			for key in "${sorted_final_report_avg_total_energy_J[@]}"; do
				printf "%02g) %-54s%-30s" "$iteration" "$key" "${final_report_avg_total_energy_J[$key]} (±${final_report_sd_total_energy_J[$key]})" >> "$final_results_file"
				printf "%-30s\n" "${final_report_avg_total_energy_J_10k[$key]}"                                                                     >> "$final_results_file"
				((iteration++))
			done
		fi
		echo "" >> "$final_results_file"
			
		echo "NOTES:" >> "$final_results_file"
		echo "  All the results showed above were calculated across the replicates selected by the user." >> "$final_results_file"
		echo "  SD: standard deviation of the sample." >> "$final_results_file"
		echo "  Avg. wall time: Average of wall time that the production run took, given the number of steps set by the user." >> "$final_results_file"
		echo "  Wall time per 10k steps: Estimated wall time of production run, per each 10,000 simulation steps." >> "$final_results_file"
		echo "  Avg. performance (ns/day): Average performance of production run, expressed as nanoseconds of simulation per wall time days." >> "$final_results_file"
		echo "  Avg. performance (h/ns): Average performance of production run, expressed as wall time hours per nanoseconds of simulation." >> "$final_results_file"
		if [ "$benchmark" == "Time performance and energy consumption" ] || [ "$benchmark" == "time_energy" ]; then
			echo "  Avg. total energy: Average of total (CPU+GPU) energy consumption of the production run, given the number of steps set by the user." >> "$final_results_file"
			echo "  Avg. total energy per 10k steps: Estimated total (CPU+GPU) energy consumption of the production run, per each 10,000 simulation steps." >> "$final_results_file"
		fi
		echo "" >> "$final_results_file"
		
		
	echo "21"
	echo "# Handling temporary files"
		if [ "$preserve_gromacs_files" == false ]; then
			rm -rf "$protein_path/$working_directory"
		fi
		
	) |
	yad --progress \
	    --title="$app_name - $protein_name" \
	    --text="Executing simulations - $benchmark" \
	    --width=400 \
	    --pulsate \
	    --button=yad-cancel \
	    --auto-kill --auto-close
	
	
	if [ "$run_without_root" == false ]; then
		sudo chown -R $(logname):$(id -gn $(logname)) $protein_path/$working_directory
	fi

	
exit 0
