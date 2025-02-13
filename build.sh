#!/bin/bash

build_revision=`date +%-m%d%H%M%S`

usage(){
    echo "usage: ./build.local.sh [-r|--revision build_revision] [-c|--clean-output] [-v|--verbose] [-s|--sharpie] [-o|--output path]"
    echo "parameters:"
    echo "  -r | --revision [build_revision]        Sets the revision number, default = mddhhMMSS ($build_revision)"
    echo "  -c | --clean-output                     Cleans the output before building"
    echo "  -v | --verbose                          Enable verbose build details from msbuild and xbuild tasks"
    echo "  -s | --sharpie                          Regenerates objective sharpie autogenerated files, useful to spot API changes"
    echo "  -o | --output [path]                    Output path"
    echo "  -h | --help                             Prints this message"
    echo
}

while [ "$1" != "" ]; do
    case $1 in
        -r | --revision )       shift
                                build_revision=$1
                                ;;
        -o | --output )         shift
                                output_path=$1
                                ;;
        -c | --clean-output )   clean_output=1
                                ;;
        -v | --verbose )        verbose=1
                                ;;
        -s | --sharpie )        sharpie=1
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     echo "### Wrong parameter: $1 ###"
                                usage
                                exit 1
    esac
    shift
done

# find the latest ID here : https://api.github.com/repos/NordicSemiconductor/IOS-Pods-DFU-Library/releases/latest
github_repo_owner=NordicSemiconductor
github_repo=IOS-Pods-DFU-Library
github_release_id=47049447
github_info_file="$github_repo_owner.$github_repo.$github_release_id.info.json"

if [ ! -f "$github_info_file" ]; then
    echo
    echo "### DOWNLOAD GITHUB INFORMATION ###"
    echo
    github_info_file_url=https://api.github.com/repos/$github_repo_owner/$github_repo/releases/$github_release_id
    echo "Downloading $github_info_file_url to $github_info_file"
    curl -s $github_info_file_url > $github_info_file
fi

echo
echo "### INFORMATION ###"
echo

# Set version
github_tag_name=`cat $github_info_file | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//'`
github_short_version=`echo "$github_tag_name" | sed 's/.LTS//'`
build_version=$github_short_version.$build_revision
echo "##vso[build.updatebuildnumber]$build_version"
if [ -z "$github_short_version" ]; then
    echo "Failed : Could not read Version"
    cat $github_info_file
    exit 1
fi

# Static configuration
nuget_project_folder="Laerdal.Dfu.iOS"
nuget_project_name="Laerdal.Dfu.iOS"
nuget_output_folder="$nuget_project_name.Output"
nuget_csproj_path="$nuget_project_folder/$nuget_project_name.csproj"
nuget_filename="$nuget_project_name.$build_version.nupkg"
nuget_output_file="$nuget_output_folder/$nuget_filename"

nuget_frameworks_folder="$nuget_project_folder/Frameworks"

source_folder="Laerdal.Dfu.iOS.Source"
source_zip_folder="Laerdal.Dfu.iOS.Zips"
source_zip_file_name="$github_short_version.zip"
source_zip_file="$source_zip_folder/$source_zip_file_name"
source_zip_url="http://github.com/$github_repo_owner/$github_repo/zipball/$github_tag_name"

xbuild=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild

if [ "$sharpie" = "1" ]; then
    sharpie_version=`sharpie -v`
    sharpie_output_path=$nuget_project_folder/Sharpie_Generated
    sharpie_output_file=$sharpie_output_path/ApiDefinitions.cs
fi

