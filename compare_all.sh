#!/bin/bash

echo "Usage: ./compare_all.sh [syn]"

mode="sim"
if [ "$1" == "syn" ]; then
    mode="syn"
    echo "Running in synthesis mode"
else 
    echo "Running in simulation mode"
fi

# Define the file name directly in the script
# Read the list of files in the programs folder and store only the filenames
correct_out_dir="correct_out"
file_list=$(ls programs | grep -E '\.c$' | sed 's/\..*$//')

file_names_to_ignore=("crt") #  "alexnet" "dft" "insertionsort" "outer_product" "sort_search"

# If the results_summary.txt file already exists, delete it
if [ -f results_summary.txt ]; then
    rm results_summary.txt
fi

# Add a header to the results_summary.txt file
printf "%-20s %-10s %-10s %-10s %-10s %-10s\n" \
    "Program Name" "WB Status" "OUT Status" "CPI Curr" "CPI Prev" "CPI Ratio" > test_summary.txt
printf "%-20s %-10s %-10s %-10s %-10s %-10s\n" \
    "------------" "---------" "----------" "---------" "----------" "---------" >> test_summary.txt

echo "Running make to check for warnings and errors"

make clean > /dev/null 2>&1

if [ "$mode" = "syn" ]; then
    make cpu.syn.out 2>&1 | grep -i -E "warning|error"
else
    make cpu.out 2>&1 | grep -i -E "warning|error"
fi

echo ""
echo "Dry run (synthesis if [syn]) completed. Running programs."
echo "Files to ignore: "
for ignore in "${file_names_to_ignore[@]}"; do
    echo -e "\t$ignore"
done

# print_current_cycle() {
#     local file=$1  # The first argument is the file name
#     sleep 10
#     while true; do
#         if [ ! -f "$file_name" ]; then
#             break;
#         fi
#         grep "cycle" "$file" | tail -n 1
#         sleep 10  # Wait for 10 seconds before running again
#     done
# }

# Loop through each file and run make to generate the output file
for filename in $file_list; do
    # if [ "$filename" = "crt" ];then
	# 	continue
	# fi
    skip=false
    for ignore in "${file_names_to_ignore[@]}"; do
        if [ "$filename" = "$ignore" ]; then
            skip=true
            break
        fi
    done
    if $skip; then
        continue
    fi
    # Print the current file being processed
    echo "-------------------------- ${filename} begins --------------------------"
    start_time=$(date +%s)
    if [ "$mode" = "syn" ]; then
        make "${filename}.syn.out" > /dev/null 2>&1
    else
        make "${filename}.out" > /dev/null 2>&1
    fi
    echo "-------------------------- ${filename} ends --------------------------"
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))
    echo "Elapsed time: ${elapsed} seconds"

    # Initialize variables for the table
    wb_status=""
    out_status=""
    cpi_current="N/A"
    cpi_previous="N/A"
    cpi_ratio="N/A"

    wb_suffix="wb"
    out_suffix="out"
    cpi_suffix="cpi"
    if [ "$mode" = "syn" ]; then
        wb_suffix="syn.wb"
        out_suffix="syn.out"
        cpi_suffix="syn.cpi"
    fi

    # Compare the output files
    if [ -f "output/${filename}.${wb_suffix}" ] && [ -f "./${correct_out_dir}/${filename}.wb" ]; then
        echo "Comparing output/${filename}.${wb_suffix} with ./${correct_out_dir}/${filename}.wb"
        diff "output/${filename}.${wb_suffix}" "./${correct_out_dir}/${filename}.wb" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            wb_status="Different"
            echo "Result is DIFFERENT!!!"
            break;
        fi
    else
        wb_status="Missing"
    fi

    # Compare the .out files
    if [ -f "output/${filename}.${out_suffix}" ] && [ -f "./${correct_out_dir}/${filename}.out" ]; then
        echo "Comparing output/${filename}.${out_suffix} with ./${correct_out_dir}/${filename}.out"
        diff "output/${filename}.${out_suffix}" "./${correct_out_dir}/${filename}.out" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            out_status="Different"
            echo "Result is DIFFERENT!!!"
            break;
        fi
    else
        out_status="Missing"
    fi

    # Extract CPI values from the current output file
    if [ -f "output/${filename}.${out_suffix}" ]; then
        cpi_current=$(grep 'CPI' "./output/${filename}.${cpi_suffix}" | sed -n 's/.*= *\([0-9]\+\.[0-9]\{3\}\)[0-9]* *CPI/\1/p')
    fi

    # Extract CPI values from the previous output file
    if [ -f "./${correct_out_dir}/${filename}.out" ]; then
        cpi_previous=$(grep 'CPI' "./${correct_out_dir}/${filename}.cpi" | sed -n 's/.*= *\([0-9]\+\.[0-9]\{3\}\)[0-9]* *CPI/\1/p')
    fi

    # Calculate the CPI ratio if both values are available
    if [[ -n $cpi_current && -n $cpi_previous ]]; then
        cpi_ratio=$(awk "BEGIN {printf \"%.2f\", $cpi_previous / $cpi_current}")
    fi



    # Append results to a summary file with proper alignment
    printf "%-20s %-10s %-10s %-10s %-10s %-10s\n" \
        "${filename}" "${wb_status}" "${out_status}" "${cpi_current}" "${cpi_previous}" "${cpi_ratio}" >> test_summary.txt
    echo -e "\a"
    sleep 0.5
    echo -e "\a"

done
echo -e "\a"
sleep 0.5
echo -e "\a"