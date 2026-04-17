from pathlib import Path
import json
import torch


def int_to_hex(val: int, bits: int) -> str:
    mask = (1 << bits) - 1
    return f"{(val & mask):0{bits // 4}x}"


def write_mem_1d(path: Path, values, bits: int):
    with open(path, "w") as f:
        for v in values:
            f.write(int_to_hex(int(v), bits) + "\n")


def write_mem_flat(path: Path, tensor: torch.Tensor, bits: int):
    with open(path, "w") as f:
        for v in tensor.reshape(-1).tolist():
            f.write(int_to_hex(int(v), bits) + "\n")


def quantize_symmetric_per_tensor(w: torch.Tensor, qmax: int = 127):
    """
    Symmetric int8 quantization:
        q = round(w / scale), scale = max(abs(w)) / 127
    Returns:
        q_w: int8 tensor
        scale: float
    """
    max_abs = w.abs().max().item()
    scale = max_abs / qmax if max_abs > 0 else 1.0
    q_w = torch.round(w / scale).clamp(-128, 127).to(torch.int8)
    return q_w, scale


def quantize_bias_int32(bias: torch.Tensor, input_scale: float, weight_scale: float):
    """
    Standard int32 bias quantization for affine integer inference:
        bias_int32 = round(bias_fp / (input_scale * weight_scale))
    """
    bias_scale = input_scale * weight_scale
    q_bias = torch.round(bias / bias_scale).to(torch.int32)
    return q_bias, bias_scale


def export_linear_to_mem(
    layer: torch.nn.Linear,
    name: str,
    input_scale: float,
    out_dir: str = "mem",
):
    """
    Export one Linear layer for Verilog.

    Files written:
      {name}_weight.mem   int8 two's complement hex, row-major
      {name}_bias.mem     int32 two's complement hex
      {name}_meta.json    shape + scales
    """
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    w = layer.weight.detach().cpu()
    b = layer.bias.detach().cpu() if layer.bias is not None else None

    if w.ndim != 2:
        raise ValueError(f"{name}: expected 2D weight, got shape {tuple(w.shape)}")
    if b is not None and b.ndim != 1:
        raise ValueError(f"{name}: expected 1D bias, got shape {tuple(b.shape)}")

    # Weight quantization
    q_w, weight_scale = quantize_symmetric_per_tensor(w)

    # Bias quantization
    if b is not None:
        q_b, bias_scale = quantize_bias_int32(b, input_scale, weight_scale)
    else:
        q_b, bias_scale = None, input_scale * weight_scale

    # Write files
    write_mem_flat(out / f"{name}_weight.mem", q_w, bits=8)
    if q_b is not None:
        write_mem_1d(out / f"{name}_bias.mem", q_b.tolist(), bits=32)

    # Metadata for software/testbench/reference
    meta = {
        "shape": list(w.shape),  # [out_features, in_features]
        "weight_scale": weight_scale,
        "input_scale": input_scale,
        "bias_scale": bias_scale,
        "weight_quantization": "symmetric_per_tensor_int8",
        "bias_quantization": "int32 using input_scale * weight_scale",
        "flatten_order": "row_major",
        "verilog_addr_formula": f"addr = neuron * {w.shape[1]} + feature",
    }

    with open(out / f"{name}_meta.json", "w") as f:
        json.dump(meta, f, indent=2)

    print(f"Exported {name}")
    print(f"  weight shape : {tuple(w.shape)}")
    print(f"  input_scale  : {input_scale}")
    print(f"  weight_scale : {weight_scale}")
    print(f"  bias_scale   : {bias_scale}")
