import argparse
import time
from typing import Any

from protocol import (
    CMD_READ_OUTPUT,
    ERROR_NAMES,
    ERR_BAD_COMMAND,
    ERR_READ_NO_RESULT,
    RESP_OUTPUT,
)


def read_byte(port: Any) -> int:
    data = port.read(1)
    if len(data) != 1:
        raise TimeoutError("expected 1 response byte, received 0")
    return data[0]


def send_expect(port: Any, byte: int, expected: int, label: str, delay: float) -> None:
    port.reset_input_buffer()
    port.write(bytes([byte]))
    port.flush()
    if delay:
        time.sleep(delay)

    actual = read_byte(port)
    if actual != expected:
        name = ERROR_NAMES.get(actual, "unknown")
        raise AssertionError(
            f"{label}: expected 0x{expected:02x}, got 0x{actual:02x} ({name})"
        )

    print(f"{label}=0x{actual:02x}")


def probe_read_output(port: Any, delay: float) -> None:
    port.reset_input_buffer()
    port.write(bytes([CMD_READ_OUTPUT]))
    port.flush()
    if delay:
        time.sleep(delay)

    actual = read_byte(port)
    if actual == ERR_READ_NO_RESULT:
        print(f"read_without_result=0x{actual:02x}")
        return

    if actual == RESP_OUTPUT:
        frame_tail = port.read(45)
        if len(frame_tail) != 45:
            raise TimeoutError(f"expected 45 output frame byte(s), received {len(frame_tail)}")
        print(f"read_existing_result=0x{actual:02x}")
        return

    name = ERROR_NAMES.get(actual, "unknown")
    raise AssertionError(
        f"read_output probe: expected 0x{ERR_READ_NO_RESULT:02x} or "
        f"0x{RESP_OUTPUT:02x}, got 0x{actual:02x} ({name})"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Probe the FPGA MLP UART protocol.")
    parser.add_argument("port", help="serial port, for example /dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--delay", type=float, default=0.01, help="seconds after each write")
    args = parser.parse_args()

    import serial

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as port:
        port.reset_input_buffer()
        port.reset_output_buffer()
        send_expect(port, 0x7F, ERR_BAD_COMMAND, "bad_command", args.delay)
        probe_read_output(port, args.delay)

    print("protocol_probe=1")


if __name__ == "__main__":
    main()
