"""Explicit-download, local-only inference probe for public/synthetic fixtures.

Full output is written only to an explicitly supplied result file, never logs.
Run each model in a separate process so unified memory is released between runs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import sys
import time
import traceback
import threading

ROOT = Path(__file__).resolve().parent
os.environ.setdefault("HF_HOME", str(ROOT / ".runtime" / "hf"))
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
MANIFEST = json.loads((ROOT / "models.json").read_text())
RESERVE_BYTES = 6 * 1024**3


class GenerationLimitError(RuntimeError):
    pass


def reject_truncated_generation(sequences, input_length, limit):
    if sequences.shape[-1] - input_length >= limit:
        raise GenerationLimitError("Generation reached its token limit")


def verify_weights(directory, entry):
    weights = Path(directory) / "model.safetensors"
    with weights.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    if weights.stat().st_size != entry["weights_bytes"] or digest != entry["weights_sha256"]:
        raise ValueError("Model weight integrity check failed")


def download(name):
    from huggingface_hub import snapshot_download
    entry = MANIFEST[name]
    # Check for the full weight even on resume. Conservative under low disk space.
    if shutil.disk_usage(ROOT).free < entry["weights_bytes"] + RESERVE_BYTES:
        raise RuntimeError("Insufficient disk: retain at least 6 GiB after download")
    directory = snapshot_download(
        entry["repository"], revision=entry["revision"],
        allow_patterns=["*.json", "*.txt", "*.jinja", "model.safetensors", "LICENSE"],
        max_workers=2,
    )
    verify_weights(directory, entry)
    return directory


def synchronize(torch, device):
    if device == "mps":
        torch.mps.synchronize()


def load_transcriber(name, device="mps", attention="sdpa"):
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    import torch
    from huggingface_hub import snapshot_download
    if device == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS is not available in this process")
    entry = MANIFEST[name]
    torch.set_num_threads(4)
    path = snapshot_download(entry["repository"], revision=entry["revision"], local_files_only=True)
    verify_weights(path, entry)
    started = time.perf_counter()
    if name == "breeze":
        from transformers import WhisperForConditionalGeneration, WhisperProcessor
        processor = WhisperProcessor.from_pretrained(path, local_files_only=True)
        model = WhisperForConditionalGeneration.from_pretrained(
            path, local_files_only=True, dtype=torch.float16,
            attn_implementation=attention,
        ).to(device).eval()

        def transcribe(samples, rate, language="zh"):
            inputs = processor(samples, sampling_rate=rate, return_tensors="pt", return_attention_mask=True)
            features = inputs.input_features.to(device=device, dtype=torch.float16)
            with torch.inference_mode():
                tokens = model.generate(features, attention_mask=inputs.attention_mask.to(device), language=None if language in (None, "auto") else language, task="transcribe", max_new_tokens=128, do_sample=False)
            reject_truncated_generation(tokens, 0, 128)
            return processor.batch_decode(tokens, skip_special_tokens=True)[0].strip()
    else:
        from qwen_asr import Qwen3ASRModel
        model = Qwen3ASRModel.from_pretrained(
            path, dtype=torch.float16, device_map=device,
            attn_implementation=attention, max_inference_batch_size=1, max_new_tokens=128,
        )
        generate = model.model.generate

        def checked_generate(*args, **kwargs):
            output = generate(*args, **kwargs)
            # qwen-asr 0.0.6 decodes GenerateOutput.sequences after input_ids.
            reject_truncated_generation(output.sequences, kwargs["input_ids"].shape[-1], kwargs["max_new_tokens"])
            return output

        model.model.generate = checked_generate

        def transcribe(samples, rate, language="zh"):
            return model.transcribe(audio=(samples, rate), language={"zh": "Chinese", "en": "English", "auto": None, None: None}[language])[0].text.strip()

    synchronize(torch, device)
    load_seconds = time.perf_counter() - started
    return transcribe, load_seconds


def run(name, audio, output, device, repeats, attention):
    # Inference may not download a model or send a request to a model host.
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    import numpy as np
    import soundfile as sf
    import torch
    from huggingface_hub import snapshot_download

    if output.exists():
        raise ValueError("Result file already exists; choose a new path")
    samples, rate = sf.read(audio, dtype="float32", always_2d=True)
    duration = len(samples) / rate
    if not 0 < duration <= 30:
        raise ValueError("Probe fixtures must be between 0 and 30 seconds")
    if rate != 16000 or samples.shape[1] != 1:
        raise ValueError("Probe requires mono 16 kHz WAV")
    if not np.isfinite(samples).all():
        raise ValueError("Audio contains non-finite samples")
    if device == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS is not available in this process")
    entry = MANIFEST[name]
    print(f"Loading {name} on {device}", flush=True)
    transcribe, load_seconds = load_transcriber(name, device, attention)
    print("Model loaded; starting inference", flush=True)
    runs = []
    for index in range(repeats):
        started = time.perf_counter()
        text = transcribe(samples[:, 0], rate)
        synchronize(torch, device)
        if not text:
            raise RuntimeError("Model returned an empty transcript")
        runs.append({"run": index + 1, "seconds": time.perf_counter() - started, "text": text})
        print(f"run {index + 1} completed", flush=True)
    result = {
        "model": name, **entry, "device": device, "dtype": "float16", "attention": attention,
        "audio_sha256": hashlib.sha256(audio.read_bytes()).hexdigest(),
        "audio_seconds": duration, "load_seconds": load_seconds, "runs": runs,
        "peak_process_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "mps_driver_allocated_bytes": torch.mps.driver_allocated_memory() if device == "mps" else None,
        "scope": "synthetic/public fixture only; not app end-to-end acceptance",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    # Fail rather than replacing a prior result or following an output symlink.
    with output.open("x") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    print("Result saved; transcript omitted from logs", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["download", "run"])
    parser.add_argument("model", choices=MANIFEST)
    parser.add_argument("--audio", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--device", choices=["mps", "cpu"], default="mps")
    parser.add_argument("--repeats", type=int, choices=range(1, 4), default=2)
    parser.add_argument("--attention", choices=["sdpa", "eager"], default="sdpa")
    parser.add_argument("--timeout", type=int, choices=range(30, 601), default=180, metavar="SECONDS")
    args = parser.parse_args()
    if args.action == "download":
        download(args.model)
    else:
        if not args.audio or not args.output:
            parser.error("run requires --audio and --output")
        def stop_on_timeout():
            print("Probe exceeded its time budget; stopping this process", file=sys.stderr, flush=True)
            # A Metal wait may not return to Python signal handlers. This probe
            # owns no shared files or child processes; OS exit releases its GPU.
            os._exit(124)
        watchdog = threading.Timer(args.timeout, stop_on_timeout)
        watchdog.daemon = True
        watchdog.start()
        try:
            run(args.model, args.audio, args.output, args.device, args.repeats, args.attention)
        finally:
            watchdog.cancel()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Keep exception payloads, URLs and model output out of routine logs.
        print(f"Probe failed ({type(error).__name__})", file=sys.stderr)
        for frame in traceback.extract_tb(error.__traceback__)[-5:]:
            print(f"  {Path(frame.filename).name}:{frame.lineno} in {frame.name}", file=sys.stderr)
        raise SystemExit(1)
