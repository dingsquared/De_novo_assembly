In order to compile and run UPC code, you will need to set the following environment variables:
You may need to change the following commands based on your shell (the following is an example for BASH)

#find the manual/help documents for UPC
export MANPATH=$MANPATH:/pylon5/cc3uv3p/bbrock/public/share/man
#find the UPC compilers and runtime
export PATH=$PATH:/pylon5/cc3uv3p/bbrock/public/bin:/pylon5/cc3uv3p/bbrock/public/opt/bin

# on ACI you need to load the upc module
#module use /gpfs/group/cfp102/cse597/sw/modules/
#module load upc