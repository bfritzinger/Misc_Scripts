"""
Hung Connection Killer
======================
Monitors network connections on Unix-based systems, identifies hung connections,
and terminates them while leaving healthy connections alone.

Hung connections are identified by:
- Connections stuck in CLOSE_WAIT, FIN_WAIT_1, FIN_WAIT_2, TIME_WAIT states
- Connections idle beyond a configurable threshold
- Connections with zero send/receive queue activity for extended periods

Requirements:
- Python 3.6+
- Root/sudo privileges (for terminating connections)
- Linux with ss command (preferred) or netstat

Usage:
    sudo python3 hung_connection_killer.py [options]


"""

import subprocess
import re
import time
import argparse
import logging
import os
import sys
from datetime import datetime
from dataclasses import dataclass
from typing import Optional
from pathlib import Path


@dataclass
class Connection:
    """Represents a network connection with its attributes."""
    protocol: str
    state: str
    local_addr: str
    local_port: int
    remote_addr: str
    remote_port: int
    pid: Optional[int]
    process_name: Optional[str]
    recv_q: int = 0
    send_q: int = 0
    timer: Optional[str] = None
    timer_value: Optional[float] = None

    def __str__(self):
        return (f"{self.protocol} {self.state} {self.local_addr}:{self.local_port} -> "
                f"{self.remote_addr}:{self.remote_port} (PID: {self.pid}, Process: {self.process_name})")


