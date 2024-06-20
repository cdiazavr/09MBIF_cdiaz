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

#TITLE          : batch_run.sh
#DESCRIPTION    : Prepare a protein in PDB format for production simulation with GROMACS.
#AUTHOR		 	: Carlos Diaz <cdiazavr@gmail.com>
#DATE           : 20240503
#VERSION        : 0.0.1    
#USAGE          : bash batch_run.sh [-p path]
#NOTES          : This is not a standalone application, but only an automatized series of steps that are part of academic research.
#BASH VERSION   : 5.2.21(1)-release


for dir in P_*/; do
  if [ -d "$dir" ]; then
    ./prepare_protein.sh -p $dir
    ./run_md_simulation.sh -r 5 -p $dir
  fi
done

    
exit 0
