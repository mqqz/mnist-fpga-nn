import copy
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim

from torchvision import datasets, transforms
from torch.optim.lr_scheduler import StepLR
from torchao.quantization import quantize_
from torchao.quantization.qat import QATConfig, QATStep, IntxFakeQuantizeConfig

from export_mem import export_linear_to_mem

# Hardcoded params
BATCH_SIZE = 64
TEST_BATCH_SIZE = 1000
EPOCHS = 10
QAT_EPOCHS = 3
LR = 1.0
GAMMA = 0.7
SAVE_MODEL = False
LOG_INTERVAL = 100
HIDDEN_SIZE = 32


class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.flatten = nn.Flatten()
        self.fc1 = nn.Linear(28 * 28, HIDDEN_SIZE)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(HIDDEN_SIZE, 10)

    def forward(self, x):
        x = self.flatten(x)
        x = self.fc1(x)
        x = self.relu(x)
        x = self.fc2(x)
        return x  # logits


def train(model, device, train_loader, optimizer, epoch):
    model.train()
    for batch_idx, (data, target) in enumerate(train_loader):
        data, target = data.to(device), target.to(device)

        optimizer.zero_grad()
        output = model(data)
        loss = F.cross_entropy(output, target)
        loss.backward()
        optimizer.step()

        if batch_idx % LOG_INTERVAL == 0:
            print(
                f"Train Epoch: {epoch} "
                f"[{batch_idx * len(data)}/{len(train_loader.dataset)} "
                f"({100. * batch_idx / len(train_loader):.0f}%)]\t"
                f"Loss: {loss.item():.6f}"
            )


def test(model, device, test_loader, label="Test"):
    model.eval()
    test_loss = 0.0
    correct = 0

    with torch.no_grad():
        for data, target in test_loader:
            data, target = data.to(device), target.to(device)
            output = model(data)
            test_loss += F.cross_entropy(output, target, reduction="sum").item()
            pred = output.argmax(dim=1)
            correct += pred.eq(target).sum().item()

    test_loss /= len(test_loader.dataset)
    acc = 100.0 * correct / len(test_loader.dataset)

    print(
        f"\n{label}: Average loss: {test_loss:.4f}, "
        f"Accuracy: {correct}/{len(test_loader.dataset)} ({acc:.2f}%)\n"
    )
    return acc

def estimate_fc1_output_scale(model, loader, device):
    model.eval()
    max_val = 0.0

    with torch.no_grad():
        for data, _ in loader:
            data = data.to(device)
            x = model.flatten(data)
            x = model.fc1(x)
            x = model.relu(x)
            max_val = max(max_val, x.max().item())  # ReLU, so nonnegative

    return max_val / 127 if max_val > 0 else 1.0

def main():
    torch.manual_seed(42)

    if hasattr(torch, "accelerator") and torch.accelerator.is_available():
        device = torch.accelerator.current_accelerator()
    else:
        device = torch.device("cpu")

    print(f"Using device: {device}")

    # Simpler for FPGA export than normalized inputs
    transform = transforms.Compose([
        transforms.ToTensor(),
    ])

    train_dataset = datasets.MNIST(
        root="./dataset", train=True, download=True, transform=transform
    )
    test_dataset = datasets.MNIST(
        root="./dataset", train=False, download=True, transform=transform
    )

    train_loader = torch.utils.data.DataLoader(
        train_dataset, batch_size=BATCH_SIZE, shuffle=True
    )
    test_loader = torch.utils.data.DataLoader(
        test_dataset, batch_size=TEST_BATCH_SIZE, shuffle=False
    )

    # 1) Train float model first
    model = MLP().to(device)
    optimizer = optim.Adadelta(model.parameters(), lr=LR)
    scheduler = StepLR(optimizer, step_size=1, gamma=GAMMA)

    print("\n--- Float training ---")
    for epoch in range(1, EPOCHS + 1):
        train(model, device, train_loader, optimizer, epoch)
        test(model, device, test_loader, label="Float")
        scheduler.step()

    if SAVE_MODEL:
        torch.save(model.state_dict(), "mlp_float.pt")

    # 2) QAT prepare
    qat_model = copy.deepcopy(model).cpu()
    qat_model.train()

    # Simple explicit fake-quant config for FPGA-oriented int8/int8
    act_cfg = IntxFakeQuantizeConfig(
        dtype=torch.int8,
        granularity="per_token",
        is_symmetric=False,
    )

    weight_cfg = IntxFakeQuantizeConfig(
        dtype=torch.int8,
        granularity="per_channel",
        is_symmetric=True,
    )

    quantize_(
        qat_model,
        QATConfig(
            activation_config=act_cfg,
            weight_config=weight_cfg,
            step=QATStep.PREPARE,
        ),
    )

    # 3) Fine-tune with fake quant enabled
    optimizer_qat = optim.Adadelta(qat_model.parameters(), lr=0.1)

    print("\n--- QAT fine-tuning ---")
    for epoch in range(1, QAT_EPOCHS + 1):
        train(qat_model, torch.device("cpu"), train_loader, optimizer_qat, epoch)
        test(qat_model, torch.device("cpu"), test_loader, label="QAT")

    # 4) Convert
    test(qat_model, torch.device("cpu"), test_loader, label="Converted")

    if SAVE_MODEL:
        torch.save(qat_model.state_dict(), "mlp_qat.pt")

    fc1_out_scale = estimate_fc1_output_scale(qat_model, train_loader, torch.device("cpu"))
    export_linear_to_mem(qat_model.fc1, "fc1", input_scale=1.0/255.0)
    export_linear_to_mem(qat_model.fc2, "fc2", input_scale=fc1_out_scale)

if __name__ == "__main__":
    main()
