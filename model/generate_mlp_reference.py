from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MEM_DIR = ROOT / "mem"
TB_DATA_DIR = ROOT / "tb" / "data"

INPUT_SIZE = 784
HIDDEN_SIZE = 32
OUTPUT_SIZE = 10

FC1_REQUANT_MULT = 26456
FC1_REQUANT_SHIFT = 27


def read_hex_mem(path: Path, bits: int) -> list[int]:
    values = []
    sign_bit = 1 << (bits - 1)
    mask = (1 << bits) - 1

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


def write_hex_mem(path: Path, values: list[int], bits: int) -> None:
    mask = (1 << bits) - 1
    digits = bits // 4

    with path.open("w") as f:
        for value in values:
            f.write(f"{value & mask:0{digits}x}\n")


def reference_input() -> list[int]:
    # Deterministic byte pattern that exercises the full unsigned pixel range.
    return [((index * 37) + 11) % 256 for index in range(INPUT_SIZE)]


def requant_relu(value: int) -> int:
    if value <= 0:
        return 0

    rounded = value * FC1_REQUANT_MULT + (1 << (FC1_REQUANT_SHIFT - 1))
    scaled = rounded >> FC1_REQUANT_SHIFT
    return min(scaled, 127)


def matvec(weights: list[int], biases: list[int], x: list[int], rows: int, cols: int) -> list[int]:
    y = []

    for row in range(rows):
        acc = biases[row]
        base = row * cols

        for col in range(cols):
            acc += x[col] * weights[base + col]

        y.append(acc)

    return y


def main() -> None:
    TB_DATA_DIR.mkdir(parents=True, exist_ok=True)

    fc1_weight = read_hex_mem(MEM_DIR / "fc1_weight.mem", 8)
    fc1_bias = read_hex_mem(MEM_DIR / "fc1_bias.mem", 32)
    fc2_weight = read_hex_mem(MEM_DIR / "fc2_weight.mem", 8)
    fc2_bias = read_hex_mem(MEM_DIR / "fc2_bias.mem", 32)

    x = reference_input()
    fc1_acc = matvec(fc1_weight, fc1_bias, x, HIDDEN_SIZE, INPUT_SIZE)
    hidden = [requant_relu(value) for value in fc1_acc]
    logits = matvec(fc2_weight, fc2_bias, hidden, OUTPUT_SIZE, HIDDEN_SIZE)
    class_id = max(range(OUTPUT_SIZE), key=lambda index: logits[index])

    write_hex_mem(TB_DATA_DIR / "mlp_reference_input.mem", x, 8)
    write_hex_mem(TB_DATA_DIR / "mlp_reference_hidden.mem", hidden, 8)
    write_hex_mem(TB_DATA_DIR / "mlp_reference_logits.mem", logits, 32)
    write_hex_mem(TB_DATA_DIR / "mlp_reference_class.mem", [class_id, logits[class_id]], 32)

    print("Generated MLP reference fixtures")
    print(f"  class_id    : {class_id}")
    print(f"  class_score : {logits[class_id]}")
    print(f"  logits      : {logits}")


if __name__ == "__main__":
    main()
