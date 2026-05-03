WSL_IP="192.168.1.5"
CMD="powershell.exe -NoProfile -Command \"Start-Process powershell -ArgumentList '-NoProfile -WindowStyle Hidden -Command \\\"route delete 172.20.0.0 MASK 255.255.0.0 2> \$null; route add 172.20.0.0 MASK 255.255.0.0 $WSL_IP\\\"' -Verb RunAs -Wait\""
echo "$CMD"
