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

#TITLE          : prepare_protein.sh
#DESCRIPTION    : Prepare a protein in PDB format for production simulation with GROMACS.
#AUTHOR		 	: Carlos Diaz <cdiazavr@gmail.com>
#DATE           : 20240503
#VERSION        : 0.0.1    
#USAGE          : bash prepare_protein.sh [-p path]
#NOTES          : This is not a standalone application, but only an automatized series of steps that are part of academic research.
#BASH VERSION   : 5.2.21(1)-release


# USAGE HELP:
	usage() {
	    echo -e "\nUsage: $0 [-p path]"
	    echo "Options:"
	    echo -e "  -p path              Directory path where the protein file (starting_protein.pdb) is located.\n"
	    exit 1
	}


# PARSE FLAGS:
	main_path=""
	while getopts "p:" opt; do
	    case "$opt" in
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

	## handle absence of mandatory argument:
	if [ -z "$main_path" ]; then
	  echo -e "\nThe -p flag with argument is mandatory."
	  usage
	  exit 1
	fi

	## Check if $main_path really exists:
	if [ ! -e "$main_path" ]; then
	    echo "Path does not exist." >&2
	    usage
	    exit 1
	fi
	

# OMIT FILE BACKUP DURING REPLICATED RUNS
	export GMX_MAXBACKUP=-1


# PREPARATION UP TO THE PRODUCTION COMMAND:

	# CLEAN PROTEIN FROM NON PROTEIC ATOMS:
	cd $main_path
	grep ^ATOM starting_protein.pdb > clean_protein.pdb

	# CREATE COORDINATE AND TOPOLOGY FILES (GRO, TOP):
	printf "6" | gmx -quiet pdb2gmx -f clean_protein.pdb -o protein.gro -water tip3p -ignh # 6: AMBER99SB-ILDN

	# CREATE THE BOX AROUND THE PROTEIN (DODECAHEDRON SHAPE):
	gmx -quiet editconf -f protein.gro -o protein_box.gro -c -d 1.0 -bt dodecahedron

	# SOLVATE THE SYSTEM:
	gmx -quiet solvate -cp protein_box.gro -cs spc216.gro -o protein_solv.gro -p topol.top

	# NEUTRALIZE THE SYSTEM:
	gmx -quiet grompp -f ../mdp/ions.mdp -c protein_solv.gro -p topol.top -o ions.tpr
	printf "13" | gmx -quiet genion -s ions.tpr -o protein_ions.gro -p topol.top -pname NA -nname CL -neutral -conc 0.15 # 13: SOL

	# ENERGY MINIMIZATION:
	gmx -quiet grompp -f ../mdp/minim.mdp -c protein_ions.gro -p topol.top -o em.tpr
	gmx -quiet mdrun -deffnm em
	## Extract data on potential energy:
	printf "10\n0" | gmx -quiet energy -f em.edr -o em_potential.xvg

	# NVT EQUILIBRATION:
	gmx -quiet grompp -f ../mdp/nvt.mdp -c em.gro -r em.gro -p topol.top -o nvt.tpr
	gmx -quiet mdrun -deffnm nvt
	## Extract data on temperature
	printf "16\n0" | gmx -quiet energy -f nvt.edr -o nvt_temperature.xvg
	
	# NPT EQUILIBRATION:
	gmx -quiet grompp -f ../mdp/npt.mdp -c nvt.gro -r nvt.gro -t nvt.cpt -p topol.top -o npt.tpr
	gmx -quiet mdrun -deffnm npt
	## Extract data on pressure and density:
	printf "18\n0" | gmx -quiet energy -f npt.edr -o npt_pressure.xvg
	printf "24\n0" | gmx -quiet energy -f npt.edr -o npt_density.xvg

	# PRE-PROCESS FOR PRODUCTION:
	gmx -quiet grompp -f ../mdp/md.mdp -c npt.gro -t npt.cpt -p topol.top -o md.tpr

	# Move final files to a directory:
	mkdir -p 'preparation_files'
	mv -f $(ls clean_protein.pdb *.edr *.gro *.log *.tpr *.trr *.itp *.top *.cpt *.mdp *.xvg) preparation_files

	
    
exit 0