# Generates variables
echo "build_version = $build_version"
echo
echo "github_repo_owner = $github_repo_owner"
echo "github_repo = $github_repo"
echo "github_release_id = $github_release_id"
echo "github_info_file = $github_info_file"
echo "github_tag_name = $github_tag_name"
echo "github_short_version = $github_short_version"
echo
echo "source_folder = $source_folder"
echo "source_zip_folder = $source_zip_folder"
echo "source_zip_file_name = $source_zip_file_name"
echo "source_zip_file = $source_zip_file"
echo "source_zip_url = $source_zip_url"
echo
echo "nuget_project_folder = $nuget_project_folder"
echo "nuget_output_folder = $nuget_output_folder"
echo "nuget_project_name = $nuget_project_name"
echo "nuget_frameworks_folder = $nuget_frameworks_folder"
echo "nuget_csproj_path = $nuget_csproj_path"
echo "nuget_filename = $nuget_filename"
echo "nuget_output_file = $nuget_output_file"

if [ "$sharpie" = "1" ]; then
    echo
    echo "sharpie_version = $sharpie_version"
    echo "sharpie_output_path = $sharpie_output_path"
    echo "sharpie_output_file = $sharpie_output_file"
fi

if [ "$clean_output" = "1" ]; then
    echo
    echo "### CLEAN OUTPUT ###"
    echo
    rm -rf $nuget_output_folder
    echo "Deleted : $nuget_output_folder"
fi

if [ ! -f "$source_zip_file" ]; then

    echo
    echo "### DOWNLOAD GITHUB RELEASE FILES ###"
    echo

    mkdir -p $source_zip_folder
    curl -L -o $source_zip_file $source_zip_url

    if [ ! -f "$source_zip_file" ]; then
        echo "Failed to download $source_zip_url into $source_zip_file"
        exit 1
    fi

    echo "Downloaded $source_zip_url into $source_zip_file"
fi

echo
echo "### UNZIP SOURCE ###"
echo

rm -rf $source_folder
unzip -qq -n -d "$source_folder" "$source_zip_file"
if [ ! -d "$source_folder" ]; then
    echo "Failed"
    exit 1
fi
echo "Unzipped $source_zip_file into $source_folder"

# NOTE : Updating objective sharpie to >3.5 made this step obsolete
# echo
# echo "### APPLY MAGIC REGEX ###"
# echo

# for i in `find ./$source_folder/ -ipath "*iOSDFULibrary/Classes/*" -iname "*.swift" -type f`; do
#     echo "- $i"
#     sed -i.old -E 's/@objc (public|internal|open) (class|enum|protocol) ([A-Za-z0-9]*)/@objc(\3) \1 \2 \3/g' $i
# done

echo
echo "### XBUILD ###"
echo

xbuild_parameters=""
xbuild_parameters="${xbuild_parameters} ONLY_ACTIVE_ARCH=NO"
xbuild_parameters="${xbuild_parameters} ENABLE_BITCODE=NO"
xbuild_parameters="${xbuild_parameters} ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES"

if [ ! "$verbose" = "1" ]; then
    xbuild_parameters="${xbuild_parameters} -quiet"
fi
xbuild_parameters="${xbuild_parameters} -project $source_folder/**/_Pods.xcodeproj"
xbuild_parameters="${xbuild_parameters} -configuration Release"

echo "xbuild_parameters = $xbuild_parameters -sdk iphoneos build"
echo

$xbuild $xbuild_parameters -sdk iphoneos build
# $xbuild $xbuild_parameters -sdk iphonesimulator build

iOSDFULibrary_iphoneos_framework=`find ./$source_folder/ -ipath "*iphoneos*" -iname "iOSDFULibrary.framework" | head -n 1`
ZIPFoundation_iphoneos_framework=`find ./$source_folder/ -ipath "*iphoneos*" -iname "ZIPFoundation.framework" | head -n 1`
# iOSDFULibrary_iphonesimulator_framework=`find ./$source_folder/ -ipath "*iphonesimulator*" -iname "iOSDFULibrary.framework" | head -n 1`
# ZIPFoundation_iphonesimulator_framework=`find ./$source_folder/ -ipath "*iphonesimulator*" -iname "ZIPFoundation.framework" | head -n 1`

