set pagination off
set confirm off
set print thread-events off
set breakpoint pending on
set $rd_count = 0
break RenderingDevice::RenderingDevice()
commands
silent
set $rd_count = $rd_count + 1
printf "RMMO_RD_CONSTRUCTOR count=%d\n", $rd_count
continue
end
run
printf "RMMO_RD_COUNT_FINAL=%d\n", $rd_count
