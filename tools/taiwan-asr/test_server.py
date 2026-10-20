import asyncio
import io
import http.client
import socket
import threading
import time
import unittest
import wave

from fastapi import HTTPException
from fastapi.testclient import TestClient
import httpx
import uvicorn
from server import ModelWorker, create_app, decode_wav, client_disconnected

TOKEN = "test-only-token-not-used-by-any-real-service"


def wav_bytes(rate=16000, channels=1, duration=0.1):
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(b"\x00\x00" * int(duration * rate) * channels)
    return output.getvalue()


class FakeWorker:
    model = None
    loaded = False
    warmed = False

    def __init__(self):
        self.calls = []
        self.closed = False

    async def transcribe(self, model, samples, language, request, timeout):
        self.calls.append((model, len(samples), language))
        return "fixture result"

    def close(self):
        self.closed = True


class ServerContractTests(unittest.TestCase):
    def setUp(self):
        self.worker = FakeWorker()
        self.client = TestClient(create_app(TOKEN, worker=self.worker))
        self.headers = {"Authorization": "Bearer " + TOKEN}

    def post(self, data=None, audio=None, headers=None):
        return self.client.post("/v1/audio/transcriptions", headers=self.headers if headers is None else headers,
                                data=data or {"model": "tea"},
                                files={"file": ("fixture.wav", wav_bytes() if audio is None else audio, "audio/wav")})

    def test_authentication_is_enforced_before_audio_processing(self):
        response = self.post(audio=b"bad audio", headers={})
        self.assertEqual(response.status_code, 401)
        self.assertFalse(self.worker.calls)

    def test_real_app_multipart_contract_and_language_mapping(self):
        response = self.post({"model": "JacobLinCool/TEA-ASR-1.1", "language": "zh-TW",
                              "response_format": "json", "temperature": "0"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["text"], "fixture result")
        self.assertEqual(response.headers["cache-control"], "no-store")
        self.assertEqual(self.worker.calls, [("tea", 1600, "zh")])

    def test_unknown_model_invalid_audio_and_parameters_are_not_success(self):
        for fields, audio, status in [
            ({"model": "missing"}, wav_bytes(), 404),
            ({"model": "tea"}, b"not a wav", 400),
            ({"model": "tea", "temperature": "1"}, wav_bytes(), 400),
            ({"model": "tea", "language": "invalid"}, wav_bytes(), 400),
            ({"model": "tea", "prompt": "unapproved context"}, wav_bytes(), 400),
        ]:
            with self.subTest(fields=fields):
                self.assertEqual(self.post(fields, audio).status_code, status)
        self.assertFalse(self.worker.calls)

    def test_large_upload_is_rejected(self):
        self.assertEqual(self.post(audio=b"x" * (12 * 1024 * 1024)).status_code, 413)
        self.assertFalse(self.worker.calls)

    def test_stereo_44100_audio_is_resampled(self):
        samples, duration = decode_wav(wav_bytes(44100, 2, 0.1))
        self.assertEqual(len(samples), 1600)
        self.assertAlmostEqual(duration, 0.1)

    def test_oversized_duration_and_truncated_wav_are_rejected(self):
        for data in [wav_bytes(duration=31), wav_bytes()[:-50]]:
            with self.assertRaises(ValueError):
                decode_wav(data)


class ModelWorkerCancellationTests(unittest.IsolatedAsyncioTestCase):
    async def test_disconnected_client_stops_before_waiting_for_a_result(self):
        class Disconnected:
            async def is_disconnected(self):
                return True
        worker = ModelWorker()
        with self.assertRaises(HTTPException) as context:
            await worker.next_message(Disconnected(), 0)
        self.assertEqual(context.exception.status_code, 499)

    async def test_timeout_is_explicit(self):
        class Connected:
            async def is_disconnected(self):
                return False
        with self.assertRaises(HTTPException) as context:
            await ModelWorker().next_message(Connected(), 0)
        self.assertEqual(context.exception.status_code, 504)


class RealHTTPDisconnectTests(unittest.TestCase):
    def test_disconnect_reaches_handler_through_auth_and_upload_middleware(self):
        canceled = threading.Event()
        entered = threading.Event()

        class WaitingWorker(FakeWorker):
            async def transcribe(self, model, samples, language, request, timeout):
                entered.set()
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    if await client_disconnected(request):
                        canceled.set()
                        raise HTTPException(499, "request_canceled")
                    await asyncio.sleep(0.01)
                raise HTTPException(504, "test_timeout")

        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        address = f"http://127.0.0.1:{listener.getsockname()[1]}"
        server = uvicorn.Server(uvicorn.Config(create_app(TOKEN, WaitingWorker()), access_log=False, log_level="critical"))
        thread = threading.Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
        thread.start()
        try:
            deadline = time.monotonic() + 3
            while not server.started:
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.01)
            boundary = "ASRDisconnectBoundary"
            body = (f'--{boundary}\r\nContent-Disposition: form-data; name="model"\r\n\r\ntea\r\n'
                    f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="fixture.wav"\r\n'
                    f'Content-Type: audio/wav\r\n\r\n').encode() + wav_bytes() + f'\r\n--{boundary}--\r\n'.encode()
            connection = http.client.HTTPConnection("127.0.0.1", listener.getsockname()[1], timeout=3)
            try:
                connection.request("POST", "/v1/audio/transcriptions", body=body,
                                   headers={"Authorization": "Bearer " + TOKEN,
                                            "Content-Type": f"multipart/form-data; boundary={boundary}"})
                self.assertTrue(entered.wait(timeout=3), "Known-positive handler entry was not observed")
            finally:
                connection.close()
            self.assertTrue(canceled.wait(timeout=1), "Middleware hid the real HTTP disconnect")
        finally:
            server.should_exit = True
            thread.join(timeout=5)
            listener.close()
            self.assertFalse(thread.is_alive())


if __name__ == "__main__":
    unittest.main()