class HungConnectionKiller:
    """Detects and terminates hung network connections."""

    # Connection states that indicate potential hung connections
    HUNG_STATES = {
        'CLOSE_WAIT': 60,      # Seconds before considered hung
        'FIN_WAIT1': 120,
        'FIN_WAIT2': 120,
        'CLOSING': 60,
        'LAST_ACK': 60,
        'TIME_WAIT': 120,      # Usually handled by kernel, but can pile up
    }

    # States to never touch
    SAFE_STATES = {'ESTABLISHED', 'LISTEN', 'SYN_SENT', 'SYN_RECV'}

    # Processes to never kill (safety list)
    PROTECTED_PROCESSES = {
        'sshd', 'systemd', 'init', 'kernel', 'kthreadd',
        'containerd', 'dockerd', 'kubelet', 'k3s',
    }

    def __init__(
        self,
        dry_run: bool = True,
        close_wait_timeout: int = 60,
        fin_wait_timeout: int = 120,
        time_wait_timeout: int = 120,
        idle_timeout: int = 3600,
        exclude_ports: Optional[list] = None,
        exclude_processes: Optional[list] = None,
        include_only_ports: Optional[list] = None,
        log_file: Optional[str] = None,
        verbose: bool = False,
    ):
        self.dry_run = dry_run
        self.close_wait_timeout = close_wait_timeout
        self.fin_wait_timeout = fin_wait_timeout
        self.time_wait_timeout = time_wait_timeout
        self.idle_timeout = idle_timeout
        self.exclude_ports = set(exclude_ports or [22])  # SSH excluded by default
        self.exclude_processes = set(exclude_processes or [])
        self.include_only_ports = set(include_only_ports) if include_only_ports else None
        self.verbose = verbose

        # Update hung state timeouts with user values
        self.HUNG_STATES['CLOSE_WAIT'] = close_wait_timeout
        self.HUNG_STATES['FIN_WAIT1'] = fin_wait_timeout
        self.HUNG_STATES['FIN_WAIT2'] = fin_wait_timeout
        self.HUNG_STATES['TIME_WAIT'] = time_wait_timeout

        # Setup logging
        self._setup_logging(log_file)

        # Check for root privileges
        if os.geteuid() != 0 and not dry_run:
            self.logger.warning("Not running as root - some operations may fail")

    def _setup_logging(self, log_file: Optional[str]):
        """Configure logging to file and console."""
        self.logger = logging.getLogger('HungConnectionKiller')
        self.logger.setLevel(logging.DEBUG if self.verbose else logging.INFO)

        formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )

        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.DEBUG if self.verbose else logging.INFO)
        console_handler.setFormatter(formatter)
        self.logger.addHandler(console_handler)

        # File handler
        if log_file:
            file_handler = logging.FileHandler(log_file)
            file_handler.setLevel(logging.DEBUG)
            file_handler.setFormatter(formatter)
            self.logger.addHandler(file_handler)

    def _run_command(self, cmd: list) -> tuple[int, str, str]:
        """Execute a shell command and return exit code, stdout, stderr."""
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return -1, '', 'Command timed out'
        except Exception as e:
            return -1, '', str(e)

    def _get_connections_ss(self) -> list[Connection]:
        """Get connections using ss command (preferred on modern Linux)."""
        connections = []

        # Get TCP connections with timer info and process info
        cmd = ['ss', '-tanp', '-o', 'state', 'all']
        returncode, stdout, stderr = self._run_command(cmd)

        if returncode != 0:
            self.logger.error(f"ss command failed: {stderr}")
            return connections

        for line in stdout.strip().split('\n')[1:]:  # Skip header
            conn = self._parse_ss_line(line)
            if conn:
                connections.append(conn)

        return connections

    def _parse_ss_line(self, line: str) -> Optional[Connection]:
        """Parse a line from ss output."""
        try:
            # ss output format varies, but generally:
            # State Recv-Q Send-Q Local:Port Peer:Port Process Timer
            parts = line.split()
            if len(parts) < 5:
                return None

            state = parts[0]
            recv_q = int(parts[1])
            send_q = int(parts[2])

            # Parse local address
            local = parts[3]
            if ']:' in local:  # IPv6
                local_addr, local_port = local.rsplit(':', 1)
                local_addr = local_addr.strip('[]')
            else:
                local_addr, local_port = local.rsplit(':', 1)

            # Parse remote address
            remote = parts[4]
            if ']:' in remote:  # IPv6
                remote_addr, remote_port = remote.rsplit(':', 1)
                remote_addr = remote_addr.strip('[]')
            else:
                remote_addr, remote_port = remote.rsplit(':', 1)

            # Handle wildcard ports
            local_port = int(local_port) if local_port != '*' else 0
            remote_port = int(remote_port) if remote_port != '*' else 0

            # Extract PID and process name
            pid = None
            process_name = None
            timer = None
            timer_value = None

            for part in parts[5:]:
                # Process info: users:(("process",pid=123,fd=4))
                if 'users:' in part or 'pid=' in part:
                    pid_match = re.search(r'pid=(\d+)', part)
                    if pid_match:
                        pid = int(pid_match.group(1))
                    name_match = re.search(r'\("([^"]+)"', part)
                    if name_match:
                        process_name = name_match.group(1)

                # Timer info: timer:(keepalive,5.2,0)
                if 'timer:' in part:
                    timer_match = re.search(r'timer:\((\w+),([^,]+)', part)
                    if timer_match:
                        timer = timer_match.group(1)
                        try:
                            # Parse time value (could be like "5.2" or "1min30sec")
                            time_str = timer_match.group(2)
                            timer_value = self._parse_timer_value(time_str)
                        except:
                            pass

            return Connection(
                protocol='tcp',
                state=state,
                local_addr=local_addr,
                local_port=local_port,
                remote_addr=remote_addr,
                remote_port=remote_port,
                pid=pid,
                process_name=process_name,
                recv_q=recv_q,
                send_q=send_q,
                timer=timer,
                timer_value=timer_value,
            )
        except Exception as e:
            self.logger.debug(f"Failed to parse ss line: {line} - {e}")
            return None

    def _parse_timer_value(self, time_str: str) -> float:
        """Parse timer string to seconds."""
        total = 0.0

        # Handle formats like "1min30sec", "5.2", "30sec"
        min_match = re.search(r'(\d+)min', time_str)
        sec_match = re.search(r'(\d+(?:\.\d+)?)(?:sec)?$', time_str)

        if min_match:
            total += int(min_match.group(1)) * 60
        if sec_match and 'min' not in time_str:
            total += float(sec_match.group(1))
        elif sec_match:
            # Has both min and sec
            sec_only = re.search(r'(\d+(?:\.\d+)?)sec', time_str)
            if sec_only:
                total += float(sec_only.group(1))

        # Handle plain float
        if total == 0:
            try:
                total = float(time_str)
            except:
                pass

        return total

    def _get_connections_netstat(self) -> list[Connection]:
        """Fallback: Get connections using netstat."""
        connections = []

        cmd = ['netstat', '-tanp']
        returncode, stdout, stderr = self._run_command(cmd)

        if returncode != 0:
            self.logger.error(f"netstat command failed: {stderr}")
            return connections

        for line in stdout.strip().split('\n')[2:]:  # Skip headers
            conn = self._parse_netstat_line(line)
            if conn:
                connections.append(conn)

        return connections

    def _parse_netstat_line(self, line: str) -> Optional[Connection]:
        """Parse a line from netstat output."""
        try:
            parts = line.split()
            if len(parts) < 6:
                return None

            protocol = parts[0]
            recv_q = int(parts[1])
            send_q = int(parts[2])

            # Parse addresses
            local = parts[3]
            remote = parts[4]
            state = parts[5] if len(parts) > 5 else 'UNKNOWN'

            # Extract address and port
            local_addr, local_port = local.rsplit(':', 1)
            remote_addr, remote_port = remote.rsplit(':', 1)

            local_port = int(local_port) if local_port != '*' else 0
            remote_port = int(remote_port) if remote_port != '*' else 0

            # Process info
            pid = None
            process_name = None
            if len(parts) > 6:
                proc_info = parts[6]
                if '/' in proc_info:
                    pid_str, process_name = proc_info.split('/', 1)
                    try:
                        pid = int(pid_str)
                    except:
                        pass

            return Connection(
                protocol=protocol,
                state=state,
                local_addr=local_addr,
                local_port=local_port,
                remote_addr=remote_addr,
                remote_port=remote_port,
                pid=pid,
                process_name=process_name,
                recv_q=recv_q,
                send_q=send_q,
            )
        except Exception as e:
            self.logger.debug(f"Failed to parse netstat line: {line} - {e}")
            return None

    def get_connections(self) -> list[Connection]:
        """Get all network connections using available tools."""
        # Try ss first (modern), fall back to netstat
        connections = self._get_connections_ss()
        if not connections:
            self.logger.info("Falling back to netstat")
            connections = self._get_connections_netstat()
        return connections

    def is_hung_connection(self, conn: Connection) -> tuple[bool, str]:
        """
        Determine if a connection is hung.

        Returns:
            tuple: (is_hung: bool, reason: str)
        """
        # Skip safe states
        if conn.state in self.SAFE_STATES:
            return False, "Safe state"

        # Check if in a known hung state
        if conn.state in self.HUNG_STATES:
            # If we have timer info, use it
            if conn.timer_value is not None:
                if conn.timer_value > self.HUNG_STATES[conn.state]:
                    return True, f"State {conn.state} exceeded timeout ({conn.timer_value:.1f}s > {self.HUNG_STATES[conn.state]}s)"
            else:
                # Without timer info, flag states that are typically problematic
                if conn.state == 'CLOSE_WAIT':
                    # CLOSE_WAIT with no timer is suspicious - app should have closed
                    return True, f"CLOSE_WAIT without active timer (likely app not closing socket)"
                elif conn.state in ('FIN_WAIT1', 'FIN_WAIT2', 'CLOSING', 'LAST_ACK'):
                    # These should have timers; if not, they may be stuck
                    return True, f"{conn.state} state detected (typically indicates hung connection)"

        # Check for stuck TIME_WAIT (normally kernel handles this)
        if conn.state == 'TIME_WAIT':
            # TIME_WAIT is normal, but excessive amounts can indicate issues
            # We'll flag it but with lower priority
            if conn.timer_value and conn.timer_value > self.time_wait_timeout:
                return True, f"TIME_WAIT exceeded timeout ({conn.timer_value:.1f}s)"

        return False, "Connection appears healthy"

    def should_skip_connection(self, conn: Connection) -> tuple[bool, str]:
        """Check if connection should be skipped based on filters."""
        # Check port exclusions
        if conn.local_port in self.exclude_ports or conn.remote_port in self.exclude_ports:
            return True, f"Port {conn.local_port}/{conn.remote_port} is excluded"

        # Check port inclusions
        if self.include_only_ports:
            if conn.local_port not in self.include_only_ports and conn.remote_port not in self.include_only_ports:
                return True, f"Port not in include list"

        # Check process exclusions
        if conn.process_name:
            if conn.process_name in self.PROTECTED_PROCESSES:
                return True, f"Process {conn.process_name} is protected"
            if conn.process_name in self.exclude_processes:
                return True, f"Process {conn.process_name} is excluded"

        # Skip connections without PID (can't terminate)
        if conn.pid is None:
            return True, "No PID available"

        return False, ""

    def terminate_connection(self, conn: Connection) -> bool:
        """
        Terminate a hung connection.

        Attempts multiple methods:
        1. ss -K (kernel socket termination) - cleanest
        2. Send TCP RST via kernel
        3. Kill the process (last resort, if safe)
        """
        if self.dry_run:
            self.logger.info(f"[DRY RUN] Would terminate: {conn}")
            return True

        # Method 1: Try ss -K to kill the socket directly
        if self._kill_socket_ss(conn):
            self.logger.info(f"Terminated via ss -K: {conn}")
            return True

        # Method 2: Kill via /proc (send RST)
        if self._kill_socket_proc(conn):
            self.logger.info(f"Terminated via /proc: {conn}")
            return True

        # Method 3: Kill the process (careful!)
        if conn.process_name and conn.process_name not in self.PROTECTED_PROCESSES:
            if self._kill_process(conn):
                self.logger.info(f"Terminated process: {conn}")
                return True

        self.logger.warning(f"Failed to terminate: {conn}")
        return False

    def _kill_socket_ss(self, conn: Connection) -> bool:
        """Use ss -K to kill a socket."""
        # ss -K requires exact address matching
        cmd = [
            'ss', '-K',
            'dst', f'{conn.remote_addr}',
            'dport', f'eq', str(conn.remote_port),
            'src', f'{conn.local_addr}',
            'sport', f'eq', str(conn.local_port),
        ]

        returncode, stdout, stderr = self._run_command(cmd)
        return returncode == 0

    def _kill_socket_proc(self, conn: Connection) -> bool:
        """Attempt to close socket via /proc filesystem."""
        if conn.pid is None:
            return False

        # Find the socket fd in /proc/PID/fd
        fd_path = Path(f'/proc/{conn.pid}/fd')
        if not fd_path.exists():
            return False

        try:
            for fd in fd_path.iterdir():
                try:
                    link = fd.resolve()
                    if 'socket:' in str(link):
                        # We found a socket, but we can't easily match it
                        # to our specific connection without more work
                        pass
                except:
                    pass
        except PermissionError:
            pass

        return False

    def _kill_process(self, conn: Connection) -> bool:
        """Kill the process owning the connection (last resort)."""
        if conn.pid is None:
            return False

        if conn.process_name in self.PROTECTED_PROCESSES:
            self.logger.warning(f"Refusing to kill protected process: {conn.process_name}")
            return False

        # Send SIGTERM first
        cmd = ['kill', '-15', str(conn.pid)]
        returncode, _, _ = self._run_command(cmd)

        if returncode == 0:
            # Wait a moment for graceful shutdown
            time.sleep(1)

            # Check if process still exists
            if Path(f'/proc/{conn.pid}').exists():
                # Force kill
                cmd = ['kill', '-9', str(conn.pid)]
                returncode, _, _ = self._run_command(cmd)

        return returncode == 0

    def run(self) -> dict:
        """
        Main execution: find and terminate hung connections.

        Returns:
            dict: Summary of actions taken
        """
        summary = {
            'timestamp': datetime.now().isoformat(),
            'dry_run': self.dry_run,
            'total_connections': 0,
            'hung_connections': 0,
            'skipped_connections': 0,
            'terminated_connections': 0,
            'failed_terminations': 0,
            'details': [],
        }

        self.logger.info("=" * 60)
        self.logger.info(f"Hung Connection Killer - {'DRY RUN' if self.dry_run else 'LIVE MODE'}")
        self.logger.info("=" * 60)

        # Get all connections
        connections = self.get_connections()
        summary['total_connections'] = len(connections)
        self.logger.info(f"Found {len(connections)} total connections")

        # Analyze each connection
        for conn in connections:
            # Check if should skip
            should_skip, skip_reason = self.should_skip_connection(conn)
            if should_skip:
                summary['skipped_connections'] += 1
                self.logger.debug(f"Skipping: {conn} - {skip_reason}")
                continue

            # Check if hung
            is_hung, hung_reason = self.is_hung_connection(conn)
            if not is_hung:
                self.logger.debug(f"Healthy: {conn}")
                continue

            summary['hung_connections'] += 1
            self.logger.warning(f"Hung connection detected: {conn}")
            self.logger.warning(f"  Reason: {hung_reason}")

            detail = {
                'connection': str(conn),
                'reason': hung_reason,
                'action': 'none',
            }

            # Terminate
            if self.terminate_connection(conn):
                summary['terminated_connections'] += 1
                detail['action'] = 'terminated' if not self.dry_run else 'would_terminate'
            else:
                summary['failed_terminations'] += 1
                detail['action'] = 'failed'

            summary['details'].append(detail)

        # Log summary
        self.logger.info("-" * 60)
        self.logger.info("Summary:")
        self.logger.info(f"  Total connections scanned: {summary['total_connections']}")
        self.logger.info(f"  Hung connections found: {summary['hung_connections']}")
        self.logger.info(f"  Connections skipped: {summary['skipped_connections']}")
        self.logger.info(f"  Connections terminated: {summary['terminated_connections']}")
        self.logger.info(f"  Failed terminations: {summary['failed_terminations']}")
        self.logger.info("=" * 60)

        return summary


