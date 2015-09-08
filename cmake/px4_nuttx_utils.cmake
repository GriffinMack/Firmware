############################################################################
#
# Copyright (c) 2015 PX4 Development Team. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name PX4 nor the names of its contributors may be
#    used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
############################################################################

include(px4_utils)

#----------------------------------------------------------------------------
#	px4_nuttx_add_firmware
#
#	This function adds a nuttx firmware target.
#
#	Usage:
#		px4_nuttx_add_firmware(OUT <out-target> EXE <in-executable>)
#
#	Input:
#		EXE			: the executable to generate the firmware from
#
#	Options:
#		PARAM_XML	: toggles generation of param_xml	
#
#	Output:
#		OUT			: the generated firmware target
#
#	Example:
#		px4_nuttx_add_firmware(TARGET fw_test EXE test)
#
#----------------------------------------------------------------------------
function(px4_nuttx_add_firmware)
	px4_parse_function_args(
		NAME px4_nuttx_add_firmware
		ONE_VALUE OUT EXE
		OPTIONS PARAM_XML
		REQUIRED EXE
		ARGN ${ARGN})

	#TODO handle param_xml
	add_custom_command(OUTPUT ${OUT}
		COMMAND ${OBJCOPY} -O binary ${EXE} ${EXE}.bin
		COMMAND ${PYTHON_EXECUTABLE} ${CMAKE_SOURCE_DIR}/Tools/px_mkfw.py
			--prototype ${CMAKE_SOURCE_DIR}/Images/${BOARD}.prototype
			--git_identity ${CMAKE_SOURCE_DIR}
			--image ${EXE}.bin > ${OUT}
		DEPENDS ${EXE}
		WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
		)
endfunction()

#----------------------------------------------------------------------------
#	px4_nuttx_generate_builtin_commands
#
#	This function generates the builtin_commands.c src for nuttx

#	Usage:
#		px4_nuttx_generate_builtin_commands(
#			MODULE_LIST <in-list>
#			OUT <file>)
#
#	Input:
#		MODULE_LIST	: list of modules
#
#	Output:
#		OUT	: generated builtin_commands.c src
#
#	Example:
#		px4_nuttx_generate_builtin_commands(OUT <generated-src> MODULE_LIST px4_simple_app)
#
#----------------------------------------------------------------------------
function(px4_nuttx_generate_builtin_commands)
	px4_parse_function_args(
		NAME px4_nuttx_generate_builtin_commands
		ONE_VALUE OUT
		MULTI_VALUE MODULE_LIST
		REQUIRED MODULE_LIST OUT
		ARGN ${ARGN})
	set(builtin_apps_string)
	set(builtin_apps_decl_string)
	set(command_count 0)
	foreach(module ${MODULE_LIST})
		# default
		set(MAIN_DEFAULT MAIN-NOTFOUND)
		set(STACK_DEFAULT 1024)
		set(PRIORITY_DEFAULT SCHED_PRIORITY_DEFAULT)
		foreach(property MAIN STACK PRIORITY) 
			get_target_property(${property} ${module} ${property})
			if(NOT ${property})
				set(${property} ${${property}_DEFAULT})
			endif()
		endforeach()
		if (MAIN)
			set(builtin_apps_string
				"${builtin_apps_string}\t{\"${MAIN}\", ${PRIORITY}, ${STACK}, ${MAIN}_main},\n")
			set(builtin_apps_decl_string
				"${builtin_apps_decl_string}extern int ${MAIN}_main(int argc, char *argv[]);\n")
			math(EXPR command_count "${command_count}+1")
		endif()
	endforeach()
	configure_file(${CMAKE_SOURCE_DIR}/cmake/builtin_commands.c.cmake
		${OUT})
endfunction()

#----------------------------------------------------------------------------
#	px4_nuttx_add_export
#
#	This function generates a nuttx export.

