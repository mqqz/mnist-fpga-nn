import argparse
import struct
from pathlib import Path
from typing import Any

from protocol import (
    CMD_LOAD_INPUT,
    CMD_READ_OUTPUT,
    CMD_RUN,
    ERROR_NAMES,
    RESP_LOAD_DONE,
    RESP_OUTPUT,
    RESP_RUN_DONE,
)


def read_exact(port: Any, count: int) -> bytes:
    data = port.read(count)
    if len(data) != count:
        raise TimeoutError(f"expected {count} byte(s), received {len(data)}")
    return data


def expect_byte(port: Any, expected: int) -> None:
    value = read_exact(port, 1)[0]
    if value == expected:
        return

    if value in ERROR_NAMES:
        raise RuntimeError(f"FPGA error 0x{value:02x}: {ERROR_NAMES[value]}")

    raise RuntimeError(f"expected 0x{expected:02x}, received 0x{value:02x}")


def load_image(path: Path) -> bytes:
    data = path.read_bytes()
    if len(data) != 784:
        raise ValueError(f"{path} must contain exactly 784 raw pixel bytes, got {len(data)}")
    return data


def read_hex_mem(path: Path, bits: int) -> list[int]:
    sign_bit = 1 << (bits - 1)
    mask = (1 << bits) - 1
    values = []

    with path.open() as f:
        for line in f:
            token = line.strip()
            if not token:
                continue

            value = int(token, 16) & mask
            if value & sign_bit:
                value -= 1 << bits
            values.append(value)

    return values


def load_reference(reference_dir: Path) -> tuple[int, int, list[int]]:
    class_values = read_hex_mem(reference_dir / "mlp_reference_class.mem", 32)
    logits = read_hex_mem(reference_dir / "mlp_reference_logits.mem", 32)

    if len(class_values) != 2:
        raise ValueError("mlp_reference_class.mem must contain class_id and class_score")
    if len(logits) != 10:
        raise ValueError("mlp_reference_logits.mem must contain 10 logits")

    return class_values[0], class_values[1], logits


def compare_reference(
    actual_class_id: int,
    actual_class_score: int,
    actual_logits: list[int],
    expected_class_id: int,
    expected_class_score: int,
    expected_logits: list[int],
) -> None:
    if actual_class_id != expected_class_id:
        raise AssertionError(f"class_id expected {expected_class_id}, got {actual_class_id}")
    if actual_class_score != expected_class_score:
        raise AssertionError(f"class_score expected {expected_class_score}, got {actual_class_score}")
    if actual_logits != expected_logits:
        for index, (actual, expected) in enumerate(zip(actual_logits, expected_logits)):
            if actual != expected:
                raise AssertionError(f"logit[{index}] expected {expected}, got {actual}")
        raise AssertionError("logit length mismatch")


def run_inference(port: Any, pixels: bytes) -> tuple[int, int, list[int]]:
    port.write(bytes([CMD_LOAD_INPUT]))
    port.write(pixels)
    expect_byte(port, RESP_LOAD_DONE)

    port.write(bytes([CMD_RUN]))
    expect_byte(port, RESP_RUN_DONE)

    port.write(bytes([CMD_READ_OUTPUT]))
    expect_byte(port, RESP_OUTPUT)

    class_id = read_exact(port, 1)[0]
    class_score = struct.unpack("<i", read_exact(port, 4))[0]
    logits = [struct.unpack("<i", read_exact(port, 4))[0] for _ in range(10)]

    return class_id, class_score, logits


def main() -> None:
    parser = argparse.ArgumentParser(description="Run FPGA MLP inference over UART.")
    parser.add_argument("port", help="serial port, for example /dev/ttyUSB0")
    parser.add_argument("image", type=Path, help="raw 784-byte uint8 image")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument(
        "--compare-reference",
        type=Path,
        metavar="DIR",
        help="compare against mlp_reference_*.mem files in DIR, usually tb/data",
    )
    args = parser.parse_args()

    import serial

    pixels = load_image(args.image)

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as port:
        port.reset_input_buffer()
        port.reset_output_buffer()
        class_id, class_score, logits = run_inference(port, pixels)

    print(f"class_id={class_id}")
    print(f"class_score={class_score}")
    print("logits=" + " ".join(str(value) for value in logits))

    if args.compare_reference is not None:
        expected_class_id, expected_class_score, expected_logits = load_reference(
            args.compare_reference
        )
        compare_reference(
            class_id,
            class_score,
            logits,
            expected_class_id,
            expected_class_score,
            expected_logits,
        )
        print("reference_match=1")


if __name__ == "__main__":
    main()
