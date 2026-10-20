"""Offline checks for integrity and synthetic-text acceptance boundaries."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from download import verified
from run_ollama import normalized
from analyze_results import equivalent_fixture

class IntegrityTests(unittest.TestCase):
    def test_verified_rejects_corruption_and_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'model';path.write_bytes(b'known artifact')
            artifact={'bytes':len(b'known artifact'),'sha256':hashlib.sha256(b'known artifact').hexdigest()}
            self.assertTrue(verified(path,artifact))
            link=Path(directory)/'link';link.symlink_to(path)
            self.assertFalse(verified(link,artifact))
            path.write_bytes(b'wrong artifact')
            self.assertFalse(verified(path,artifact))
    def test_numeral_variant_is_not_amount_loss(self):
        self.assertTrue(equivalent_fixture('金額一千二百元','金額一千兩百元'))
        self.assertFalse(equivalent_fixture('金額一萬兩千元','金額一千二百元'))
    def test_fixture_comparison_preserves_negation_and_amount(self):
        expected='訂單金額是一萬兩千五百元，不是一千兩百五十元。'
        self.assertEqual(normalized(expected),normalized('訂單金額是12500元，不是1250元。'))
        self.assertNotEqual(normalized(expected),normalized('訂單金額是1250元，不是12500元。'))
        self.assertNotEqual(normalized('今天不要deploy'),normalized('今天要deploy'))

if __name__=='__main__':unittest.main()
