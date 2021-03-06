#!/bin/bash
if [[ $# -ne 6 ]]; then
	echo -e "\nUsage:	`basename $0` <subjectFolder> <config.ini> <parc_scheme> <use_existing_FS> <move_probabilistic_tracks_to_dir> <move_cmpfolder_to_dir>\n"
	echo -e "	i.e. `basename $0` subject1 Diffusion_config_mrtrix.ini Lausanne2008 True /scratch/grayson_temp ."
	echo -e "	OR `basename $0` subject1 Diffusion_config_mrtrix.ini NativeFreesurfer False /scratch/grayson_temp ."
	echo -e "	OR `basename $0` subject1 Diffusion_config_mrtrix.ini Gordon False 0 .\n"
	echo -e "You MUST spell and capitalize the <parc_scheme> and <use_existing_FS> arguments exactly as shown above.\n<move_probabilistic_trks_to_dir> must be either an existing directory or 0 (meaning don't move the .trk and .tck files)\n<move_cmpfolder_to_dir> must be an existing directory\n"
	exit 1
fi

basedir=`dirname $0`
sub=$1
config=$2
parc=$3
existingFS=$4
movetrks=$5
movetrks_dir=`readlink -m $5`
movefinaldir=`readlink -m $6`

#sanity check
if [ ! -d "$movefinaldir" ]; then
	echo "ERROR: $movefinaldir is not an existing directory"
	exit 1	
fi

function make_config {
	sub=$1;	config=$2; parc=$3; existingFS=$4

	#edit config file to use command arguments; check if using custom parcellation or not
	if [[ $parc == NativeFreesurfer || $parc == Lausanne2008 ]]; then
		sed "s/parcellation_scheme = .*/parcellation_scheme = ${parc}/" $config | sed "s/insert_sub_here/${sub}/g" | sed "s/use_existing_freesurfer_data = .*/use_existing_freesurfer_data = ${existingFS}/" > ${sub}.ini
		sed -i "s|insert_PWD_here|${PWD}|g" ${sub}.ini
	else
		sed 's/seg_tool = Freesurfer/seg_tool = Custom segmentation/' $config | sed 's/parcellation_scheme = Lausanne2008/parcellation_scheme = Custom/' | sed "s/insert_sub_here/${sub}/g" | sed "s/CustomParcHere/${parc}/g" | sed 's/custom_parcellation = False/custom_parcellation = True/' > ${sub}.ini
		sed -i "s|insert_PWD_here|${PWD}|g" ${sub}.ini
		graphml=`cat ${sub}.ini | grep graphml_file | awk '{print $3}'`
		numreg=`cat ${graphml} | grep "node id" | tail -1 | sed 's/.*="//' | sed 's/">//'`
		echo "Using $parc custom Parcellation, with $numreg GM regions."
		sed -i "s/number_of_regions = 0/number_of_regions = ${numreg}/g" ${sub}.ini
		sed -i "s/'number_of_regions': 0/'number_of_regions': ${numreg}/g" ${sub}.ini
	fi
}

#activate cmp beta v02 (David's edition; has mrtrix and gibbs)
source /group_shares/PSYCH/code/release/pipelines/CMP_beta_v02/bin/activate
export SUBJECTS_DIR=/group_shares/PSYCH/code/release/pipelines/CMP_beta_v02/Freesurfer_temp

#disable FSL's automatic parallelization
unset FSLPARALLEL
unset SGE_ROOT

#run connectomemapper according to whether parc is custom or not
if [[ $parc == NativeFreesurfer || $parc == Lausanne2008 ]];then
	make_config $sub $config $parc $existingFS
	connectomemapper $sub ${sub}.ini
else
	#check if CMP has been run yet
	if [ ! -d ${sub}/NIPYPE/diffusion_pipeline/connectome_stage/compute_matrice ];then
		#rerun with Lausanne2008
		echo -e "\n*************************\n"
		echo -e "\nCMP custom matrix creation requires that CMP is first run with Lausanne2008 or NativeFreesurfer...\n"
		echo -e "\nRunning: `basename $0` $sub $config Lausanne2008 $existingFS 0 .\n"
		echo -e "\n*************************\n"
		`basename $0` $sub $config Lausanne2008 $existingFS 0 .
		existingFS=True
	fi
	#now run the custom CMP scripts
	make_cmp_customParc.bash $sub $parc
	make_config $sub $config $parc $existingFS
	CMPdir=`which connectomemapper | sed 's/bin\/connectomemapper/cmp_nipype\/build\/lib/'`
	python2.7 ${basedir}/cmp_v2.1beta_getMatrix.py $sub $sub.ini $parc $CMPdir
fi

##########################################
#### AIRC CLEAN UP #######################
#### perform only if the CMP finished ####
##########################################

#get most recent config file and results folder
confname=`echo $config | sed 's/.*\///' | sed 's/\.ini//'`
cfdir=`ls -d ${sub}/RESULTS/DTI/*/ | tail -1 | sed 's/\/$//'`

if [ -f ${cfdir}/${sub}.ini ];then
	if [ -d ${cfidr} ];then

		#copy custom parc matrices into it
		if [[ $parc != NativeFreesurfer && $parc != Lausanne2008 ]];then
			cp -f ${sub}/NIPYPE/diffusion_pipeline/connectome_stage/compute_matrice/connectome_${parc}*  ${cfdir}/connectivity_matrices
		fi

		#move .tck and .trk files to scratch folder (only if mrtrix probabilistic tracking was run)
		if [[ -f ${sub}/NIPYPE/diffusion_pipeline/diffusion_stage/tracking/mrtrix_probabilistic_tracking/mapflow/_mrtrix_probabilistic_tracking1/diffusion_resampled_CSD_tracked.tck && "$movetrks" != "0" ]];then
			file=${sub}/NIPYPE/diffusion_pipeline/diffusion_stage/tracking/mrtrix_probabilistic_tracking
			mkdir -p `echo ${movetrks_dir}/${file} | sed 's/mrtrix_probabilistic_tracking$//'`
			mv -f ${file} ${movetrks_dir}/${file}
		fi
		if [[ -f ${sub}/NIPYPE/diffusion_pipeline/diffusion_stage/tracking/trackvis/mapflow/_trackvis1/converted.trk && "$movetrks" != "0" ]];then
			file=${sub}/NIPYPE/diffusion_pipeline/diffusion_stage/tracking/trackvis
			mkdir -p `echo ${movetrks_dir}/${file} | sed 's/trackvis$//'`
			mv -f ${file} ${movetrks_dir}/${file}
		fi

		#move config file into subject folder
		mv -f ${sub}.ini ${sub}/${sub}.ini
		#move subject folder to the final directory (if final directory is not .)
		if [[ ${movefinaldir} != ${PWD} ]]; then mv -f ${sub} ${movefinaldir};fi
		#jump to final directory
		pushd ${movefinaldir}
		#convert results folder to full path
		cfdir=`readlink -m ${cfdir}`

		### create symbolic links to the most recent diffusion connectome files
		mkdir -p connectomes_${confname}/${sub}/connectivity_matrices
		for filepath in ${cfdir}/*.ini ${cfdir}/*.log;do #link to the files in the parent connectome folder
			filename=`echo $filepath | sed 's/.*\///'`
			ln -sf ${filepath} connectomes_${confname}/${sub}/${filename}
		done
		for filepath in ${cfdir}/connectivity_matrices/*;do #link to the files in the connectivity_matrices subfolder
			filename=`echo $filepath | sed 's/.*\///'`
			ln -sf ${filepath} connectomes_${confname}/${sub}/connectivity_matrices/${filename}
		done

		#jump back
		popd
	fi
fi

exit
