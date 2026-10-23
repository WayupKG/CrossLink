"""Independent Python reference tests for the CrossLink v1 wire contract.

These tests confirm the specification, not compiled Swift/Kotlin binaries.
Run: python -m unittest discover -s tests -v
"""
import base64
import hashlib
import hmac
import json
import os
import struct
import unittest
from urllib.parse import parse_qs, urlsplit

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAX_FRAME = 512 * 1024


def hkdf_sha256(key: bytes, salt: bytes, info: str) -> bytes:
    prk = hmac.digest(salt, key, hashlib.sha256)
    return hmac.digest(prk, info.encode() + b"\x01", hashlib.sha256)[:32]


def discovery_id(secret: bytes) -> str:
    """Bonjour TXT "id": lets the phone pick its Mac without publishing the secret."""
    return hmac.digest(secret, b"crosslink/v1/discovery", hashlib.sha256)[:8].hex()


def frame(payload: bytes) -> bytes:
    if not 1 <= len(payload) <= MAX_FRAME:
        raise ValueError("invalid frame length")
    return struct.pack(">I", len(payload)) + payload


def unframe_parts(parts):
    buf = bytearray()
    out = []
    for part in parts:
        buf.extend(part)
        while len(buf) >= 4:
            size, = struct.unpack(">I", buf[:4])
            if not 1 <= size <= MAX_FRAME:
                raise ValueError("invalid frame")
            if len(buf) < size + 4:
                break
            out.append(bytes(buf[4:4 + size]))
            del buf[:4 + size]
    return out, bytes(buf)


class ProtocolContract(unittest.TestCase):
    def setUp(self):
        self.secret = os.urandom(32)
        self.client_nonce = os.urandom(32)
        self.mac_nonce = os.urandom(32)
        salt = self.client_nonce + self.mac_nonce
        self.mac_to_android = hkdf_sha256(self.secret, salt, "crosslink/v1/mac-to-android")
        self.android_to_mac = hkdf_sha256(self.secret, salt, "crosslink/v1/android-to-mac")

    def test_qr_url_roundtrip(self):
        encoded = base64.urlsafe_b64encode(self.secret).rstrip(b"=").decode()
        pair_url = f"crosslink://pair?host=192.168.1.2&port=48321&key={encoded}"
        parts = urlsplit(pair_url)
        query = parse_qs(parts.query)
        self.assertEqual((parts.scheme, parts.netloc), ("crosslink", "pair"))
        recovered = base64.urlsafe_b64decode(query["key"][0] + "==")
        self.assertEqual(self.secret, recovered)

    def test_separate_keys_for_each_direction(self):
        self.assertNotEqual(self.mac_to_android, self.android_to_mac)
        salt = self.client_nonce + self.mac_nonce
        self.assertEqual(self.mac_to_android,
                         hkdf_sha256(self.secret, salt, "crosslink/v1/mac-to-android"))

    def test_ready_handshake_mac_to_android_and_back(self):
        mac_payload = json.dumps({"type": "ready", "seq": 1, "text": "Mac готов"}).encode()
        iv = os.urandom(12)
        sealed = iv + AESGCM(self.mac_to_android).encrypt(iv, mac_payload, None)
        received = AESGCM(self.mac_to_android).decrypt(sealed[:12], sealed[12:], None)
        self.assertEqual(json.loads(received)["seq"], 1)
        android_payload = json.dumps({"type": "ready_ack", "seq": 1, "text": ""}).encode()
        iv2 = os.urandom(12)
        sealed_android = iv2 + AESGCM(self.android_to_mac).encrypt(iv2, android_payload, None)
        self.assertEqual(json.loads(AESGCM(self.android_to_mac).decrypt(iv2, sealed_android[12:], None))["type"],
                         "ready_ack")

    def test_ciphertext_tampering_fails(self):
        iv = os.urandom(12)
        blob = iv + AESGCM(self.mac_to_android).encrypt(iv, b'{"type":"clipboard"}', None)
        modified = blob[:-1] + bytes([blob[-1] ^ 1])
        with self.assertRaises(Exception):
            AESGCM(self.mac_to_android).decrypt(modified[:12], modified[12:], None)
        with self.assertRaises(Exception):
            AESGCM(self.android_to_mac).decrypt(blob[:12], blob[12:], None)

    def test_partial_frames_and_order(self):
        one = frame(b'hello')
        two = frame(b'world')
        data = one + two
        pieces = [data[:1], data[1:3], data[3:10], data[10:12], data[12:]]
        output, remaining = unframe_parts(pieces)
        self.assertEqual(output, [b"hello", b"world"])
        self.assertEqual(remaining, b"")

    def test_oversized_frame_rejected(self):
        with self.assertRaises(ValueError):
            frame(b"x" * (MAX_FRAME + 1))
        with self.assertRaises(ValueError):
            unframe_parts([struct.pack(">I", MAX_FRAME + 1)])

    def test_discovery_id_vector(self):
        # Same value from Pairing.discoveryID (Swift) and LinkController.discoveryId (Kotlin);
        # bytes >= 0x80 catch signed-byte formatting bugs on the JVM.
        secret = bytes(range(0x80, 0xA0))
        self.assertEqual(discovery_id(secret), "4e572e46ce400629")

    def test_discovery_id_does_not_reveal_key(self):
        tag = discovery_id(self.secret)
        self.assertEqual(len(tag), 16)
        self.assertNotIn(tag, self.secret.hex())
        self.assertNotEqual(tag, discovery_id(os.urandom(32)))


if __name__ == "__main__":
    unittest.main()
