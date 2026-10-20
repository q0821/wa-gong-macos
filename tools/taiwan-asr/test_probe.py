import hashlib
from pathlib import Path
import tempfile
import unittest

from probe import run, verify_weights, reject_truncated_generation, GenerationLimitError


class ProbeBoundaryTests(unittest.TestCase):
    def test_generation_limit_does_not_return_partial_text(self):
        class Tokens:
            shape = (1, 138)
        reject_truncated_generation(Tokens(), input_length=11, limit=128)
        with self.assertRaises(GenerationLimitError):
            reject_truncated_generation(Tokens(), input_length=10, limit=128)

    def test_same_size_corruption_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            weights = Path(directory) / "model.safetensors"
            weights.write_bytes(b"known weights")
            entry = {"weights_bytes": weights.stat().st_size,
                     "weights_sha256": hashlib.sha256(weights.read_bytes()).hexdigest()}
            verify_weights(directory, entry)
            weights.write_bytes(b"wrong weights")
            with self.assertRaisesRegex(ValueError, "integrity"):
                verify_weights(directory, entry)

    def test_existing_result_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.json"
            output.write_text("previous result")
            with self.assertRaisesRegex(ValueError, "already exists"):
                run("breeze", Path(directory) / "missing.wav", output, "cpu", 1, "sdpa")
            self.assertEqual(output.read_text(), "previous result")

    def test_incompatible_audio_is_rejected_before_model_loading(self):
        import numpy as np
        import soundfile as sf
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "wrong-rate.wav"
            sf.write(audio, np.zeros(8000, dtype="float32"), 8000)
            with self.assertRaisesRegex(ValueError, "16 kHz"):
                run("tea", audio, Path(directory) / "output.json", "cpu", 1, "sdpa")
            self.assertFalse((Path(directory) / "output.json").exists())


if __name__ == "__main__":
    unittest.main()
