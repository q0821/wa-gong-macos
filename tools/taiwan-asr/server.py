"""Manually started loopback ASR service. No persistent audio or transcript logs."""
import argparse
import asyncio
from contextlib import asynccontextmanager
import getpass
import hmac
import io
import logging
import math
import multiprocessing
import time
import wave

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from starlette.datastructures import Headers

from probe import MANIFEST

MAX_BODY_BYTES = 12 * 1024 * 1024
MAX_AUDIO_SECONDS = 30
LANGUAGES = {"zh": "zh", "zh-TW": "zh", "en": "en", "auto": "auto", "": "auto"}
logger = logging.getLogger("taiwan_asr")


class AuthenticatedBodyLimit:
    """Pure ASGI preserves the original disconnect channel while bounding uploads."""
    def __init__(self, app, token):
        self.app = app
        self.token = ("Bearer " + token).encode("ascii")

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        authorization = Headers(scope=scope).get("authorization", "").encode("utf-8")
        if not hmac.compare_digest(authorization, self.token):
            return await JSONResponse({"detail": "unauthorized"}, status_code=401)(scope, receive, send)
        if scope["method"] != "POST":
            return await self.app(scope, receive, send)
        chunks = []
        size = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > MAX_BODY_BYTES:
                return await JSONResponse({"detail": "audio_upload_too_large"}, status_code=413)(scope, receive, send)
            chunks.append(chunk)
            if not message.get("more_body", False):
                break
        body = b"".join(chunks)
        delivered = False
        disconnected = asyncio.Event()
        scope.setdefault("state", {})["asr_disconnected"] = disconnected

        async def monitor_disconnect():
            while True:
                message = await receive()
                if message["type"] == "http.disconnect":
                    disconnected.set()
                    return

        async def replay_then_receive():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": body, "more_body": False}
            await disconnected.wait()
            return {"type": "http.disconnect"}

        monitor = asyncio.create_task(monitor_disconnect())
        try:
            return await self.app(scope, replay_then_receive, send)
        finally:
            monitor.cancel()
            await asyncio.gather(monitor, return_exceptions=True)


async def client_disconnected(request):
    event = getattr(getattr(request, "state", None), "asr_disconnected", None)
    if event is not None:
        return event.is_set()
    return await request.is_disconnected()


