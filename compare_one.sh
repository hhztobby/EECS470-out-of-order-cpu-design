#!/bin/bash
 echo "Usage: ./compare_one.sh [program_name]  You can see diff_output.txt for details"
 # Define the file name directly in the script insertionsort
 filename="mult_no_lsq"
if [ -n "$1" ]; then
    filename="$1"
    echo "Running ${filename} "
else 
    echo "Running default program"
fi
 
 
 # Run make to generate the output file
 make "${filename}.out"
 
 # Compare the output files
 if [ -f "output/${filename}.wb" ] && [ -f "./correct_out/${filename}.wb" ]; then
     echo "Comparing output/${filename}.wb with .correct_out/${filename}.wb"
     diff "output/${filename}.wb" "./correct_out/${filename}.wb" > diff_output_wb.txt
     if [ $? -eq 0 ]; then
         echo -e "\e[32mThe wb files are identical.\e[0m" # Display message in green
     else
         echo -e "\e[31mThe wb files differ. Check diff_output.txt for details.\e[0m" # Display message in red
     fi
    # 还要比较.out文件
    if [ -f "output/${filename}.out" ] && [ -f "./correct_out/${filename}.out" ]; then
        echo "Comparing output/${filename}.out with .correct_out/${filename}.out"
        diff "output/${filename}.out" "./correct_out/${filename}.out" > diff_output_out.txt
        if [ $? -eq 0 ]; then
           echo -e "\e[32mThe .out files are identical.\e[0m" # Display message in green
        else
           echo -e "\e[31mThe .out files differ. Check diff_output_out.txt for details.\e[0m" # Display message in red
        fi
    else
        echo "One or both .out files do not exist. Please check the file paths."
    fi

 else
     echo "One or both files do not exist. Please check the file paths."
 fi

# Play two beeps to indicate completion
echo -e "\a"
sleep 0.5
echo -e "\a"
