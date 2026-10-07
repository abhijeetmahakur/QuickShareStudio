"""Writes a valid one-page PDF of about the requested size (a large random RGB image, which
does not compress), for transfer tests with a realistic file:

    python tool/e2e/make_test_pdf.py build/e2e_web/Lab-Report-20MB.pdf 20
"""
import math
import os
import sys


def main():
    path = sys.argv[1]
    megabytes = float(sys.argv[2]) if len(sys.argv) > 2 else 20
    side = int(math.sqrt(megabytes * 1024 * 1024 / 3))
    pixels = os.urandom(side * side * 3)
    content = b"q 540 0 0 540 36 126 cm /Im1 Do Q BT /F1 18 Tf 36 690 Td (QuickShare transfer test) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        b"/Resources << /XObject << /Im1 5 0 R >> /Font << /F1 6 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream",
        b"<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB "
        b"/BitsPerComponent 8 /Length %d >>\nstream\n" % (side, side, len(pixels)) + pixels + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(out)
    print(f"{path}: {len(out)} bytes")


if __name__ == "__main__":
    main()
