import argparse
from pathlib import Path
from typing import Any


def parse_payload(value: str) -> bytes:
    path = Path(value)
    if path.exists():
        return path.read_bytes()

    if value.startswith("hex:"):
        return bytes.fromhex(value[4:])

    return value.encode("utf-8")


def read_exact(port: Any, count: int) -> bytes:
    data = port.read(count)
    if len(data) != count:
        raise TimeoutError(f"expected {count} byte(s), received {len(data)}")
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate FPGA UART echo.")
    parser.add_argument("port", help="serial port, for example /dev/ttyUSB1")
    parser.add_argument(
        "--payload",
        default="hex:0055aa7e813fc0ff",
        help="text, hex:<bytes>, or a file path; default is a binary smoke pattern",
    )
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=2.0)
    args = parser.parse_args()

    import serial

    payload = parse_payload(args.payload)
    if not payload:
        raise ValueError("payload must not be empty")

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as port:
        port.reset_input_buffer()
        port.reset_output_buffer()
        port.write(payload)
        port.flush()
        echoed = read_exact(port, len(payload))

    if echoed != payload:
        raise AssertionError(f"echo mismatch: expected {payload.hex()}, got {echoed.hex()}")

    print(f"echo_bytes={len(payload)}")
    print(f"echo_hex={echoed.hex()}")
    print("echo_match=1")


if __name__ == "__main__":
    main()
