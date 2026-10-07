"""Verify the official release signature without a system GnuPG install."""
import sys
import pgpy

key, _ = pgpy.PGPKey.from_file(sys.argv[1])
if str(key.fingerprint) != "FCF986EA15E6E293A5644F10B4322F04D67658D8":
    raise SystemExit("Unexpected FFmpeg release-signing fingerprint")
signature = pgpy.PGPSignature.from_file(sys.argv[2])
with open(sys.argv[3], "rb") as source:
    if not key.verify(source.read(), signature):
        raise SystemExit("FFmpeg source signature verification failed")
print("PASS: FFmpeg source signature matches official release key")
