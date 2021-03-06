#!/usr/bin/env bash
THISDIR="$( cd "$( dirname "$0" )" && pwd )"

# Run with --gpu if CUDA GPU is available


if [ $# -eq 0 ]; then
    echo "Too few arguments. Usage:
    sh run_ALICE.sh <data_location>
    or
    sh run_ALICE.sh <data_location> --gpu (for GPU-supported environments)

    Data location can be a folder with .wavs, an individual .wav file,
    or a .txt file with file paths to .wavs, one per row. "
    exit 2
fi

if [ $# -ge 3 ]; then
    echo "Too many arguments. Usage:
    sh run_ALICE.sh <data_locationr>
    or
    sh run_ALICE.sh <data_location> --gpu (for GPU-supported environments)

    Data location can be a folder  with .wavs, an individual .wav file,
    or a .txt file with file paths to .wavs, one per row. "
    exit 2
fi

cp $THISDIR/apply_overwrite.sh $THISDIR/voice_type_classifier/apply.sh

DATADIR=$1

if [ $# -ge 2 ]; then
    GPU=$2;
fi;

rm -rf $THISDIR/tmp_data/

mkdir -p $THISDIR/tmp_data/
mkdir -p $THISDIR/tmp_data/short/
mkdir -p $THISDIR/tmp_data/features/

# Run SAD on the files
python prepare_data.py $THISDIR $DATADIR

# Call voice_type_classifier to do broad-class diarization
source activate pyannote
rm -rf $THISDIR/output_voice_type_classifier/
sh $THISDIR/voice_type_classifier/apply.sh $THISDIR/tmp_data/ "MAL FEM" $GPU
source deactivate

# Read .rttm files and split into utterance-sized wavs
python split_to_utterances.py $THISDIR
rm $THISDIR/tmp_data/*.wav


# Extract SylNet syllable counts
python $THISDIR/SylNet/run_SylNet.py $THISDIR/tmp_data/short/ $THISDIR/tmp_data/features/SylNet_out.txt $THISDIR/SylNet_model/model_1

# Extract signal level features
python extract_basic_features.py $THISDIR

# Combine features
paste -d'\t' $THISDIR/tmp_data/features/SylNet_out.txt $THISDIR/tmp_data/features/other_feats.txt > $THISDIR/tmp_data/features/final_feats.txt

# Linear regression from features to unit counts
python regress_ALUCs.py $THISDIR

# Merge with filename information
paste -d'\t' $THISDIR/tmp_data/features/SylNet_out_files.txt $THISDIR/tmp_data/features/ALUCs_out_individual_tmp.txt > $THISDIR/tmp_data/features/ALUCs_out_individual.txt
rm $THISDIR/tmp_data/features/ALUCs_out_individual_tmp.txt

# Get final estimates at clip-level (sum results from short .wavs)
python getFinalEstimates.py $THISDIR $DATADIR

# Cleanup
rm -rf $THISDIR/tmp_data/
cp $THISDIR/output_voice_type_classifier/tmp_data/all.rttm $THISDIR/diarization_output.rttm
rm -rf $THISDIR/output_voice_type_classifier/
