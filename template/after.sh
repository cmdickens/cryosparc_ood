# Wait for the cryoSPARC server to start
echo "Waiting for cryoSPARC server to open host:port ${host}:${port}..."
echo "TIMING - Starting wait at: $(date)"
if wait_until_port_used "${host}:${port}" 39000; then
  echo "Discovered cryoSPARC server listening on port ${port}!"
  echo "TIMING - Wait ended at: $(date)"
  sleep 150
else
  echo "Timed out waiting for cryoSPARC server to open host port ${host}:${port}!"
  echo "TIMING - Wait ended at: $(date)"
  pkill -P ${SCRIPT_PID}
  clean_up 1
fi
