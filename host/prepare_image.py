import argparse
from pathlib import Path

from PIL import Image, ImageOps


IMAGE_SIZE = 28
OUTPUT_BYTES = IMAGE_SIZE * IMAGE_SIZE


def resample_filter() -> int:
    if hasattr(Image, "Resampling"):
        return Image.Resampling.LANCZOS
    return Image.LANCZOS


def prepare_image(input_path: Path, invert: bool) -> bytes:
    with Image.open(input_path) as image:
        image = ImageOps.grayscale(image)
        image = image.resize((IMAGE_SIZE, IMAGE_SIZE), resample=resample_filter())

        if invert:
            image = ImageOps.invert(image)

        data = image.tobytes()

    if len(data) != OUTPUT_BYTES:
        raise ValueError(f"expected {OUTPUT_BYTES} output bytes, got {len(data)}")

    return data


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert an image to the raw 28x28 uint8 format used by the FPGA MLP."
    )
    parser.add_argument("input", type=Path, help="input image, for example a PNG")
    parser.add_argument("output", type=Path, help="output raw 784-byte image")
    parser.add_argument(
        "--invert",
        action="store_true",
        help="invert grayscale values before writing; useful for black digits on white backgrounds",
    )
    args = parser.parse_args()

    data = prepare_image(args.input, args.invert)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)

    print(f"input={args.input}")
    print(f"output={args.output}")
    print(f"bytes={len(data)}")
    print(f"min={min(data)}")
    print(f"max={max(data)}")


if __name__ == "__main__":
    main()
