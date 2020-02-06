shell echo -e "\nWaiting for 2 secs..."
shell sleep 2
shell echo -e "Executing gdb commands in local .gdbinit ..."

shell echo -e "\n(gdb) target remote :1234"
target remote :1234

shell sleep 1
shell echo -e "\n(gdb) break main"
break main

shell sleep 1
shell echo -e "\n(gdb) continue"
continue