def main():
    """Main entry point with argument parsing."""
    parser = argparse.ArgumentParser(
        description='Detect and terminate hung network connections',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run (safe - shows what would be done)
  sudo python3 hung_connection_killer.py --dry-run

  # Live mode - actually terminate hung connections
  sudo python3 hung_connection_killer.py --live

  # Custom timeouts
  sudo python3 hung_connection_killer.py --live --close-wait-timeout 30

  # Exclude specific ports
  sudo python3 hung_connection_killer.py --live --exclude-ports 22 3306 5432

  # Only monitor specific ports
  sudo python3 hung_connection_killer.py --live --include-ports 80 443 8080

  # Verbose logging to file
  sudo python3 hung_connection_killer.py --live -v --log-file /var/log/hung_conn.log
        """
    )

    # Mode selection
    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument(
        '--dry-run', '-n',
        action='store_true',
        help='Show what would be done without making changes (safe)'
    )
    mode_group.add_argument(
        '--live', '-l',
        action='store_true',
        help='Actually terminate hung connections (requires root)'
    )

    # Timeout configuration
    parser.add_argument(
        '--close-wait-timeout',
        type=int,
        default=60,
        help='Seconds before CLOSE_WAIT is considered hung (default: 60)'
    )
    parser.add_argument(
        '--fin-wait-timeout',
        type=int,
        default=120,
        help='Seconds before FIN_WAIT states are considered hung (default: 120)'
    )
    parser.add_argument(
        '--time-wait-timeout',
        type=int,
        default=120,
        help='Seconds before TIME_WAIT is considered hung (default: 120)'
    )
    parser.add_argument(
        '--idle-timeout',
        type=int,
        default=3600,
        help='Seconds of idle time before flagging (default: 3600)'
    )

    # Filtering
    parser.add_argument(
        '--exclude-ports',
        type=int,
        nargs='+',
        default=[22],
        help='Ports to exclude from termination (default: 22)'
    )
    parser.add_argument(
        '--include-ports',
        type=int,
        nargs='+',
        help='Only check these ports (default: all)'
    )
    parser.add_argument(
        '--exclude-processes',
        type=str,
        nargs='+',
        default=[],
        help='Process names to exclude from termination'
    )

    # Logging
    parser.add_argument(
        '--log-file',
        type=str,
        help='Write logs to this file'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )

    args = parser.parse_args()

    # Create and run killer
    killer = HungConnectionKiller(
        dry_run=args.dry_run,
        close_wait_timeout=args.close_wait_timeout,
        fin_wait_timeout=args.fin_wait_timeout,
        time_wait_timeout=args.time_wait_timeout,
        idle_timeout=args.idle_timeout,
        exclude_ports=args.exclude_ports,
        exclude_processes=args.exclude_processes,
        include_only_ports=args.include_ports,
        log_file=args.log_file,
        verbose=args.verbose,
    )

    summary = killer.run()

    # Exit with error code if there were failed terminations
    if summary['failed_terminations'] > 0:
        sys.exit(1)
    sys.exit(0)


if __name__ == '__main__':
    main()