if [ ! -d "$iOSDFULibrary_iphoneos_framework" ]; then
    echo "Failed : $iOSDFULibrary_iphoneos_framework does not exist"
    exit 1
fi
if [ ! -d "$ZIPFoundation_iphoneos_framework" ]; then
    echo "Failed : $ZIPFoundation_iphoneos_framework does not exist"
    exit 1
fi
# if [ ! -d "$iOSDFULibrary_iphonesimulator_framework" ]; then
#     echo "Failed : $iOSDFULibrary_iphonesimulator_framework does not exist"
#     exit 1
# fi
# if [ ! -d "$ZIPFoundation_iphonesimulator_framework" ]; then
#     echo "Failed : $ZIPFoundation_iphonesimulator_framework does not exist"
#     exit 1
# fi

echo "Created :"
echo "  - $iOSDFULibrary_iphoneos_framework"
echo "  - $ZIPFoundation_iphoneos_framework"
# echo "  - $iOSDFULibrary_iphonesimulator_framework"
# echo "  - $ZIPFoundation_iphonesimulator_framework"

echo
echo "### LIPO / CREATE FAT LIBRARY ###"
echo

rm -rf $nuget_frameworks_folder
cp -a $(dirname $iOSDFULibrary_iphoneos_framework)/. $nuget_frameworks_folder
cp -a $(dirname $ZIPFoundation_iphoneos_framework)/. $nuget_frameworks_folder

rm -rf $nuget_frameworks_folder/iOSDFULibrary.framework/iOSDFULibrary
lipo -create -output $nuget_frameworks_folder/iOSDFULibrary.framework/iOSDFULibrary $iOSDFULibrary_iphoneos_framework/iOSDFULibrary
lipo -info $nuget_frameworks_folder/iOSDFULibrary.framework/iOSDFULibrary

# TODO : Create Laerdal.Xamarin.ZipFoundation.iOS
#rm -rf $nuget_frameworks_folder/ZIPFoundation.framework/ZIPFoundation
#lipo -create -output $nuget_frameworks_folder/ZIPFoundation.framework/ZIPFoundation $ZIPFoundation_iphoneos_framework/ZIPFoundation $ZIPFoundation_iphonesimulator_framework/ZIPFoundation
lipo -info $nuget_frameworks_folder/ZIPFoundation.framework/ZIPFoundation

if [ "$sharpie" = "1" ]; then
    echo
    echo "### SHARPIE ###"
    echo

    sharpie bind -sdk iphoneos -o $sharpie_output_path -n $nuget_project_name -f $nuget_frameworks_folder/iOSDFULibrary.framework
fi

echo
echo "### MSBUILD ###"
echo

msbuild_parameters=""
if [ ! "$verbose" = "1" ]; then
    msbuild_parameters="${msbuild_parameters} -nologo -verbosity:quiet"
fi
msbuild_parameters="${msbuild_parameters} -t:Rebuild"
msbuild_parameters="${msbuild_parameters} -restore:True"
msbuild_parameters="${msbuild_parameters} -p:Configuration=Release"
msbuild_parameters="${msbuild_parameters} -p:PackageVersion=$build_version"
echo "msbuild_parameters = $msbuild_parameters"
echo

rm -rf $nuget_project_folder/bin
rm -rf $nuget_project_folder/obj
msbuild $nuget_csproj_path $msbuild_parameters

if [ -f "$nuget_output_file" ]; then
    echo "Created :"
    echo "  - $nuget_output_file"
    echo
    rm -rf $nuget_frameworks_folder
else
    echo "Failed : Can't find '$nuget_output_file'"
    exit 1
fi

if [ ! -z "$output_path" ]; then

    echo
    echo "### COPY FILES TO OUTPUT ###"
    echo

    mkdir -p $output_path
    cp -a $(dirname $nuget_output_file)/. $output_path

    echo "Copied into $output_path"
fi