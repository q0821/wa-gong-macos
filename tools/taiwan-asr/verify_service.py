"""Real loopback/API/worker acceptance using only a known synthetic fixture.

Creates an ephemeral token in memory. Stops both the server and model worker.
"""
import argparse
import http.client
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import threading
import time

import httpx
import uvicorn
from server import ModelWorker, create_app


def normalized(text):
    return re.sub(r"[^\w]", "", text).replace("3", "三")


def verify(audio, output, app_probe=None):
    if output.exists():
        raise ValueError("Choose a new output file")
    expected = normalized("今天下午三點開會，請保留原始資料，不要刪除。")
    token = secrets.token_urlsafe(32)
    worker = ModelWorker()
    app = create_app(token, worker=worker)
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    address = f"http://127.0.0.1:{listener.getsockname()[1]}"
    server = uvicorn.Server(uvicorn.Config(app, access_log=False, log_level="critical"))
    thread = threading.Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
    thread.start()
    headers = {"Authorization": "Bearer " + token}
    result = {"scope": "synthetic fixture over real loopback API and real model workers", "requests": []}

    def post(model, timeout=180):
        started = time.perf_counter()
        with httpx.Client(timeout=timeout, trust_env=False) as client:
            response = client.post(address + "/v1/audio/transcriptions", headers=headers,
                                   data={"model": model, "language": "zh", "response_format": "json", "temperature": "0"},
                                   files={"file": ("fixture.wav", audio.read_bytes(), "audio/wav")})
        response.raise_for_status()
        matches = normalized(response.json()["text"]) == expected
        if not matches:
            raise AssertionError("Transcript did not match the synthetic fixture")
        return {"model": model, "seconds": time.perf_counter() - started, "matches": matches}

    try:
        deadline = time.monotonic() + 10
        while not server.started:
            if time.monotonic() > deadline:
                raise RuntimeError("Server did not start")
            time.sleep(0.05)
        with httpx.Client(timeout=10, trust_env=False) as client:
            assert client.get(address + "/health").status_code == 401
            result["unauthorized_rejected"] = True
            with ThreadPoolExecutor(max_workers=1) as executor:
                first = executor.submit(post, "tea")
                deadline = time.monotonic() + 10
                while client.get(address + "/health", headers=headers).json()["status"] != "busy":
                    if time.monotonic() > deadline:
                        raise RuntimeError("Did not observe a live busy request")
                    time.sleep(0.05)
                busy_response = client.post(address + "/v1/audio/transcriptions", headers=headers,
                                             data={"model": "tea"}, files={"file": ("fixture.wav", audio.read_bytes())})
                assert busy_response.status_code == 429
                result["concurrent_request_rejected"] = True
                result["requests"].append(first.result(timeout=185))
            print("TEA live API passed", flush=True)
            result["requests"].append(post("tea"))
            tea_pid = worker.process.pid
            result["requests"].append(post("breeze"))
            assert worker.model == "breeze" and worker.process.pid != tea_pid
            result["model_switch_replaces_worker"] = True
            print("Breeze live API passed", flush=True)
            if app_probe:
                environment = os.environ.copy()
                environment.update({"WAGONG_ASR_TEST_ENDPOINT": address + "/v1/audio/transcriptions",
                                    "WAGONG_ASR_TEST_TOKEN": token, "WAGONG_ASR_TEST_AUDIO": str(audio.resolve()),
                                    "LLVM_PROFILE_FILE": str(output.parent.resolve() / "app-transport-%p.profraw")})
                completed = subprocess.run([str(app_probe.resolve())], env=environment,
                                           capture_output=True, timeout=180)
                if completed.returncode:
                    raise RuntimeError("Actual App transport probe failed")
                result["actual_app_transport_passed"] = True
                print("Actual App transport live check passed", flush=True)
            boundary = "LiveASRCancelBoundary"
            body = (f'--{boundary}\r\nContent-Disposition: form-data; name="model"\r\n\r\ntea\r\n'
                    f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="fixture.wav"\r\n'
                    f'Content-Type: audio/wav\r\n\r\n').encode() + audio.read_bytes() + f'\r\n--{boundary}--\r\n'.encode()
            connection = http.client.HTTPConnection("127.0.0.1", listener.getsockname()[1], timeout=10)
            try:
                connection.request("POST", "/v1/audio/transcriptions", body=body,
                                   headers={**headers, "Content-Type": f"multipart/form-data; boundary={boundary}"})
                deadline = time.monotonic() + 20
                while True:
                    health = client.get(address + "/health", headers=headers).json()
                    if health["model"] == "tea" and health["status"] == "busy":
                        break
                    if time.monotonic() > deadline:
                        raise RuntimeError("Known-positive cancellation worker was not observed")
                    time.sleep(0.05)
            finally:
                connection.close()
            deadline = time.monotonic() + 30
            while True:
                health = client.get(address + "/health", headers=headers).json()
                if health["model"] is None and health["status"] == "idle":
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError("Canceled worker survived disconnect")
                time.sleep(0.1)
            result["disconnect_stops_worker"] = True
            result["requests"].append(post("breeze"))
            result["recovery_after_cancel"] = True
            print("Cancellation and recovery passed", flush=True)
    finally:
        server.should_exit = True
        thread.join(timeout=10)
        if thread.is_alive():
            raise RuntimeError("Verification server did not stop")
        listener.close()
        worker.close()
    result["server_and_worker_stopped"] = True
    with output.open("x") as handle:
        json.dump(result, handle, indent=2)
    print("Verification stopped its server and worker; token was not persisted", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--app-probe", type=Path)
    args = parser.parse_args()
    verify(args.audio, args.output, args.app_probe)