#	Usage:
#		px4_nuttx_add_export(
#			OUT <out-target>
#			CONFIG <in-string>
#			DEPENDS <in-list>)
#
#	Input:
#		CONFIG	: the board to generate the export for
#		DEPENDS	: dependencies
#
#	Output:
#		OUT	: the export target
#
#	Example:
#		px4_nuttx_add_export(OUT nuttx_export CONFIG px4fmu-v2)
#
#----------------------------------------------------------------------------
function(px4_nuttx_add_export)

	px4_parse_function_args(
		NAME px4_nuttx_add_export
		ONE_VALUE OUT CONFIG THREADS
		MULTI_VALUE DEPENDS
		REQUIRED OUT CONFIG THREADS
		ARGN ${ARGN})

	set(nuttx_src ${CMAKE_BINARY_DIR}/${CONFIG}/NuttX)

	# patch
	add_custom_target(__nuttx_patch_${CONFIG})
	file(GLOB nuttx_patches RELATIVE ${CMAKE_SOURCE_DIR}
	    ${CMAKE_SOURCE_DIR}/nuttx-patches/*.patch)
	foreach(patch ${nuttx_patches})
		string(REPLACE "/" "_" patch_name "${patch}-${CONFIG}")
	    message(STATUS "nuttx-patch: ${patch}")
		add_custom_command(OUTPUT nuttx_patch_${patch_name}.stamp
			COMMAND patch -p0 -N  < ${CMAKE_SOURCE_DIR}/${patch}
			COMMAND touch nuttx_patch_${patch_name}.stamp
			DEPENDS ${DEPENDS}
			)
	    add_custom_target(nuttx_patch_${patch_name}
			DEPENDS nuttx_patch_${patch_name}.stamp)
	    add_dependencies(nuttx_patch nuttx_patch_${patch_name})
	endforeach()

	# copy
	add_custom_command(OUTPUT nuttx_copy_${CONFIG}.stamp
		COMMAND mkdir -p ${CMAKE_BINARY_DIR}/${CONFIG}
		COMMAND cp -r ${CMAKE_SOURCE_DIR}/NuttX ${nuttx_src}
		COMMAND rm -rf ${nuttx_src}/.git
		COMMAND touch nuttx_copy_${CONFIG}.stamp
		DEPENDS ${DEPENDS})
	add_custom_target(__nuttx_copy_${CONFIG}
		DEPENDS nuttx_copy_${CONFIG}.stamp __nuttx_patch_${CONFIG})

	# export
	add_custom_command(OUTPUT ${CONFIG}.export
		COMMAND echo Configuring NuttX for ${CONFIG}
		COMMAND make -C${nuttx_src}/nuttx -j${THREADS}
			-r --quiet distclean
		COMMAND cp -r ${CMAKE_SOURCE_DIR}/nuttx-configs/${CONFIG}
			${nuttx_src}/nuttx/configs
		COMMAND cd ${nuttx_src}/nuttx/tools &&
			./configure.sh ${CONFIG}/nsh
		COMMAND echo Exporting NuttX for ${CONFIG}
		COMMAND make -C ${nuttx_src}/nuttx -j${THREADS}
			-r CONFIG_ARCH_BOARD=${CONFIG} export
		COMMAND cp -r ${nuttx_src}/nuttx/nuttx-export.zip
			${CONFIG}.export
		DEPENDS ${DEPENDS} __nuttx_copy_${CONFIG})

	# extract
	add_custom_command(OUTPUT nuttx_export_${BOARD}.stamp
		COMMAND rm -rf ${nuttx_src}/nuttx-export
		COMMAND unzip ${BOARD}.export -d ${nuttx_src}
		COMMAND touch nuttx_export_${BOARD}.stamp
		DEPENDS ${DEPENDS} ${BOARD}.export)

	add_custom_target(${OUT}
		DEPENDS nuttx_export_${BOARD}.stamp)

endfunction()

#----------------------------------------------------------------------------
#	px4_nuttx_generate_romfs
#
#	The functions generates the ROMFS filesystem for nuttx.
#
#	Usage:
#		px4_nuttx_generate_romfs(OUT <out-target> ROOT <in-directory>)
#
#	Input:
#		ROOT	: the root of the ROMFS
#
#	Output:
#		OUT		: the generated ROMFS
#
#	Example:
#		px4_nuttx_generate_romfs(OUT my_romfs ROOT "ROMFS/my_board")
#
#----------------------------------------------------------------------------
function(px4_nuttx_generate_romfs)

	px4_parse_function_args(
		NAME px4_nuttx_generate_romfs
		ONE_VALUE OUT ROOT
		REQUIRED OUT ROOT
		ARGN ${ARGN})

	file(GLOB_RECURSE romfs_files ${ROOT}/*)
	set(romfs_temp_dir ${CMAKE_BINARY_DIR}/${ROOT})
	set(romfs_src_dir ${CMAKE_SOURCE_DIR}/${ROOT})

	add_custom_command(OUTPUT ${OUT}
		COMMAND cmake -E remove_directory ${romfs_temp_dir}
		COMMAND cmake -E copy_directory ${romfs_src_dir} ${romfs_temp_dir}
		#TODO add romfs cleanup and pruning
		COMMAND ${GENROMFS} -f ${OUT} -d ${romfs_temp_dir} -V "NSHInitVol"
		DEPENDS ${romfs_files}
		WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
		)
	add_custom_target(gen_romfs DEPENDS ${OUT})

endfunction()

#----------------------------------------------------------------------------
#	px4_add_nuttx_flags
#
#	Set ths nuttx build flags.
#
#	Usage:
#		px4_add_nuttx_flags(
#			C_FLAGS <inout-variable>
#			CXX_FLAGS <inout-variable>
#			EXE_LINKER_FLAGS <inout-variable>
#			INCLUDE_DIRS <inout-variable>
#			LINK_DIRS <inout-variable>
#			DEFINITIONS <inout-variable>)
#
#	Input:
#		BOARD					: flags depend on board/nuttx config

#	Input/Output: (appends to existing variable)
#		C_FLAGS					: c compile flags variable
#		CXX_FLAGS				: c++ compile flags variable
#		EXE_LINKER_FLAGS		: executable linker flags variable
#		INCLUDE_DIRS			: include directories
#		LINK_DIRS				: link directories
#		DEFINITIONS				: definitions
#
#	Example:
#		px4_add_nuttx_flags(
#			C_FLAGS CMAKE_C_FLAGS
#			CXX_FLAGS CMAKE_CXX_FLAGS
#			EXE_LINKER_FLAG CMAKE_EXE_LINKER_FLAGS
#			INCLUDES <list>)
#
#----------------------------------------------------------------------------
function(px4_add_nuttx_flags)

	set(inout_vars
		C_FLAGS CXX_FLAGS EXE_LINKER_FLAGS INCLUDE_DIRS LINK_DIRS DEFINITIONS)

	px4_parse_function_args(
		NAME px4_add_nuttx_flags
		ONE_VALUE ${inout_vars} BOARD
		REQUIRED ${inout_vars} BOARD
		ARGN ${ARGN})

	set(nuttx_export_dir ${CMAKE_BINARY_DIR}/${BOARD}/NuttX/nuttx-export)
	set(added_include_dirs
		${nuttx_export_dir}/include
		${nuttx_export_dir}/include/cxx
		${nuttx_export_dir}/arch/chip
		${nuttx_export_dir}/arch/common
		)
	set(added_link_dirs
		${nuttx_export_dir}/libs
		)
	set(added_definitions
		-D__PX4_NUTTX
		)
	set(added_c_flags
		-nodefaultlibs
		-nostdlib
		)
	set(added_cxx_flags
		-nodefaultlibs
		-nostdlib
		)

	set(added_exe_linker_flags) # none currently

	if ("${BOARD}" STREQUAL "px4fmu-v2")
		set(arm_build_flags
			-mcpu=cortex-m4
			-mthumb
			-march=armv7e-m
			-mfpu=fpv4-sp-d16
			-mfloat-abi=hard
			)
		list(APPEND c_flags ${arm_build_flags})
		list(APPEND cxx_flags ${arm_build_flags})
	endif()

	# output
	foreach(var ${inout_vars})
		string(TOLOWER ${var} lower_var)
		set(${${var}} ${${${var}}} ${added_${lower_var}} PARENT_SCOPE)
	endforeach()

endfunction()

# vim: set noet fenc=utf-8 ff=unix nowrap:
