#!/bin/bash -e

if [[ $# -ne 2 ]]; then
	echo -e "\nUsage:	`basename $0` <subjectFolder> <HCP_group>"
	echo -e "\ni.e	`basename $0` 101939-200_1 ADHD-HumanYouth-OHSU"
	exit 1
fi

sub=$1
group=$2
FSdir=`readlink -m /group_shares/FAIR_HCP/HCP/processed/${group}/${sub}/????????-SIEMENS_TrioTim-Nagel_K_Study/HCP_prerelease_FNL_0_1/T1w/${sub}`
Rawdir=`readlink -m /group_shares/FAIR_HCP/HCP/sorted/${group}/${sub}/????????-SIEMENS_TrioTim-Nagel_K_Study/`
T1data=`readlink -m ${Rawdir}/*T1Anatomical_1_ISO`
DTIdata=`readlink -m ${Rawdir}/*Woodward_DTI_72directions_10b0`
T2data=`readlink -m ${Rawdir}/*t2_spc_1mm_p2`

echo "RUNNING SET-UP SCRIPT ON RAW DATA"
OHSU_createSub.bash ${sub} ${T1data} ${DTIdata} ${T2data}

echo "MAKING FREESURFER FOLDER WITH ALL SYMLINKS TO EXISTING DATA"
pushd $sub
currdir=`readlink -m .`
cp -rs ${FSdir}/ ${currdir}/
mv ${sub} FREESURFER
popd

exit