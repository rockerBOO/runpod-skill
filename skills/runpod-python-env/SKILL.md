---
name: runpod-python-env
description: Use when installing a Python project or its dependencies on a Runpod pod (or any image with a preinstalled CUDA torch), or when torch.cuda.is_available() is False, torch shows +cpu, or torchaudio fails with "Could not load libtorchaudio.so" after uv/pip install.
---

# Python deps on a pod: keep the image's CUDA torch

`runpod/pytorch` images ship a CUDA-matched torch. `uv sync` / `pip install` often pull a fresh one instead: many projects pin the PyTorch index to the **CPU** wheel URL, and you silently get `torch 2.x+cpu`. Downloading and then removing that copy also wastes paid minutes, so keep the torch family out of the resolution entirely.

## Recipe

```bash
PY=$(command -v python3)
$PY -c "import torch; print(torch.__version__, torch.cuda.is_available())"   # image torch, must be True
$PY -m pip install -q uv
export UV_LINK_MODE=copy            # /workspace is another filesystem; hardlinks fail and slow everything down
printf 'torch\ntorchvision\ntorchaudio\n' > /tmp/torch-excludes.txt          # whichever of these the image provides
uv venv --system-site-packages --python "$PY" .venv-sys
uv pip install --python .venv-sys/bin/python --excludes /tmp/torch-excludes.txt -e .
.venv-sys/bin/python -c "import torch; print(torch.__file__, torch.__version__, torch.cuda.is_available())"
#   must be the image's path (not .venv-sys), no +cpu, True
```

- `uv pip install` does not count system-site torch as satisfying the requirement; without `--excludes` it installs its own copy, which shadows the system one and breaks system `torchaudio`. Older uv without `--excludes`: install normally, then `uv pip uninstall --python .venv-sys/bin/python torch torchvision torchaudio` (each one the venv got).
- The venv can also shadow other image packages (e.g. a newer `numpy`); check versions if something the image provides misbehaves.
- `uv pip install` ignores `uv.lock`; transitive versions drift. Record `uv pip freeze --python .venv-sys/bin/python` in the run log.
- To keep the lockfile instead, override the project's own index name: `uv sync --index <project-index-name>=https://download.pytorch.org/whl/cu128` (e.g. `pytorch-cpu=...`). Downloads several GB of torch and re-resolves.
- Venv location: on `/workspace` it survives `pod stop` but installs slower; on the container disk it is faster but wiped on stop.
- Caches on the volume: `export HF_HOME=/workspace/hf`.
- Always run the verification line before launching the job.