def decode_wav(data):
    """Validate uncompressed WAV metadata before allocating decoded samples."""
    import numpy as np
    import soundfile as sf
    from scipy.signal import resample_poly

    try:
        with wave.open(io.BytesIO(data)) as wav:
            rate, channels, frames = wav.getframerate(), wav.getnchannels(), wav.getnframes()
            if channels not in (1, 2) or not 8000 <= rate <= 96000:
                raise ValueError("unsupported_audio")
            if not 0 < frames / rate <= MAX_AUDIO_SECONDS:
                raise ValueError("audio_too_long_or_empty")
            if wav.getsampwidth() not in (1, 2, 3, 4):
                raise ValueError("unsupported_audio")
            expected_bytes = frames * channels * wav.getsampwidth()
            pcm = wav.readframes(frames)
            if len(pcm) != expected_bytes:
                raise ValueError("truncated_audio")
        samples, actual_rate = sf.read(io.BytesIO(data), dtype="float32", always_2d=True)
        if len(samples) != frames or actual_rate != rate or not np.isfinite(samples).all():
            raise ValueError("invalid_audio")
        mono = samples.mean(axis=1)
        if rate != 16000:
            divisor = math.gcd(rate, 16000)
            mono = resample_poly(mono, 16000 // divisor, rate // divisor).astype("float32")
        return mono, frames / rate
    except (wave.Error, EOFError, RuntimeError, OSError) as error:
        raise ValueError("invalid_audio") from error


def inference_worker(connection, model):
    """A killable, model-scoped process. Its pipe is never forwarded to logs."""
    try:
        from probe import load_transcriber
        transcribe, _ = load_transcriber(model)
        connection.send({"status": "loaded"})
        while True:
            job = connection.recv()
            if job is None:
                return
            samples, language = job
            text = transcribe(samples, 16000, language)
            connection.send({"status": "result", "text": text})
    except EOFError:
        return
    except Exception as error:
        # Exception messages can contain input text and request data.
        try:
            connection.send({"status": "error", "kind": type(error).__name__})
        except (BrokenPipeError, EOFError, OSError):
            logger.error("worker_result_channel_closed")
    finally:
        connection.close()


class ModelWorker:
    def __init__(self):
        self.process = None
        self.connection = None
        self.model = None
        self.loaded = False
        self.warmed = False

    def close(self):
        if self.process is not None:
            if self.process.is_alive():
                # GPU waits need not return to Python SIGTERM handlers. This
                # disposable worker owns no writable files, so stop it directly.
                self.process.kill()
            self.process.join(timeout=10)
            if self.process.is_alive():
                raise RuntimeError("Worker did not stop")
            self.process.close()
        if self.connection is not None:
            self.connection.close()
        self.process = self.connection = self.model = None
        self.loaded = False
        self.warmed = False

    async def start(self, model):
        await asyncio.to_thread(self.close)
        context = multiprocessing.get_context("spawn")
        self.connection, child = context.Pipe()
        self.process = context.Process(target=inference_worker, args=(child, model), daemon=True)
        self.process.start()
        child.close()
        self.model = model

    async def next_message(self, request, deadline):
        while True:
            if await client_disconnected(request):
                raise HTTPException(499, "request_canceled")
            if time.monotonic() >= deadline:
                raise HTTPException(504, "inference_timeout")
            if self.connection.poll():
                try:
                    message = self.connection.recv()
                except (EOFError, OSError) as error:
                    raise HTTPException(503, "model_worker_stopped") from error
                if message.get("status") == "error":
                    logger.error("inference_failed type=%s", message.get("kind", "unknown"))
                    if message.get("kind") == "GenerationLimitError":
                        raise HTTPException(422, "transcript_limit_reached")
                    raise HTTPException(503, "inference_failed")
                return message
            if not self.process.is_alive():
                raise HTTPException(503, "model_worker_stopped")
            await asyncio.sleep(0.05)

    async def transcribe(self, model, samples, language, request, timeout):
        deadline = time.monotonic() + timeout
        started = time.monotonic()
        try:
            if self.model != model or self.process is None or not self.process.is_alive():
                await self.start(model)
                message = await self.next_message(request, deadline)
                if message.get("status") != "loaded":
                    raise HTTPException(503, "model_load_failed")
                self.loaded = True
                logger.warning("model_loaded model=%s seconds=%.2f", model, time.monotonic() - started)
            self.connection.send((samples, language))
            message = await self.next_message(request, deadline)
            if message.get("status") != "result" or not isinstance(message.get("text"), str):
                raise HTTPException(503, "invalid_model_result")
            self.warmed = True
            return message["text"]
        except BaseException as error:
            # No late result, queued work or old model may survive cancellation.
            logger.warning("inference_stopped type=%s status=%s seconds=%.2f",
                           type(error).__name__, getattr(error, "status_code", "none"), time.monotonic() - started)
            await asyncio.to_thread(self.close)
            raise


def create_app(token, worker=None, timeout=150, models=None):
    if len(token) < 32 or not token.isascii() or any(c.isspace() for c in token):
        raise ValueError("Use an ASCII token with at least 32 non-whitespace characters")
    registry = MANIFEST if models is None else models
    worker = worker or ModelWorker()
    busy = asyncio.Lock()

    @asynccontextmanager
    async def lifespan(app):
        yield
        await asyncio.to_thread(worker.close)

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    app.add_middleware(AuthenticatedBodyLimit, token=token)

    @app.get("/health")
    async def health():
        return {"status": "busy" if busy.locked() else "idle", "model": worker.model,
                "loaded": worker.loaded, "supports_streaming": False,
                "ready": worker.warmed and not busy.locked(),
                "max_audio_seconds": MAX_AUDIO_SECONDS}

    @app.post("/v1/audio/transcriptions")
    async def transcribe(request: Request):
        if busy.locked():
            raise HTTPException(429, "model_busy")
        if not request.headers.get("content-type", "").startswith("multipart/form-data;"):
            raise HTTPException(415, "multipart_form_required")
        async with busy:
            try:
                async with request.form(max_files=1, max_fields=5, max_part_size=MAX_BODY_BYTES) as form:
                    if set(form) - {"file", "model", "language", "response_format", "temperature"}:
                        raise HTTPException(400, "unsupported_fields")
                    if any(len(form.getlist(key)) != 1 for key in form):
                        raise HTTPException(400, "duplicate_fields")
                    model_id = form.get("model")
                    aliases = {entry["repository"]: name for name, entry in registry.items()}
                    if not isinstance(model_id, str):
                        raise HTTPException(400, "model_required")
                    model = aliases.get(model_id, model_id)
                    if model not in registry:
                        raise HTTPException(404, "model_not_found")
                    language = form.get("language", "auto")
                    if language not in LANGUAGES:
                        raise HTTPException(400, "unsupported_language")
                    if form.get("response_format", "json") != "json":
                        raise HTTPException(400, "only_json_supported")
                    if form.get("temperature", "0") not in ("0", "0.0"):
                        raise HTTPException(400, "only_zero_temperature_supported")
                    file = form.get("file")
                    if not hasattr(file, "read"):
                        raise HTTPException(400, "audio_file_required")
                    data = await file.read(MAX_BODY_BYTES + 1)
                    if len(data) > MAX_BODY_BYTES:
                        raise HTTPException(413, "audio_upload_too_large")
                    try:
                        samples, duration = await asyncio.to_thread(decode_wav, data)
                    except ValueError as error:
                        # Decoder errors are mapped to a fixed string, not raw input.
                        raise HTTPException(400, "invalid_or_unsupported_wav_max_30_seconds") from error
                    if await client_disconnected(request):
                        raise HTTPException(499, "request_canceled")
                    text = await worker.transcribe(model, samples, LANGUAGES[language], request, timeout)
                    if await client_disconnected(request):
                        worker.close()
                        raise HTTPException(499, "request_canceled")
                    return JSONResponse({"text": text, "duration": duration}, headers={"Cache-Control": "no-store"})
            except HTTPException:
                raise
            except asyncio.CancelledError:
                worker.close()
                raise
            except Exception as error:
                logger.error("transcription_request_failed type=%s", type(error).__name__)
                worker.close()
                raise HTTPException(500, "transcription_failed") from error

    return app


def main():
    import uvicorn
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    token = getpass.getpass("Local ASR token (at least 32 characters): ")
    app = create_app(token)
    # Do not expose a configurable bind address in this local-only tool.
    uvicorn.run(app, host="127.0.0.1", port=args.port, access_log=False,
                log_level="warning", timeout_graceful_shutdown=5)


if __name__ == "__main__":
    main()
