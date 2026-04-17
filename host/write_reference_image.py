from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INPUT_MEM = ROOT / "tb" / "data" / "mlp_reference_input.mem"
OUTPUT_RAW = ROOT / "build" / "reference" / "mlp_reference_input.raw"


def main() -> None:
    values = []

    with INPUT_MEM.open() as f:
        for line in f:
            token = line.strip()
            if token:
                values.append(int(token, 16) & 0xFF)

    if len(values) != 784:
        raise ValueError(f"expected 784 pixels, got {len(values)}")

    OUTPUT_RAW.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_RAW.write_bytes(bytes(values))
    print(OUTPUT_RAW)


if __name__ == "__main__":
    main()
