recipient="${1:-junwenyu}"

# Run the synthesis command
make cpu.syn.out

# Check if make succeeded
if [ $? -ne 0 ]; then
    echo "Synthesis failed. Email will not be sent."
    exit 1
fi

clock_period=$(grep "export CLOCK_PERIOD" Makefile)
date_line=$(grep "Date" ./synth/cpu.rep | head -1)
slack_lines=$(grep "slack" ./synth/cpu.rep)
ways_lines=$(grep "WIDTH" ./verilog/sys_defs.svh | head -4)

# Compose the email body
email_body=$(cat <<EOF
$clock_period
$date_line
$slack_lines
$ways_lines
EOF
)

# Send the email
echo "$email_body" | mail -s "[caen] Synthesize result" -a ./synth/cpu.rep "$recipient"